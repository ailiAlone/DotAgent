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
## ReAct 循环真正结束（区别于 round_complete 可能触发 retry）
signal loop_finished()


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
var _skill_manager: SkillManager = null
var _active_skill_content: String = ""
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
	host_node.add_child(_llm_client)
	_tool_registry = ToolRegistry.new()
	_logger = SessionLog.instance()
	_session_store = SessionStore.new()
	_skill_manager = SkillManager.new()

	_llm_client.tool_registry = _tool_registry
	_tool_client_setup()

	_llm_client.chunk_received.connect(_on_stream_chunk)
	_llm_client.stream_finished.connect(_on_stream_finished)
	_llm_client.stream_error.connect(_on_stream_error)
	_llm_client.progress_remaining.connect(_on_progress_remaining)
	_llm_client.progress_done.connect(_on_progress_done)

	_register_tools()
	_messages.append({"role": "system", "content": _system_prompt_with_model()})


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

	# Auto-match skills based on user message, inject into system prompt
	_active_skill_content = _skill_manager.match(text)
	if not _active_skill_content.is_empty():
		_logger.append("SKILL", "Matched skills, injecting %d chars" % _active_skill_content.length())

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
	_messages.append({"role": "system", "content": _system_prompt_with_model()})
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
	_messages.append({"role": "system", "content": _system_prompt_with_model()})
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
	_messages.append({"role": "system", "content": _system_prompt_with_model()})

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
	# Session 加载时检查消息量，过多则压缩存储（不影响发送——发送走 _build_send_messages）
	if _messages.size() > 50:
		var before := _messages.size()
		compact_context(3)
		_logger.warn("Auto-compacted on session load: %d → %d msgs" % [before, _messages.size()])
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


## 构建发送给 LLM 的压缩消息列表。
## 与 _messages（完整历史）不同，此方法按三层策略压缩：
##   L1（全量）: 最后 2 轮 — user + assistant + tool_calls + tool_results 原样保留
##   L2（纯文本）: 前 4 轮 — 只保留 user 文本 + assistant 文本（丢弃 tool_calls/results）
##   L3（仅提问）: 再前 6 轮 — 只保留 user 消息
##   更早的: 丢弃
## 目标：无论对话多久，发送量控制在 ~30KB 以内。
func _build_send_messages() -> Array:
	var result: Array = []

	# 1. System prompt
	for msg in _messages:
		if msg.get("role") == "system":
			result.push_front(msg)
			break

	# 2. 从后往前找 user 消息，标记每一轮的起点
	var user_positions: Array = []  # 每个 user 消息在 _messages 中的 index
	for idx in range(_messages.size() - 1, -1, -1):
		if _messages[idx].get("role") == "user":
			user_positions.push_front(idx)

	if user_positions.is_empty():
		return result

	# 3. 分三层收集
	var seen_indices: Dictionary = {}  # 避免重复

	# L1: 最后 1 轮全量
	var l1_rounds := min(1, user_positions.size())
	for r in range(l1_rounds):
		var uidx: int = user_positions[user_positions.size() - 1 - r]
		_collect_round_full(result, uidx, seen_indices)

	# L2: 前 4 轮纯文本
	var l2_start: int = max(0, user_positions.size() - l1_rounds - 4)
	var l2_end: int = user_positions.size() - l1_rounds
	for r in range(l2_start, l2_end):
		var uidx: int = user_positions[r]
		_collect_round_text_only(result, uidx, seen_indices)

	# L3: 再前 6 轮只保留 user 消息
	var l3_start: int = max(0, l2_start - 6)
	for r in range(l3_start, l2_start):
		var uidx: int = user_positions[r]
		if not seen_indices.has(uidx):
			var umsg: Dictionary = _messages[uidx]
			result.append({"role": "user", "content": _summarize_tool_content(umsg)})
			seen_indices[uidx] = true

	_logger.append("LLM", "Send messages: %d (from %d total, L1=%d L2=%d L3=%d)" % [result.size(), _messages.size(), l1_rounds, l2_end - l2_start, l2_start - l3_start])
	return result


## 收集一轮的完整消息（user → assistant → tool results）
func _collect_round_full(result: Array, user_idx: int, seen: Dictionary) -> void:
	var i := user_idx
	var umsg: Dictionary = _messages[i]
	result.append({"role": "user", "content": _summarize_tool_content(umsg)})
	seen[i] = true
	i += 1
	while i < _messages.size():
		var role: String = _messages[i].get("role", "")
		if role == "user":
			break  # 下一轮开始了
		if seen.has(i):
			i += 1
			continue
		var msg: Dictionary = _messages[i]
		if role == "assistant":
			result.append(msg.duplicate(true))
		elif role == "tool":
			# 截断超长 tool 结果
			var tc: Dictionary = msg.duplicate(true)
			var content: String = tc.get("content", "")
			if content.length() > 1000:
				tc["content"] = content.substr(0, 1000) + "…[%d chars]" % content.length()
			result.append(tc)
		seen[i] = true
		i += 1


## 收集一轮的纯文本消息（user + assistant text，丢弃 tool_calls 和 tool results）
func _collect_round_text_only(result: Array, user_idx: int, seen: Dictionary) -> void:
	var i := user_idx
	var umsg: Dictionary = _messages[i]
	result.append({"role": "user", "content": _summarize_tool_content(umsg)})
	seen[i] = true
	i += 1
	while i < _messages.size():
		var role: String = _messages[i].get("role", "")
		if role == "user":
			break
		if seen.has(i):
			i += 1
			continue
		if role == "assistant":
			var content = _messages[i].get("content", "")
			if content != null and str(content) != "":
				# 只保留纯文本，显示截断标记
				var text: String = str(content)
				if text.length() > 500:
					text = text.substr(0, 500) + "…"
				result.append({"role": "assistant", "content": text})
		# tool 消息直接跳过
		seen[i] = true
		i += 1


## 如果 user 消息包含大量 tool 输出引用（图片注入等），截断处理
func _summarize_tool_content(msg: Dictionary) -> String:
	var content = msg.get("content", "")
	if content == null:
		return ""
	var text: String = str(content)
	if text.length() > 3000:
		text = text.substr(0, 3000) + "…[user message truncated]"
	return text


## 压缩 _messages 存储（保留 system + 最后 N 轮用户问答）。
## 只在 session 加载/保存时用于控制存储大小，不影响发送（发送走 _build_send_messages）。
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

		# 构建压缩发送消息（非完整历史），然后调 LLM
		var send_msgs := _build_send_messages()
		var tools_def := _tool_registry.get_tool_definitions()
		var err: int = _llm_client.chat_stream(send_msgs, tools_def)
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
			_messages.append({
				"role": "assistant",
				"content": _stream_content if _stream_content != "" else null,
				"tool_calls": _pending_tool_calls.duplicate(true),
			})
			await _execute_tool_round()
			# 稳定延迟
			await Engine.get_main_loop().create_timer(0.3).timeout
			round_complete.emit(_stream_content, _pending_tool_calls.duplicate(true), _round_tool_results.duplicate(true))
			continue
		else:
			# 无 tool call，纯文本
			if _stream_content != "":
				_messages.append({"role": "assistant", "content": _stream_content})
			round_complete.emit(_stream_content, [], [])

			# 如果有待处理的图片（analyze_image 留下的），注入并继续，不退出
			if _has_pending_image():
				if _inject_pending_image():
					continue
			break

	_running = false
	loop_finished.emit()
	progress_done.emit()
	_logger.append("SESSION", "Loop finished. total_messages=%d" % _messages.size())
	_logger.end_session(_messages, {"session_id": _current_session_id})
	_save_current_session()
	# 循环结束后统一刷新文件系统（之前工具写操作都跳过了 _refresh_filesystem）
	_deferred_filesystem_refresh()


## 循环结束后的统一文件系统刷新。延迟 0.5s 执行，确保所有文件变更已落盘。
func _deferred_filesystem_refresh() -> void:
	if plugin == null:
		return
	var ei = plugin.get_editor_interface()
	if ei == null:
		return
	var fs = ei.get_resource_filesystem()
	if fs == null:
		return
	# 延迟一帧再 scan，避免与编辑器自身文件监控冲突
	await Engine.get_main_loop().create_timer(0.5).timeout
	fs.scan()
	_logger.append("LLM", "Deferred filesystem scan complete")


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


## 检测本轮是否全是只读工具。连续只读 ≥2 轮则强制注入写操作提醒。
## Check for pending image marker and inject as user message with image attachment.
## Returns true if an image was injected and the loop should continue.
func _has_pending_image() -> bool:
	const marker_path := "res://.dotagent_pending_image.json"
	return FileAccess.file_exists(marker_path)


func _inject_pending_image() -> bool:
	const marker_path := "res://.dotagent_pending_image.json"
	if not FileAccess.file_exists(marker_path):
		return false
	var f := FileAccess.open(marker_path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(marker_path))

	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var marker: Dictionary = json.data
	var path: String = marker.get("path", "")
	var question: String = marker.get("question", "")
	if path.is_empty():
		return false

	_messages.append({
		"role": "user",
		"content": question,
		"images": [path],
	})
	_logger.append("IMAGE", "Injected image: %s" % path.get_file())
	return true


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

func _system_prompt_with_model() -> String:
	var base := STATIC_SYSTEM_PROMPT + "\n\n当前模型: " + _config_manager.get_model()
	if _config_manager.get_vision_enabled():
		base += "\n🖼️ 视觉能力: 支持图片输入 — 可使用 screenshot_editor / screenshot_runtime / analyze_image"
	return base


func _update_system_with_context() -> void:
	var dynamic := _build_dynamic_context()
	var combined := _system_prompt_with_model() + "\n\n[当前上下文]\n" + dynamic
	# Inject matched skill content if any
	if not _active_skill_content.is_empty():
		combined += "\n\n[场景技能 — 开发规范]\n" + _active_skill_content
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
