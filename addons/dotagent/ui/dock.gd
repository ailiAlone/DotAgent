@tool
extends VBoxContainer
## AI Panel 主 Dock - UI 层（纯前端，所有业务走 DockController）
##
## 职责:
## - 渲染消息流、按钮状态、进度倒计时
## - 接收用户输入(按钮、键盘)
## - 把所有业务调用转发给 DockController
##
## 关键约束:
## - **不持有任何业务对象**(_llm_client / _tool_registry / _messages 都在 controller 中)
## - **所有 UI 副作用只走本地方法**,业务副作用通过 controller signal 触发
## - **plugin / activity_panel 由 plugin.gd 注入**,在 _ready() 里转发给 controller

# 由 plugin.gd 注入
var plugin: EditorPlugin
var activity_panel: Control

# 业务后端
var _controller: DockController = null

# UI 节点引用
@onready var message_list: VBoxContainer = %MessageList
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var input_field: TextEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var stop_button: Button = %StopButton
@onready var settings_button: Button = %SettingsButton
@onready var clear_button: Button = %ClearButton
@onready var compact_button: Button = %CompactButton
@onready var session_button: Button = %SessionButton
@onready var session_popup: PopupPanel = %SessionPopup
@onready var session_list: ItemList = %SessionList
@onready var new_button: Button = %NewButton
@onready var switch_button: Button = %SwitchButton
@onready var rename_button: Button = %RenameButton
@onready var fork_button: Button = %ForkButton
@onready var delete_button: Button = %DeleteButton
@onready var close_button: Button = %CloseButton
@onready var search_field: LineEdit = %SearchField
@onready var title_label: Label = %TitleLabel
@onready var context_label: Label = %ContextLabel

# UI 内部状态
var _stream_node: RichTextLabel = null
var _stream_content: String = ""
var _round_tool_results: Array = []
var _progress_node: RichTextLabel = null
var _session_store: SessionStore = null  # UI 需要它来读 session 列表展示
var _tool_nodes: Dictionary = {}  # tool_name → RichTextLabel, 流式工具反馈


func _ready() -> void:
	# 1. 业务后端
	_controller = DockController.new()
	_controller.setup(plugin, activity_panel, self)
	_session_store = SessionStore.new()  # UI 自己也持一份，只用来列 / 查 session 元数据
	# 2. 订阅 controller signal
	_controller.stream_started.connect(_on_stream_started)
	_controller.stream_chunk.connect(_on_stream_chunk)
	_controller.round_complete.connect(_on_round_complete)
	_controller.stream_error.connect(_on_stream_error)
	_controller.progress_remaining.connect(_on_progress_remaining)
	_controller.progress_done.connect(_on_progress_done)
	_controller.config_changed.connect(_on_config_changed)
	_controller.session_changed.connect(_on_session_changed)
	_controller.tool_started.connect(_on_tool_started)
	_controller.tool_finished.connect(_on_tool_finished)

	# 3. 按钮绑定 → 转发给 controller / UI 自身
	send_button.pressed.connect(_on_send_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	compact_button.pressed.connect(_on_compact_pressed)
	session_button.pressed.connect(_on_session_pressed)
	new_button.pressed.connect(_on_new_session_pressed)
	switch_button.pressed.connect(_on_switch_session_pressed)
	rename_button.pressed.connect(_on_rename_session_pressed)
	fork_button.pressed.connect(_on_fork_session_pressed)
	delete_button.pressed.connect(_on_delete_session_pressed)
	close_button.pressed.connect(session_popup.hide)
	session_list.item_activated.connect(_on_session_item_activated)
	search_field.text_changed.connect(_on_session_search_changed)
	input_field.gui_input.connect(_on_input_gui_input)

	# 4. 启动
	_apply_locale()
	_refresh_title()
	_update_context_label()
	_controller.bootstrap_session()

	if not _controller.get_config_manager().is_configured():
		_append_assistant_node(Locale.t("Please configure API in Settings first (Base URL / Key / Model)."))


# ============ Controller signal 订阅 ============

func _on_stream_started() -> void:
	_stream_node = _append_message_node("assistant", "", true)
	_stream_content = ""
	_round_tool_results = []
	_tool_nodes.clear()  # 新轮次清掉上一轮的工具节点


func _on_stream_chunk(chunk: String) -> void:
	if _stream_node and is_instance_valid(_stream_node):
		_stream_content += chunk
		_stream_node.text = _stream_content
		_scroll_to_bottom()


func _on_round_complete(content: String, tool_calls: Array, tool_results: Array) -> void:
	_finalize_stream_node(_stream_node, tool_calls, tool_results)
	_stream_node = null
	_stream_content = ""
	_round_tool_results = []
	_set_running(false)
	_update_context_label()


func _on_stream_error(error: String) -> void:
	_append_assistant_node("❌ " + Locale.t("LLM error") + ": " + error)
	if _stream_node and is_instance_valid(_stream_node):
		_stream_node.queue_free()
		_stream_node = null
	_set_running(false)


func _on_progress_remaining(remaining: float) -> void:
	if _progress_node == null or not is_instance_valid(_progress_node):
		_progress_node = RichTextLabel.new()
		_progress_node.bbcode_enabled = true
		_progress_node.fit_content = true
		message_list.add_child(_progress_node)
	_progress_node.clear()
	_progress_node.append_text(("[color=#888888][i]" + Locale.t("Waiting for response... %ds timeout") + "[/i][/color]") % int(remaining))
	_scroll_to_bottom()


func _on_progress_done() -> void:
	if _progress_node and is_instance_valid(_progress_node):
		_progress_node.queue_free()
		_progress_node = null


func _on_tool_started(tool_name: String) -> void:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	message_list.add_child(node)
	node.append_text("[color=#888888]⏳ %s...[/color]" % tool_name)
	_tool_nodes[tool_name] = node
	_scroll_to_bottom()


func _on_tool_finished(tool_name: String, ok: bool) -> void:
	var node: RichTextLabel = _tool_nodes.get(tool_name, null)
	if node == null or not is_instance_valid(node):
		return
	var mark := "✅" if ok else "❌"
	var color := "#88cc88" if ok else "#dd6666"
	node.clear()
	node.append_text("[color=%s]%s %s[/color]" % [color, mark, tool_name])


func _on_config_changed() -> void:
	_apply_locale()
	_refresh_title()
	_update_context_label()
	_append_assistant_node(Locale.t("Configuration saved."))


func _on_session_changed(_session_id: String, _messages: Array) -> void:
	# 重渲消息列表
	for child in message_list.get_children():
		child.queue_free()

	var i := 0
	while i < _messages.size():
		var msg: Dictionary = _messages[i]
		var role: String = msg.get("role", "?")

		if role == "system":
			i += 1
			continue

		var content = msg.get("content", "")
		if content == null:
			content = ""

		if role == "user":
			_append_user_node(content)
			i += 1

		elif role == "assistant":
			var has_tool_calls: bool = msg.has("tool_calls") and not msg["tool_calls"].is_empty()
			if not has_tool_calls:
				# 纯文本 assistant 消息 — 直接渲染
				var node := _append_message_node("assistant", "")
				node.append_text(content)
				i += 1
			else:
				# 带 tool_calls 的 assistant 消息 — 收集后续 tool 结果
				var tool_calls: Array = msg.get("tool_calls", [])
				var tool_results: Array = []

				# 扫描后续 tool 消息
				var j := i + 1
				while j < _messages.size() and _messages[j].get("role", "") == "tool":
					var tc_id: String = _messages[j].get("tool_call_id", "")
					var tc_name := _find_tool_name(tool_calls, tc_id)
					var tc_content: String = _messages[j].get("content", "")
					var ok := not tc_content.begins_with("Error") and not tc_content.begins_with("Failed")
					tool_results.append({"name": tc_name, "ok": ok})
					j += 1

				# 渲染 assistant 消息节点 + 工具结果摘要
				var node := _append_message_node("assistant", "")
				node.append_text(content)
				_append_tool_results_for_history(node, tool_results)
				i = j

		elif role == "tool":
			# 孤立 tool 消息（前面没有 assistant）— 跳过
			i += 1

		else:
			i += 1

	_refresh_title()


## 从 tool_calls 数组里按 id 找 tool name
func _find_tool_name(tool_calls: Array, call_id: String) -> String:
	for tc in tool_calls:
		if tc.get("id", "") == call_id:
			return tc.get("function", {}).get("name", "?")
	return "?"


## 为历史 session 渲染工具结果摘要（类似 _finalize_stream_node，但无"等待下一轮"文本）
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


# ============ UI 事件 → controller 转发 ============

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ENTER and not key.shift_pressed:
			input_field.release_focus()
			_on_send_pressed()
			get_viewport().set_input_as_handled()


func _on_send_pressed() -> void:
	if _controller.is_running():
		return
	var text := input_field.text.strip_edges()
	if text.is_empty():
		return
	if not _controller.get_config_manager().is_configured():
		_append_assistant_node(Locale.t("Please configure API in Settings first."))
		return
	input_field.text = ""
	_append_user_node(text)
	_set_running(true)
	await _controller.send_user_message(text)


func _on_stop_pressed() -> void:
	_controller.abort_current()
	_set_running(false)


func _on_settings_pressed() -> void:
	_controller.open_settings()


func _on_clear_pressed() -> void:
	_controller.clear_messages()
	for child in message_list.get_children():
		child.queue_free()
	# clear_messages 不会 emit session_changed,需要手动重渲 system
	_append_assistant_node("[i]" + Locale.t("— cleared —") + "[/i]")


func _on_compact_pressed() -> void:
	if _controller.is_running():
		return
	_controller.compact_context(5)
	_update_context_label()


# ============ Session UI ============

func _on_session_pressed() -> void:
	_populate_session_list("")
	session_popup.popup_centered()


func _on_session_search_changed(text: String) -> void:
	_populate_session_list(text)


func _populate_session_list(filter: String) -> void:
	session_list.clear()
	var sessions: Array
	if filter.strip_edges() == "":
		sessions = _session_store.list_sessions(50)
	else:
		sessions = _session_store.search_sessions(filter, 50)
	if sessions.is_empty():
		session_list.add_item("(no sessions yet — click New)")
		session_list.set_item_disabled(0, true)
		return
	for s in sessions:
		var id: String = s.get("id", "?")
		var name: String = s.get("name", "")
		var msgs: int = int(s.get("message_count", 0))
		var updated: String = s.get("updated_at", "")
		var short_time := updated
		if updated.length() >= 16:
			short_time = updated.substr(5, 11).replace("T", " ")
		var marker := " ● " if id == _controller.get_current_session_id() else ""
		session_list.add_item("[b]%s[/b]  %d msgs  %s%s" % [name, msgs, short_time, marker])
		var idx := session_list.item_count - 1
		session_list.set_item_metadata(idx, id)


func _on_session_item_activated(idx: int) -> void:
	var session_id: String = session_list.get_item_metadata(idx)
	if session_id.is_empty() or session_id == _controller.get_current_session_id():
		return
	_controller.switch_session(session_id)
	_populate_session_list(search_field.text)


func _on_new_session_pressed() -> void:
	_controller.new_session()
	_populate_session_list(search_field.text)


func _on_switch_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty() or session_id == _controller.get_current_session_id():
		return
	_controller.switch_session(session_id)
	_populate_session_list(search_field.text)


func _on_rename_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var info := _session_store.get_session(session_id)
	var current_name: String = info.get("name", session_id)
	_show_rename_dialog(session_id, current_name)


func _show_rename_dialog(session_id: String, current_name: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Rename session"
	dlg.dialog_text = "New name:"
	var edit := LineEdit.new()
	edit.text = current_name
	edit.custom_minimum_size = Vector2(300, 0)
	dlg.add_child(edit)
	dlg.confirmed.connect(func():
		var new_name := edit.text.strip_edges()
		if new_name != "" and new_name != current_name:
			_controller.rename_session(session_id, new_name)
			_populate_session_list(search_field.text)
			_refresh_title()
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered()


func _on_fork_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var new_id: String = _controller.fork_session(session_id)
	if new_id != "":
		_populate_session_list(search_field.text)


func _on_delete_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete session?"
	dlg.dialog_text = "Delete session %s?\nThis cannot be undone." % session_id
	dlg.confirmed.connect(func():
		_controller.delete_session(session_id)
		_populate_session_list(search_field.text)
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered()


# ============ 消息节点渲染 ============

func _now_str() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]


func _append_message_node(role: String, content: String, streaming: bool = false) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = true
	node.selection_enabled = true
	node.custom_minimum_size = Vector2(0, 24)
	message_list.add_child(node)
	_format_message(node, role, content)
	_scroll_to_bottom()
	return node


func _append_user_node(content: String) -> void:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	message_list.add_child(node)
	node.append_text("[b][color=#7eb6ff]You[/color][/b] [color=#666666][i]%s[/i][/color]\n" % _now_str())
	node.append_text(content)
	_scroll_to_bottom()


func _append_assistant_node(content: String) -> void:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	message_list.add_child(node)
	node.append_text("[b][color=#a8d977]AI[/color][/b] [color=#666666][i]%s[/i][/color]\n" % _now_str())
	node.append_text(content)
	_scroll_to_bottom()


func _format_message(node: RichTextLabel, role: String, content: String) -> void:
	match role:
		"system":
			node.append_text("[i][color=#888888]system[/color][/i]\n")
			node.append_text(content)
		"user":
			node.append_text("[b][color=#7eb6ff]You[/color][/b] [color=#666666][i]%s[/i][/color]\n" % _now_str())
			node.append_text(content)
		"assistant":
			node.append_text("[b][color=#a8d977]AI[/color][/b] [color=#666666][i]%s[/i][/color]\n" % _now_str())
			node.append_text(content)
		_:
			node.append_text("[b]%s[/b]\n" % role)
			node.append_text(content)


func _finalize_stream_node(node: RichTextLabel, tool_calls: Array, tool_results: Array = []) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.append_text("\n")
	if tool_calls.is_empty():
		node.append_text(("[color=#88aa88][i]" + Locale.t("— done —") + " %s[/i][/color]") % _now_str())
		return
	var ok_count := 0
	var err_count := 0
	for r in tool_results:
		if r.get("ok", true):
			ok_count += 1
		else:
			err_count += 1
	if err_count > 0:
		node.append_text(("[color=#ddaa66][i]" + Locale.t("— Round done: %d ok, %d failed —") + "[/i][/color]\n") % [ok_count, err_count])
	else:
		node.append_text(("[color=#88aa88][i]" + Locale.t("— Round done: %d tools all ok —") + "[/i][/color]\n") % ok_count)
	for r in tool_results:
		var mark := "✅" if r.get("ok", true) else "❌"
		var color := "#88cc88" if r.get("ok", true) else "#dd6666"
		node.append_text("[color=%s]  %s %s[/color]\n" % [color, mark, r.get("name", "?")])
	node.append_text("[color=#666666][i]⏳ 等待下一轮 —[/i][/color]")


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if message_scroll:
		message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)

# ============ 工具方法 ============

func _set_running(running: bool) -> void:
	send_button.disabled = running
	input_field.editable = not running
	stop_button.disabled = not running


func _refresh_title() -> void:
	var model: String = _controller.get_config_manager().get_model()
	if model.is_empty():
		model = Locale.t("(not configured)")
	title_label.text = model


func _apply_locale() -> void:
	Locale.set_lang(_controller.get_config_manager().get_language())
	_set_text(%SessionButton, Locale.t("Sessions"))
	_set_text(%ClearButton, Locale.t("Clear"))
	_set_text(%CompactButton, Locale.t("Compact"))
	_set_text(%SettingsButton, Locale.t("Settings"))
	_set_text(%SendButton, Locale.t("Send"))
	_set_text(%StopButton, Locale.t("Stop"))
	_set_text(%NewButton, Locale.t("New"))
	_set_text(%SwitchButton, Locale.t("Switch"))
	_set_text(%RenameButton, Locale.t("Rename"))
	_set_text(%ForkButton, Locale.t("Fork"))
	_set_text(%DeleteButton, Locale.t("Delete"))
	_set_text(%CloseButton, Locale.t("Close"))
	_set_placeholder(%SearchField, Locale.t("search…"))
	_set_placeholder(%InputField, Locale.t("Ask AI to do something... (Enter to send, Shift+Enter for newline)"))
	if context_label:
		context_label.text = ""


func _set_text(node: Node, text: String) -> void:
	if node and node is Button:
		node.text = text


func _set_placeholder(node: Node, text: String) -> void:
	if node and (node is LineEdit or node is TextEdit):
		node.placeholder_text = text


func _update_context_label() -> void:
	if context_label == null or not is_instance_valid(context_label):
		return
	var stats := _controller.estimate_context_usage()
	var used_k: int = stats.get("used_k", 0)
	var max_k: int = stats.get("max_k", 128)
	var pct: int = stats.get("pct", 0)
	if used_k == 0:
		context_label.text = ""
		return
	var color := Color(0.5, 0.85, 0.5)
	if pct > 50:
		color = Color(0.95, 0.45, 0.45)
	elif pct > 25:
		color = Color(0.95, 0.65, 0.2)
	context_label.text = "📊 %dK / %dK (%d%%)" % [used_k, max_k, pct]
	context_label.add_theme_color_override("font_color", color)


## 兼容旧 API:plugin.gd 仍可能调 dock.on_config_saved
func on_config_saved() -> void:
	_controller.on_config_saved()
