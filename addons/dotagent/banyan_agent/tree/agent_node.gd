@tool
class_name AgentNode
extends RefCounted
## Agent Node — 唯一的节点类。
##
## 节点 = 上下文。持久化到磁盘的是这个上下文，加载回来时节点就"醒"了。
## 节点持有领域知识，同时能执行 ReAct 循环。
## 所有节点同构 — 同一个类、同一套行为、同一个决策逻辑。

signal progress_chunk(chunk: String)
signal progress_tool_started(tool_name: String)
signal progress_tool_finished(tool_name: String, ok: bool)
signal progress_done()
signal progress_error(error: String)

const Pool = preload("res://addons/dotagent/banyan_agent/http/http_client_pool.gd")
const ReqSlot = preload("res://addons/dotagent/banyan_agent/http/request_slot.gd")
const MsgBldr = preload("res://addons/dotagent/banyan_agent/context/message_builder.gd")
const BanyanToolExecutor = preload("res://addons/dotagent/banyan_agent/tools/tool_executor.gd")

const MAX_ROUNDS := 15
const MAX_FAILURES := 2
const ROUND_DELAY := 0.3
const MAX_CHILDREN := 8
const CHILD_TIMEOUT := 600.0

const ACTION_EXECUTE := "execute"
const ACTION_NUDGE := "nudge"
const ACTION_REDIRECT := "redirect"
const ACTION_FINISH := "finish"
const ACTION_FAILED := "failed"

# ============ 状态 ============

enum NodeState { IDLE, RUNNING, LLM_REQUEST, TOOL_EXEC, COMPLETED, FAILED }

var node_state: NodeState = NodeState.IDLE
var messages: Array = []
var system_prompt: String = ""
var tool_definitions: Array = []

# ============ 持久化上下文 ============

var node_id: String = ""
var parent_id: String = ""
var state: String = "IDLE"
var domain_knowledge: String = ""
var managed_files: Array = []
var managed_nodes: Array = []
var children_summaries: Array = []
var history: Array = []

# ============ 依赖注入（不持久化） ============

var _pool = null
var _tool_registry = null
var _host_node: Node = null
var _logger: SessionLog = null
var _tool_executor: BanyanToolExecutor = null

# ============ 子节点管理 ============

var _children: Dictionary = {}
var _pending_children: Dictionary = {}
var _child_reports: Dictionary = {}

# ============ LLM 配置 ============

var _base_url: String = ""
var _api_key: String = ""
var _model: String = ""
var _max_tokens: int = 4096

# ============ 对话上下文 ============

var prior_messages: Array = []

# ============ 内部状态 ============

var _current_slot = null
var _round_count: int = 0
var _failure_count: int = 0
var _abort_requested: bool = false
var _files_created: Array = []
var _read_files: Array = []
var _signals_connected: Dictionary = {}

# ============ 执行轨迹 ============

var _execution_trace: Dictionary = {}
var _run_start_time: float = 0.0
var _current_round_trace: Dictionary = {}


# ============ 初始化 ============

## 注入运行时依赖 — 必须在 run() 之前调用
func setup(pool, tool_registry, host_node: Node, logger: SessionLog = null) -> void:
	_pool = pool
	_tool_registry = tool_registry
	_host_node = host_node
	_logger = logger if logger else SessionLog.instance()
	_tool_executor = BanyanToolExecutor.new()
	_tool_executor.setup(tool_registry, _logger)
	_tool_executor.set_management_handler(_handle_management_tool)


## 配置 LLM 连接参数
func configure_llm(base_url: String, api_key: String, model: String, max_tokens: int = 4096) -> void:
	_base_url = base_url
	_api_key = api_key
	_model = model
	_max_tokens = max_tokens


# ============ ReAct 循环 ============
##
## 核心原则：每一轮 LLM 必须产出思考（文字内容）。
## 如果 LLM 只调用工具而不解释为什么要做，这不是真正的推理 — 是盲动。
## 当检测到"无思考行动"时，要求 LLM 先解释再执行。

func run(ticket: Dictionary = {}) -> void:
	if _pool == null:
		progress_error.emit("Pool not set")
		return

	node_state = NodeState.RUNNING
	_abort_requested = false
	_round_count = 0
	_failure_count = 0
	_files_created.clear()
	_run_start_time = float(Time.get_ticks_msec())

	_execution_trace = {
		"node_id": node_id,
		"model": _model,
		"started_at": Time.get_datetime_string_from_system(),
		"status": "RUNNING",
		"summary": "",
		"duration_sec": 0.0,
		"rounds": [],
		"children": [],
	}

	messages = [{"role": "system", "content": system_prompt}]

	# 注入节点自身的持久化上下文 — 让节点醒来时知道自己是谁
	var ctx: String = _build_node_context()
	if not ctx.is_empty():
		messages.append({"role": "system", "content": ctx})

	for msg in prior_messages:
		messages.append(msg)
	var user_msg: String = _construct_user_message(ticket)
	if not user_msg.is_empty():
		messages.append({"role": "user", "content": user_msg})

	var _nudged: bool = false
	var _redirected: bool = false
	var _total_tool_calls: int = 0

	while not _abort_requested:
		if _round_count >= MAX_ROUNDS:
			_log("Hit max rounds (%d)" % MAX_ROUNDS)
			node_state = NodeState.FAILED
			progress_error.emit("Max rounds reached")
			break

		node_state = NodeState.LLM_REQUEST
		var llm_ok: bool = await _do_llm_request()

		if not llm_ok:
			_failure_count += 1
			if _failure_count >= MAX_FAILURES:
				node_state = NodeState.FAILED
				progress_error.emit("Failed after %d errors" % _failure_count)
				break
			await _delay(1.0)
			continue

		_failure_count = 0
		_round_count += 1
		_current_round_trace = {"round": _round_count, "llm_preview": "", "tools": []}

		var action: String = _analyze_response(_nudged, _redirected, _total_tool_calls)

		# 更新状态和统计
		if action == ACTION_EXECUTE or action == ACTION_NUDGE:
			_total_tool_calls += messages.back().get("tool_calls", []).size()
		var llm_content = messages.back().get("content", "")
		if llm_content != null and not str(llm_content).is_empty():
			_current_round_trace["llm_preview"] = str(llm_content).substr(0, 300)

		var is_done: bool = await _act_on_response(action, _nudged)

		# 更新 nudge/redirect 状态
		if action == ACTION_NUDGE:
			_nudged = true
		elif action == ACTION_EXECUTE:
			_nudged = false
		elif action == ACTION_REDIRECT:
			_redirected = true

		_execution_trace["rounds"].append(_current_round_trace)
		_current_round_trace = {}

		if is_done:
			break
		await _delay(ROUND_DELAY)

	# ── 收束阶段 ──
	await _request_convergence_summary()

	_release_slot()

	# 运行结束 — 更新持久化上下文
	var elapsed: float = (float(Time.get_ticks_msec()) - _run_start_time) / 1000.0
	_execution_trace["duration_sec"] = elapsed
	_execution_trace["status"] = "COMPLETED" if node_state == NodeState.COMPLETED else "FAILED"
	_execution_trace["summary"] = _extract_summary()

	# 更新领域知识
	state = "COMPLETED" if node_state == NodeState.COMPLETED else "FAILED"
	var summary: String = _extract_summary()
	if not summary.is_empty():
		domain_knowledge = summary
	# 更新文件列表
	for f in _files_created:
		if not managed_files.has(f):
			managed_files.append(f)
	# 更新子节点摘要
	_update_children_summaries()
	# 添加历史记录
	if _round_count > 0:
		var entry_summary: String = summary.substr(0, 80) if not summary.is_empty() else "(no summary)"
		add_history_entry("R%d, %d files — %s" % [_round_count, _files_created.size(), entry_summary])

	# 收集子节点执行轨迹
	for cname in _children:
		var child = _children[cname]
		if child._execution_trace.size() > 0:
			_execution_trace["children"].append(child._execution_trace)

	progress_done.emit()
	_log("Finished: state=%s rounds=%d duration=%.1fs" % [state, _round_count, elapsed])


# ============ ReAct 循环子步骤 ============

## 分析 LLM 最新回复，返回应采取的动作（纯决策，不操作消息）
func _analyze_response(nudged: bool, redirected: bool, total_tool_calls: int) -> String:
	var last_msg: Dictionary = messages.back()
	var has_tool_calls: bool = last_msg.has("tool_calls") and not last_msg.get("tool_calls", []).is_empty()
	var llm_content = last_msg.get("content", "")
	var has_reasoning: bool = llm_content != null and not str(llm_content).is_empty()

	if has_tool_calls:
		if not has_reasoning and not nudged:
			return ACTION_NUDGE
		# 有 reasoning + tool_calls，或已被 nudge 过 → 正常执行
		return ACTION_EXECUTE

	# 无 tool_calls
	if total_tool_calls == 0 and not redirected and _round_count <= 2:
		return ACTION_REDIRECT
	return ACTION_FINISH


## 执行决策。所有消息操作集中在此，保证 API 协议合规
## （assistant tool_calls 后必有对应 tool 消息）
func _act_on_response(action: String, nudged: bool) -> bool:
	var last_msg: Dictionary = messages.back()

	match action:
		ACTION_NUDGE:
			_log("Round %d: tool calls without reasoning — nudge" % _round_count)
			# 协议合规：为每个未执行的 tool_call 追加占位结果
			for tc in last_msg.get("tool_calls", []):
				messages.append({
					"role": "tool",
					"tool_call_id": tc.get("id", ""),
					"content": "Tool call was not executed — the assistant should explain its reasoning before calling tools.",
				})
			messages.append({
				"role": "system",
				"content": "You called tools but did not explain your reasoning. Before calling any tool, briefly explain: (1) what you need to learn or accomplish, (2) why this tool is the right next step, (3) what you expect to find. Then proceed with your plan.",
			})
			return false

		ACTION_EXECUTE:
			if nudged:
				_log("Round %d: still no reasoning after nudge — executing anyway" % _round_count)
			node_state = NodeState.TOOL_EXEC
			await _execute_tool_round(last_msg.tool_calls)
			return false

		ACTION_REDIRECT:
			_log("Round %d: no tool calls ever — redirecting LLM to use tools" % _round_count)
			messages.append({
				"role": "user",
				"content": "You have tools available to accomplish this task. Please use them to gather information and take action. Start by using perception tools (read_script, inspect_scene_structured, get_project_architecture) to understand the project, then use execution tools as needed.",
			})
			return false

		ACTION_FINISH:
			node_state = NodeState.COMPLETED
			return true

	return false


## 收束阶段：用精简消息集请求 LLM 生成最终总结
func _request_convergence_summary() -> void:
	var summary: String = _extract_summary()
	if not summary.is_empty() or _abort_requested or _round_count == 0:
		return

	_log("No summary after %d rounds — requesting final answer" % _round_count)
	var exec_brief: String = _build_execution_brief()
	var convergence_msgs: Array = [
		{"role": "system", "content": "You are an AI assistant working inside a Godot game engine editor. You just completed a series of tool calls. Summarize the results concisely."},
		{"role": "user", "content": "You completed %d rounds of tool execution. Here is what happened:\n\n%s\n\nProvide a concise summary of what was accomplished, any files created or modified, and the current status. Do not call any tools." % [_round_count, exec_brief]},
	]
	node_state = NodeState.LLM_REQUEST
	var saved_messages: Array = messages
	var saved_tools: Array = tool_definitions
	messages = convergence_msgs
	tool_definitions = []
	var summary_ok: bool = await _do_llm_request()
	messages = saved_messages
	tool_definitions = saved_tools
	if summary_ok:
		var final_msg: Dictionary = convergence_msgs.back()
		if final_msg.get("role", "") == "assistant":
			messages.append(final_msg)
		node_state = NodeState.COMPLETED


## 定时器辅助 — 安全处理 host_node 可能为 null 的情况
func _delay(seconds: float) -> void:
	if _host_node and _host_node.get_tree():
		await _host_node.get_tree().create_timer(seconds).timeout


# ============ 子类可重写 ============

func _construct_user_message(ticket: Dictionary) -> String:
	return MsgBldr._format_ticket(ticket)


func execute_tool(tc_name: String, args_raw: String) -> Dictionary:
	var result: Dictionary
	if BanyanToolExecutor.is_management_tool(tc_name):
		if _tool_executor:
			result = await _tool_executor.execute(tc_name, args_raw)
		else:
			result = {"ok": false, "content": "ToolExecutor not initialized"}
	else:
		if _tool_registry:
			result = await _tool_registry.execute_tool(tc_name, args_raw)
		else:
			result = {"ok": false, "content": "ToolRegistry not available"}

	# 追踪已读文件，用于 spawn 时注入父节点知识
	if result.get("ok", false) and tc_name in ["read_script", "inspect_scene_structured", "extract_script_interface"]:
		var parsed_args: Variant = JSON.parse_string(args_raw)
		if parsed_args is Dictionary:
			var fp: String = str(parsed_args.get("path", parsed_args.get("scene_path", "")))
			if not fp.is_empty() and fp not in _read_files:
				_read_files.append(fp)

	return result


func _handle_management_tool(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"spawn_child":
			return await _handle_spawn_child(args)
		"route_to_child":
			return await _handle_route_to_child(args)
		"wait_for_children":
			return await _handle_wait_for_children(args)
		"list_children":
			return _handle_list_children(args)
		"save_knowledge":
			var k_summary: String = str(args.get("summary", ""))
			var k_category: String = str(args.get("category", "general"))
			var k_tags = args.get("tags", [])
			if k_summary.is_empty():
				return {"ok": false, "content": "summary is required"}
			var entry: Dictionary = {
				"node_id": node_id,
				"summary": k_summary,
				"category": k_category,
				"tags": k_tags if k_tags is Array else [],
				"timestamp": Time.get_datetime_string_from_system(),
			}
			_save_shared_knowledge(entry)
			return {"ok": true, "content": "Knowledge saved: %s" % k_summary.substr(0, 80)}
		"query_knowledge":
			var q_category: String = str(args.get("category", ""))
			var q_module: String = str(args.get("module", ""))
			var entries: Array = _load_shared_knowledge()
			var filtered: Array = []
			for e in entries:
				if not q_category.is_empty() and str(e.get("category", "")) != q_category:
					continue
				if not q_module.is_empty() and str(e.get("node_id", "")) != q_module:
					continue
				filtered.append(e)
			if filtered.is_empty():
				return {"ok": true, "content": "No knowledge entries found%s." % (" for category: " + q_category if not q_category.is_empty() else "")}
			var result_parts: Array = []
			var max_show: int = mini(filtered.size(), 10)
			for i in range(max_show):
				var e: Dictionary = filtered[i]
				result_parts.append("[%s] %s (by %s)" % [str(e.get("category", "")), str(e.get("summary", "")), str(e.get("node_id", ""))])
			return {"ok": true, "content": "Found %d entries:\n%s" % [filtered.size(), "\n".join(result_parts)]}
		"search_knowledge":
			var query: String = str(args.get("keyword", "")).to_lower()
			if query.is_empty():
				return {"ok": false, "content": "keyword is required"}
			var s_module: String = str(args.get("module", ""))
			var s_category: String = str(args.get("category", ""))
			var all_entries: Array = _load_shared_knowledge()
			var matches: Array = []
			for e in all_entries:
				if not s_module.is_empty() and str(e.get("node_id", "")) != s_module:
					continue
				if not s_category.is_empty() and str(e.get("category", "")) != s_category:
					continue
				var text: String = str(e.get("summary", "")).to_lower()
				if text.find(query) >= 0:
					matches.append(e)
			if matches.is_empty():
				return {"ok": true, "content": "No matches for '%s'." % query}
			var result_parts: Array = []
			var max_show: int = mini(matches.size(), 10)
			for i in range(max_show):
				var e: Dictionary = matches[i]
				result_parts.append("[%s] %s (by %s)" % [str(e.get("category", "")), str(e.get("summary", "")), str(e.get("node_id", ""))])
			return {"ok": true, "content": "Found %d matches for '%s':\n%s" % [matches.size(), query, "\n".join(result_parts)]}
		_:
			return {"ok": false, "content": "Unknown management tool: %s" % tool_name}


# ============ LLM 请求 ============

func _do_llm_request() -> bool:
	_current_slot = await _pool.wait_for_slot(node_id)
	if _current_slot == null:
		progress_error.emit("No available slot after waiting")
		return false

	var builder: MsgBldr = MsgBldr.new()
	builder.setup(messages, _logger)
	var send_msgs: Array = builder.build()

	var url_info: Dictionary = Pool.parse_url(_base_url)
	var endpoint: String = url_info.path
	if not endpoint.ends_with("/chat/completions"):
		endpoint = endpoint.trim_suffix("/") + "/chat/completions"

	var body: String = Pool.build_request_body(_model, send_msgs, tool_definitions, true, _max_tokens)
	var headers: PackedStringArray = Pool.build_headers(_api_key)

	_log("POST %s model=%s msgs=%d tools=%d" % [url_info.host + endpoint, _model, send_msgs.size(), tool_definitions.size()])

	_current_slot.send(url_info.host, url_info.port, endpoint, body, headers, url_info.use_tls)

	var emitted_len: int = 0
	while _current_slot != null and not _current_slot.is_terminal():
		if _abort_requested:
			return false
		var current_len: int = _current_slot.accumulated_content.length()
		if current_len > emitted_len:
			var delta: String = _current_slot.accumulated_content.substr(emitted_len)
			progress_chunk.emit(delta)
			emitted_len = current_len
		if _host_node and _host_node.get_tree():
			await _host_node.get_tree().process_frame

	if _current_slot == null:
		return false

	if _current_slot.state != ReqSlot.State.COMPLETED:
		var err: String = _current_slot.error_message
		progress_error.emit("LLM error: %s" % err)
		_log("LLM error: %s" % err)
		_release_slot()
		return false

	var tool_calls: Array = _current_slot.accumulated_tool_calls
	var content: String = _current_slot.accumulated_content
	if content.length() > emitted_len:
		progress_chunk.emit(content.substr(emitted_len))

	var assistant_msg: Dictionary = {"role": "assistant"}
	if content != "":
		assistant_msg["content"] = content
	if not tool_calls.is_empty():
		assistant_msg["tool_calls"] = tool_calls.duplicate(true)
	if not assistant_msg.has("content"):
		assistant_msg["content"] = null
	messages.append(assistant_msg)

	_release_slot()
	return true


# ============ 工具执行 ============

func _execute_tool_round(tool_calls: Array) -> void:
	for tc in tool_calls:
		if _abort_requested:
			break

		var tc_id: String = tc.get("id", "")
		var fn: Dictionary = tc.get("function", {})
		var tc_name: String = fn.get("name", "")
		var tc_args_raw: String = fn.get("arguments", "{}")

		progress_tool_started.emit(tc_name)
		_log("Tool: %s" % tc_name)

		var result: Dictionary = await execute_tool(tc_name, tc_args_raw)
		var ok: bool = result.get("ok", true)

		progress_tool_finished.emit(tc_name, ok)
		_log("Tool result: %s ok=%s" % [tc_name, str(ok)])

		if not _current_round_trace.is_empty():
			var result_content: String = str(result.get("content", ""))
			_current_round_trace["tools"].append({
				"name": tc_name,
				"ok": ok,
				"args_preview": tc_args_raw.substr(0, 200),
				"result_preview": result_content.substr(0, 300),
			})

		messages.append({
			"role": "tool",
			"tool_call_id": tc_id,
			"content": result.get("content", ""),
		})

		if tc_name in ["build_scene", "build_script", "update_script", "write_file"] and ok:
			_track_files(result)


func _track_files(result: Dictionary) -> void:
	var content: String = result.get("content", "")
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if d.has("path"):
			_files_created.append(d.get("path"))


# ============ 子节点管理 ============

func _handle_spawn_child(args: Dictionary) -> Dictionary:
	var task_desc: String = args.get("task_description", "")
	if task_desc.is_empty():
		return {"ok": false, "content": "task_description is required"}

	if _children.size() >= MAX_CHILDREN:
		return {"ok": false, "content": "Max children (%d) reached" % MAX_CHILDREN}

	var child_name: String = args.get("name", "Child_%s_%03d" % [node_id, _children.size() + 1])

	_log("Spawning child: %s — %s" % [child_name, task_desc.substr(0, 60)])

	# 创建子节点 — 同构，就是另一个 AgentNode
	var child = AgentNode.new()
	child.setup(_pool, _tool_registry, _host_node, _logger)
	child.configure_llm(_base_url, _api_key, _model, _max_tokens)
	child.node_id = child_name
	child.parent_id = node_id
	# 子节点获得基础 prompt + 任务聚焦指令 + 父节点已知信息
	var parent_context: String = "\n\n## Your Specific Task\nYou are: **%s**\nYour parent (%s) assigned you: %s\n\nFocus ONLY on this task. Do not read files unrelated to your domain. When you have enough information, write your summary and stop." % [child_name, node_id, task_desc]
	if not _read_files.is_empty():
		var recent_files: Array = _read_files.slice(max(0, _read_files.size() - 20))
		parent_context += "\n\n## Parent's Already-Read Files (do NOT re-read these)\n%s" % "\n".join(recent_files)
	if not domain_knowledge.is_empty():
		var trimmed_knowledge: String = domain_knowledge.substr(0, 800)
		parent_context += "\n\n## Parent's Domain Knowledge (for context, do not re-explore)\n%s" % trimmed_knowledge
	child.system_prompt = system_prompt + parent_context
	child.tool_definitions = tool_definitions

	var ticket: Dictionary = {
		"ticket_id": "T-%s-%03d" % [child_name, Time.get_ticks_msec() % 1000],
		"type": "implement",
		"scope": child_name,
		"worker_id": child_name,
		"requirements": [task_desc],
		"parent": node_id,
	}

	child.progress_chunk.connect(func(chunk: String):
		progress_chunk.emit(chunk)
	)
	child.progress_done.connect(func():
		_pending_children[child_name] = true
		_child_reports[child_name] = child.generate_report()
		_log("Child %s completed" % child_name)
	)
	child.progress_error.connect(func(err: String):
		_log("Child %s error: %s" % [child_name, err])
	)
	_signals_connected[child_name] = true

	_children[child_name] = child
	_pending_children[child_name] = false

	var runner: Callable = func():
		await child.run(ticket)
	runner.call_deferred()

	return {"ok": true, "content": JSON.stringify({
		"spawned": child_name,
		"total_children": _children.size(),
	})}


func _handle_route_to_child(args: Dictionary) -> Dictionary:
	var child_name: String = args.get("child_name", "")
	var task_desc: String = args.get("task_description", "")
	if child_name.is_empty() or task_desc.is_empty():
		return {"ok": false, "content": "child_name and task_description are required"}

	# 查找已有子节点
	var child = _children.get(child_name)
	if child == null:
		return {"ok": false, "content": "Child '%s' not found. Available: %s. Use spawn_child to create a new one." % [child_name, ", ".join(_children.keys())]}

	_log("Routing to existing child: %s — %s" % [child_name, task_desc.substr(0, 60)])

	# 重新激活子节点的运行时依赖
	child.setup(_pool, _tool_registry, _host_node, _logger)
	child.configure_llm(_base_url, _api_key, _model, _max_tokens)

	# 保留子节点的历史对话 — 让"持久化专家"真正保持上下文
	if child.messages.size() > 1:
		var history: Array = []
		for msg in child.messages:
			var role: String = msg.get("role", "")
			if role != "system":
				history.append(msg)
		child.prior_messages = history

	var ticket: Dictionary = {
		"ticket_id": "T-%s-%03d" % [child_name, Time.get_ticks_msec() % 1000],
		"type": "implement",
		"scope": child_name,
		"requirements": [task_desc],
		"parent": node_id,
	}

	# 转发进度信号（仅首次连接，防止重复路由导致信号泄漏）
	if not _signals_connected.has(child_name):
		child.progress_chunk.connect(func(chunk: String):
			progress_chunk.emit(chunk)
		)
		child.progress_done.connect(func():
			_pending_children[child_name] = true
			_child_reports[child_name] = child.generate_report()
			_log("Child %s completed (routed)" % child_name)
		)
		child.progress_error.connect(func(err: String):
			_log("Child %s error: %s" % [child_name, err])
		)
		_signals_connected[child_name] = true

	_pending_children[child_name] = false

	var runner: Callable = func():
		await child.run(ticket)
	runner.call_deferred()

	return {"ok": true, "content": JSON.stringify({
		"routed_to": child_name,
		"task": task_desc.substr(0, 100),
	})}


func _handle_wait_for_children(args: Dictionary) -> Dictionary:
	if _children.is_empty():
		return {"ok": true, "content": JSON.stringify({"waited_for": "NONE", "completed": [], "reports": {}})}

	var target: String = args.get("name", "")
	var timeout: float = float(args.get("timeout_seconds", CHILD_TIMEOUT))

	_log("Waiting for children (target=%s, timeout=%ds)" % [target if not target.is_empty() else "ALL", int(timeout)])

	var elapsed: float = 0.0
	var poll_interval: float = 0.5

	while elapsed < timeout:
		var all_done: bool = true

		if not target.is_empty():
			all_done = _pending_children.get(target, true)
		else:
			for cname in _pending_children:
				if not _pending_children[cname]:
					all_done = false
					break

		if all_done:
			break

		if _host_node and _host_node.get_tree():
			await _host_node.get_tree().create_timer(poll_interval).timeout
		elapsed += poll_interval

	var completed: Array = []
	var reports: Dictionary = {}

	if not target.is_empty():
		if _pending_children.get(target, false):
			completed.append(target)
			reports[target] = _child_reports.get(target, {})
	else:
		for cname in _children:
			if _pending_children.get(cname, false):
				completed.append(cname)
				reports[cname] = _child_reports.get(cname, {})

	var pending: Array = []
	for cname in _pending_children:
		if not _pending_children[cname]:
			pending.append(cname)

	return {"ok": true, "content": JSON.stringify({
		"waited_for": target if not target.is_empty() else "ALL",
		"completed": completed,
		"pending": pending,
		"timed_out": elapsed >= timeout and not pending.is_empty(),
		"reports": reports,
	})}


func _handle_list_children(_args: Dictionary) -> Dictionary:
	var result: Array = []
	for cname in _children:
		var child = _children[cname]
		result.append({
			"name": cname,
			"state": child.node_state,
			"rounds": child.get_round_count(),
			"done": _pending_children.get(cname, false),
		})
	return {"ok": true, "content": JSON.stringify({"children": result, "count": result.size()})}


# ============ 公共查询 ============

func get_round_count() -> int:
	return _round_count


func get_files_created() -> Array:
	return _files_created.duplicate()


func get_execution_trace() -> Dictionary:
	return _execution_trace.duplicate(true)


func abort() -> void:
	_abort_requested = true
	_release_slot()
	node_state = NodeState.FAILED
	for cname in _children:
		_children[cname].abort()


func generate_report() -> Dictionary:
	var children_reports: Dictionary = {}
	for cname in _child_reports:
		children_reports[cname] = _child_reports[cname]
	var report: Dictionary = {
		"node_id": node_id,
		"status": state,
		"summary": domain_knowledge,
		"rounds": _round_count,
		"files": managed_files.duplicate(),
		"children_count": _children.size(),
		"children_reports": children_reports,
	}
	# 失败时附加诊断信息
	if state == "FAILED":
		var failures: Array = []
		for r in _execution_trace.get("rounds", []):
			for t in r.get("tools", []):
				if not t.get("ok", true):
					failures.append({"tool": t.get("name", ""), "error": t.get("result_preview", "")})
		report["failures"] = failures
		report["error_summary"] = "%d tool failures in %d rounds" % [failures.size(), _round_count]
	return report


# ============ 持久化 ============

func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"parent_id": parent_id,
		"state": state,
		"domain_knowledge": domain_knowledge,
		"managed_files": managed_files.duplicate(),
		"managed_nodes": managed_nodes.duplicate(),
		"children_summaries": children_summaries.duplicate(true),
		"history": history.duplicate(),
	}


static func from_dict(data: Dictionary) -> AgentNode:
	var node: AgentNode = AgentNode.new()
	node.node_id = str(data.get("node_id", ""))
	node.parent_id = str(data.get("parent_id", ""))
	node.state = str(data.get("state", "IDLE"))
	node.domain_knowledge = str(data.get("domain_knowledge", ""))
	var mf = data.get("managed_files", [])
	if mf is Array:
		for f in mf:
			node.managed_files.append(str(f))
	var mn = data.get("managed_nodes", [])
	if mn is Array:
		for n in mn:
			node.managed_nodes.append(str(n))
	var cs = data.get("children_summaries", [])
	if cs is Array:
		node.children_summaries = cs.duplicate(true)
	var h = data.get("history", [])
	if h is Array:
		for entry in h:
			node.history.append(str(entry))
	return node


func add_history_entry(entry: String) -> void:
	var day: String = Time.get_date_string_from_system()
	history.append("%s: %s" % [day, entry])
	while history.size() > 50:
		history.pop_front()


# ============ 内部 ============

func _release_slot() -> void:
	if _current_slot and _pool:
		_pool.release_slot(_current_slot)
	_current_slot = null


func _extract_summary() -> String:
	for i in range(messages.size() - 1, -1, -1):
		var msg: Dictionary = messages[i]
		if msg.get("role", "") == "assistant":
			var raw_content = msg.get("content", "")
			if raw_content == null:
				continue
			var content: String = str(raw_content)
			if content == "<null>":
				continue
			if not content.is_empty():
				return content
	return ""


## 从执行轨迹构建精简摘要 — 供收束阶段使用，避免发送完整消息历史
func _build_execution_brief() -> String:
	var lines: Array = []
	var rounds: Array = _execution_trace.get("rounds", [])
	for r in rounds:
		var round_num: int = r.get("round", 0)
		var tools: Array = r.get("tools", [])
		if tools.is_empty():
			continue
		for t in tools:
			var name: String = t.get("name", "?")
			var ok: bool = t.get("ok", true)
			var preview: String = t.get("result_preview", "")
			if preview.length() > 150:
				preview = preview.substr(0, 150) + "…"
			lines.append("Round %d: %s [%s] — %s" % [round_num, name, "OK" if ok else "FAIL", preview])
	if lines.is_empty():
		return "(%d rounds, no tool results recorded)" % _round_count
	return "\n".join(lines)


func _update_children_summaries() -> void:
	children_summaries.clear()
	for cname in _children:
		var report = _child_reports.get(cname, {})
		if not report.is_empty():
			var summary: String = str(report.get("summary", ""))
			children_summaries.append({
				"id": cname,
				"status": str(report.get("status", "UNKNOWN")),
				"summary": summary.substr(0, 200),
				"files": report.get("files", []),
			})
		else:
			var child = _children[cname]
			children_summaries.append({
				"id": cname,
				"status": child.state,
				"summary": child.domain_knowledge.substr(0, 200),
				"files": child.managed_files.duplicate(),
			})


func _log(msg: String) -> void:
	if _logger:
		_logger.append("BANYAN", "[%s] %s" % [node_id, msg])


const SHARED_KNOWLEDGE_PATH := "res://addons/dotagent/banyan_agent/persistence/shared_knowledge.json"
const MAX_KNOWLEDGE_ENTRIES := 200


func _save_shared_knowledge(entry: Dictionary) -> void:
	var entries: Array = _load_shared_knowledge()
	entries.append(entry)
	while entries.size() > MAX_KNOWLEDGE_ENTRIES:
		entries.pop_front()
	var dir_path: String = SHARED_KNOWLEDGE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f: FileAccess = FileAccess.open(SHARED_KNOWLEDGE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"entries": entries}, "\t"))
		f.close()


func _load_shared_knowledge() -> Array:
	if not FileAccess.file_exists(SHARED_KNOWLEDGE_PATH):
		return []
	var f: FileAccess = FileAccess.open(SHARED_KNOWLEDGE_PATH, FileAccess.READ)
	if f == null:
		return []
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var entries = parsed.get("entries", [])
	return entries if entries is Array else []


## 构建节点上下文字符串 — 注入到 LLM 让节点醒来时知道自己的身份和领域
func _build_node_context() -> String:
	var parts: Array = []

	parts.append("# Your Identity")
	parts.append("You are node: %s" % node_id)
	if not parent_id.is_empty():
		parts.append("Parent: %s" % parent_id)

	if not domain_knowledge.is_empty():
		parts.append("")
		parts.append("## Your Domain Knowledge")
		parts.append(domain_knowledge)

	if not managed_files.is_empty():
		parts.append("")
		parts.append("## Files You Manage")
		for f in managed_files:
			parts.append("- %s" % str(f))

	if not children_summaries.is_empty():
		parts.append("")
		parts.append("## Your Child Nodes")
		parts.append("These nodes already exist and hold knowledge about their areas. Route tasks to them when appropriate.")
		for cs in children_summaries:
			var cid: String = str(cs.get("id", ""))
			var cstatus: String = str(cs.get("status", ""))
			var csummary: String = str(cs.get("summary", ""))
			var cfiles = cs.get("files", [])
			var fc: int = cfiles.size() if cfiles is Array else 0
			parts.append("- **%s** [%s] — %s (%d files)" % [cid, cstatus, csummary.substr(0, 120), fc])

	if not history.is_empty():
		parts.append("")
		parts.append("## Your History")
		var recent: Array = history
		if recent.size() > 10:
			recent = recent.slice(-10)
		for h in recent:
			parts.append("- %s" % str(h))

	if parts.size() <= 1:
		return ""

	return "\n".join(parts)
