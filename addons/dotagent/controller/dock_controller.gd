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

const STATIC_SYSTEM_PROMPT := """你是 Godot 编辑器 AI 助手,可以通过工具调用直接修改项目。回答语言跟随用户。

## 核心原则
- 能用工具就动手,不要只描述
- 复杂任务拆多轮,每轮完成一个小目标
- 写文件前先 `read_script` 看一下当前内容(但如果 prompt 已给你完整目标内容,直接覆盖)
- **写操作自动备份**:`update_script` / `update` 类工具会先把原文件备份到 `res://.dotagent_backups/<时间戳>/<原路径>`,放心覆盖

## EditorInterface 陷阱
- `execute_gdscript` 拿不到 EditorInterface 单例 — RefCounted wrapper 不行
- 切场景用 `open_scene` 工具,不要用 `execute_gdscript` 调 EditorInterface
- `execute_gdscript` 里要访问 EditorInterface,直接用 `ei.xxx`,**不要**用 `EditorInterface.xxx`(那是类型)或 `get_editor_interface()`(拿不到)

## 避免 context 爆炸
- **不要 read 整个 log 文件**(`res://logs/.../conversation.md` 等)— 几万个字符,会撑爆 context 触发超时
- **不要无脑 `list_files("res://")` 看全树** — 路径多时上百条,浪费 token。用 pattern(`.gd`、`.tscn`)或限定 directory
- `read_resource_as_text` 默认只返 2000 字符,够用就别手动加大 max_chars
- 调 `execute_gdscript` / `open_scene` / `run_scene_capture` 前先看工具 description 的 parameters,别瞎试参数名

## 路径
- `res://...` 相对项目根
- 节点路径相对当前编辑场景的根

## 构建/修复场景最佳实践
1. **创建新场景第一步：调 `create_scene` 工具**（工具名就叫 create_scene，不是 create_scene_file 也不是 create_script）。指定 path="res://xxx.tscn" + root_type="Control"，编辑器立刻显示空场景。然后逐节点 `add_node` 构建。用户实时看到变化。
2. **绝不要用 `execute_gdscript` + `FileAccess` 手写 .tscn** — 那是 6 轮工具调用、UID 猜测、字符串转义的低效做法，编辑器要等文件系统重扫才显示，不实时。如果你发现自己在写 `[gd_scene load_steps=` 字符串，立刻停下来用 create_scene。
3. **构建场景用 `add_node` 工具**,不要用 `execute_gdscript` PackedScene.pack(后者经常丢 unique_name / 不保存)
4. **节点要给脚本用 `%` 访问,加时设 `unique_name=true`** — 例:`add_node(parent="...", type="Button", name="BackButton", unique_name=true)`
5. **"Node not found" 错误**先 `read_resource_as_text` 读 .tscn 实际内容,知道场景有什么再补
6. **不要暴力删 .tscn / .gd 文件** — 先确认内容,通常问题在节点没建,不是文件坏了
7. **list_files 的 pattern 是 glob**:`*.gd` / `settings.*` / `*.tscn` 都支持,`*` 任意字符,`?` 单字符

## 调试场景工作流(用户说"跑一下看看"或场景可能有错时)
1. 调 `run_scene_capture(scene_path, frames)` headless 跑 + 抓 stdout
2. 拿错误后调 `read_script` / `search_in_scripts` 找问题
3. 调 `create_script` / `update_script` 修复
4. 再 `run_scene_capture` 验证(可能几次迭代)
- **不要用 `run_current_scene`**(EditorInterface.play 真跑 F5,不自动停,没 stdout 抓)
- `run_scene_capture` 是 autonomous 修错的关键"""


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
			# 执行每个工具
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
				_round_tool_results.append({
					"name": tc_name,
					"ok": ok,
				})
				_messages.append({
					"role": "tool",
					"tool_call_id": tc_id,
					"content": result.get("content", ""),
				})
			# emit round_complete,继续下一轮
			round_complete.emit(_stream_content, _pending_tool_calls.duplicate(true), _round_tool_results.duplicate(true))
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
		var script := load(path)
		if script == null:
			push_warning("Failed to load tool module: %s" % path)
			continue
		if not script.has_method("new"):
			push_warning("Loaded module is not instantiable (parse error?): %s" % path)
			continue
		var mod: Object = script.new()
		_tool_registry.register_module(mod)


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
