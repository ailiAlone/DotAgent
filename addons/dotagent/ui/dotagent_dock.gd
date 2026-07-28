@tool
extends VBoxContainer
## DotAgent 共享对话面板
##
## 两种模式（Legacy / Banyan）共用同一个 Dock。
## 右侧 Dock 只显示对话流。模式特有面板在编辑器底部。
## 通过 bottom_panel 引用将 update_tree / add_log 转发给底部面板。

# ============ 信号 ============

signal run_requested(prompt: String, mode: String)
signal stop_requested()
signal clear_requested()
signal session_requested(action: String, id: String)
signal settings_requested()
signal model_change_requested()
signal model_selected(model_name: String)

# ============ 常量 ============

const MAX_STREAM_AGE_MS := 100
const GRAY := Color(0.5, 0.5, 0.5)

# ============ UI 组件 (@onready) ============

@onready var _status_label: Label = $Header/Status
@onready var _msg_scroll: ScrollContainer = $MsgScroll
@onready var _msg_list: VBoxContainer = $MsgScroll/MsgList
@onready var _prompt_input: TextEdit = $PromptInput
@onready var _send_button: Button = $BottomBar/SendBtn
@onready var _stop_button: Button = $BottomBar/StopBtn
@onready var _context_label: Label = $Header/ContextLabel
@onready var _settings_button: Button = $Header/SettingsBtn
@onready var _model_button: Button = $BottomBar/ModelButton
@onready var _refresh_button: Button = $BottomBar/RefreshBtn
@onready var _model_popup: PopupMenu = $ModelPopup

# ============ 外部引用 ============

## 编辑器插件引用，由 plugin.gd 注入
var plugin = null
## 底部面板（Nodes + Log），由 plugin.gd 注入
var bottom_panel = null

# ============ 状态 ============

var _running: bool = false
var _stream_node: RichTextLabel = null
var _stream_content: String = ""
var _stream_last_update: int = 0
var _session_id: String = ""
var _typing_node: RichTextLabel = null  # "正在思考..." 指示器


func _init() -> void:
	name = "DotAgent"


func _ready() -> void:
	# 连接信号
	get_node("Header/NewBtn").pressed.connect(func(): session_requested.emit("new", ""))
	_send_button.pressed.connect(_on_send_pressed)
	_stop_button.pressed.connect(func(): stop_requested.emit())
	_prompt_input.gui_input.connect(_on_prompt_gui_input)
	_prompt_input.text_changed.connect(_on_prompt_text_changed)
	_settings_button.pressed.connect(func(): settings_requested.emit())
	_model_button.pressed.connect(_on_model_button_pressed)
	_refresh_button.pressed.connect(func(): model_change_requested.emit())
	_model_popup.id_pressed.connect(_on_model_popup_selected)


# ============ 公共 API ============

func set_running(running: bool) -> void:
	_running = running
	_send_button.disabled = running
	_stop_button.disabled = not running
	_prompt_input.editable = not running
	if not running:
		_finalize_stream()
		_hide_typing_indicator()


func set_banyan_status(status: String, color: Color = GRAY) -> void:
	if _status_label:
		_status_label.text = " " + status
		_status_label.add_theme_color_override("font_color", color)


func set_model(model: String) -> void:
	if _model_button:
		_model_button.text = model if not model.is_empty() else "(not configured)"


## 填充模型列表 — 由 plugin.gd 调用
func populate_models(models: Array) -> void:
	_model_popup.clear()
	for i in range(models.size()):
		var m = models[i]
		var name: String = m.get("id", m.get("name", str(m))) if m is Dictionary else str(m)
		_model_popup.add_item(name, i)


## 显示模型弹窗 — 定位在 ModelButton 上方
func _on_model_button_pressed() -> void:
	if _model_popup.item_count == 0:
		model_change_requested.emit()
		return
	var btn_rect: Rect2 = _model_button.get_global_rect()
	var popup_size: Vector2 = _model_popup.size
	_model_popup.position = Vector2i(int(btn_rect.position.x), int(btn_rect.position.y - popup_size.y))
	_model_popup.popup()


func _on_model_popup_selected(id: int) -> void:
	var text: String = _model_popup.get_item_text(id)
	model_selected.emit(text)


## 更新上下文用量显示 — 由 plugin 调用
func set_context_usage(used_k: int, max_k: int) -> void:
	if _context_label:
		var pct: int = 0
		if max_k > 0:
			pct = int(float(used_k) / float(max_k) * 100.0)
		_context_label.text = "%dK/%dK" % [used_k, max_k]
		if pct > 80:
			_context_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		elif pct > 60:
			_context_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		else:
			_context_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4))


func set_session_id(sid: String) -> void:
	_session_id = sid


# ---- 消息流 ----

func append_user_message(text: String) -> void:
	_add_separator()
	var rtl: RichTextLabel = _make_rtl()
	rtl.text = "[b][color=#7eb6ff]You[/color][/b]\n%s" % text
	_msg_list.add_child(rtl)
	_smart_scroll(true)  # force scroll for user messages
	# 显示 typing 指示器
	_show_typing_indicator()


func append_assistant_message(text: String, node_id: String = "") -> void:
	_finalize_stream()
	_add_separator()
	var tag: String = ""
	if not node_id.is_empty():
		tag = " [color=#888888][%s][/color]" % node_id
	var rtl: RichTextLabel = _make_rtl()
	rtl.text = "[b][color=#a8d977]AI[/color][/b]%s\n%s" % [tag, text]
	_msg_list.add_child(rtl)
	_smart_scroll()


func begin_stream(node_id: String = "") -> void:
	_finalize_stream()
	_hide_typing_indicator()
	_add_separator()
	var tag: String = ""
	if not node_id.is_empty():
		tag = " [color=#888888][%s][/color]" % node_id
	_stream_node = _make_rtl()
	_stream_node.text = "[b][color=#a8d977]AI[/color][/b]%s\n" % tag
	_stream_content = ""
	_msg_list.add_child(_stream_node)


func receive_chunk(chunk: String, node_id: String = "") -> void:
	if _stream_node == null:
		begin_stream(node_id)
	_hide_typing_indicator()
	_stream_content += chunk
	var now: int = Time.get_ticks_msec()
	if now - _stream_last_update >= MAX_STREAM_AGE_MS:
		_stream_last_update = now
		_update_stream_display()
		_smart_scroll()


func end_stream(tool_calls: Array = [], tool_results: Array = []) -> void:
	_update_stream_display()
	if not tool_calls.is_empty():
		var parts: Array = []
		for i in range(tool_calls.size()):
			var tc: String = tool_calls[i] if i < tool_calls.size() else "?"
			var ok: bool = true
			if i < tool_results.size() and tool_results[i] is Dictionary:
				ok = tool_results[i].get("ok", true)
			parts.append("%s %s" % ["✅" if ok else "❌", tc])
		var rtl: RichTextLabel = _make_rtl()
		rtl.text = "[color=#777777]── %d tools: %s ──[/color]" % [tool_calls.size(), "  ".join(parts)]
		_msg_list.add_child(rtl)
	_stream_node = null
	_stream_content = ""
	_smart_scroll()


func append_tool_started(tool_name: String) -> void:
	var rtl: RichTextLabel = _make_rtl()
	rtl.text = "  [color=#999999]⏳ %s[/color]" % tool_name
	rtl.custom_minimum_size = Vector2(0, 16)
	_msg_list.add_child(rtl)
	_smart_scroll()


func append_tool_finished(tool_name: String, ok: bool) -> void:
	var color: String = "#88cc88" if ok else "#dd6666"
	var icon: String = "✅" if ok else "❌"
	var found: bool = false
	for i in range(_msg_list.get_child_count() - 1, -1, -1):
		var child = _msg_list.get_child(i)
		if child is RichTextLabel and ("⏳ %s" % tool_name) in child.text:
			child.text = "  [%s]%s %s[/%s]" % [color, icon, tool_name, color]
			found = true
			break
	if not found:
		var rtl: RichTextLabel = _make_rtl()
		rtl.text = "  [%s]%s %s[/%s]" % [color, icon, tool_name, color]
		rtl.custom_minimum_size = Vector2(0, 16)
		_msg_list.add_child(rtl)
	_smart_scroll()


func append_error(error: String) -> void:
	_finalize_stream()
	var rtl: RichTextLabel = _make_rtl()
	rtl.text = "[color=#dd6666]❌ %s[/color]" % error
	_msg_list.add_child(rtl)
	_smart_scroll()


# ---- 节点树 & 日志（转发到底部面板） ----

func update_tree(data: Dictionary) -> void:
	if bottom_panel:
		bottom_panel.update_tree(data)


func add_log(message: String, level: String = "info") -> void:
	if bottom_panel:
		bottom_panel.add_log(message, level)


# ---- 清除 ----

func clear_all() -> void:
	for child in _msg_list.get_children():
		child.queue_free()
	_stream_node = null
	_stream_content = ""
	if bottom_panel:
		bottom_panel.clear_log()


func rebuild_messages(messages: Array) -> void:
	clear_all()
	for msg in messages:
		if not msg is Dictionary:
			continue
		var role = msg.get("role", "")
		var content = msg.get("content", "")
		if content == null:
			content = ""
		match str(role):
			"user":
				append_user_message(content)
			"assistant":
				append_assistant_message(content)
			"tool":
				var ok: bool = not str(content).to_lower().begins_with("error")
				append_tool_finished(str(msg.get("name", "tool")), ok)


# ============ 内部 ============

func _add_separator() -> void:
	var sep: HSeparator = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_list.add_child(sep)


func _update_stream_display() -> void:
	if _stream_node and not _stream_content.is_empty():
		var nl: int = _stream_node.text.find("\n") + 1
		if nl <= 0:
			nl = _stream_node.text.length()
		_stream_node.text = _stream_node.text.substr(0, nl) + _stream_content


func _finalize_stream() -> void:
	if _stream_node and not _stream_content.is_empty():
		_update_stream_display()
	_stream_node = null
	_stream_content = ""


func _make_rtl() -> RichTextLabel:
	var rtl: RichTextLabel = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	rtl.custom_minimum_size = Vector2(0, 20)
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rtl


func _is_scrolled_to_bottom() -> bool:
	if not _msg_scroll:
		return true
	var bar: VScrollBar = _msg_scroll.get_v_scroll_bar()
	return bar.max_value - bar.value < 20


func _smart_scroll(force: bool = false) -> void:
	if not _msg_scroll:
		return
	if not force and not _is_scrolled_to_bottom():
		return
	call_deferred("_do_scroll_bottom")


func _do_scroll_bottom() -> void:
	if _msg_scroll:
		_msg_scroll.scroll_vertical = int(_msg_scroll.get_v_scroll_bar().max_value)


# ============ 回调 ============

func _auto_resize_input() -> void:
	var lc: int = _prompt_input.get_line_count()
	_prompt_input.custom_minimum_size.y = clampi(lc * 18 + 12, 52, 160)


func _on_prompt_text_changed() -> void:
	_auto_resize_input()


func _on_prompt_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			_on_send_pressed()
			_prompt_input.accept_event()


func _on_send_pressed() -> void:
	var prompt: String = _prompt_input.text.strip_edges()
	if prompt.is_empty() or _running:
		return
	run_requested.emit(prompt, "banyan")
	append_user_message(prompt)
	_prompt_input.text = ""
	_auto_resize_input()


# ============ Typing 指示器 ============

func _show_typing_indicator() -> void:
	_hide_typing_indicator()
	_typing_node = _make_rtl()
	_typing_node.text = "[color=#888888][i]正在思考...[/i][/color]"
	_typing_node.custom_minimum_size = Vector2(0, 18)
	_msg_list.add_child(_typing_node)
	_smart_scroll(true)


func _hide_typing_indicator() -> void:
	if _typing_node and is_instance_valid(_typing_node):
		_typing_node.queue_free()
	_typing_node = null
