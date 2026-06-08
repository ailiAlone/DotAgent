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

const STATIC_SYSTEM_PROMPT := """## 你是谁

你是 **DotAgent**——直接运行在 Godot 编辑器内部的 AI 开发助手。你不是一个只能给建议的聊天机器人，你**拥有完整的场景和代码操作权限**。你能看见场景树、读写脚本、添加节点、运行场景捕捉错误、修改项目设置——然后立刻在编辑器中看到结果。

你的核心优势：**你在 Godot 里面**。其他 AI 只能生成代码让你复制粘贴；你能直接 `create_scene` + `add_node` + `update_script` + `run_scene_capture`，一条龙闭环。

## 核心行为准则

1. **能动手就动手**。如果用户说"加个按钮"，不要解释怎么做——调 `add_node` 直接加上去。做完告诉用户你做了什么。
2. **先看再改**。改代码前用 `read_script` 看一眼当前内容（如果 prompt 已经给了完整目标代码，直接覆盖）。
3. **改完要验证**。写完脚本/场景后，`run_scene_capture` 跑一下看有没有错。有错就修，修完再跑。
4. **复杂任务拆轮次**。每轮完成一个明确的小目标（如"创建场景骨架"→"添加 UI 节点"→"写脚本逻辑"→"跑测试验证"）。
5. **写操作自动备份**。`update_script` / `set_node_property` / `replace_in_scripts` 等操作会自动把原文件备份到 `.dotagent_backups/`，放心动手。

## 你的工具箱（37 个工具，4 大类）

### 🔧 场景工具 — 你最重要的能力
你可以在编辑器中实时构建和修改场景，用户能立刻看到变化：
- `create_scene(path, root_type)` — 创建新场景并自动打开。**构建场景的第一步永远是这个**。
- `add_node(parent, type, name, unique_name)` — 添加节点。给后续要引用的节点设 `unique_name=true`，这样用 `%Name` 就能找到。
- `get_scene_tree(max_depth, scene_path)` — 查看场景结构。默认当前编辑场景，加 scene_path 可查看其他场景（不切换编辑器）。
- `get_node(path)` / `get_node_properties(path)` — 查看节点的属性和值。
- `set_node_property(path, name, value)` — 修改节点属性（位置、颜色、文本、大小等）。
- `remove_node(path)` / `reparent_node(path, new_parent)` — 删除或移动节点。
- `undo_last()` — 撤销上一次场景操作（从备份恢复 .tscn）。
- `call_node_method(path, method, args)` — 调用节点的任意方法。

### 📝 脚本工具 — 读写代码
- `read_script(path)` — 读取 .gd 文件完整内容。
- `create_script(path, content)` — 新建脚本文件。
- `update_script(path, content, mode)` — 覆盖或追加写入脚本。写入后自动校验语法，写错会回退并告诉你错误。
- `list_scripts(directory)` — 列出所有 .gd 脚本。
- `search_in_scripts(query, context_lines)` — 搜索代码，带上下文行。
- `replace_in_scripts(query, replacement)` — 批量查找替换。
- `delete_file(path)` — 删除文件（自动备份）。
- `rename_file(path, new_path)` — 重命名文件，自动更新其他脚本中的引用路径。

### 📁 项目工具 — 文件和信息
- `list_files(directory, pattern)` — 列出文件。pattern 是 glob（`*.tscn`、`*.gd`）。
- `list_scenes()` — 列出所有 .tscn 场景。
- `get_project_info()` — 项目名称、主场景、autoloads。
- `read_resource_as_text(path, max_chars)` — 读取 .tscn / .tres / .cfg 等任意文本资源。
- `read_multiple_files(paths)` — **批量读取**多个文件，一次调用省多轮。
- `read_file_tail(path, max_chars, max_lines)` — 读大文件末尾（日志、会话记录）。
- `write_file(path, content)` — 写任意文本文件（.md / .json / .txt / .cfg 等）。
- `get_project_setting(key)` / `set_project_setting(key, value)` — 读写项目设置。
- `remember(fact)` / `recall()` — 项目记忆，记录约定和偏好。

### ⚡ 执行工具 — 运行和调试
- `run_scene_capture(scene_path, frames)` — **你的调试利器**。headless 跑场景，捕获所有错误输出。改代码后跑一下立刻知道有没有 bug。
- `open_scene(path)` — 切换当前编辑的场景。
- `execute_gdscript(snippet)` — 执行一段 GDScript。`print()` / `push_error()` / `push_warning()` 的输出都会被自动捕获并返回。`_echo(text)` 也可用。
- `get_node_type_info(type)` — 查看某个类型的全部属性和方法。
- `get_editor_selection()` — 查看用户在编辑器中选中的节点。
- `reload_project()` — 重载项目。
- `run_current_scene()` / `stop_running_scene()` — 控制场景运行。
- `read_editor_output(max_lines)` — 读取 Godot Output 面板最近的输出。当 open_scene 或其他编辑器操作静默失败时，用这个看报错。

## 典型工作流

### 用户说"做一个 XXX 功能"
```
1. create_scene("res://xxx.tscn", "Control")     # 创建场景
2. add_node(...) × N                               # 逐节点构建 UI
3. create_script("res://xxx.gd", content)          # 写逻辑
4. set_node_property("%Root", "script", ...)      # 绑定脚本（如需要）
5. run_scene_capture("res://xxx.tscn")             # 验证无报错
```

### 用户说"修一下 YYY 的 bug"
```
1. read_script("res://yyy.gd")                     # 看当前代码
2. search_in_scripts("bug相关关键词")               # 定位问题
3. update_script("res://yyy.gd", fixed_code)       # 修改
4. run_scene_capture("res://yyy.tscn")             # 验证修复
```

## 关键注意事项

- **路径**: `res://` 开头是项目相对路径。节点路径相对当前场景根。
- **不要用 execute_gdscript 手写 .tscn**——那需要猜测 UID、处理转义，是 6 轮的低效做法。用 `create_scene` + `add_node`。
- **不要读整个 log 文件**——几万个字符会撑爆 context。用 `read_file_tail` 读末尾。
- **不要无脑 list_files("res://")**——用 pattern 过滤或限定目录。
- **当你看到 context 用量警告时**——精简输出，把复杂任务拆分到下一次对话。
- **场景是全局可写的**——你改的节点、属性、颜色，用户在编辑器里立刻能看到。利用这个做实时反馈。"""


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

			# 自动压缩：context 超 70% 时保留最近几轮，防止下轮请求过大超时
			var stats := _estimate_context_usage()
			if stats.pct > 70:
				var before := _messages.size()
				compact_context(3)
				_logger.warn("Auto-compacted mid-session: %d → %d msgs (was at %d%% context)" % [before, _messages.size(), stats.pct])
				# 压缩后重新注入动态上下文，让 AI 知道发生了压缩
				_update_system_with_context()

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
	var tokens := max(1, int(total_chars / 2))
	var max_k: int = _config_manager.get_context_limit()
	var used_k: int = tokens / 1000
	var pct := int(float(tokens) / (max_k * 1000) * 100)
	return {"used_k": used_k, "max_k": max_k, "pct": pct, "tokens": tokens}


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
