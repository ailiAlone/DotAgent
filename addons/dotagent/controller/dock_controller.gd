@tool
class_name DockController
extends RefCounted
## 后端业务逻辑层(纯 RefCounted,无 UI 依赖)
##
## 职责:依赖注入、UI 门面、Session 门面、ReAct 编排、工具注册、上下文管理。
## Session 管理拆分到 SessionManager, ReAct 循环拆分到 Reactor。

# ============ Signals(给 UI / harness 订阅) ============

signal stream_started()
signal stream_chunk(chunk: String)
signal round_complete(content: String, tool_calls: Array, tool_results: Array)
signal stream_error(error: String)
signal progress_remaining(seconds: float)
signal progress_done()
signal config_changed()
signal session_changed(session_id: String, messages: Array)
signal tool_started(tool_name: String)
signal tool_finished(tool_name: String, ok: bool)
signal loop_finished()

# ============ Constants ============

const STATIC_SYSTEM_PROMPT = SystemPrompt.PROMPT
const SessionManagerScript := preload("res://addons/dotagent/session/session_manager.gd")
const ReactorScript := preload("res://addons/dotagent/core/reactor.gd")

# ============ 注入的依赖 ============

var plugin: Object = null
var activity_panel: Object = null
var host_node: Node = null

# ============ 内部状态 ============

var _config_manager: ConfigManager = null
var _tool_registry: ToolRegistry = null
var _logger: SessionLog = null
var _skill_manager: SkillManager = null
var _context_builder: ContextBuilder = null
var _session_manager: SessionManagerScript = null
var _reactor: ReactorScript = null
var _session_memory: SessionMemory = null

var _active_skill_content: String = ""
var _current_session_id: String = ""
var _messages: Array[Dictionary] = []


# ============ Setup ============

func setup(p_plugin: Object, p_activity_panel: Object, p_host_node: Node) -> void:
	plugin = p_plugin
	activity_panel = p_activity_panel
	host_node = p_host_node

	_config_manager = ConfigManager.instance()
	_tool_registry = ToolRegistry.new()
	_logger = SessionLog.instance()
	_skill_manager = SkillManager.new()
	_session_memory = SessionMemory.new()

	_context_builder = ContextBuilder.new()
	_context_builder.setup(plugin, _messages, _config_manager, _tool_registry, STATIC_SYSTEM_PROMPT)

	_session_manager = SessionManagerScript.new()
	_session_manager.setup(_logger)
	_session_manager.session_changed.connect(_on_session_manager_changed)
	_session_manager.config_changed.connect(func(): config_changed.emit())

	_reactor = ReactorScript.new()
	_reactor.setup(plugin, _messages, _logger, _context_builder, _tool_registry, host_node)
	# 转发 Reactor signal → DockController signal(UI 仍订阅 controller)
	_reactor.stream_started.connect(func(): stream_started.emit())
	_reactor.stream_chunk.connect(func(c): stream_chunk.emit(c))
	_reactor.round_complete.connect(func(c, tc, tr): round_complete.emit(c, tc, tr))
	_reactor.stream_error.connect(func(e): stream_error.emit(e))
	_reactor.progress_remaining.connect(func(s): progress_remaining.emit(s))
	_reactor.progress_done.connect(func(): progress_done.emit())
	_reactor.tool_started.connect(func(t): tool_started.emit(t))
	_reactor.tool_finished.connect(func(t, o): tool_finished.emit(t, o))
	_reactor.loop_finished.connect(func(): loop_finished.emit())

	_tool_client_setup()
	_register_tools()
	_messages.append({"role": "system", "content": _context_builder._system_prompt_with_model()})


func _tool_client_setup() -> void:
	_tool_registry.set_editor_context(plugin, activity_panel)


# ============ Public API(给 UI / harness 调用) ============

func bootstrap_session() -> void:
	var system_prompt := _system_prompt_with_model()
	_messages = _session_manager.bootstrap(system_prompt)
	_current_session_id = _session_manager.current_session_id
	# 注入当前编辑器状态，让 AI 一启动就知道发生了什么
	_inject_startup_context()


## UI "Send" 按钮 / harness 直接调:用户发消息,触发 ReAct 循环
func send_user_message(text: String) -> void:
	if _reactor.is_running():
		return
	if not _config_manager.is_configured():
		stream_error.emit("⚠️ Please configure API in Settings first (Base URL / Key / Model).")
		return
	_logger.start_session()
	_logger.set_model(_config_manager.get_model())
	_logger.append("USER", "Sent: " + text)
	_logger.record_user_message(text)

	# 🆕 压缩上一轮对话 → 摘要注入当前上下文
	if _has_prior_user_message():
		await _summarize_and_compress_previous()

	# 🆕 注入会话记忆到 system prompt
	_inject_session_memory()

	_messages.append({"role": "user", "content": text})

	# Auto-match skills based on user message, inject into system prompt
	_active_skill_content = _skill_manager.match(text)
	if not _active_skill_content.is_empty():
		_logger.append("SKILL", "Matched skills, injecting %d chars" % _active_skill_content.length())

	_context_builder.set_skill_content(_active_skill_content)
	_context_builder.resync(_messages)
	_context_builder.update_system_message()

	_session_manager.save_with_model(_current_session_id, _messages, _config_manager.get_model())
	await _reactor.run(_messages)
	_logger.end_session(_messages, {"session_id": _current_session_id})
	_session_manager.save_with_model(_current_session_id, _messages, _config_manager.get_model())


## UI "Stop" 按钮:中止当前 LLM 请求
func abort_current() -> void:
	_reactor.abort()
	progress_done.emit()


## UI "Clear" 按钮:清空 messages(保留 system prompt)
func clear_messages() -> void:
	if _reactor.is_running():
		_reactor.abort()
	_messages.clear()
	_messages.append({"role": "system", "content": _system_prompt_with_model()})
	_session_manager.save(_current_session_id, _messages)


## UI "Settings" 按钮:打开设置弹窗
func open_settings() -> void:
	if plugin and plugin.has_method("open_config_dialog"):
		plugin.open_config_dialog()


## UI "New session" 按钮 / harness 强制新 session
func new_session() -> void:
	var system_prompt := _system_prompt_with_model()
	_messages = _session_manager.create_new(system_prompt)
	_current_session_id = _session_manager.current_session_id


## 强制建一个全新 session 并清空 messages(测试用,绕开历史脏数据)
func force_clean_session() -> String:
	var system_prompt := _system_prompt_with_model()
	_messages = _session_manager.create_clean(system_prompt)
	_current_session_id = _session_manager.current_session_id
	return _current_session_id


## UI "Switch session" 按钮
func switch_session(session_id: String, suppress_save: bool = false) -> void:
	var system_prompt := _system_prompt_with_model()
	_messages = _session_manager.switch(session_id, system_prompt, _messages, suppress_save)
	_current_session_id = _session_manager.current_session_id


## UI "Rename" 按钮
func rename_session(session_id: String, new_name: String) -> bool:
	return _session_manager.rename(session_id, new_name)


## UI "Fork" 按钮
func fork_session(source_id: String) -> String:
	return _session_manager.fork(source_id)


## UI "Delete" 按钮
func delete_session(session_id: String) -> bool:
	var was_current := session_id == _current_session_id
	var ok: bool = _session_manager.delete(session_id)
	if ok and was_current:
		var system_prompt := _system_prompt_with_model()
		_messages = _session_manager.switch(_session_manager.current_session_id, system_prompt, _messages, true)
		_current_session_id = _session_manager.current_session_id
	return ok


## 设置已保存(UI 收到 config_dialog 的 config_saved 信号后调)
func on_config_saved() -> void:
	config_changed.emit()


## 暴露只读状态给 UI(harness 也可以读)
func get_messages() -> Array:
	return _messages.duplicate(true)


func get_current_session_id() -> String:
	return _current_session_id


func is_running() -> bool:
	return _reactor.is_running()


func get_config_manager() -> ConfigManager:
	return _config_manager


## 压缩 _messages 存储（保留 system + 最后 N 轮用户问答）
func compact_context(keep_exchanges: int = 5) -> Dictionary:
	var result: Dictionary = _session_manager.compact(_messages, keep_exchanges)
	_session_manager.save(_current_session_id, _messages)
	session_changed.emit(_current_session_id, _messages.duplicate(true))
	return result


## 公开的 context 估算接口（供 dock.gd 的 context_label 调用）
func estimate_context_usage() -> Dictionary:
	return _context_builder.estimate_context_usage()


# ============ 内部辅助 ============

## 检测 _messages 中是否已存在旧 user 消息
func _has_prior_user_message() -> bool:
	for msg in _messages:
		if msg.get("role", "") == "user":
			return true
	return false


## 🆕 总结上一轮对话 + 压缩消息
func _summarize_and_compress_previous() -> void:
	# 找到对话的起始位置（第一个 user 消息）
	var conv_start := -1
	for i in range(_messages.size()):
		if _messages[i].get("role") == "user":
			conv_start = i
			break
	if conv_start < 0:
		return

	# 提取对话消息并获取 user 原文
	var user_msg_text := str(_messages[conv_start].get("content", ""))
	var conv_msgs: Array = []
	for i in range(conv_start, _messages.size()):
		conv_msgs.append(_messages[i].duplicate(true))

	if conv_msgs.is_empty():
		return

	# 调用 LLM 生成摘要
	var summary := await _call_summary_llm(conv_msgs)
	if summary.is_empty():
		return

	_logger.append("MEMORY", "Summary generated: %s" % summary.substr(0, 100))
	_session_memory.add_summary(user_msg_text, summary)

	# 压缩：只保留 system 开头的信息 + 会话记忆上下文 + 重置为准备接收新消息
	_compress_for_next_conversation()


## 🆕 调用 LLM 生成对话摘要
func _call_summary_llm(conversation_messages: Array) -> String:
	var client := LLMClient.new()
	host_node.add_child(client)

	var msgs: Array = [
		{"role": "system", "content": "请用中文总结以下对话。格式：用户要求[X]，AI 做了[Y]，关键发现[Z]。不超过 150 字。不要调用工具，直接输出纯文本摘要。"},
	]
	msgs.append_array(conversation_messages)
	msgs.append({"role": "user", "content": "请总结以上对话。"})

	var result_text := ""
	var completed := false
	client.stream_finished.connect(func(content, _tc, _fr):
		result_text = content
		completed = true
	)
	client.stream_error.connect(func(_e):
		completed = true
	)
	client.chat_stream(msgs, [])
	# 等待完成，最多 15 秒
	var elapsed := 0.0
	while not completed and elapsed < 15.0:
		await Engine.get_main_loop().process_frame
		elapsed += 0.1

	client.queue_free()
	return result_text.strip_edges()


## 🆕 压缩消息数组，只保留 system + 会话记忆 + 编辑器上下文
func _compress_for_next_conversation() -> void:
	# 找到第一个 user 消息的位置（对话起点）
	var first_user := -1
	for i in range(_messages.size()):
		if _messages[i].get("role") == "user":
			first_user = i
			break
	if first_user < 0:
		return

	# 删除从第一个 user 开始的所有消息
	for _i in range(_messages.size() - first_user):
		_messages.pop_back()

	# 重建 system 消息
	_messages[0]["content"] = _context_builder._system_prompt_with_model()


## 🆕 注入会话记忆到 system 消息中
func _inject_session_memory() -> void:
	var ctx := _session_memory.get_context()
	if ctx.is_empty():
		return
	if _messages.size() > 0 and _messages[0].get("role", "") == "system":
		_messages[0]["content"] = _messages[0]["content"] + "\n\n" + ctx


# ============ Session 变更回调 ============

func _on_session_manager_changed(session_id: String, messages: Array) -> void:
	_current_session_id = session_id
	_messages.clear()
	for m in messages:
		_messages.append(m)
	session_changed.emit(session_id, _messages.duplicate(true))


# ============ 启动上下文注入 ============

func _inject_startup_context() -> void:
	if plugin == null:
		return
	var ei = plugin.get_editor_interface()
	if ei == null:
		return
	var root = ei.get_edited_scene_root()
	if root == null:
		return
	var scene_name: String = root.scene_file_path.get_file() if not root.scene_file_path.is_empty() else "(unsaved)"
	var node_count := _count_nodes(root)
	var sel = ei.get_selection().get_selected_nodes()
	var sel_info := ""
	if not sel.is_empty():
		var names: Array = []
		for n in sel:
			names.append("%s (%s)" % [n.name, n.get_class()])
		sel_info = "\n- 选中: " + ", ".join(names)
	var ctx := "- 当前打开场景: %s (%d 个节点)%s" % [scene_name, node_count, sel_info]
	_messages.append({"role": "system", "content": "[启动上下文]\n" + ctx})


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


# ============ 动态上下文注入 ============

func _system_prompt_with_model() -> String:
	return _context_builder._system_prompt_with_model()


func _update_system_with_context() -> void:
	_context_builder.set_skill_content(_active_skill_content)
	_context_builder.update_system_message()


# ============ 工具注册 ============

func _register_tools() -> void:
	for path in [
		"res://addons/dotagent/tools/scene_tools.gd",
		"res://addons/dotagent/tools/node_query_tools.gd",
		"res://addons/dotagent/tools/script_tools.gd",
		"res://addons/dotagent/tools/script_file_tools.gd",
		"res://addons/dotagent/tools/project_tools.gd",
		"res://addons/dotagent/tools/file_tools.gd",
		"res://addons/dotagent/tools/screenshot_tools.gd",
		"res://addons/dotagent/tools/exec_tools.gd",
	]:
		var res = load(path)
		if res == null:
			push_warning("Failed to load tool module: %s" % path)
			continue
		if not res.has_method("new"):
			push_warning("Loaded module is not instantiable (parse error?): %s" % path)
			continue
		var mod = _call_new(res)
		if mod == null:
			push_warning("Failed to instantiate tool module: %s" % path)
			continue
		_tool_registry.register_module(mod)


## 调用 res.new() 的包装函数 — 无类型标注彻底绕过 Godot 4.5 的静态分析
func _call_new(res) -> Object:
	return res.new()
