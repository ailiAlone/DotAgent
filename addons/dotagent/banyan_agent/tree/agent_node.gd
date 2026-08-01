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

# 重复读取短路：这些读工具的路径命中 _read_this_run 且未被本轮写过时直接拦截
const REREAD_TOOLS := ["read_script", "read_file", "read_file_tail", "read_multiple_files", "read_resource_as_text"]
# 写工具执行成功后记录路径 — 写后重读属合法验证，不拦截
const WRITE_TRACK_TOOLS := ["update_script", "replace_in_file", "write_file", "patch_scene",
	"create_scene", "create_script", "apply_patch", "edit_script"]

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
var _nudge_count: int = 0              # 本次运行中 nudge 次数（限制 reminder 消息）
var _recent_actions: Array = []         # 最近 6 轮的动作（"nudge"/"execute"/other）用于检测 nudge 占比
var _knowledge_saved_count: int = 0     # 本次运行保存的知识条目数（用于 Completion Challenge 快速通道）
var _spawn_recommended: bool = false    # (deprecated, use _spawn_rec_stage)
var _spawn_rec_stage: int = 0           # spawn 推荐阶段: 0=未推荐, 1=首次(具体方案), 2=二次(强制提醒)
var _routed_this_run: bool = false      # 本次运行是否已 route/spawn 过（路由推荐的前提检查）
var _route_recommended: bool = false    # 本次运行是否已推过路由提醒（只推一次）
var _file_summaries: Dictionary = {}  # path → one-line summary
var _signals_connected: Dictionary = {}
var _read_this_run: Dictionary = {}   # 本轮读取 path → {round, full}（重复读取短路用，每轮运行清空；full=false 为残篇读）
var _written_this_run: Array = []     # 本轮本节点写过的文件（写后重读属合法验证，不拦截）

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
var _usage_input_tokens: int = 0    # 本次运行累计 input tokens（成本度量）
var _usage_output_tokens: int = 0   # 本次运行累计 output tokens
var _syntax_fail_streak: int = 0    # 连续语法校验失败次数（≥2 注入一次定向提醒）
var _syntax_reminded: bool = false  # 本次运行是否已注入过语法提醒
var _fail_sig_counts: Dictionary = {}  # 工具签名(hash)→ 连续失败次数（同参数连败守卫）


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
## max_tokens: 绝对 token 数。默认从 config.cfg 的 max_tokens_k * 1000 读取。
func configure_llm(base_url: String, api_key: String, model: String, max_tokens: int = -1) -> void:
	_base_url = base_url
	_api_key = api_key
	_model = model
	if max_tokens <= 0:
		_max_tokens = ConfigManager.instance().get_max_tokens_k() * 1000
	else:
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
	_nudge_count = 0
	_recent_actions = []
	_knowledge_saved_count = 0
	_spawn_recommended = false
	_spawn_rec_stage = 0
	_routed_this_run = false
	_route_recommended = false
	_usage_input_tokens = 0
	_usage_output_tokens = 0
	_syntax_fail_streak = 0
	_syntax_reminded = false
	_fail_sig_counts.clear()
	_read_this_run.clear()
	_written_this_run.clear()
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

	# 按需注入领域技能 — 任务文本命中 triggers 的技能全文注入为 system 消息（每次运行一次）
	var skills_msg: String = _match_skills(user_msg)
	if not skills_msg.is_empty():
		messages.append({"role": "system", "content": skills_msg})

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
		# ── 自适应 spawn 推荐：任务规模扩大时给模型一个全局视野 ──
		_check_spawn_recommendation()
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

		# 成果校验：零执行 + 零知识产出就收工，大概率是"只分析没干活"。
		# 委派（route/spawn）计入 _exec_actions_this_run — 纯委派运行是合法完成，
		# 不挑战（曾误伤：Root R1 路由 R3 收工被挑战，被迫重复读子节点管辖的文件）。
		# 保存过知识条目 = 有具体产出，跳过挑战直接收束（省一轮 LLM 调用）。
		# 每次运行挑战一次 — 要求继续动手，或明确说明任务本就是纯分析
		if action == ACTION_FINISH and not _completion_challenged \
				and _files_created.is_empty() \
				and _knowledge_saved_count == 0 \
				and _exec_actions_this_run == 0 \
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
			_recent_actions.append("execute")
			if _recent_actions.size() > 6:
				_recent_actions.pop_front()
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
	var analysis_only: bool = _completion_challenged and _files_created.is_empty()
	if not analysis_only:
		await _request_convergence_summary()

	_release_slot()

	# 运行结束 — 更新持久化上下文
	var elapsed: float = (float(Time.get_ticks_msec()) - _run_start_time) / 1000.0
	_execution_trace["duration_sec"] = elapsed
	_execution_trace["status"] = "COMPLETED" if node_state == NodeState.COMPLETED else "FAILED"
	_execution_trace["summary"] = _extract_summary()
	_execution_trace["usage"] = {
		"input_tokens": _usage_input_tokens,
		"output_tokens": _usage_output_tokens,
	}

	# 更新领域知识 — 只接受结构化的蒸馏总结；
	# 原始思考流会被 _request_convergence_summary 用结构化模板重写
	state = "COMPLETED" if node_state == NodeState.COMPLETED else "FAILED"
	var summary: String = _extract_summary()
	if not summary.is_empty() and _is_structured_summary(summary):
		domain_knowledge = summary
	# 更新文件列表 — 只认领真正的"新地盘"（写入 ≠ 拥有）
	_auto_claim_files()
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
			var ctrace: Dictionary = child._execution_trace
			# 子节点还在跑（路由后未等待）— duration/usage 只在 run() 收尾时写入，
			# 这里用实时值补齐并标记，避免 trace 出现 rounds>0 但 duration=0/tokens=0 的假象
			if float(ctrace.get("duration_sec", 0.0)) == 0.0:
				ctrace["duration_sec"] = (float(Time.get_ticks_msec()) - child._run_start_time) / 1000.0
				ctrace["usage"] = {
					"input_tokens": child._usage_input_tokens,
					"output_tokens": child._usage_output_tokens,
				}
				ctrace["status"] = "IN_PROGRESS"
			_execution_trace["children"].append(ctrace)

	progress_done.emit()
	_log("Finished: state=%s rounds=%d duration=%.1fs tokens=%din/%dout" % [state, _round_count, elapsed, _usage_input_tokens, _usage_output_tokens])


# ============ ReAct 循环子步骤 ============

# ============ 自适应 spawn 推荐 ============
#
# 核心发现：system message 被模型当背景噪音忽略，user message 被视为必须回应的请求。
# 两个阶段都用 user message 注入，附带具体 spawn 命令模板。
#
# 触发条件（全部满足）：
#   1. 当前轮次 >= 6（Stage 1）或 >= 12（Stage 2）
#   2. 已读文件数 >= 4（领域在扩大）
#   3. 尚无子节点（还没拆过）
# 任意节点都可分裂（架构文档第九节：反对叶子节点限制）— 不只 Root

const SPAWN_REC_ROUND_THRESHOLD := 6
const SPAWN_REC_FILE_THRESHOLD := 4
const SPAWN_REC_STAGE2_ROUND := 12
const NEW_DOMAIN_REC_ROUND := 4   # 新领域 spawn 推荐的触发轮次（比路由推荐更早——新域越早 spawn 越省）

## 每轮 LLM 请求前调用 — 检测是否应注入 spawn 推荐
func _check_spawn_recommendation() -> void:
	# ── 路由推荐：已有子节点，读了它们管辖的文件却迟迟不路由 ──
	# 实测 Root 会在有专家子节点时仍自己包办全部实现（35 轮 / 210k tokens），
	# 重复加载子节点已持有的知识 — 提醒一次，由模型决定
	if not _children.is_empty() and not _routed_this_run and not _route_recommended \
			and _round_count >= SPAWN_REC_ROUND_THRESHOLD \
			and _read_files.size() >= SPAWN_REC_FILE_THRESHOLD:
		var overlap: Dictionary = _find_child_file_overlap()
		if not overlap.is_empty():
			_route_recommended = true
			var rmsg := "## Routing Reminder\n\nYou have read files managed by your existing children:\n"
			for cname in overlap:
				rmsg += "- **%s** manages: %s\n" % [cname, ", ".join(overlap[cname])]
			rmsg += "\nThese children already hold deep knowledge of those files. Consider `route_to_child` for work in their domains instead of doing everything yourself — it saves your context and keeps expertise where it belongs. If a change truly requires your direct edit, proceed."
			_log("Routing recommendation (round=%d, overlap=%s)" % [_round_count, str(overlap.keys())])
			messages.append({"role": "user", "content": rmsg})

	# ── 新领域 spawn 推荐：已有子节点，但工作落在无人管辖的新领域 ──
	# 实测 R17：magnet_powerup 新域任务，Root 因已有子节点收不到 spawn 推荐
	#（原推荐只对无子节点节点触发），自己包办 27 轮才想起路由。
	# 新领域该 spawn 新专家沉淀知识，而不是自己硬扛或塞给不匹配的子节点。
	if not _children.is_empty() and not _routed_this_run and not _route_recommended \
			and _round_count >= NEW_DOMAIN_REC_ROUND:
		var uncovered: Array = _find_uncovered_files()
		if uncovered.size() >= 2:
			_route_recommended = true
			var nd_msg := "## New Domain Detected\n\nYou are working with files nobody manages — not yours, not any child's: %s\n\n" % ", ".join(uncovered)
			nd_msg += "For a feature spanning 2+ unmanaged files, prefer `spawn_child` to create a specialist for this new domain instead of doing everything yourself — the child keeps the knowledge for next time (your existing children cover other domains). If the change is tiny (a single small edit), proceed yourself."
			_log("New-domain spawn recommendation (round=%d, uncovered=%s)" % [_round_count, str(uncovered)])
			messages.append({"role": "user", "content": nd_msg})

	if _read_files.size() < SPAWN_REC_FILE_THRESHOLD:
		return
	if not _children.is_empty():
		return

	var domain_map: Dictionary = _detect_domains_dict(_read_files)
	var active_domains: Array = []
	for domain in domain_map:
		if not domain_map[domain].is_empty():
			active_domains.append(domain)

	# ── 第一阶段：轮次>=6，具体 spawn 方案（user message 格式） ──
	if _spawn_rec_stage == 0 and _round_count >= SPAWN_REC_ROUND_THRESHOLD and active_domains.size() >= 2:
		_spawn_rec_stage = 1
		_spawn_recommended = true
		var msg: String = _build_spawn_plan(active_domains, domain_map)
		_log("Spawn recommendation STAGE 1 (round=%d, files=%d, domains=%d)" % [_round_count, _read_files.size(), active_domains.size()])
		messages.append({"role": "user", "content": msg})

	# ── 第二阶段：轮次>=12 且仍无子节点，更强约束（user message） ──
	elif _spawn_rec_stage == 1 and _round_count >= SPAWN_REC_STAGE2_ROUND and _children.is_empty():
		_spawn_rec_stage = 2
		var domain_list: String = ", ".join(active_domains)
		var msg: String = "URGENT: You are on round %d with %d files across %d domains (%s) and ZERO children.\n\n" % [
			_round_count, _read_files.size(), active_domains.size(), domain_list]
		msg += "This is exactly the scenario spawn_child is designed for. You MUST do one of the following NOW:\n\n"
		msg += "**Option A (preferred):** Call spawn_child for at least 2 domains:\n"
		for i in range(active_domains.size()):
			var d: String = active_domains[i]
			var flist: String = ", ".join(domain_map[d])
			msg += "  - spawn_child(name='%s', task_description='Handle %s files: %s')\n" % [d.capitalize().replace(" ", ""), d, flist]
		msg += "  Then call wait_for_children.\n\n"
		msg += "**Option B:** If you believe the domains are tightly coupled and CANNOT be parallelized, "
		msg += "respond with a one-line explanation of which files have cross-dependencies that prevent parallel work.\n\n"
		msg += "Do NOT continue modifying files alone without addressing this."
		_log("Spawn recommendation STAGE 2 (round=%d, files=%d, domains=%d)" % [_round_count, _read_files.size(), active_domains.size()])
		messages.append({"role": "user", "content": msg})


## 构建具体的 spawn 方案 — 给模型一个可直接执行的模板
func _build_spawn_plan(active_domains: Array, domain_map: Dictionary) -> String:
	var msg: String = "## Task Decomposition Plan\n\n"
	msg += "Progress: **%d rounds**, **%d files read**, **%d domains detected**.\n\n" % [_round_count, _read_files.size(), active_domains.size()]
	msg += "This task spans multiple independent domains. Recommended parallel approach:\n\n"

	# 为每个活跃领域生成具体建议
	for i in range(active_domains.size()):
		var domain: String = active_domains[i]
		var files: Array = domain_map[domain]
		var child_name: String = domain.capitalize().replace(" ", "")
		msg += "### Child %d: `%s`\n" % [i + 1, child_name]
		msg += "**Files:** %s\n" % ", ".join(files)
		msg += "**Task:** Handle all %s-related modifications. You already know these files from the parent's analysis.\n\n" % domain

	msg += "### Execution Steps\n"
	msg += "1. Call `spawn_child` for each domain above (can batch in one round)\n"
	msg += "2. Call `wait_for_children` to collect results\n"
	msg += "3. Integrate results and finish\n\n"
	msg += "**Why this helps:** Children run in parallel — a 3-domain task that takes you 30 rounds alone can finish in ~10 rounds with 3 children.\n"
	return msg


## 从文件路径列表推断领域分组，返回 domain→files 映射
func _find_child_file_overlap() -> Dictionary:
	var overlap: Dictionary = {}
	for f in _read_files:
		for cname in _children:
			var child = _children[cname]
			if child.managed_files.has(f):
				if not overlap.has(cname):
					overlap[cname] = []
				overlap[cname].append(f)
	return overlap


## 找出本轮读取/创建中"无人管辖"的文件 — 不在自己名下，也不在任何子节点名下。
## 用于新领域 spawn 推荐：这些文件代表一片没有专家的处女地。
func _find_uncovered_files() -> Array:
	var covered: Dictionary = {}
	for f in managed_files:
		covered[str(f)] = true
	for cname in _children:
		var child: AgentNode = _children[cname]
		if child == null:
			continue
		for f in child.managed_files:
			covered[str(f)] = true
	var out: Array = []
	for f in _read_files + _files_created:
		var fp: String = str(f)
		if not covered.has(fp) and fp not in out:
			out.append(fp)
	return out


## 从文件路径列表推断领域分组，返回 domain→files 映射
func _detect_domains_dict(files: Array) -> Dictionary:
	var domain_map: Dictionary = {
		"player": [], "enemy": [], "boss": [],
		"bullet": [], "weapon": [], "powerup": [],
		"ui": [], "menu": [],
		"game": [], "audio": [],
		"config": [], "manager": [],
	}
	var domain_keywords: Dictionary = {
		"player": ["player", "character", "hero"],
		"enemy": ["enemy", "mob", "foe"],
		"boss": ["boss"],
		"bullet": ["bullet", "projectile", "shot"],
		"weapon": ["weapon", "gun", "cannon"],
		"powerup": ["powerup", "pickup", "item"],
		"ui": ["hud", "label", "button", "panel", "canvas"],
		"menu": ["menu", "game_over", "title", "pause"],
		"game": ["game", "wave", "level", "stage"],
		"audio": ["audio", "sound", "music", "sfx", "bgm"],
		"config": ["config", "settings", "save", "data"],
		"manager": ["manager", "controller", "system"],
	}

	for f in files:
		var fname: String = f.get_file().to_lower()
		var matched: bool = false
		for domain in domain_keywords:
			for kw in domain_keywords[domain]:
				if kw in fname:
					domain_map[domain].append(f)
					matched = true
					break
			if matched:
				break
	return domain_map


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
			_nudge_count += 1
			_recent_actions.append("nudge")
			if _recent_actions.size() > 6:
				_recent_actions.pop_front()
			# 滑动窗口检测：最近 6 轮中 4+ 轮是 nudge → 强制停止
			var nudge_in_window: int = 0
			for a in _recent_actions:
				if a == "nudge":
					nudge_in_window += 1
			if nudge_in_window >= 4:
				# 硬限制：nudge 占比过高 — 拒绝执行工具，强制 LLM 停下来思考
				_log("Round %d: %d/%d recent rounds are nudge — HARD STOP, refusing tool execution" % [_round_count, nudge_in_window, _recent_actions.size()])
				messages.append({
					"role": "user",
					"content": "STOP. %d of your last 6 rounds had tool calls without any reasoning. Do NOT call any tools in your next reply. Instead, write a brief plan: what is your goal, what have you accomplished so far, and what is your next step. Then resume work with reasoning before each tool call." % nudge_in_window,
				})
			else:
				# 软 nudge：正常执行工具，但前 2 次附加提醒消息
				_log("Round %d: tool calls without reasoning — soft nudge (executing + reminder)" % _round_count)
				_set_node_state(NodeState.TOOL_EXEC)
				await _execute_tool_round(last_msg.tool_calls)
				if _nudge_count <= 2:
					messages.append({
						"role": "system",
						"content": "Reminder: Before calling tools, briefly explain your reasoning — what you need to learn, why this tool is the right step, and what you expect to find.",
					})
			return false

		ACTION_EXECUTE:
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
			_log("Round %d: finish attempted with zero files — challenging" % _round_count)
			messages.append({
				"role": "user",
				"content": "Before finishing, check your work: this run produced no file changes (no files created, modified, or written). If the task requires real changes, keep working — build/create/modify with execution tools, or delegate with spawn_child/route_to_child. A plan or analysis is NOT completion. Only finish without changes if the task is purely a question or analysis request — in that case state explicitly that no changes were needed and deliver your final answer.",
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
	var pre_convergence_state: int = node_state  # 保存收束前状态，防止 FAILED 被洗成 COMPLETED
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
		if pre_convergence_state != NodeState.FAILED:
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
	var base: String = MsgBldr._format_ticket(ticket)
	return base + _build_delegation_hint(base)


## 任务消息末尾的分工提示 — 紧凑列出子节点管辖，任务文本命中时点名。
## 实测 R10：system 上下文里已有 "Your Child Nodes" 详表，Root 仍先自己
## patch hud.tscn、拖到第 7 轮才路由 — 提示贴在任务消息里才不被忽略。
func _build_delegation_hint(task_text: String) -> String:
	if _children.is_empty():
		return ""
	var lower_task: String = task_text.to_lower()
	var lines: Array = []
	var any_hit: bool = false
	for cname in _children:
		var child: AgentNode = _children[cname]
		if child == null or child.managed_files.is_empty():
			continue
		var hits: Array = []
		for f in child.managed_files:
			var stem: String = str(f).get_file().get_basename().to_lower()
			if stem.length() >= 3 and lower_task.contains(stem):
				hits.append(str(f))
		var files_brief: String = ", ".join(child.managed_files.slice(0, mini(child.managed_files.size(), 5) - 1))
		if not hits.is_empty():
			any_hit = true
			lines.append("- **%s** → %s  ◀ 本任务命中: %s" % [cname, files_brief, ", ".join(hits)])
		else:
			lines.append("- **%s** → %s" % [cname, files_brief])
	if lines.is_empty():
		return ""
	var hint := "\n\n## Delegation Map (orchestrator)\n这些文件各有专家子节点管辖：\n" + "\n".join(lines)
	if any_hit:
		hint += "\n本任务明确涉及上面点名的文件——先把那部分用 route_to_child 委派（task_description 里带完整上下文），再做你自己的部分。不要亲自读/改它们管辖的文件，除非委派失败。"
	else:
		hint += "\n涉及以上文件的工作请 route_to_child，不要亲自读/改。"
	return hint


func execute_tool(tc_name: String, args_raw: String) -> Dictionary:
	var result: Dictionary

	# ── 本轮重复读取短路 ──
	# 同一文件本轮已全量读过、且之后本节点没写过它，再读就是纯浪费（实测 R10：
	# Root R1 read_multiple_files 后 R3/R4 又单读同两个文件，白花 ~4k in）。
	# 写后重读属合法验证，不拦；怀疑外部变更可传 "force": true 绕过。
	# 上次读到的是残篇（truncated/tail）时不拦 — 拿全量是正当需求（R11 实测：
	# read_multiple_files 默认截断 2500 字，模型不得不再读一次全文）。
	if tc_name in REREAD_TOOLS:
		var read_args: Variant = JSON.parse_string(args_raw)
		if read_args is Dictionary and not read_args.get("force", false):
			var req_paths: Array = _extract_paths(read_args)
			var dupes: Array = []
			for p in req_paths:
				var rec: Variant = _read_this_run.get(p, null)
				if not (rec is Dictionary) or p in _written_this_run:
					continue
				# 全量已读 → 拦一切重读；残篇读 → 只拦同工具的完全重复
				#（换工具拿全量放行；R19 实测同文件 read_file_tail 连读两次纯属焦虑）
				if rec.get("full", false) or str(rec.get("tool", "")) == tc_name:
					dupes.append(p)
			if not req_paths.is_empty() and dupes.size() == req_paths.size():
				var first_rec: Dictionary = _read_this_run[dupes[0]]
				return {
					"ok": true,
					"content": "[重复读取拦截] %s 你在本轮第 %d 轮已经用相同方式读过，且之后没有修改过——内容就在你上面的上下文里，直接使用。如确需重读（文件被外部改动或需要更多内容），请在参数中加 \"force\": true。" % [
						", ".join(dupes), int(first_rec.get("round", 0))],
				}

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
		if tc_name in REREAD_TOOLS:
			var parsed_args: Variant = JSON.parse_string(args_raw)
			if parsed_args is Dictionary:
				# 残篇读（截断/tail）不算"已持有全文"——后续全量读放行；
				# 全量记录不被残篇读降级
				var result_text: String = str(result.get("content", ""))
				var got_full: bool = tc_name != "read_file_tail" \
					and not result_text.contains("[truncated]") \
					and not result_text.contains("TRUNCATED")
				for p in _extract_paths(parsed_args):
					var prev: Variant = _read_this_run.get(p, null)
					if got_full or not (prev is Dictionary and prev.get("full", false)):
						_read_this_run[p] = {"round": _round_count, "full": got_full, "tool": tc_name}
					if p not in _read_files:
						_read_files.append(p)
				# 读子节点管辖的文件 → 结果末尾追加分权提醒（不阻断）。
				# 实测 R11：Root 委派后仍亲自读 hud.gd 全文， jurisdictional
				# 提示放在 system 上下文里被忽略，贴在工具结果里才看得见
				if not _children.is_empty():
					var note: String = _jurisdiction_note(_extract_paths(parsed_args))
					if not note.is_empty():
						result["content"] = result_text + note
		elif tc_name in WRITE_TRACK_TOOLS:
			var parsed_args: Variant = JSON.parse_string(args_raw)
			if parsed_args is Dictionary:
				var wpaths: Array = _extract_paths(parsed_args)
				for p in wpaths:
					if p not in _written_this_run:
						_written_this_run.append(p)
				# 直接改子节点管辖的文件 → 结果末尾追加告诫（下次先委派）
				if not _children.is_empty():
					var wnote: String = _jurisdiction_write_note(wpaths)
					if not wnote.is_empty():
						result["content"] = str(result.get("content", "")) + wnote
		elif tc_name in ["inspect_scene_structured", "extract_script_interface"]:
			var parsed_args: Variant = JSON.parse_string(args_raw)
			if parsed_args is Dictionary:
				var fp: String = str(parsed_args.get("path", parsed_args.get("scene_path", "")))
				if not fp.is_empty() and fp not in _read_files:
					_read_files.append(fp)

	return result


## 若读取路径落在子节点管辖范围，生成一行提醒（附在工具结果末尾）
func _jurisdiction_note(paths: Array) -> String:
	var hits: Dictionary = {}
	for p in paths:
		for cname in _children:
			var child: AgentNode = _children[cname]
			if child != null and p in child.managed_files:
				if not hits.has(p):
					hits[p] = cname
	if hits.is_empty():
		return ""
	var parts: Array = []
	for p in hits:
		parts.append("%s → %s" % [p, hits[p]])
	return "\n\n[管辖提醒] 以上文件由子节点管辖（%s）。它持有这些文件的最新知识——相关改动请 route_to_child，不要亲自读改，除非只是快速确认。" % ", ".join(parts)


## 写子节点管辖文件后的告诫（写已发生，重点在下次先委派）。
## 实测 R13：Root 委派 Ui 后仍亲自 patch_scene 改 hud.tscn——子节点持有的
## 蒸馏知识与文件实际状态从此脱节，下次它醒来会基于过期认知工作。
## 重叠管辖（自己也管该文件）时降级为一致性提示。
func _jurisdiction_write_note(paths: Array) -> String:
	var strong: Array = []
	var overlap: Array = []
	for p in paths:
		for cname in _children:
			var child: AgentNode = _children[cname]
			if child != null and p in child.managed_files:
				if p in managed_files:
					if "%s → %s" % [p, cname] not in overlap:
						overlap.append("%s → %s" % [p, cname])
				elif "%s → %s" % [p, cname] not in strong:
					strong.append("%s → %s" % [p, cname])
	var note: String = ""
	if not strong.is_empty():
		note += "\n\n[管辖告诫] 你刚刚直接修改了子节点管辖的文件（%s）。该节点持有这些文件的蒸馏知识，你的直接改动已与它的认知脱节。下次涉及这些文件的改动请先 route_to_child；本次请确认改动与子节点已有实现不冲突。" % ", ".join(strong)
	if not overlap.is_empty():
		note += "\n\n[管辖提示] 刚修改的文件同时由你和子节点管辖（%s）。为保持知识一致，这类改动优先 route_to_child 委派。" % ", ".join(overlap)
	return note


## 从工具参数里提取文件路径（兼容单 path / paths 数组 / 各种 path 别名）
func _extract_paths(parsed_args: Dictionary) -> Array:
	var out: Array = []
	if parsed_args.get("paths") is Array:
		for p in parsed_args["paths"]:
			var ps: String = str(p)
			if not ps.is_empty() and ps not in out:
				out.append(ps)
	else:
		for key in ["path", "file_path", "scene_path", "script_path"]:
			var fp: String = str(parsed_args.get(key, ""))
			if not fp.is_empty() and fp not in out:
				out.append(fp)
	return out


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
			_knowledge_saved_count += 1
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

	# 根据 URL 自动检测 provider 格式（OpenAI / Anthropic / Ollama）
	var provider: LLMProvider = ProviderFactory.create_for_url(_base_url, _api_key)
	var url_info: Dictionary = Pool.parse_url(provider.get_base_url())
	var endpoint: String = Pool.get_endpoint_with_provider(provider)

	var body: String = Pool.build_request_body_with_provider(provider, _model, send_msgs, tool_definitions, true, _max_tokens)
	var headers: PackedStringArray = Pool.build_headers_with_provider(provider)

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
	# 累计 token 用量 — 成本度量进执行轨迹
	_usage_input_tokens += int(_current_slot.usage.get("input_tokens", 0))
	_usage_output_tokens += int(_current_slot.usage.get("output_tokens", 0))
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

		# 连续语法失败 → 注入一次定向提醒（user 消息才会被模型当回事）。
		# 实测 MiniMax-M2.7 会连续 3 次写出同类型语法错误，每次浪费一整轮
		var result_text: String = str(result.get("content", ""))
		if tc_name in EXECUTION_TOOLS:
			if ok:
				_syntax_fail_streak = 0
			elif "Parse Error" in result_text or "Syntax validation failed" in result_text:
				_syntax_fail_streak += 1
				if _syntax_fail_streak >= 2 and not _syntax_reminded:
					_syntax_reminded = true
					messages.append({
						"role": "user",
						"content": "Your last %d file modifications failed GDScript syntax validation. Before retrying, fix the root cause — the most common violations are: missing explicit types (`var x: int = 0`, never `var x = 0` or `:=`), missing return types (`-> void`), untyped for-loop iterators (`for i: int in range(...)`), and code placed before class-level declarations. Re-read the exact parse error above, rewrite the code with ALL type annotations in place, then retry." % _syntax_fail_streak,
					})
					_log("Syntax failure streak %d — injected targeted typing reminder" % _syntax_fail_streak)

		# 同参数连败守卫：同一工具+同一参数连续失败 ≥2 次 → 注入一次换路提醒。
		# 实测 X3：replace_in_file 同一组参数连挂 3 次，每次白烧一整轮上下文。
		var sig: String = tc_name + "|" + str(tc_args_raw.hash())
		if ok:
			_fail_sig_counts.erase(sig)
		else:
			_fail_sig_counts[sig] = int(_fail_sig_counts.get(sig, 0)) + 1
			if int(_fail_sig_counts[sig]) == 2:
				messages.append({
					"role": "user",
					"content": "The exact same tool call (%s) has now failed twice with IDENTICAL arguments — a third identical retry will fail again. Stop and change strategy: re-read the target file to see its CURRENT exact content, fix your match string / preconditions, or switch to a different tool, then retry." % tc_name,
				})
				_log("Same-signature failure streak on %s — injected change-strategy reminder" % tc_name)

		if tc_name in ["build_scene", "build_script", "update_script", "write_file", "patch_scene", "configure_resource"] and ok:
			_track_files(result)
		if tc_name == "replace_in_file" and ok:
			var tc_args: Variant = JSON.parse_string(tc_args_raw)
			if tc_args is Dictionary:
				var p: String = tc_args.get("path", "")
				if not p.is_empty() and p not in _files_created:
					_files_created.append(p)


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


## 运行结束自动认领本轮创建/修改的文件 — 但祖先已管辖的不认。
## 写入 ≠ 拥有：受委派改别人的文件只是"代笔"，不改变管辖权。
## 实测 R12：Ui 受 Root 委派改 game.gd（Root 管辖）后自动认领了它，
## 管辖地图被侵蚀 — 后续 game.gd 任务会被错误路由给 Ui。
func _auto_claim_files() -> void:
	var ancestor_files: Dictionary = {}
	var anc: AgentNode = _parent_ref.get_ref() if _parent_ref else null
	while anc != null:
		for af in anc.managed_files:
			ancestor_files[str(af)] = true
		anc = anc._parent_ref.get_ref() if anc._parent_ref else null
	for f in _files_created:
		if not managed_files.has(f) and not ancestor_files.has(f):
			managed_files.append(f)


# ============ 子节点管理 ============

func _handle_spawn_child(args: Dictionary) -> Dictionary:
	var task_desc: String = args.get("task_description", "")
	if task_desc.is_empty():
		return {"ok": false, "content": "task_description is required"}

	if MAX_CHILDREN > 0 and _children.size() >= MAX_CHILDREN:
		return {"ok": false, "content": "Max children (%d) reached" % MAX_CHILDREN}

	var child_name: String = args.get("name", "Child_%s_%03d" % [node_id, _children.size() + 1])

	_log("Spawning child: %s — %s" % [child_name, task_desc.substr(0, 200)])

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

	# 1b. 输出要求 — 防止子节点结束时空总结导致父节点补救
	parent_context += "\n### Output Requirements\n"
	parent_context += "When you finish, your final message MUST be a structured summary including:\n"
	parent_context += "- Key mechanisms and responsibilities of your domain\n"
	parent_context += "- Public interfaces (signals, exported variables, key methods)\n"
	parent_context += "- Dependencies and callers\n"
	parent_context += "- Issues or concerns found\n"
	parent_context += "Do NOT end with an empty or vague reply. Always deliver a concrete summary.\n"
	parent_context += "\n### Verification Requirements\n"
	parent_context += "- After `patch_scene` / `build_scene`, call `inspect_scene_structured` and confirm the nodes AND properties you intended actually exist in the scene. Your parent will trust your report — an unverified claim (e.g. a button whose `text` was never set) forces the parent to re-read files and redo verification, which is far more expensive than your own check.\n"
	parent_context += "- Run `check_script_syntax` on every script you modified before finishing.\n"
	parent_context += "\n### Efficiency Rules\n"
	parent_context += "- **Batch tool calls in a single round.** If you need to call `save_knowledge` 5 times, do ALL 5 in one tool_calls response — do NOT spread them across 5 separate rounds. Same for `inspect_scene_structured`, `read_script`, etc.\n"
	parent_context += "- **Use `read_multiple_files` instead of individual `read_script` calls** when reading 2+ files.\n"

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

	_routed_this_run = true
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

	_log("Routing to existing child: %s — %s" % [child_name, task_desc.substr(0, 200)])

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

	_routed_this_run = true
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

	# 检测空总结的子节点 — 提示父节点路由补充任务而非自己重做
	var empty_summary: Array = []
	for cname in completed:
		var report: Dictionary = reports.get(cname, {})
		var summary: String = str(report.get("summary", ""))
		if summary.is_empty() or summary.length() < 20:
			empty_summary.append(cname)

	var result_data: Dictionary = {
		"waited_for": target if not target.is_empty() else "ALL",
		"completed": completed,
		"pending": pending,
		"timed_out": elapsed >= timeout and not pending.is_empty(),
		"reports": reports,
	}
	if not empty_summary.is_empty():
		result_data["empty_summary_children"] = empty_summary
		result_data["action_needed"] = "These children finished but produced no summary. Use route_to_child to ask each one for a structured summary of their domain."

	return {"ok": true, "content": JSON.stringify(result_data)}


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
	# 已到终态的节点不覆写 — 优雅收束期间完成的子节点不能被改判 FAILED
	if node_state != NodeState.COMPLETED and node_state != NodeState.FAILED:
		_set_node_state(NodeState.FAILED)
	for cname in _children:
		_children[cname].abort()


## 优雅收束 — 只设置中止标志，让运行中的循环在当前步骤结束后自行走收尾流程
## （记录用量、蒸馏知识、落终态）。与 abort() 的区别：不强制改状态、不立即释放槽位。
## 调用方应给一个宽限期，到期后再用 abort() 硬中止残余节点。
func wind_down() -> void:
	_abort_requested = true
	for cname in _children:
		_children[cname].wind_down()


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
	var restored_state := str(data.get("state", "IDLE"))
	# 上次运行中途被 kill/崩溃时，树里可能残留 RUNNING 等瞬态 ——
	# 进程已死，这些状态永远不会再收敛，必须归一化为终态，
	# 否则驱动器会把死节点当作活跃节点永久空等。
	if restored_state in ["RUNNING", "LLM_REQUEST", "TOOL_EXEC", "RETRYING"]:
		restored_state = "FAILED"
	node.state = restored_state
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

# ============ 领域技能注入 ============
#
# prompts/skills/*.md 每个文件首行以 "# triggers: kw1, kw2, ..." 声明触发关键词。
# 任务文本命中任一关键词即把该技能全文注入为 system 消息（每次运行一次，随消息流每轮携带）。

const SKILLS_DIR := "res://addons/dotagent/banyan_agent/prompts/skills/"
static var _skills_cache: Array = []  # [{name, triggers, content}] — 全进程共享，只扫盘一次


static func _load_skills() -> Array:
	if not _skills_cache.is_empty():
		return _skills_cache
	var dir: DirAccess = DirAccess.open(SKILLS_DIR)
	if dir == null:
		return _skills_cache
	for fname in dir.get_files():
		if not fname.ends_with(".md"):
			continue
		var text: String = FileAccess.get_file_as_string(SKILLS_DIR.path_join(fname))
		if text.is_empty():
			continue
		var triggers: Array = []
		var content: String = text
		var first_line: String = text.get_slice("\n", 0)
		if first_line.begins_with("# triggers:"):
			var raw: String = first_line.trim_prefix("# triggers:").strip_edges()
			for t in raw.split(",", false):
				var kw: String = t.strip_edges().to_lower()
				if not kw.is_empty():
					triggers.append(kw)
			content = text.substr(text.find("\n") + 1).strip_edges()
		_skills_cache.append({"name": fname, "triggers": triggers, "content": content})
	return _skills_cache


## 任务文本命中 triggers 的技能 → 拼成一条 system 消息（未命中返回空串）
func _match_skills(task_text: String) -> String:
	if task_text.is_empty():
		return ""
	var haystack: String = task_text.to_lower()
	var matched: Array = []
	for s in _load_skills():
		for kw in s["triggers"]:
			if haystack.contains(str(kw)):
				matched.append(s)
				break
	if matched.is_empty():
		return ""
	var parts: Array = ["# Domain Skills (auto-injected based on your task — follow these conventions)"]
	var names: Array = []
	for s in matched:
		parts.append("\n---\n" + str(s["content"]))
		names.append(str(s["name"]))
	_log("Skills injected: %s" % ", ".join(names))
	return "\n".join(parts)


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
