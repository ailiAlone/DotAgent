@tool
class_name MessageRenderer
extends RefCounted
## 消息渲染器（拆自 dock.gd）
##
## 职责:
##   - 创建/追加 用户、助手（含 think 折叠块）消息节点
##   - 滚动到底部
##   - 维护流式渲染时的内部状态（_stream_node / _stream_content / think 状态机）
##   - 应用 bbcode 格式化
##
## think 解析采用参考版算法：在完整 _stream_content 上查找标签，用 substr 切分

enum Role { SYSTEM, USER, ASSISTANT, TOOL }

const ThinkSectionRendererType = preload("res://addons/dotagent/ui/think_section_renderer.gd")

## think 标签匹配——支持多种模型格式
const THINK_PATTERNS := [
	["<think>", "</think>"],
	["<thinking>", "</thinking>"],
	["[THINK]", "[/THINK]"],
]

var _message_list: VBoxContainer
var _message_scroll: ScrollContainer

# 流式状态
var _stream_node: RichTextLabel = null
var _stream_content: String = ""
var _stream_pending: String = ""
var _stream_last_render: float = 0.0
var _round_tool_results: Array = []
var _tool_nodes: Dictionary = {}  # tool_name → RichTextLabel，流式工具反馈

# Think 块状态 — 参考版算法
var _in_think: bool = false
var _think_start: int = 0
var _think_end_tag: String = ""
var _think_section: VBoxContainer = null
var _think_label: RichTextLabel = null
var _think_renderer: ThinkSectionRenderer


func _init(message_list: VBoxContainer, message_scroll: ScrollContainer) -> void:
	_message_list = message_list
	_message_scroll = message_scroll
	_think_renderer = ThinkSectionRendererType.new()


# ============ 流式控制 ============

func begin_stream() -> void:
	_stream_node = append_assistant_node("")
	_stream_content = ""
	_stream_pending = ""
	_stream_last_render = 0.0
	_round_tool_results = []
	_tool_nodes.clear()
	_in_think = false
	_think_start = 0
	_think_end_tag = ""
	_think_section = null
	_think_label = null


func end_stream(tool_calls: Array, tool_results: Array) -> void:
	if _in_think:
		# `</think>` 从未出现 → 回退：内容放回正文，丢弃 think 框
		if _stream_node and is_instance_valid(_stream_node):
			_stream_node.text = _stream_content
		if _think_section and is_instance_valid(_think_section):
			_think_section.queue_free()
		_think_section = null
		_think_label = null
		_in_think = false
	# 重置 think 框引用（框本身留在消息列表中作为历史记录）
	_think_section = null
	_think_label = null
	# 强制恢复可见（think 解析可能设了 visible=false）
	if _stream_node and is_instance_valid(_stream_node):
		_stream_node.visible = true
	_finalize_stream_node(_stream_node, tool_calls, tool_results)
	_stream_node = null
	_stream_content = ""
	_round_tool_results = []


## 接收 chunk + 节流渲染 —— 参考版 think 解析算法
func receive_chunk(chunk: String) -> void:
	if not _stream_node or not is_instance_valid(_stream_node):
		return
	_stream_content += chunk
	_stream_pending += chunk

	var now := Time.get_ticks_msec() / 1000.0
	if now - _stream_last_render < 0.05:
		return
	_stream_pending = ""
	_stream_last_render = now

	# —— Think 块解析（多格式，在完整 _stream_content 上查找） ——
	var display_text := _stream_content
	if not _in_think:
		var found := _find_think_start(_stream_content)
		var start_idx: int = found["idx"]
		if start_idx >= 0:
			_in_think = true
			_think_end_tag = found["end_tag"]
			var tag_len: int = found["tag_len"]
			_think_start = start_idx + tag_len
			if _think_section == null or not is_instance_valid(_think_section):
				_think_renderer.create(_message_list, _stream_node)
				_think_section = _think_renderer.section
				_think_label = _think_renderer.content
			else:
				# 复用已有 think 框（多段 think）
				var content_box := _think_section.get_node_or_null("ThinkContent") as VBoxContainer
				if content_box:
					content_box.visible = true
				var lbl := _think_section.get_child(0) as Label
				if lbl:
					lbl.text = "💭 思考过程 ▾"
				if _think_label and is_instance_valid(_think_label):
					var prev := _think_label.text
					if prev != "":
						_think_label.text = prev + "\n[color=#444444]———[/color]\n"
			display_text = _stream_content.substr(0, start_idx)
			var after := _stream_content.substr(_think_start)
			var end_idx := _find_think_end_tag(after, _think_end_tag)
			if end_idx >= 0:
				var end_len := _think_end_tag.length()
				_think_label.text = (_think_label.text if _think_label else "") + after.substr(0, end_idx)
				display_text += after.substr(end_idx + end_len)
				var processed_len := start_idx + tag_len + end_idx + end_len
				_stream_content = _stream_content.substr(processed_len)
				_think_renderer.finalize()
				_in_think = false
			else:
				_think_label.text = (_think_label.text if _think_label else "") + after
				display_text = ""
	else:
		var search_from := _stream_content.substr(_think_start)
		var end_idx := _find_think_end_tag(search_from, _think_end_tag)
		if end_idx >= 0:
			var end_len := _think_end_tag.length()
			_think_label.text = (_think_label.text if _think_label else "") + search_from.substr(0, end_idx)
			display_text = search_from.substr(end_idx + end_len)
			var processed_len := _think_start + end_idx + end_len
			_stream_content = _stream_content.substr(processed_len)
			_think_renderer.finalize()
			_in_think = false
		else:
			_think_label.text = search_from
			display_text = ""

	# 去除前导空行
	display_text = _strip_leading_newlines(display_text)
	if _think_label and is_instance_valid(_think_label):
		_think_label.text = _strip_leading_newlines(_think_label.text)
	# 空内容时隐藏节点，避免大片空白
	if _stream_node:
		_stream_node.visible = display_text != ""
		_stream_node.text = display_text
	# —— Think 解析结束 ——

	_scroll_to_bottom()


# ============ 直接追加（用户消息 / 非流式 AI 消息 / 历史回放） ============

func append_user_node(content: String) -> void:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	_message_list.add_child(node)
	node.append_text("[b][color=#7eb6ff]You[/color][/b] [color=#666666][i]%s[/i][/color]\n" % _now_str())
	node.append_text(content)
	_scroll_to_bottom(true)


func append_assistant_node(content: String) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	_message_list.add_child(node)
	node.append_text("[b][color=#a8d977]AI[/color][/b] [color=#666666][i]%s[/i][/color]\n" % _now_str())
	node.append_text(content)
	if _is_scrolled_to_bottom():
		_scroll_to_bottom(true)
	return node


## 工具开始反馈 — 在消息列表中插入 "⏳ tool_name..."
func append_tool_started(tool_name: String) -> void:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	_message_list.add_child(node)
	node.append_text("[color=#888888]⏳ %s...[/color]" % tool_name)
	_tool_nodes[tool_name] = node
	if _is_scrolled_to_bottom():
		_scroll_to_bottom(true)


## 工具完成反馈 — 更新为 "✅/❌ tool_name"
func append_tool_finished(tool_name: String, ok: bool) -> void:
	var node: RichTextLabel = _tool_nodes.get(tool_name, null)
	if node == null or not is_instance_valid(node):
		return
	var mark := "✅" if ok else "❌"
	var color := "#88cc88" if ok else "#dd6666"
	node.clear()
	node.append_text("[color=%s]%s %s[/color]" % [color, mark, tool_name])


## 清空所有消息节点
func clear() -> void:
	if _message_list == null:
		return
	for child in _message_list.get_children():
		child.queue_free()


## 重新渲染整个消息列表（session 切换时使用）
func rebuild(messages: Array) -> void:
	clear()
	var i := 0
	while i < messages.size():
		var msg: Dictionary = messages[i]
		var role: String = msg.get("role", "?")

		if role == "system":
			i += 1
			continue

		var content = msg.get("content", "")
		if content == null:
			content = ""

		if role == "user":
			append_user_node(content)
			i += 1

		elif role == "assistant":
			var has_tool_calls: bool = msg.has("tool_calls") and not msg["tool_calls"].is_empty()
			if not has_tool_calls:
				var node := append_assistant_node("")
				node.append_text(content)
				i += 1
			else:
				var tool_calls: Array = msg.get("tool_calls", [])
				var tool_results: Array = []
				var j := i + 1
				while j < messages.size() and messages[j].get("role", "") == "tool":
					var tc_id: String = messages[j].get("tool_call_id", "")
					var tc_name := _find_tool_name(tool_calls, tc_id)
					var tc_content: String = messages[j].get("content", "")
					var ok := not tc_content.begins_with("Error") and not tc_content.begins_with("Failed")
					tool_results.append({"name": tc_name, "ok": ok})
					j += 1
				var node := append_assistant_node("")
				node.append_text(content)
				_append_tool_results_for_history(node, tool_results)
				i = j

		elif role == "tool":
			i += 1
		else:
			i += 1
	_scroll_to_bottom(true)


# ============ 内部 ============

func _now_str() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]


func _finalize_stream_node(node: RichTextLabel, tool_calls: Array, tool_results: Array = []) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.append_text("\n")
	if tool_calls.is_empty():
		node.append_text("[color=#88aa88][i]— done — %s[/i][/color]" % _now_str())
		return
	var ok_count := 0
	var err_count := 0
	for r in tool_results:
		if r.get("ok", true):
			ok_count += 1
		else:
			err_count += 1
	if err_count > 0:
		node.append_text("[color=#ddaa66][i]— Round done: %d ok, %d failed —[/i][/color]\n" % [ok_count, err_count])
	else:
		node.append_text("[color=#88aa88][i]— Round done: %d tools all ok —[/i][/color]\n" % ok_count)
	for r in tool_results:
		var mark := "✅" if r.get("ok", true) else "❌"
		var color := "#88cc88" if r.get("ok", true) else "#dd6666"
		node.append_text("[color=%s]  %s %s[/color]\n" % [color, mark, r.get("name", "?")])
	node.append_text("[color=#666666][i]⏳ 等待下一轮 —[/i][/color]")


func _append_tool_results_for_history(node: RichTextLabel, tool_results: Array) -> void:
	if tool_results.is_empty():
		return
	var ok_count := 0
	var err_count := 0
	for r in tool_results:
		if r.get("ok", true):
			ok_count += 1
		else:
			err_count += 1
	node.append_text("\n")
	if err_count > 0:
		node.append_text("[color=#ddaa66][i]— %d ok, %d failed —[/i][/color]\n" % [ok_count, err_count])
	else:
		node.append_text("[color=#88aa88][i]— %d tools all ok —[/i][/color]\n" % ok_count)
	for r in tool_results:
		var mark := "✅" if r.get("ok", true) else "❌"
		var color := "#88cc88" if r.get("ok", true) else "#dd6666"
		node.append_text("[color=%s]  %s %s[/color]\n" % [color, mark, r.get("name", "?")])


func _find_tool_name(tool_calls: Array, call_id: String) -> String:
	for tc in tool_calls:
		if tc.get("id", "") == call_id:
			return tc.get("function", {}).get("name", "?")
	return "?"


func _is_scrolled_to_bottom() -> bool:
	if _message_scroll == null:
		return true
	var bar := _message_scroll.get_v_scroll_bar()
	return bar.max_value - bar.value < 20


func _scroll_to_bottom(force: bool = false) -> void:
	if _message_scroll == null:
		return
	if not force and not _is_scrolled_to_bottom():
		return
	# call_deferred：帧末执行，此时 RichTextLabel 已完成 fit_content 布局重算
	_message_scroll.call_deferred("set", "scroll_vertical", 99999999)


# ============ Think 标签解析 ============

func _find_think_start(text: String) -> Dictionary:
	for pat in THINK_PATTERNS:
		var start_tag: String = pat[0]
		var idx := text.find(start_tag)
		if idx >= 0:
			return {"idx": idx, "tag": start_tag, "end_tag": pat[1], "tag_len": start_tag.length()}
	return {"idx": -1, "tag": "", "end_tag": "", "tag_len": 0}


func _find_think_end_tag(text: String, end_tag: String) -> int:
	var idx := text.find(end_tag)
	if idx >= 0:
		return idx
	# 尝试去掉前导空白（模型有时在标签前加空格）
	var trimmed := text.strip_edges(false, true)
	if trimmed != text:
		idx = trimmed.find(end_tag)
		if idx >= 0:
			return idx + (text.length() - trimmed.length())
	return -1


func _strip_leading_newlines(text: String) -> String:
	if text.is_empty():
		return text
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch != "\n" and ch != "\r":
			break
		i += 1
	return text.substr(i)
