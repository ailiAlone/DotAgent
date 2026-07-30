extends SceneTree
## 无头驱动一次真实 Banyan 运行（绕过 EditorPlugin UI，复刻 plugin.run_banyan 的核心装配）
##
## 运行:
##   DOTAGENT_API_KEY=... godot --headless --path . --script res://tests/run_banyan_headless.gd
##
## 任务文本可通过环境变量 BANYAN_TASK 覆盖。

const BanyanPool = preload("res://addons/dotagent/banyan_agent/http/http_client_pool.gd")
const AgentTreeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_tree.gd")
const AgentNode = preload("res://addons/dotagent/banyan_agent/tree/agent_node.gd")
const ToolRegistry = preload("res://addons/dotagent/tools/tool_registry.gd")
const SessionLog = preload("res://addons/dotagent/log/logger.gd")
const ConfigManager = preload("res://addons/dotagent/config/config_manager.gd")
const BanyanToolLoader = preload("res://addons/dotagent/banyan_agent/tools/tool_loader.gd")
const BanyanRunLogScript = preload("res://addons/dotagent/log/banyan_run_log.gd")

const DEFAULT_TASK := "读取 res://tests/README.md，总结这个测试目录的用途。不要修改任何文件。"
const IDLE_TIMEOUT_SEC := 90.0  # 空闲超时：90秒内无任何活动才 abort

var _logger = null
var _host: Node = null
var _pool = null
var _registry: ToolRegistry = null
var _agent_tree = null
var _root_node = null
var _done := false
var _failed := false
var _fail_msg := ""
var _start_msec := 0
var _last_activity_msec := 0  # 最近一次活动时间（空闲超时用）

# ============ 实时监控 ============

var _monitored: Dictionary = {}      # node instance → true（防止重复连接）
var _chunk_ticks: Dictionary = {}    # node_id → [累计字符数, 上次打印时间]
var _last_status_msec := 0           # 上次打印状态概览的时间
var _last_status_snapshot: String = ""  # 上次状态快照（去重）


func _initialize() -> void:
	call_deferred("_main")


func _process(_delta: float) -> bool:
	# 空闲看门狗：IDLE_TIMEOUT_SEC 内无任何活动才 abort
	if not _done and _last_activity_msec > 0 and float(Time.get_ticks_msec() - _last_activity_msec) / 1000.0 > IDLE_TIMEOUT_SEC:
		var idle_sec: float = float(Time.get_ticks_msec() - _last_activity_msec) / 1000.0
		print("\n[WATCHDOG] 空闲 %.0fs 无活动，强制 abort" % idle_sec)
		if _root_node:
			_root_node.abort()
		_finish_run()
	# 周期状态概览：每 30 秒打印一次所有节点的状态
	if _root_node and _start_msec > 0 and float(Time.get_ticks_msec() - _last_status_msec) / 1000.0 > 30.0:
		_last_status_msec = Time.get_ticks_msec()
		_print_tree_status()
	return _done


func _print_tree_status() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _start_msec) / 1000.0
	var idle: float = float(Time.get_ticks_msec() - _last_activity_msec) / 1000.0
	# 构建快照字符串（用于去重）
	var snapshot: String = ""
	snapshot += _build_node_snapshot(_root_node)
	if snapshot == _last_status_snapshot:
		return  # 状态无变化，跳过打印
	_last_status_snapshot = snapshot
	print("[TREE %.0fs idle=%.0fs] ─────────────────────────" % [elapsed, idle])
	_print_node_status(_root_node, 0)


func _build_node_snapshot(node: AgentNode) -> String:
	if node == null:
		return ""
	var s: String = "%s:%s:R%d " % [node.node_id, _state_name(node.node_state), node.get_round_count()]
	for cname in node._children:
		s += _build_node_snapshot(node._children[cname])
	return s


func _print_node_status(node: AgentNode, depth: int) -> void:
	if node == null:
		return
	var indent: String = "  ".repeat(depth)
	var state: String = _state_name(node.node_state)
	var rounds: int = node.get_round_count()
	var children_count: int = node._children.size()
	print("[TREE] %s%-18s [%-10s] R%d children=%d" % [indent, node.node_id, state, rounds, children_count])
	for cname in node._children:
		_print_node_status(node._children[cname], depth + 1)


func _touch_activity() -> void:
	_last_activity_msec = Time.get_ticks_msec()


func _main() -> void:
	_start_msec = Time.get_ticks_msec()
	_last_activity_msec = _start_msec
	_logger = SessionLog.instance()

	# 1. 基础设施（复刻 plugin._init_shared + _init_banyan）
	_host = Node.new()
	_host.name = "DotAgentHost"
	root.add_child(_host)

	_pool = BanyanPool.new(4)
	_pool.name = "BanyanPool"
	_host.add_child(_pool)

	_registry = _create_tool_registry()

	# 2. 配置
	var config: ConfigManager = ConfigManager.instance()
	var base_url: String = config.get_base_url()
	var api_key: String = config.get_api_key()
	var model: String = config.get_model()
	if base_url.is_empty() or api_key.is_empty():
		print("[FATAL] API 未配置（需要 DOTAGENT_API_KEY 环境变量）")
		_done = true
		return
	print("[SETUP] model=%s  base_url=%s" % [model, base_url])

	# 3. 工具定义 + system prompt
	var tool_loader: RefCounted = BanyanToolLoader.new(_logger)
	var node_tools: Array = tool_loader.get_tools("node")
	var prompt_text: String = _read_text("res://addons/dotagent/banyan_agent/prompts/node_prompt.md")

	# 4. 持久化树
	_agent_tree = AgentTreeScript.new(_logger)
	_agent_tree.load()
	print("[SETUP] 已有节点: %d" % _agent_tree.get_node_count())

	_root_node = _agent_tree.ensure_root("Root")
	_root_node.setup(_pool, _registry, _host, _logger)
	_root_node.configure_llm(base_url, api_key, model)
	_root_node.system_prompt = prompt_text
	_root_node.tool_definitions = node_tools

	# 加载已有子节点（复刻 plugin.run_banyan）
	for nid in _agent_tree.get_all_nodes():
		var n: AgentNode = _agent_tree.get_all_nodes()[nid]
		if n.parent_id == "Root" and n.node_id != "Root":
			_root_node._children[n.node_id] = n
			n._parent_ref = weakref(_root_node)
			_root_node._pending_children[n.node_id] = true
	if _root_node._children.size() > 0:
		print("[SETUP] 恢复子节点: %s" % str(_root_node._children.keys()))

	# 5. 信号 + 运行
	_root_node.progress_done.connect(_on_done)
	_root_node.progress_error.connect(_on_error)
	# 实时监控：Root 的 state_changed 会冒泡整棵树的来源 id，
	# 每次触发重新遍历，给新 spawn 的节点挂上直连监控
	_root_node.state_changed.connect(_on_tree_state_changed)
	_attach_monitor(_root_node)

	var task: String = OS.get_environment("BANYAN_TASK")
	if task.is_empty():
		task = DEFAULT_TASK
	print("[RUN] 任务: %s" % task)
	print("────────────────────────────────────────")

	var ticket: Dictionary = {
		"ticket_id": "T-Headless-%03d" % [Time.get_ticks_msec() % 1000],
		"type": "implement",
		"scope": "Root",
		"requirements": [task],
	}
	_root_node.run(ticket)


# ============ 实时监控实现 ============

func _on_tree_state_changed(origin_id: String) -> void:
	_touch_activity()
	# 冒泡上来的来源 id — 先打印状态变化，再遍历树给新节点挂监控
	var node: AgentNode = _find_node(origin_id)
	if node:
		_monitor_print(origin_id, "状态 → " + _state_name(node.node_state))
	else:
		_monitor_print(origin_id, "状态变化（节点未找到）")
	_walk_attach(_root_node)


func _walk_attach(node: AgentNode) -> void:
	if node == null:
		return
	_attach_monitor(node)
	for cname in node._children:
		_walk_attach(node._children[cname])


func _attach_monitor(node: AgentNode) -> void:
	if _monitored.has(node):
		return
	_monitored[node] = true
	var nid: String = node.node_id
	node.progress_tool_started.connect(func(tool_name: String):
		_touch_activity()
		_monitor_print(nid, "工具 → " + tool_name)
	)
	node.progress_tool_finished.connect(func(tool_name: String, ok: bool):
		_touch_activity()
		_monitor_print(nid, "工具 ✓ " + tool_name if ok else "工具 ✗ " + tool_name + " 失败")
	)
	node.progress_chunk.connect(func(chunk: String):
		_touch_activity()
		# 生成中 — 节流打印累计输出量，证明流式输出是实时的
		if not _chunk_ticks.has(nid):
			_chunk_ticks[nid] = [0, 0]
		_chunk_ticks[nid][0] += chunk.length()
		var now: int = Time.get_ticks_msec()
		if now - _chunk_ticks[nid][1] > 2000:
			_chunk_ticks[nid][1] = now
			_monitor_print(nid, "生成中… 已输出 %d 字符" % _chunk_ticks[nid][0])
	)
	node.progress_done.connect(func():
		_touch_activity()
		_monitor_print(nid, "完成（%d 轮）" % node.get_round_count())
	)
	node.progress_error.connect(func(err: String):
		_touch_activity()
		_monitor_print(nid, "终态错误: " + err.substr(0, 120))
	)
	_monitor_print(nid, "监控已接入")


func _find_node(target_id: String) -> AgentNode:
	return _find_node_recursive(_root_node, target_id)


func _find_node_recursive(node: AgentNode, target_id: String) -> AgentNode:
	if node == null:
		return null
	if node.node_id == target_id:
		return node
	for cname in node._children:
		var found: AgentNode = _find_node_recursive(node._children[cname], target_id)
		if found:
			return found
	return null


func _monitor_print(node_id: String, msg: String) -> void:
	var t: float = float(Time.get_ticks_msec() - _start_msec) / 1000.0
	print("[MON %6.1fs] [%-18s] %s" % [t, node_id, msg])


func _state_name(s: int) -> String:
	match s:
		0: return "IDLE"
		1: return "RUNNING"
		2: return "LLM_REQUEST"
		3: return "TOOL_EXEC"
		4: return "COMPLETED"
		5: return "FAILED"
		6: return "RETRYING"
		_: return "UNKNOWN(%d)" % s


func _on_done() -> void:
	print("\n────────────────────────────────────────")
	print("[DONE] Root 完成")
	_finish_run()


func _on_error(err: String) -> void:
	print("\n────────────────────────────────────────")
	print("[ERROR] Root 失败: %s" % err)
	_failed = true
	_fail_msg = err
	_finish_run()


func _finish_run() -> void:
	if _done:
		return
	_done = true

	var trace: Dictionary = _root_node.get_execution_trace() if _root_node else {}
	_print_trace(trace, 0)

	# 写运行日志（验证 P2-6 按时间戳命名）
	var session_id := "headless-" + Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var run_log = BanyanRunLogScript.new(session_id, _logger)
	var result: Dictionary = run_log.write(trace)
	print("\n[RUNLOG] %s" % str(result))

	# 持久化树
	if _agent_tree:
		_agent_tree.save()
		print("[TREE] 已保存，节点数: %d" % _agent_tree.get_node_count())

	print("\n=== HEADLESS RUN %s ===" % ("FAILED: " + _fail_msg if _failed else "OK"))


func _print_trace(trace: Dictionary, depth: int) -> void:
	if trace.is_empty():
		print("[TRACE] <empty>")
		return
	var indent := "  ".repeat(depth)
	var rounds: Array = trace.get("rounds", [])
	print("%s• %s [%s] rounds=%d duration=%.1fs" % [
		indent, trace.get("node_id", "?"), trace.get("status", "?"),
		rounds.size(), float(trace.get("duration_sec", 0.0))])
	for r in rounds:
		var tools: Array = r.get("tools", [])
		for t in tools:
			print("%s    R%s %s [%s] %s" % [
				indent, str(r.get("round", "?")), t.get("name", "?"),
				"OK" if t.get("ok", true) else "FAIL",
				str(t.get("result_preview", "")).substr(0, 100).replace("\n", " ")])
	var summary: String = str(trace.get("summary", ""))
	if not summary.is_empty():
		print("%s  Summary: %s" % [indent, summary.substr(0, 400).replace("\n", " ")])
	for c in trace.get("children", []):
		_print_trace(c, depth + 1)


# ============ 辅助 ============

func _create_tool_registry() -> ToolRegistry:
	var registry := ToolRegistry.new()
	registry.set_editor_context(null, null)
	var tool_dir := "res://addons/dotagent/tools"
	var tool_scripts: Array = [
		"file_tools.gd", "scene_tools.gd", "script_tools.gd", "script_file_tools.gd",
		"node_query_tools.gd", "exec_tools.gd", "screenshot_tools.gd", "project_tools.gd",
		"perception_tools.gd", "configuration_tools.gd", "composite_tools.gd",
	]
	for script_name in tool_scripts:
		var script_res: GDScript = load(tool_dir.path_join(script_name)) as GDScript
		if script_res:
			registry.register_module(script_res.new())
	print("[SETUP] 工具模块已注册: %d 个工具" % registry.get_tool_definitions().size())
	return registry


func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content := f.get_as_text()
	f.close()
	return content
