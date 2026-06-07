@tool
extends VBoxContainer
## AI Panel 主 Dock - 消息流 + 输入 + ReAct 循环
##
## 负责:
## - 用户输入收集
## - 消息流展示
## - ReAct 多轮工具调用循环
## - 调度 LLMClient 和 ToolRegistry
## - 触发设置弹窗、活动面板

const MAX_REACT_ITERATIONS := 10
const STATIC_SYSTEM_PROMPT := """你是 Godot 编辑器 AI 助手。你可以通过工具调用直接修改项目。
回答语言跟随用户。

## 工作风格
- 能用工具就动手,不要只描述
- 复杂任务拆成多轮,每轮完成一个清晰的小目标
- 修改前先 get_node / read_script 看一下当前状态
- 一次只调一个工具,等结果再调下一个
- 切场景(从 main_menu 到 settings 等)用 `open_scene` 工具,**不要**用 execute_gdscript 调 EditorInterface — RefCounted wrapper 拿不到 editor API
- `execute_gdscript` 的 snippet 里要访问 EditorInterface,直接用 `ei.xxx`,**不要**用 `EditorInterface.xxx`(那是类型不是实例)也不要调 `get_editor_interface()`(RefCounted wrapper 拿不到)

## 避免 context 爆炸
- **不要 read 整个 log 文件** (`res://logs/.../conversation.md` 等)— 那是历史记录,几万个字符,会撑爆 LLM context 触发 25s 超时。要查历史用 `get_debug_output` MCP 工具,或者直接看文件末尾几行
- **不要无脑 `list_files("res://")` 看全树** — 路径多时上百条,浪费 token。要查特定东西用 pattern(`.gd`、`.tscn`)或限定 directory
- `read_resource_as_text` 默认只返 2000 字符,够用就别手动加大 max_chars
- 调 execute_gdscript / open_scene / run_scene_capture 之前先看工具 description 的 parameters,别瞎试参数名(已经因为这个超时过)

## 复杂任务每轮回复格式(简单问题可省略)
每轮回复必须包含 3 段,清晰结构化:
1. **本轮目的**(1 句话):你这轮要做什么、为什么
2. **工具调用**:实际调工具
3. **本轮小结**(1-2 句):这轮做了什么、结果如何、下一步

示例:
"本轮目的: 先了解项目当前状态,看看有没有现成的菜单脚本。
[调 list_files 工具]
本轮小结: 发现 res://main_menu.gd 已存在,可以直接用。下一轮我建配套的场景。"

## 路径
- res:// 路径相对项目根
- 节点路径相对当前编辑场景的根

## 跑场景 + 修错工作流
当用户要求"跑一下看看"或"测试场景"或场景可能有错时:
1. 调 `run_scene_capture(scene_path, frames)` 跑 headless 场景 + 抓 stdout
   - 这会卡 UI 几秒(同步 OS.execute),但拿到完整错误信息
2. 拿到错误后,分析原因,调 `read_script` 读脚本、`search_in_scripts` 找引用等
3. 调 `create_script` / `update_script` 修复
4. 调 `run_scene_capture` 再次验证(可能几次迭代直到无错)
注意:不要用 `run_current_scene`(EditorInterface.play 真实跑 F5,不会自动停,没 stdout 抓)。
`run_scene_capture` 是 autonomous 修错的关键。

## 构建 / 修复场景最佳实践
1. **构建场景优先用 `add_node` 工具**,不要用 `execute_gdscript` PackedScene.pack
   - 后者经常出怪事(节点没保存、unique_name 丢失)
   - `add_node` 一次加一个,失败立刻报错
2. **节点要给脚本用 `%` 访问,加时设 `unique_name=true`**
   - 例:`add_node(parent="SettingsContainer", type="Button", name="BackButton", unique_name=true)`
3. **看到 "Node not found" 错误,先调 `read_resource_as_text` 读 .tscn 实际内容**
   - 知道场景里到底有什么节点,再决定补哪个
4. **不要暴力删 .tscn / .gd 文件** — 先确认文件内容,通常问题在节点没建,不是文件坏了
5. **调试代码用 `_echo(text)` 替代 `print(text)`**
   - `_echo` 走 _result,会进 tool result 让你看到
   - `print` 仍然工作但只到 Godot Output 面板,AI 看不到
6. **list_files 的 pattern 是 glob 风格**:`*.gd` / `settings.*` / `*.tscn` 都支持
   - 跟 shell 一样,`*` 任意字符,`?` 单字符"""

# 由 plugin.gd 注入
var plugin: EditorPlugin
var activity_panel: Control

@onready var message_list: VBoxContainer = %MessageList
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var input_field: TextEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var stop_button: Button = %StopButton
@onready var settings_button: Button = %SettingsButton
@onready var clear_button: Button = %ClearButton
@onready var activity_button: Button = %ActivityButton
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

var _config_manager: ConfigManager
var _llm_client: LLMClient
var _tool_registry: ToolRegistry
var _logger: SessionLog
var _session_store: SessionStore
var _current_session_id: String = ""  # 当前激活的 session,所有写盘都走它
var _messages: Array[Dictionary] = []
var _running: bool = false
var _abort_requested: bool = false
var _stream_node: RichTextLabel = null
var _stream_content: String = ""
var _pending_tool_calls: Array = []
var _round_tool_results: Array = []  # 本轮每个工具调用的 {name, ok}
var _progress_node: RichTextLabel = null  # 等待响应时的倒计时节点


func _ready() -> void:
	_config_manager = ConfigManager.new()
	_llm_client = LLMClient.new()
	_tool_registry = ToolRegistry.new()
	_logger = SessionLog.instance()
	_session_store = SessionStore.new()

	_llm_client.tool_registry = _tool_registry
	_llm_client.set_host(self)  # HTTPRequest 需要挂在 SceneTree 节点上
	_tool_client_setup()

	_llm_client.chunk_received.connect(_on_stream_chunk)
	_llm_client.stream_finished.connect(_on_stream_finished)
	_llm_client.stream_error.connect(_on_stream_error)
	_llm_client.progress_remaining.connect(_on_progress_remaining)
	_llm_client.progress_done.connect(_on_progress_done)

	send_button.pressed.connect(_on_send_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	activity_button.pressed.connect(_on_activity_pressed)
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

	_register_tools()

	# 更新标题显示当前 model
	_refresh_title()

	# system prompt 只放进 _messages 数组,不渲染到 UI(用户不需要看)
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})

	# 启动时自动激活最近的 session(让对话历史连续)
	_auto_resume_or_create_session()

	if not _config_manager.is_configured():
		_append_assistant_node("⚠️ Please configure API in Settings first (Base URL / Key / Model).")


func _tool_client_setup() -> void:
	# 让工具能回写活动日志和触发危险确认
	_tool_registry.set_editor_context(plugin, activity_panel)


func _register_tools() -> void:
	for path in [
		"res://addons/ai_panel/tools/scene_tools.gd",
		"res://addons/ai_panel/tools/script_tools.gd",
		"res://addons/ai_panel/tools/project_tools.gd",
		"res://addons/ai_panel/tools/exec_tools.gd",
		"res://addons/ai_panel/tools/session_tools.gd",
	]:
		var script := load(path)
		if script == null:
			push_warning("Failed to load tool module: %s" % path)
			continue
		if not script.has_method("new"):
			push_warning("Loaded module is not instantiable (parse error?): %s" % path)
			continue
		var mod: Object = script.new()
		_tool_registry.register_module(mod)


# ============ UI 事件 ============

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ENTER and not key.shift_pressed:
			input_field.release_focus()
			_on_send_pressed()
			get_viewport().set_input_as_handled()


func _on_send_pressed() -> void:
	if _running:
		return
	var text := input_field.text.strip_edges()
	if text.is_empty():
		return
	if not _config_manager.is_configured():
		_append_assistant_node("⚠️ Please configure API in Settings first.")
		return

	# 启动日志 session(可选,纯 log;session 业务走 SessionStore)
	var logger_id := _logger.start_session()
	_logger.append("USER", "Sent: " + text)

	input_field.text = ""
	_append_user_node(text)
	_messages.append({"role": "user", "content": text})
	# 立刻落盘 user message — Godot 崩了也不丢
	_save_current_session()
	_run_react_loop(logger_id)


func _on_stop_pressed() -> void:
	_abort_requested = true
	_llm_client.abort()
	_set_running(false)


func _on_settings_pressed() -> void:
	if plugin and plugin.has_method("open_config_dialog"):
		plugin.open_config_dialog()


func _on_clear_pressed() -> void:
	if _running:
		_on_stop_pressed()
	# 清理当前 messages 但保留 system prompt + 落盘
	_messages.clear()
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})
	for child in message_list.get_children():
		child.queue_free()
	_save_current_session()


func _on_activity_pressed() -> void:
	if plugin and activity_panel and is_instance_valid(activity_panel):
		# EditorPlugin 没有直接的 show API,但 make_bottom_panel_item_visible 接受 Control
		if plugin.has_method("make_bottom_panel_item_visible"):
			plugin.call("make_bottom_panel_item_visible", activity_panel)


# ============ Session 管理 ============

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
		# 简化 updated_at:2026-06-07T15:10:42 → 06-07 15:10
		var short_time := updated
		if updated.length() >= 16:
			short_time = updated.substr(5, 11).replace("T", " ")
		var marker := " ●" if id == _current_session_id else ""
		session_list.add_item("[b]%s[/b]  %d msgs  %s%s" % [name, msgs, short_time, marker])
		var idx := session_list.item_count - 1
		session_list.set_item_metadata(idx, id)


func _on_session_item_activated(idx: int) -> void:
	var session_id: String = session_list.get_item_metadata(idx)
	if session_id.is_empty() or session_id == _current_session_id:
		return
	_switch_session(session_id)


func _on_new_session_pressed() -> void:
	var info := _session_store.create_session("")
	_switch_session(info["id"], true)
	_populate_session_list(search_field.text)


func _on_switch_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty() or session_id == _current_session_id:
		return
	_switch_session(session_id)


func _on_rename_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	var info := _session_store.get_session(session_id)
	var current_name: String = info.get("name", session_id)
	# 用 AcceptDialog / LineEdit 弹输入框 — 简化:用 OS 弹一个 native prompt
	# Godot 没有原生 prompt,简单做法:把名字写到 search_field 临时让用户编辑
	# 更友好:用 ConfirmationDialog + LineEdit
	_show_rename_dialog(session_id, current_name)


func _show_rename_dialog(session_id: String, current_name: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Rename session"
	dlg.dialog_text = "New name:"
	var edit := LineEdit.new()
	edit.text = current_name
	edit.custom_minimum_size = Vector2(300, 0)
	dlg.add_child(edit)
	# AcceptDialog 默认 OK 按钮
	dlg.confirmed.connect(func():
		var new_name := edit.text.strip_edges()
		if new_name != "" and new_name != current_name:
			_session_store.rename_session(session_id, new_name)
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
	var info := _session_store.fork_session(session_id, "Fork of " + session_id)
	_switch_session(info["id"], true)
	_populate_session_list(search_field.text)


func _on_delete_session_pressed() -> void:
	var idx := session_list.get_selected_items()
	if idx.is_empty():
		return
	var session_id: String = session_list.get_item_metadata(idx[0])
	if session_id.is_empty():
		return
	# ConfirmDialog 二次确认
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete session?"
	dlg.dialog_text = "Delete session %s?\nThis cannot be undone." % session_id
	dlg.confirmed.connect(func():
		if _session_store.delete_session(session_id):
			# 如果删的是当前,自动建一个新的
			if session_id == _current_session_id:
				var info := _session_store.create_session("")
				_switch_session(info["id"], true)
			_populate_session_list(search_field.text)
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	get_tree().root.add_child(dlg)
	dlg.popup_centered()


## 切换到指定 session(把它的消息载入到 _messages + 重渲 UI)
## is_new:可选,表示这是新创建的 session(不需要提示"已加载")
func _switch_session(session_id: String, is_new: bool = false) -> void:
	# 先把当前 session 落盘(防止切换时丢失最近的 assistant 回复)
	_save_current_session()
	var msgs := _session_store.read_messages(session_id)
	# 替换 _messages:保留新的 system prompt(版本对齐)+ 加载历史 user/assistant,跳过 system/tool
	_messages.clear()
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})
	for msg in msgs:
		var role: String = msg.get("role", "?")
		if role == "system" or role == "tool":
			continue
		_messages.append(msg)
	_current_session_id = session_id
	# 重渲 UI
	for child in message_list.get_children():
		child.queue_free()
	for msg in _messages:
		var role: String = msg.get("role", "?")
		if role == "system":
			continue
		var content = msg.get("content", "")
		if content == null:
			content = ""
		if role == "user":
			_append_user_node(content)
		elif role == "assistant":
			var node := _append_message_node("assistant", "")
			node.append_text(content)
	_refresh_title()
	if is_new:
		_append_assistant_node("[i]— new session created —[/i]")
	else:
		_append_assistant_node("[i]— loaded session %s (%d messages) —[/i]" % [session_id, msgs.size()])
	session_popup.hide()


func _auto_resume_or_create_session() -> void:
	# 找最近 updated 的 session
	var sessions := _session_store.list_sessions(1)
	if sessions.is_empty():
		var info := _session_store.create_session("")
		_current_session_id = info["id"]
		_append_assistant_node("[i]— new session: %s —[/i]" % info["name"])
	else:
		_switch_session(sessions[0]["id"])


func _save_current_session() -> void:
	if _current_session_id.is_empty():
		return
	_session_store.write_messages(_current_session_id, _messages)
	# 顺便把 model 记到 session 元数据
	var info := _session_store.get_session(_current_session_id)
	if info and info.get("model", "") != _config_manager.get_model():
		info["model"] = _config_manager.get_model()
		_session_store._write_session_meta(_current_session_id, info)


func on_config_saved() -> void:
	_refresh_title()
	_append_assistant_node("✅ Configuration saved.")


# ============ ReAct 循环 ============

func _run_react_loop(session_id: String = "") -> void:
	_set_running(true)
	_abort_requested = false

	# 更新 system prompt,注入当前编辑器上下文
	_update_system_with_context()

	var round_count := 0
	for iteration in range(MAX_REACT_ITERATIONS):
		if _abort_requested:
			break

		# 准备流式输出的 RichTextLabel
		_stream_node = _append_message_node("assistant", "", true)
		_stream_content = ""
		_pending_tool_calls = []
		_round_tool_results = []
		round_count += 1

		# 调 LLM
		var tools_def := _tool_registry.get_tool_definitions()
		_llm_client.chat_stream(_messages, tools_def)

		# 等待完成
		await _llm_client.request_completed

		if _abort_requested:
			break

		# 处理响应 — assistant 消息只写一次
		# 有 tool_call:写一条 content + tool_calls 消息
		# 无 tool_call:写一条 content-only 消息
		if _pending_tool_calls.size() > 0:
			# 有 tool call
			_messages.append({
				"role": "assistant",
				"content": _stream_content if _stream_content != "" else null,
				"tool_calls": _pending_tool_calls.duplicate(true),
			})

			# 执行每个工具,记录结果
			for tc in _pending_tool_calls:
				if _abort_requested:
					break
				var tc_id: String = tc.get("id", "")
				var tc_name: String = tc.get("function", {}).get("name", "")
				var tc_args_raw: String = tc.get("function", {}).get("arguments", "{}")
				var result: Dictionary = await _tool_registry.execute_tool(tc_name, tc_args_raw)
				_round_tool_results.append({
					"name": tc_name,
					"ok": result.get("ok", true),
				})
				_messages.append({
					"role": "tool",
					"tool_call_id": tc_id,
					"content": result.get("content", ""),
				})

			# 标记本轮完成,stream_node 保留显示
			_finalize_stream_node(_stream_node, _pending_tool_calls, _round_tool_results)
			_stream_node = null  # 下一轮会建新的

			# 继续下一轮
			continue
		else:
			# 无 tool call,纯文本回复
			if _stream_content != "":
				_messages.append({"role": "assistant", "content": _stream_content})
			_finalize_stream_node(_stream_node, [], [])
			_stream_node = null
			break

	_set_running(false)
	_stream_node = null

	# 写日志(纯 log,可选)+ 写 SessionStore(必做)
	_logger.append("SESSION", "Loop finished. total_messages=%d" % _messages.size())
	_logger.end_session(_messages, {"session_id": session_id})
	_save_current_session()


# ============ 流式回调 ============

func _on_stream_chunk(chunk: String) -> void:
	if _stream_node and is_instance_valid(_stream_node):
		_stream_content += chunk
		_stream_node.text = _stream_content
		_scroll_to_bottom()


func _on_stream_finished(content: String, tool_calls: Array) -> void:
	_stream_content = content
	_pending_tool_calls = tool_calls


func _on_stream_error(error: String) -> void:
	_append_assistant_node("❌ LLM error: " + error)
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
	_progress_node.append_text("[color=#888888][i]⏱ Waiting for response... %ds timeout[/i][/color]" % int(remaining))
	_scroll_to_bottom()


func _on_progress_done() -> void:
	if _progress_node and is_instance_valid(_progress_node):
		_progress_node.queue_free()
		_progress_node = null


# ============ 消息节点 ============

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
	node.append_text("[b][color=#7eb6ff]You[/color][/b]\n")
	node.append_text(content)
	_scroll_to_bottom()


func _append_assistant_node(content: String) -> void:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.selection_enabled = true
	message_list.add_child(node)
	node.append_text("[b][color=#a8d977]AI[/color][/b]\n")
	node.append_text(content)
	_scroll_to_bottom()


func _format_message(node: RichTextLabel, role: String, content: String) -> void:
	match role:
		"system":
			node.append_text("[i][color=#888888]system[/color][/i]\n")
			node.append_text(content)
		"user":
			node.append_text("[b][color=#7eb6ff]You[/color][/b]\n")
			node.append_text(content)
		"assistant":
			node.append_text("[b][color=#a8d977]AI[/color][/b]\n")
			node.append_text(content)
		_:
			node.append_text("[b]%s[/b]\n" % role)
			node.append_text(content)


## 在 stream_node 末尾追加完成标记 + 工具调用摘要
## 用户能区分"正在流式"和"这一轮已结束",还能看到 AI 调了啥、成功了几个、失败几个
func _finalize_stream_node(node: RichTextLabel, tool_calls: Array, tool_results: Array = []) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.append_text("\n")
	if tool_calls.is_empty():
		# 纯文本回复,标记完成
		node.append_text("[color=#88aa88][i]— done —[/i][/color]")
		return

	# 有工具调用,显示结果摘要
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
		var mark := "✓" if r.get("ok", true) else "✗"
		var color := "#88cc88" if r.get("ok", true) else "#dd6666"
		node.append_text("[color=%s]  %s %s[/color]\n" % [color, mark, r.get("name", "?")])
	node.append_text("[color=#666666][i]— 等待下一轮 —[/i][/color]")


## 在两个 round 之间插入一个细分割线 + 轮次编号
## (已废弃 — UI 拥挤,改为靠 _finalize_stream_node 里的"完成"标记区分)
func _append_round_separator(round: int) -> void:
	pass


# ============ 工具方法 ============

func _set_running(running: bool) -> void:
	_running = running
	send_button.disabled = running
	input_field.editable = not running
	stop_button.disabled = not running


func _refresh_title() -> void:
	# 标题:Agent · <model> · <session_name>
	var model := _config_manager.get_model()
	if model.is_empty():
		model = "(not configured)"
	var session_part := ""
	if not _current_session_id.is_empty():
		var info := _session_store.get_session(_current_session_id)
		var name: String = info.get("name", "")
		if name != "":
			session_part = " · " + name
	title_label.text = "Agent · " + model + session_part


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if message_scroll:
		message_scroll.scroll_vertical = int(message_scroll.get_v_scroll_bar().max_value)


# ============ 动态上下文注入 ============

func _update_system_with_context() -> void:
	# 在 _messages[0] 里把 system prompt + 动态上下文拼起来
	# 每次 LLM 请求前调用,确保 LLM 看到最新编辑器状态
	var dynamic := _build_dynamic_context()
	var combined := STATIC_SYSTEM_PROMPT + "\n\n[当前上下文]\n" + dynamic
	if _messages.size() > 0 and _messages[0].get("role", "") == "system":
		_messages[0]["content"] = combined
	else:
		_messages.push_front({"role": "system", "content": combined})


func _build_dynamic_context() -> String:
	var lines: Array = []
	if plugin == null:
		lines.append("(plugin not available)")
		return "\n".join(lines)

	var ei := plugin.get_editor_interface()
	if ei == null:
		lines.append("(EditorInterface unavailable)")
		return "\n".join(lines)

	# 当前场景
	var root := ei.get_edited_scene_root()
	if root == null:
		lines.append("- 当前场景: (未打开)")
	else:
		lines.append("- 当前场景: %s" % root.scene_file_path)
		# 简化的场景结构(只列名字 + 类型,不递归太深)
		var tree := _summarize_scene(root, 2, 0)
		lines.append("  结构:")
		lines.append(tree)

	# 选中节点
	var sel := ei.get_selection().get_selected_nodes()
	if sel.is_empty():
		lines.append("- 选中节点: (无)")
	else:
		var sel_desc: Array = []
		for n in sel:
			sel_desc.append("%s (%s)" % [n.name, n.get_class()])
		lines.append("- 选中节点: " + ", ".join(sel_desc))

	# Godot 版本
	lines.append("- Godot 版本: %s" % Engine.get_version_info().get("string", "unknown"))

	return "\n".join(lines)


func _summarize_scene(node: Node, max_depth: int, depth: int) -> String:
	if depth >= max_depth:
		return ""
	var indent := "  ".repeat(depth + 1)
	var s := "%s- %s (%s)" % [indent, node.name, node.get_class()]
	var children_strs: Array = []
	for child in node.get_children():
		var child_s := _summarize_scene(child, max_depth, depth + 1)
		if child_s != "":
			children_strs.append(child_s)
	if not children_strs.is_empty():
		s += "\n" + "\n".join(children_strs)
	return s
