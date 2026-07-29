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
## 树状态变化通知 — 节点状态切换 / 子节点诞生时发射，供 UI 实时刷新 Agent Graph
signal state_changed(node_id: String)

const Pool = preload("res://addons/dotagent/banyan_agent/http/http_client_pool.gd")
const ReqSlot = preload("res://addons/dotagent/banyan_agent/http/request_slot.gd")
const MsgBldr = preload("res://addons/dotagent/banyan_agent/context/message_builder.gd")
const BanyanToolExecutor = preload("res://addons/dotagent/banyan_agent/tools/tool_executor.gd")

const ROUND_BUDGET_DEFAULT := 15  # 非 Root 节点每次运行的初始轮数预算（Root 无限）
const ROUND_GRANT_SIZE := 10      # 预算耗尽时向父级申请获批的轮数
const MAX_FAILURES := 5        # 连续 LLM 失败熔断次数 — 开发阶段给更多恢复机会
const ROUND_DELAY := 0.3
const MAX_CHILDREN := 0        # 0 = 无限制
const CHILD_TIMEOUT := 600.0

const ACTION_EXECUTE := "execute"
const ACTION_NUDGE := "nudge"
const ACTION_REDIRECT := "redirect"
const ACTION_FINISH := "finish"
const ACTION_FAILED := "failed"
const ACTION_CHALLENGE := "challenge"  # 零执行就收工 — 挑战一次，要求继续干活或明确说明任务无需修改

# 算"实际执行"的工具：改动项目或委派子节点干活。
# 只读探索（perception/discovery）不算 — 防止"只分析不动手"被误判为完成
const EXECUTION_TOOLS := [
	"build_scene", "build_script", "update_script", "write_file",
	"patch_scene", "replace_in_file", "configure_resource", "configure_project",
]
const DELEGATION_TOOLS := ["spawn_child", "route_to_child"]
const PERCEPTION_TOOLS := [
	"list_files", "list_scenes", "list_resources",
	"read_script", "read_multiple_files", "read_file_tail",
	"inspect_scene_structured", "extract_script_interface",
	"get_scene_dependencies", "inspect_resource_interface",
	"analyze_signal_flow", "get_project_architecture",
	"check_script_syntax",
]

# ============ 状态 ============

enum NodeState { IDLE, RUNNING, LLM_REQUEST, TOOL_EXEC, COMPLETED, FAILED, RETRYING }

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
var _round_budget: int = -1        # 剩余轮数预算；-1 = 无限（仅 Root）
var _parent_ref: WeakRef = null    # 父节点弱引用 — 用于申请轮数（弱引用避免引用环）
var _failure_count: int = 0
var _abort_requested: bool = false
var _files_created: Array = []
var _read_files: Array = []
var _exec_actions_this_run: int = 0    # 本次运行中执行/委派类工具调用次数（只读探索不计）
var _completion_challenged: bool = false  # 本次运行是否已挑战过"零执行收工"（每次运行最多挑战一次）
var _file_summaries: Dictionary = {}  # path → one-line summary
var _signals_connected: Dictionary = {}

# ============ 上下文大小增量缓存 ============

var _ctx_size_cache: int = -1      # -1 = 未计算
var _ctx_msg_count: int = 0        # 缓存统计到的消息数
var _persisted_ctx_size: int = 0   # 上次运行持久化的 ctx 大小 — messages 为空时展示用

# ============ 执行轨迹 ============

var _execution_trace: Dictionary = {}
var _run_start_time: float = 0.0
var _current_round_trace: Dictionary = {}
var _last_reasoning: String = ""    # 最近一次 LLM 响应的推理流（reasoning_content）
var _stream_chars: int = 0          # 本次请求已流入的字符数（content + reasoning）— 供 Agent Graph 显示流式进度
var _last_stream_notify: int = 0    # 流式心跳节流（msec）


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

## 统一的状态切换入口 — 发射 state_changed 供 Agent Graph 实时刷新
func _set_node_state(s: NodeState) -> void:
	if node_state == s:
		return
	node_state = s
	state_changed.emit(node_id)


## 上下文总大小（字符数）— 增量缓存：messages 只增不减，每次只统计新增部分
## messages 被整体替换时必须调用 _invalidate_ctx_cache()
func get_ctx_size() -> int:
	# messages 为空（重启后/未运行）→ 展示上次运行持久化的大小
	if messages.is_empty() and _persisted_ctx_size > 0:
		return _persisted_ctx_size
	if _ctx_size_cache >= 0 and _ctx_msg_count == messages.size():
		return _ctx_size_cache
	if _ctx_size_cache < 0 or messages.size() < _ctx_msg_count:
		_ctx_size_cache = 0
		_ctx_msg_count = 0
	for i in range(_ctx_msg_count, messages.size()):
		var msg: Dictionary = messages[i]
		var content = msg.get("content", "")
		if content != null:
			_ctx_size_cache += str(content).length()
		if msg.has("tool_calls"):
			_ctx_size_cache += JSON.stringify(msg.get("tool_calls", [])).length()
	_ctx_msg_count = messages.size()
	return _ctx_size_cache


func _invalidate_ctx_cache() -> void:
	_ctx_size_cache = -1
	_ctx_msg_count = 0

func run(ticket: Dictionary = {}) -> void:
	if _pool == null:
		progress_error.emit("Pool not set")
		return

	_set_node_state(NodeState.RUNNING)
	_abort_requested = false
	_round_count = 0
	# 轮数预算：Root（无父节点）无限；非 Root 节点带初始预算，耗尽后向父级申请
	_round_budget = -1 if parent_id.is_empty() else ROUND_BUDGET_DEFAULT
	_failure_count = 0
	_files_created.clear()
	_exec_actions_this_run = 0
	_completion_challenged = false
	# _read_files 和 _file_summaries 从持久化加载，不清除
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
	_invalidate_ctx_cache()

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
		# ── 轮数预算：耗尽时向父级申请；被拒（如父链断开）则正常收束，不算失败 ──
		if _round_budget == 0:
			var granted: int = await _request_rounds_from_parent()
			if granted <= 0:
				_log("Round budget exhausted, parent denied grant — converging after %d rounds" % _round_count)
				break
			_round_budget = granted

		var round_start_msec: int = Time.get_ticks_msec()
		_set_node_state(NodeState.LLM_REQUEST)
		var llm_ok: bool = await _do_llm_request()
		var llm_elapsed: float = float(Time.get_ticks_msec() - round_start_msec) / 1000.0

		if not llm_ok:
			_failure_count += 1
			if _failure_count >= MAX_FAILURES:
				_log("LLM failed %d times consecutively — circuit breaker open" % _failure_count)
				_set_node_state(NodeState.FAILED)
				progress_error.emit("Failed after %d consecutive errors" % _failure_count)
				break
			# 熔断前的重试：退避等待 + RETRYING 状态上图，让故障可见
			_set_node_state(NodeState.RETRYING)
			var backoff: float = [1.0, 5.0, 15.0][mini(_failure_count, 3) - 1]
			_log("LLM error %d/%d — retrying in %.0fs" % [_failure_count, MAX_FAILURES, backoff])
			await _delay(backoff)
			continue

		_failure_count = 0
		_round_count += 1
		if _round_budget > 0:
			_round_budget -= 1
		_current_round_trace = {"round": _round_count, "llm_preview": "", "tools": []}

		var action: String = _analyze_response(_nudged, _redirected, _total_tool_calls)

		# 成果校验：零执行/零委派/零文件就收工，大概率是"只分析没干活"。
		# 每次运行挑战一次 — 要求继续动手，或明确说明任务本就是纯分析
		if action == ACTION_FINISH and not _completion_challenged \
				and _exec_actions_this_run == 0 and _files_created.is_empty() \
				and not _abort_requested:
			_completion_challenged = true
			action = ACTION_CHALLENGE

		# 更新状态和统计
		if action == ACTION_EXECUTE or action == ACTION_NUDGE:
			_total_tool_calls += messages.back().get("tool_calls", []).size()
		var llm_content = messages.back().get("content", "")
		if llm_content != null and not str(llm_content).is_empty():
			_current_round_trace["llm_preview"] = str(llm_content).substr(0, 300)
		elif not _last_reasoning.is_empty():
			# content 为空时用推理流做预览 — 运行日志能看到节点在想什么
			_current_round_trace["llm_preview"] = "[思考] " + _last_reasoning.substr(0, 280)

		var action_start_msec: int = Time.get_ticks_msec()
		var is_done: bool = await _act_on_response(action, _nudged)
		var action_elapsed: float = float(Time.get_ticks_msec() - action_start_msec) / 1000.0
		var total_round: float = float(Time.get_ticks_msec() - round_start_msec) / 1000.0
		_log("Round %d timing: LLM=%.1fs action=%s/%.1fs total=%.1fs" % [_round_count, llm_elapsed, action, action_elapsed, total_round])

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
	# 挑战后仍零执行 = 节点已确认这是纯分析/问答任务 — 保留它自己的最终答复，
	# 不再套用架构分析模板（否则模板总结会掩盖"什么都没做"的事实）
	var analysis_only: bool = _completion_challenged and _exec_actions_this_run == 0 and _files_created.is_empty()
	if not analysis_only:
		await _request_convergence_summary()

	_release_slot()

	# 运行结束 — 更新持久化上下文
	var elapsed: float = (float(Time.get_ticks_msec()) - _run_start_time) / 1000.0
	_execution_trace["duration_sec"] = elapsed
	_execution_trace["status"] = "COMPLETED" if node_state == NodeState.COMPLETED else "FAILED"
	_execution_trace["summary"] = _extract_summary()

	# 更新领域知识 — 只接受结构化的蒸馏总结；
	# 原始思考流会被 _request_convergence_summary 用结构化模板重写
	state = "COMPLETED" if node_state == NodeState.COMPLETED else "FAILED"
	var summary: String = _extract_summary()
	if not summary.is_empty() and _is_structured_summary(summary):
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

	# 收集子节点执行轨迹 — 只收本次运行的（started_at 不早于 Root），
	# 过滤掉内存中残留的历史 trace，否则旧 trace 会被扫进新运行日志，
	# 看起来像"未被调用的节点擅自动了文件"（曾导致严重误判）
	var root_started: String = str(_execution_trace.get("started_at", ""))
	for cname in _children:
		var child = _children[cname]
		if child._execution_trace.size() > 0 \
				and str(child._execution_trace.get("started_at", "")) >= root_started:
			_execution_trace["children"].append(child._execution_trace)

	progress_done.emit()
	_log("Finished: state=%s rounds=%d duration=%.1fs" % [state, _round_count, elapsed])


# ============ ReAct 循环子步骤 ============

## 分析 LLM 最新回复，返回应采取的动作（纯决策，不操作消息）
func _analyze_response(nudged: bool, redirected: bool, total_tool_calls: int) -> String:
	var last_msg: Dictionary = messages.back()
	var has_tool_calls: bool = last_msg.has("tool_calls") and not last_msg.get("tool_calls", []).is_empty()
	var llm_content = last_msg.get("content", "")
	# 推理模型的思考流在 reasoning_content（不进 messages），也算有推理
	var has_reasoning: bool = (llm_content != null and not str(llm_content).is_empty()) or not _last_reasoning.is_empty()

	if has_tool_calls:
		# 拦截：只调工具不解释推理 = 盲动，先 nudge 要求解释
		# 但感知/探索类工具（只读）豁免 — 不需要解释推理
		if not has_reasoning and not nudged:
			var all_perception: bool = true
			for tc in last_msg.get("tool_calls", []):
				var fn: Dictionary = tc.get("function", {})
				var tname: String = fn.get("name", "")
				if tname not in PERCEPTION_TOOLS:
					all_perception = false
					break
			if not all_perception:
				return ACTION_NUDGE
		# 有 reasoning、已被 nudge 过、或全是感知工具 → 正常执行
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
			if nudged and _last_reasoning.is_empty():
				# 仅在确实没有推理时报警（有 reasoning_content 时不算盲动）
				_log("Round %d: still no reasoning after nudge — executing anyway" % _round_count)
			_set_node_state(NodeState.TOOL_EXEC)
			await _execute_tool_round(last_msg.tool_calls)
			return false

		ACTION_REDIRECT:
			_log("Round %d: no tool calls ever — redirecting LLM to use tools" % _round_count)
			messages.append({
				"role": "user",
				"content": "You have tools available to accomplish this task. Please use them to gather information and take action. Start by using perception tools (read_script, inspect_scene_structured, get_project_architecture) to understand the project, then use execution tools as needed.",
			})
			return false

		ACTION_CHALLENGE:
			_log("Round %d: finish attempted with zero execution — challenging" % _round_count)
			messages.append({
				"role": "user",
				"content": "Before finishing, check your work: this run made no actual changes (no execution tools used, no files created or modified, no children delegated). If the task requires real changes, keep working — build/create/modify with execution tools, or delegate with spawn_child/route_to_child. A plan or analysis is NOT completion. Only finish without changes if the task is purely a question or analysis request — in that case state explicitly that no changes were needed and deliver your final answer.",
			})
			return false

		ACTION_FINISH:
			_set_node_state(NodeState.COMPLETED)
			return true

	return false


## 收束阶段：用结构化模板请求 LLM 生成高质量领域知识总结
func _request_convergence_summary() -> void:
	var summary: String = _extract_summary()
	# 已有合格总结（结构化）则跳过；原始思考流不算总结，必须重写
	if (not summary.is_empty() and _is_structured_summary(summary)) or _abort_requested or _round_count == 0:
		return

	_log("No summary after %d rounds — requesting structured analysis" % _round_count)
	var exec_brief: String = _build_execution_brief()
	var files_brief: String = ""
	if not _read_files.is_empty():
		files_brief = "\n\nFiles explored:\n%s" % "\n".join(_read_files)

	var convergence_msgs: Array = [
		{"role": "system", "content": """You are an AI architect summarizing a Godot project analysis. Write a structured domain knowledge summary using EXACTLY this format:

## Project Overview
[project type, architecture pattern, main entry point]

## System Modules
| Module | Responsibility | Key Files | Key Functions/Signals |
|--------|---------------|-----------|----------------------|
[one row per major system/subsystem]

## Dependencies & Signal Flow
[which modules depend on which, key signal chains, autoload usage]

## Issues Found
[bugs, missing connections, inconsistencies discovered during analysis]

Be specific: include file paths, function names, signal names. Do NOT list every file you read — distill the architecture. Focus on what a developer needs to understand the project."""},
		{"role": "user", "content": "You completed %d rounds of analysis.%s%s\n\nWrite your structured domain knowledge summary now. Do not call any tools." % [_round_count, exec_brief, files_brief]},
	]
	_set_node_state(NodeState.LLM_REQUEST)
	var saved_messages: Array = messages
	var saved_tools: Array = tool_definitions
	messages = convergence_msgs
	_invalidate_ctx_cache()
	tool_definitions = []
	var summary_ok: bool = await _do_llm_request()
	messages = saved_messages
	_invalidate_ctx_cache()
	tool_definitions = saved_tools
	if summary_ok:
		var final_msg: Dictionary = convergence_msgs.back()
		if final_msg.get("role", "") == "assistant":
			var content = final_msg.get("content", "")
			if content != null and not str(content).is_empty():
				domain_knowledge = str(content)
				messages.append(final_msg)
		# 收束总结不能把 FAILED 洗成 COMPLETED（如熔断后）；
		# 预算耗尽等正常收束时状态不是 FAILED，不受影响
		if node_state != NodeState.FAILED:
			_set_node_state(NodeState.COMPLETED)


## 定时器辅助 — 安全处理 host_node 可能为 null 的情况
func _delay(seconds: float) -> void:
	if _host_node and _host_node.get_tree():
		await _host_node.get_tree().create_timer(seconds).timeout


# ============ 轮数预算 ============
##
## 轮数像水一样从 Root 流下整棵树：
## Root 预算无限；非 Root 节点带初始预算运行，耗尽后向父级申请；
## 父级从自己的预算中拨付，不足时递归向上申请。
## 没有硬性轮数上限 — 只有预算流动，申请被拒时节点正常收束而非失败。

## 预算耗尽时向父节点申请轮数 — 返回获批数量，0 = 拒绝
func _request_rounds_from_parent(amount: int = ROUND_GRANT_SIZE) -> int:
	var parent: AgentNode = _parent_ref.get_ref() if _parent_ref else null
	if parent == null:
		_log("No parent available for round grant (parent_id=%s)" % parent_id)
		return 0
	_log("Requesting %d rounds from parent '%s'" % [amount, parent_id])
	return await parent.grant_rounds(node_id, amount)


## 父节点侧：向子节点拨付轮数。
## Root（预算 -1）无限拨付；非 Root 从自身预算扣减，不足时先向上级申请补充。
func grant_rounds(child_id: String, amount: int) -> int:
	if _round_budget < 0:
		_log("Grant %d rounds → %s (unlimited)" % [amount, child_id])
		return amount
	if _round_budget < amount:
		var top_up: int = await _request_rounds_from_parent(maxi(amount - _round_budget, ROUND_GRANT_SIZE))
		_round_budget += top_up
	var granted: int = mini(amount, _round_budget)
	_round_budget -= granted
	_log("Grant %d/%d rounds → %s (remaining budget: %d)" % [granted, amount, child_id, _round_budget])
	return granted


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

	# ── 追踪已读文件路径 ──
	if result.get("ok", false):
		if tc_name == "read_script":
			var parsed_args: Variant = JSON.parse_string(args_raw)
			if parsed_args is Dictionary:
				var fp: String = str(parsed_args.get("path", ""))
				if not fp.is_empty() and fp not in _read_files:
					_read_files.append(fp)
		elif tc_name == "read_multiple_files":
			var parsed_args: Variant = JSON.parse_string(args_raw)
			if parsed_args is Dictionary:
				for p in parsed_args.get("paths", []):
					var ps: String = str(p)
					if ps not in _read_files:
						_read_files.append(ps)
		elif tc_name in ["inspect_scene_structured", "extract_script_interface"]:
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
		"claim_files":
			var paths = args.get("paths", [])
			if not paths is Array or paths.is_empty():
				return {"ok": false, "content": "paths array is required and must not be empty"}
			var action: String = str(args.get("action", "set"))
			var claimed: Array = []
			for p in paths:
				var ps: String = str(p)
				if not ps.is_empty():
					claimed.append(ps)
			match action:
				"set":
					managed_files = claimed.duplicate()
				"add":
					for fp in claimed:
						if fp not in managed_files:
							managed_files.append(fp)
				"remove":
					for fp in claimed:
						managed_files.erase(fp)
				_:
					return {"ok": false, "content": "Unknown action '%s'. Use set, add, or remove." % action}
			return {"ok": true, "content": "Claimed %d files (%s). You now manage %d files total." % [claimed.size(), action, managed_files.size()]}
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
	_stream_chars = 0  # 新请求开始，流式计数归零
	_current_slot = await _pool.wait_for_slot(node_id)
	if _current_slot == null:
		# 瞬态失败：只记日志，由 run 循环退避重试；
		# progress_error 保留给熔断后的终态失败（见 run 循环）
		_log("No available slot after waiting — will retry")
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
		# 流式心跳：content + reasoning 都在流入，节流上报让 Agent Graph 实时看到进度
		_stream_chars = current_len + _current_slot.accumulated_reasoning.length()
		var now_msec: int = Time.get_ticks_msec()
		if now_msec - _last_stream_notify > 500:
			_last_stream_notify = now_msec
			state_changed.emit(node_id)
		if _host_node and _host_node.get_tree():
			await _host_node.get_tree().process_frame

	if _current_slot == null:
		return false

	if _current_slot.state != ReqSlot.State.COMPLETED:
		var err: String = _current_slot.error_message
		# 瞬态失败：只记日志（429/网络抖动等会由 run 循环退避重试恢复），
		# 不发射 progress_error — 该信号只代表熔断后的终态失败，
		# 否则 UI/驱动方会把一次可恢复的瞬态错误误判为整轮失败
		_log("LLM error (transient, will retry): %s" % err)
		_release_slot()
		return false

	var tool_calls: Array = _current_slot.accumulated_tool_calls
	var content: String = _current_slot.accumulated_content
	_last_reasoning = _current_slot.accumulated_reasoning
	if content.length() > emitted_len:
		progress_chunk.emit(content.substr(emitted_len))

	var assistant_msg: Dictionary = {"role": "assistant"}
	if content != "":
		assistant_msg["content"] = content
	if not tool_calls.is_empty():
		assistant_msg["tool_calls"] = tool_calls.duplicate(true)
	if not assistant_msg.has("content"):
		assistant_msg["content"] = ""  # Kimi API 不接受 null content，必须是字符串
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

		var tool_msg: Dictionary = {
			"role": "tool",
			"tool_call_id": tc_id,
			"content": result.get("content", ""),
		}
		# 管理工具（wait_for_children 报告、list_children 等）返回的是蒸馏信息，
		# 标记为不截断 — 截断报告曾导致父节点误判"报告不全"而重复 route
		if BanyanToolExecutor.is_management_tool(tc_name):
			tool_msg["_no_truncate"] = true
		messages.append(tool_msg)

		if tc_name in EXECUTION_TOOLS or tc_name in DELEGATION_TOOLS:
			_exec_actions_this_run += 1

		if tc_name in ["build_scene", "build_script", "update_script", "write_file"] and ok:
			_track_files(result)


func _track_files(result: Dictionary) -> void:
	var content: String = result.get("content", "")
	if content.is_empty():
		return
	var parsed: Variant = JSON.parse_string(content)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return  # 非 JSON 或非字典结果 — 静默跳过
	var d: Dictionary = parsed
	if d.has("path"):
		_files_created.append(d.get("path"))


# ============ 子节点管理 ============

func _handle_spawn_child(args: Dictionary) -> Dictionary:
	var task_desc: String = args.get("task_description", "")
	if task_desc.is_empty():
		return {"ok": false, "content": "task_description is required"}

	if MAX_CHILDREN > 0 and _children.size() >= MAX_CHILDREN:
		return {"ok": false, "content": "Max children (%d) reached" % MAX_CHILDREN}

	var child_name: String = args.get("name", "Child_%s_%03d" % [node_id, _children.size() + 1])

	_log("Spawning child: %s — %s" % [child_name, task_desc.substr(0, 60)])

	# 创建子节点 — 同构，就是另一个 AgentNode
	var child = AgentNode.new()
	child.setup(_pool, _tool_registry, _host_node, _logger)
	child.configure_llm(_base_url, _api_key, _model, _max_tokens)
	child.node_id = child_name
	child.parent_id = node_id
	child._parent_ref = weakref(self)  # 轮数预算申请通道
	# ── 构建父节点上下文注入 — 传递已有知识，避免子节点重复探索 ──
	var parent_context: String = ""

	# 1. 任务定义
	parent_context += "\n\n## Your Specific Task\n"
	parent_context += "You are: **%s**\n" % child_name
	parent_context += "Your parent (%s) assigned you:\n%s\n\n" % [node_id, task_desc]
	parent_context += "Focus ONLY on this task. When you have enough information, write your summary and stop.\n"

	# 2. 文件索引（路径 + 一行摘要）— 子节点可直接引用，无需重读
	if not _file_summaries.is_empty():
		parent_context += "\n\n## Parent's File Index (already analyzed — use these summaries instead of re-reading)\n"
		for fp in _file_summaries:
			parent_context += "- `%s`: %s\n" % [fp, _file_summaries[fp]]

	# 3. 仅路径（无摘要的文件，如 inspect_scene 结果）
	var bare_paths: Array = []
	for f in _read_files:
		if f not in _file_summaries:
			bare_paths.append(f)
	if not bare_paths.is_empty():
		parent_context += "\n\n## Parent Also Read (no summary available)\n%s\n" % "\n".join(bare_paths)

	# 4. 父节点的领域知识
	if not domain_knowledge.is_empty():
		var trimmed: String = domain_knowledge.substr(0, 2000)
		parent_context += "\n\n## Parent's Domain Knowledge\n"
		parent_context += "%s\n" % trimmed

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
	# 转发子节点状态/工具事件到父链 — Agent Graph 实时感知整棵树的运行状态
	# 透传来源节点 id（而非父节点自身 id），监控方能精确定位是哪个节点在变化
	child.state_changed.connect(func(origin_id: String):
		state_changed.emit(origin_id)
	)
	child.progress_tool_started.connect(func(tool_name: String):
		progress_tool_started.emit(tool_name)
	)
	child.progress_tool_finished.connect(func(tool_name: String, ok: bool):
		progress_tool_finished.emit(tool_name, ok)
	)
	child.progress_done.connect(func():
		_pending_children[child_name] = true
		_child_reports[child_name] = child.generate_report()
		_log("Child %s completed" % child_name)
		state_changed.emit(node_id)
	)
	child.progress_error.connect(func(err: String):
		_log("Child %s error: %s" % [child_name, err])
	)
	_signals_connected[child_name] = true

	_children[child_name] = child
	_pending_children[child_name] = false
	state_changed.emit(node_id)  # 新子节点诞生 — 通知 Agent Graph 立即刷新

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
	child._parent_ref = weakref(self)  # 轮数预算申请通道
	# 从磁盘恢复的子节点没有内存态 prompt/tools — 从父节点继承基础配置，
	# 否则 system 消息为空 + tools=0，API 直接 400，子节点必熔断失败
	if child.system_prompt.is_empty():
		child.system_prompt = system_prompt
	if child.tool_definitions.is_empty():
		child.tool_definitions = tool_definitions

	# 轻量唤醒 — 不回灌历史对话。
	# 节点 = 蒸馏后的上下文：domain_knowledge（每次运行结束的自总结）+
	# managed_files + file_summaries 已在 _build_node_context() 中注入。
	# 原始对话是一次性流水，不属于节点本体（架构文档第四节）。
	child.prior_messages = []

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
		# 转发子节点状态/工具事件到父链 — Agent Graph 实时感知整棵树的运行状态
		# 透传来源节点 id（而非父节点自身 id），监控方能精确定位是哪个节点在变化
		child.state_changed.connect(func(origin_id: String):
			state_changed.emit(origin_id)
		)
		child.progress_tool_started.connect(func(tool_name: String):
			progress_tool_started.emit(tool_name)
		)
		child.progress_tool_finished.connect(func(tool_name: String, ok: bool):
			progress_tool_finished.emit(tool_name, ok)
		)
		child.progress_done.connect(func():
			_pending_children[child_name] = true
			_child_reports[child_name] = child.generate_report()
			_log("Child %s completed (routed)" % child_name)
			state_changed.emit(node_id)
		)
		child.progress_error.connect(func(err: String):
			_log("Child %s error: %s" % [child_name, err])
		)
		_signals_connected[child_name] = true

	_pending_children[child_name] = false
	state_changed.emit(node_id)  # 子节点被重新激活 — 通知 Agent Graph 刷新

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
	_set_node_state(NodeState.FAILED)
	for cname in _children:
		_children[cname].abort()


func generate_report() -> Dictionary:
	var children_reports: Dictionary = {}
	for cname in _child_reports:
		children_reports[cname] = _child_reports[cname]
	var fresh_output: bool = state == "COMPLETED" and _round_count > 0
	# 本次未正常完成时，summary 是上次运行留下的旧知识 — 必须明确标注，
	# 否则父节点会把过时知识误当本次任务成果（曾导致 Root 把熔断失败的
	# 子节点判断为"实际已完成"）
	var summary_text: String = domain_knowledge
	if not fresh_output:
		summary_text = "[警告：本节点本次运行未产出新结果（status=%s, rounds=%d）。以下是上次运行持久化的旧知识，不代表本次任务已完成]\n%s" % [state, _round_count, domain_knowledge]
	var report: Dictionary = {
		"node_id": node_id,
		"status": state,
		"fresh_output": fresh_output,
		"summary": summary_text,
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
		# messages 不持久化（见下），但最后一次运行的上下文大小要留下来，
		# 否则重启编辑器后图上 CTX 全部归零
		"ctx_size": get_ctx_size(),
		# 不持久化原始 messages — 节点只带蒸馏后的总结（domain_knowledge），
		# 原始对话是一次性流水，持久化会导致重激活时上下文爆炸
		"file_summaries": _file_summaries.duplicate(),
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
	# 兼容旧格式：忽略已废弃的 "messages" 字段（原始对话不再回灌）
	# 恢复上次运行保存的上下文大小 — messages 为空时供 get_ctx_size 展示
	node._persisted_ctx_size = int(data.get("ctx_size", 0))
	# 加载文件摘要
	var fs = data.get("file_summaries", {})
	if fs is Dictionary:
		for key in fs:
			node._file_summaries[str(key)] = str(fs[key])
			if str(key) not in node._read_files:
				node._read_files.append(str(key))
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


## 判断文本是否是合格的蒸馏总结（含结构化小节），
## 而不是模型泄漏的原始思考流（如 "I notice that... Let me check..."）
func _is_structured_summary(content: String) -> bool:
	return content.contains("##")


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

	if not _file_summaries.is_empty():
		parts.append("")
		parts.append("## Files You Have Read (with summaries)")
		parts.append("You previously read these files. Use these summaries as context — no need to re-read unless you need specific details.")
		for fp in _file_summaries:
			parts.append("- `%s`: %s" % [fp, _file_summaries[fp]])

	if not prior_messages.is_empty():
		parts.append("")
		parts.append("## Prior Conversation")
		parts.append("Your previous conversation is loaded below as context. You already know what was discussed — build on it, don't repeat it.")

	if not children_summaries.is_empty():
		parts.append("")
		parts.append("## Your Child Nodes")
		parts.append("IMPORTANT: These nodes are persistent experts in their domains. Before doing any work yourself, check if the task falls within a child's managed files below. If it does, use route_to_child() — do NOT do the work yourself.")
		for cs in children_summaries:
			var cid: String = str(cs.get("id", ""))
			var cstatus: String = str(cs.get("status", ""))
			var csummary: String = str(cs.get("summary", ""))
			var cfiles = cs.get("files", [])
			var fc: int = cfiles.size() if cfiles is Array else 0
			parts.append("- **%s** [%s] (%d files)" % [cid, cstatus, fc])
			if fc > 0:
				var file_list: String = ""
				for i in range(mini(fc, 8)):
					file_list += str(cfiles[i]) + ", "
				if fc > 8:
					file_list += "... (+%d more)" % (fc - 8)
				parts.append("  Files: %s" % file_list)
			if not csummary.is_empty():
				parts.append("  Knowledge: %s" % csummary.substr(0, 150))

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
