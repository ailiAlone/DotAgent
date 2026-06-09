@tool
class_name DockController
extends RefCounted
## 后端业务逻辑层(纯 RefCounted,无 UI 依赖)
##
## 这是 dock 的"后端":消息、ReAct 循环、LLM 客户端、工具注册、session 存储。
## 任何 UI(dock.gd / 测试 harness)都可以驱动这个 controller 跑业务逻辑。
##
## 关键约束:
## - **无 UI 节点引用**(无 RichTextLabel / Button / Container)
## - **可被 headless harness 直接实例化**跑 ReAct 循环
## - **所有 UI 副作用走 signal**:stream_started / stream_chunk / round_complete /
##   stream_error / progress_remaining / progress_done / config_changed / session_changed
## - **plugin 和 activity_panel 注入**,可被 stub 替换

# ============ Signals(给 UI / harness 订阅) ============

## 一轮新的流式输出开始(LLM 正在响应)。UI 应创建一个新的 stream 节点。
signal stream_started()
## 流式 chunk 到达(可能是字符、子词或 SSE 合并段)
signal stream_chunk(chunk: String)
## 一轮完成(content 累计完,tool_calls 解析完,tool_results 拿回)
## content 可能是 ""(LLM 决定不说话直接调工具)
## tool_calls 是 OpenAI 格式 [{id, type, function:{name, arguments}}]
## tool_results 是 [{name, ok}],无 tool call 时为空数组
signal round_complete(content: String, tool_calls: Array, tool_results: Array)
## LLM 出错(网络、watchdog、HTTP 错误)
signal stream_error(error: String)
## watchdog 倒计时(每秒一次,剩余秒数)
signal progress_remaining(seconds: float)
## watchdog 结束(成功/失败/取消都 emit)
signal progress_done()
## 配置已变更(供 UI 刷标题、显示提示)
signal config_changed()
## session 切换或新建(messages 已替换,UI 应重渲)
signal session_changed(session_id: String, messages: Array)
## 单个工具开始执行(流式反馈)
signal tool_started(tool_name: String)
## 单个工具执行完成
signal tool_finished(tool_name: String, ok: bool)


# ============ Constants ============

const STATIC_SYSTEM_PROMPT = SystemPrompt.PROMPT


# ============ 注入的依赖 ============

## EditorPlugin 实例(让 controller 能拿 EditorInterface、打开设置弹窗)
## UI / harness 注入;harness 用 stub(不强制 EditorPlugin 类型,duck typing)
## 用 Object 而不是 EditorPlugin 是因为 headless 模式没法 extends EditorPlugin
var plugin: Object = null
## 活动日志面板(让 ToolRegistry 能 log tool calls / warnings)
## UI / harness 注入;harness 用 stub(duck typing)
var activity_panel: Object = null
## HTTPRequest 宿主节点(LLMClient 需要一个 SceneTree 节点)
## UI: 传 self(dock 本身就是 VBoxContainer 节点)
## Harness: 传一个手动创建并 add_child 到 root 的 Node
var host_node: Node = null


# ============ 内部状态 ============

var _config_manager: ConfigManager = null
var _llm_client: LLMClient = null
var _tool_registry: ToolRegistry = null
var _logger: SessionLog = null
var _session_store: SessionStore = null
var _current_session_id: String = ""
var _messages: Array[Dictionary] = []
var _running: bool = false
var _abort_requested: bool = false

# 流式内部状态(本轮)
var _stream_content: String = ""
var _pending_tool_calls: Array = []
var _pending_finish_reason: String = ""  # LLM API: "stop"=结束, "tool_calls"=继续, "length"=token上限
var _round_tool_results: Array = []


# ============ Setup ============

## 注入所有依赖并初始化业务对象。
## host_node 必须在 SceneTree 里(已 add_child 且 await 了一帧)。
## p_plugin / p_activity_panel 用 Object 是为了 headless stub 也能传(duck typing)
func setup(p_plugin: Object, p_activity_panel: Object, p_host_node: Node) -> void:
	plugin = p_plugin
	activity_panel = p_activity_panel
	host_node = p_host_node

	_config_manager = ConfigManager.instance()
	_llm_client = LLMClient.new()
	_tool_registry = ToolRegistry.new()
	_logger = SessionLog.instance()
	_session_store = SessionStore.new()

	_llm_client.tool_registry = _tool_registry
	_llm_client.set_host(host_node)
	_tool_client_setup()

	_llm_client.chunk_received.connect(_on_stream_chunk)
	_llm_client.stream_finished.connect(_on_stream_finished)
	_llm_client.stream_error.connect(_on_stream_error)
	_llm_client.progress_remaining.connect(_on_progress_remaining)
	_llm_client.progress_done.connect(_on_progress_done)

	_register_tools()
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})


func _tool_client_setup() -> void:
	_tool_registry.set_editor_context(plugin, activity_panel)


# ============ Public API(给 UI / harness 调用) ============

## 启动 / 恢复 session
## 找最近 updated 的 session;没有就建一个新的
## 完成后 emit session_changed(id, messages),UI 据此重渲
func bootstrap_session() -> void:
	var sessions := _session_store.list_sessions(1)
	if sessions.is_empty():
		var info := _session_store.create_session("")
		_current_session_id = info["id"]
		session_changed.emit(_current_session_id, _messages.duplicate())
	else:
		switch_session(sessions[0]["id"], true)
	# 注入当前编辑器状态，让 AI 一启动就知道发生了什么
	_inject_startup_context()


## 注入启动时的编辑器上下文：打开的场景、选中节点等
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


## UI "Send" 按钮 / harness 直接调:用户发消息,触发 ReAct 循环
func send_user_message(text: String) -> void:
	if _running:
		return
	if not _config_manager.is_configured():
		stream_error.emit("⚠️ Please configure API in Settings first (Base URL / Key / Model).")
		return
	_logger.start_session()
	_logger.append("USER", "Sent: " + text)
	_messages.append({"role": "user", "content": text})
	_save_current_session()
	await _run_react_loop()


## UI "Stop" 按钮:中止当前 LLM 请求
func abort_current() -> void:
	_abort_requested = true
	_llm_client.abort()
	_running = false
	progress_done.emit()


## UI "Clear" 按钮:清空 messages(保留 system prompt)
func clear_messages() -> void:
	if _running:
		abort_current()
	_messages.clear()
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})
	_save_current_session()


## UI "Settings" 按钮:打开设置弹窗
func open_settings() -> void:
	if plugin and plugin.has_method("open_config_dialog"):
		plugin.open_config_dialog()


## UI "New session" 按钮 / harness 强制新 session
func new_session() -> void:
	var info := _session_store.create_session("")
	switch_session(info["id"], true)


## 强制建一个全新 session 并清空 messages(测试用,绕开历史脏数据)
## 返回新 session id
func force_clean_session() -> String:
	var info := _session_store.create_session("")
	_current_session_id = info["id"]
	_messages.clear()
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})
	_save_current_session()
	session_changed.emit(_current_session_id, _messages.duplicate())
	return _current_session_id


## UI "Switch session" 按钮
## 加载历史 session 的 messages。
## **脏数据防护**:逐段检查 assistant{tool_calls}+后续 tool 消息是否配对。
## 不完整的段(用户 Stop 或 crash 导致 tool 结果缺失)会被整段丢弃，
## 避免 LLM 看到不配对的 tool_calls 报 HTTP 400。
func switch_session(session_id: String, suppress_save: bool = false) -> void:
	if not suppress_save:
		_save_current_session()
	var msgs := _session_store.read_messages(session_id)

	# 逐段扫描，按 assistant→tool 配对处理
	_messages.clear()
	_messages.append({"role": "system", "content": STATIC_SYSTEM_PROMPT})

	var i := 0
	while i < msgs.size():
		var msg: Dictionary = msgs[i]
		var role: String = msg.get("role", "")
		if role == "system":
			i += 1
			continue

		if role == "assistant" and msg.has("tool_calls"):
			# 收集本段 assistant 声明的 tool_call_ids
			var declared_ids := {}
			for tc in msg.get("tool_calls", []):
				var tid: String = tc.get("id", "")
				if not tid.is_empty():
					declared_ids[tid] = true

			# 扫描后续 tool 消息，看哪些 tool_call_id 实际存在
			var j := i + 1
			var found_ids := {}
			while j < msgs.size() and msgs[j].get("role", "") == "tool":
				var tid: String = msgs[j].get("tool_call_id", "")
				if not tid.is_empty():
					found_ids[tid] = true
				j += 1

			# 检查：所有声明的 tool_call_id 是否都有对应 tool 结果
			var all_ok := true
			for tid in declared_ids.keys():
				if not found_ids.has(tid):
					all_ok = false
					break

			if not all_ok:
				# 脏段 — 整个 assistant+tool 段丢弃
				_logger.warn("switch_session: dropping orphan assistant segment (missing tool results)")
				i = j
				continue

			# 完整 — 保留 assistant 及其 tool 结果
			_messages.append(msg)
			i += 1
			while i < j:
				_messages.append(msgs[i])
				i += 1
		elif role == "tool":
			# 孤立 tool 消息（前面没有 assistant）→ 跳过
			_logger.warn("switch_session: skipping orphan tool message (tool_call_id=%s)" % msg.get("tool_call_id", "?"))
			i += 1
		else:
			# user / assistant(无 tool_calls) — 直接保留
			_messages.append(msg)
			i += 1

	_current_session_id = session_id
	# 自动压缩：如果消息过多（估算超 context 70%），自动精简
	var stats := _estimate_context_usage()
	if stats.pct > 70:
		var before := _messages.size()
		compact_context(max(2, int(5 * 70.0 / stats.pct)))
		_logger.warn("Auto-compacted on session load: %d → %d msgs (was at %d%% context)" % [before, _messages.size(), stats.pct])
	session_changed.emit(session_id, _messages.duplicate())


## UI "Rename" 按钮
func rename_session(session_id: String, new_name: String) -> bool:
	var ok := _session_store.rename_session(session_id, new_name)
	if ok:
		config_changed.emit()  # 复用信号,UI 刷新相关显示
	return ok


## UI "Fork" 按钮
func fork_session(source_id: String) -> String:
	var info := _session_store.fork_session(source_id, "Fork of " + source_id)
	return info.get("id", "")


## UI "Delete" 按钮
func delete_session(session_id: String) -> bool:
	var ok := _session_store.delete_session(session_id)
	# 如果删的是当前,自动建一个新的
	if ok and session_id == _current_session_id:
		var info := _session_store.create_session("")
		switch_session(info["id"], true)
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
	return _running


func get_config_manager() -> ConfigManager:
	return _config_manager


## 压缩 context：保留 system + 最后 N 轮用户问答
## 返回压缩前后的消息数
func compact_context(keep_exchanges: int = 5) -> Dictionary:
	var kept: Array[Dictionary] = []
	for msg in _messages:
		if msg.get("role") == "system":
			kept.append(msg)
			break
	var user_indices := []
	for idx in range(_messages.size() - 1, -1, -1):
		if _messages[idx].get("role") == "user":
			user_indices.append(idx)
			if user_indices.size() >= keep_exchanges:
				break
	if user_indices.is_empty():
		return {"before": _messages.size(), "after": _messages.size()}
	var start: int = user_indices[user_indices.size() - 1]
	for idx in range(start, _messages.size()):
		if _messages[idx].get("role") != "system":
			kept.append(_messages[idx])
	var before := _messages.size()
	_messages = kept
	_save_current_session()
	session_changed.emit(_current_session_id, _messages.duplicate())
	return {"before": before, "after": kept.size()}


# ============ ReAct 循环(后端核心) ============

func _run_react_loop() -> void:
	_running = true
	_abort_requested = false

	_update_system_with_context()

	while true:
		if _abort_requested:
			break

		_stream_content = ""
		_pending_tool_calls = []
		_pending_finish_reason = ""
		_round_tool_results = []

		stream_started.emit()

		# 调 LLM
		var tools_def := _tool_registry.get_tool_definitions()
		var err: int = _llm_client.chat_stream(_messages, tools_def)
		if err != OK:
			stream_error.emit("chat_stream failed: %d" % err)
			break
		await _llm_client.request_completed

		if _abort_requested:
			break

		# 处理响应 — 用 finish_reason 判断，不是 tool_calls 判空
		# LLM 可以返回文本解释思路，然后 finish_reason="tool_calls" 继续干活
		_logger.append("LLM", "finish_reason=%s tool_calls=%d" % [_pending_finish_reason, _pending_tool_calls.size()])
		if _pending_finish_reason == "tool_calls" or _pending_tool_calls.size() > 0:
			# 有 tool call
			_messages.append({
				"role": "assistant",
				"content": _stream_content if _stream_content != "" else null,
				"tool_calls": _pending_tool_calls.duplicate(true),
			})
			await _execute_tool_round()
			round_complete.emit(_stream_content, _pending_tool_calls.duplicate(true), _round_tool_results.duplicate(true))
			_maybe_auto_compact()

			continue
		else:
			# 无 tool call,纯文本
			if _stream_content != "":
				_messages.append({"role": "assistant", "content": _stream_content})
			round_complete.emit(_stream_content, [], [])
			break

	_running = false
	progress_done.emit()
	_logger.append("SESSION", "Loop finished. total_messages=%d" % _messages.size())
	_logger.end_session(_messages, {"session_id": _current_session_id})
	_save_current_session()


## Execute all pending tool calls from the current round.
## Emits tool_started/tool_finished, appends tool results to _messages.
func _execute_tool_round() -> void:
	for tc in _pending_tool_calls:
		if _abort_requested:
			break
		var tc_id: String = tc.get("id", "")
		var fn: Dictionary = tc.get("function", {})
		var tc_name: String = fn.get("name", "")
		var tc_args_raw: String = fn.get("arguments", "{}")
		tool_started.emit(tc_name)
		var result: Dictionary = await _tool_registry.execute_tool(tc_name, tc_args_raw)
		var ok: bool = result.get("ok", true)
		tool_finished.emit(tc_name, ok)
		_round_tool_results.append({"name": tc_name, "ok": ok})
		_messages.append({"role": "tool", "tool_call_id": tc_id, "content": result.get("content", "")})


## Auto-compact if context exceeds 70% — keeps last 3 exchanges, re-injects system context.
func _maybe_auto_compact() -> void:
	var stats := _estimate_context_usage()
	if stats.pct > 70:
		var before := _messages.size()
		compact_context(3)
		_logger.warn("Auto-compacted mid-session: %d → %d msgs (was at %d%% context)" % [before, _messages.size(), stats.pct])
		_update_system_with_context()


# ============ LLM 流式回调 ============

func _on_stream_chunk(chunk: String) -> void:
	_stream_content += chunk
	stream_chunk.emit(chunk)


func _on_stream_finished(content: String, tool_calls: Array, finish_reason: String) -> void:
	_stream_content = content
	_pending_tool_calls = tool_calls
	_pending_finish_reason = finish_reason


func _on_stream_error(error: String) -> void:
	stream_error.emit(error)
	_running = false


func _on_progress_remaining(seconds: float) -> void:
	progress_remaining.emit(seconds)


func _on_progress_done() -> void:
	progress_done.emit()


# ============ 工具注册 ============

func _register_tools() -> void:
	for path in [
		"res://addons/dotagent/tools/scene_tools.gd",
		"res://addons/dotagent/tools/script_tools.gd",
		"res://addons/dotagent/tools/project_tools.gd",
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


# ============ Session 持久化 ============

func _save_current_session() -> void:
	if _current_session_id.is_empty():
		return
	_session_store.write_messages(_current_session_id, _messages)
	var info := _session_store.get_session(_current_session_id)
	if info and info.get("model", "") != _config_manager.get_model():
		info["model"] = _config_manager.get_model()
		_session_store._write_session_meta(_current_session_id, info)


# ============ 动态上下文注入 ============

func _update_system_with_context() -> void:
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

	var ei = plugin.get_editor_interface()
	if ei == null:
		lines.append("(EditorInterface unavailable)")
		return "\n".join(lines)

	# 当前场景
	var root = ei.get_edited_scene_root()
	if root == null:
		lines.append("- 当前场景: (未打开)")
	else:
		lines.append("- 当前场景: %s" % root.scene_file_path)
		var tree := _summarize_scene(root, 1, 0)  # 深度 1=只列根的直接子节点，省 token
		lines.append("  结构:")
		lines.append(tree)

	# 选中节点
	var sel = ei.get_selection().get_selected_nodes()
	if sel.is_empty():
		lines.append("- 选中节点: (无)")
	else:
		var sel_desc: Array = []
		for n in sel:
			sel_desc.append("%s (%s)" % [n.name, n.get_class()])
		lines.append("- 选中节点: " + ", ".join(sel_desc))

	# Godot 版本
	lines.append("- Godot 版本: %s" % Engine.get_version_info().get("string", "unknown"))

	# Context 用量（让 AI 知道自己离上限还有多远）
	var stats := _estimate_context_usage()
	lines.append("- Context 用量: ~%dK / %dK (%d%%)" % [stats.used_k, stats.max_k, stats.pct])
	if stats.pct > 60:
		lines.append("⚠️ Context 已用 %d%%，建议本任务尽量精简输出，复杂任务拆分到下一次对话" % stats.pct)

	return "\n".join(lines)


func _estimate_context_usage() -> Dictionary:
	var total_chars := 0
	for msg in _messages:
		total_chars += str(msg.get("content", "")).length()
		for tc in msg.get("tool_calls", []):
			total_chars += str(tc.get("function", {}).get("arguments", "")).length()

	# 工具定义也占用 context（每次请求都发送完整 tools schema）
	total_chars += _count_tool_def_chars()

	var tokens := _estimate_tokens_from_chars(total_chars)
	var max_k: int = _config_manager.get_context_limit()
	var used_k: int = max(1, tokens / 1000)
	var pct := int(min(100, float(tokens) / (max_k * 1000) * 100))
	return {"used_k": used_k, "max_k": max_k, "pct": pct, "tokens": tokens}


## 按字符类型加权估算 token 数（比简单 /2 更准确）
## ASCII 约 4 字符/token，CJK 约 1.2 字符/token，平均 ≈ 2.0
func _estimate_tokens_from_chars(total_chars: int) -> int:
	# 粗略但实用的近似：假设中英混合场景约 2 字符 = 1 token
	# 更保守的估计（对中文更准）让 AI 更早看到警告
	return max(1, int(total_chars / 2.2))


## 序列化所有工具定义并返回字符数
func _count_tool_def_chars() -> int:
	if _tool_registry == null:
		return 0
	var defs := _tool_registry.get_tool_definitions()
	if defs.is_empty():
		return 0
	return JSON.stringify(defs).length()


## 公开的 context 估算接口（供 dock.gd 的 context_label 调用）
func estimate_context_usage() -> Dictionary:
	return _estimate_context_usage()


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
