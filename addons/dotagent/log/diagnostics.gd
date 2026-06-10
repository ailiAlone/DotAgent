@tool
class_name SessionDiagnostics
extends RefCounted
## 会话诊断引擎 — 自动检测日志异常，生成诊断报告
##
## 纯函数，输入 session_data，输出 anomalies 数组 + diagnostics.json

## 对 session_data 运行全部诊断规则，返回诊断结果 Dictionary
static func analyze(session_data: Dictionary) -> Dictionary:
	var anomalies: Array = []
	var rounds: Array = session_data.get("rounds", [])

	if rounds.is_empty():
		return _build_result(anomalies, session_data)

	_check_redundant_tools(rounds, anomalies)
	_check_stale_message_count(rounds, anomalies)
	_check_excessive_rounds(rounds, session_data, anomalies)
	_check_read_only_loop(rounds, anomalies)
	_check_slow_llm(rounds, anomalies)
	_check_tool_errors(rounds, anomalies)
	_check_context_pressure(session_data, anomalies)

	return _build_result(anomalies, session_data)


## 规则1：同一工具多次调用且结果相同 → 冗余
static func _check_redundant_tools(rounds: Array, anomalies: Array) -> void:
	var tool_history: Dictionary = {}  # tool_name → [{round, args, summary}]
	for rd in rounds:
		for tc in rd.get("tools", []):
			var name: String = tc.get("name", "")
			if not tool_history.has(name):
				tool_history[name] = []
			tool_history[name].append({
				"round": rd.get("round", 0),
				"args": tc.get("args", {}),
				"summary": tc.get("summary", ""),
			})

	for tname in tool_history:
		var calls: Array = tool_history[tname]
		if calls.size() >= 3:
			# 检查结果是否相同
			var summaries: Array = []
			for c in calls:
				summaries.append(c.get("summary", ""))
			var unique_summaries: Array = []
			for s in summaries:
				if not unique_summaries.has(s):
					unique_summaries.append(s)
			if unique_summaries.size() <= 1:
				anomalies.append({
					"rule": "redundant_tool",
					"severity": "high",
					"tool": tname,
					"count": calls.size(),
					"rounds": _extract_rounds(calls),
					"detail": "%s 被调用 %d 次，结果相同 → AI 可能失忆或陷入循环" % [tname, calls.size()],
				})


## 规则2：每轮发送消息数不增长 → MessageBuilder 引用可能断裂
static func _check_stale_message_count(rounds: Array, anomalies: Array) -> void:
	var counts: Array = []
	for rd in rounds:
		var llm: Dictionary = rd.get("llm", {})
		var sent: int = llm.get("messages_sent", 0)
		counts.append(sent)

	if counts.is_empty():
		return

	# 检查是否所有值相同且 > 0
	var first: int = counts[0]
	if first <= 0:
		return
	var all_same := true
	for c in counts:
		if c != first:
			all_same = false
			break

	if all_same and counts.size() >= 3:
		var total_msgs: int = 0
		for rd in rounds:
			total_msgs += rd.get("llm", {}).get("messages_total", 0)
		if total_msgs > first * counts.size():
			anomalies.append({
				"rule": "stale_message_count",
				"severity": "high",
				"messages_per_round": counts,
				"expected_growth": true,
				"actual_growth": false,
				"detail": "全部 %d 轮 LLM 请求都只发送 %d 条消息，但会话总消息数在增长 → MessageBuilder 可能持有旧数组引用" % [counts.size(), first],
			})


## 规则3：轮次过多但工具种类少 → 可能陷入无效循环
static func _check_excessive_rounds(rounds: Array, session_data: Dictionary, anomalies: Array) -> void:
	var user_msgs: int = session_data.get("statistics", {}).get("user_messages", 0)
	if user_msgs <= 0:
		user_msgs = 1

	var tool_set: Dictionary = {}
	var total_tools := 0
	for rd in rounds:
		for tc in rd.get("tools", []):
			tool_set[tc.get("name", "")] = true
			total_tools += 1

	# 简单任务（1条用户消息）超过 5 轮
	if user_msgs == 1 and rounds.size() > 5:
		anomalies.append({
			"rule": "excessive_rounds",
			"severity": "medium",
			"rounds": rounds.size(),
			"user_messages": user_msgs,
			"detail": "%d 轮完成单条用户请求，正常应 2-5 轮" % rounds.size(),
		})

	# 工具调用中冗余比例过高
	if total_tools > 0:
		var redundancy := 1.0 - float(tool_set.size()) / float(total_tools)
		if redundancy > 0.4:
			anomalies.append({
				"rule": "high_tool_redundancy",
				"severity": "medium",
				"unique_tools": tool_set.size(),
				"total_calls": total_tools,
				"redundancy_ratio": snapped(redundancy, 0.01),
				"detail": "%.0f%% 的工具调用是重复的（%d 种 / %d 次）" % [redundancy * 100, tool_set.size(), total_tools],
			})


## 规则4：连续多轮只有读操作 → 可能卡在"收集信息"阶段
static func _check_read_only_loop(rounds: Array, anomalies: Array) -> void:
	const READ_TOOLS := ["get_project_info", "get_scene_tree", "get_node", "get_node_properties",
		"get_editor_selection", "read_script", "list_scripts", "list_scenes",
		"list_resources", "list_files", "get_project_setting", "get_node_type_info",
		"search_in_scripts", "peek_scene", "focus_editor_view", "screenshot_editor",
		"check_script_syntax", "list_skills", "recall"]

	var consecutive_reads := 0
	var max_consecutive := 0
	for rd in rounds:
		var tools: Array = rd.get("tools", [])
		if tools.is_empty():
			consecutive_reads += 1
			continue
		var all_read := true
		for tc in tools:
			var tname: String = tc.get("name", "")
			if not READ_TOOLS.has(tname):
				all_read = false
				break
		if all_read:
			consecutive_reads += 1
			max_consecutive = max(max_consecutive, consecutive_reads)
		else:
			consecutive_reads = 0

	if max_consecutive >= 3:
		anomalies.append({
			"rule": "read_only_loop",
			"severity": "medium",
			"consecutive_rounds": max_consecutive,
			"detail": "连续 %d 轮只有读操作，没有写操作 → 可能卡在收集信息阶段" % max_consecutive,
		})


## 规则5：LLM 响应时间过长
static func _check_slow_llm(rounds: Array, anomalies: Array) -> void:
	var slow_rounds: Array = []
	for rd in rounds:
		var duration_ms: int = rd.get("llm", {}).get("duration_ms", 0)
		if duration_ms > 30000:
			slow_rounds.append(rd.get("round", 0))

	if not slow_rounds.is_empty():
		anomalies.append({
			"rule": "slow_llm",
			"severity": "low",
			"slow_rounds": slow_rounds,
			"threshold_ms": 30000,
			"detail": "第 %s 轮 LLM 响应超过 30 秒" % str(slow_rounds),
		})


## 规则6：工具返回 error
static func _check_tool_errors(rounds: Array, anomalies: Array) -> void:
	var error_tools: Array = []
	for rd in rounds:
		for tc in rd.get("tools", []):
			if not tc.get("ok", true):
				error_tools.append({
					"round": rd.get("round", 0),
					"tool": tc.get("name", ""),
					"summary": tc.get("summary", ""),
				})

	if not error_tools.is_empty():
		anomalies.append({
			"rule": "tool_errors",
			"severity": "medium",
			"count": error_tools.size(),
			"errors": error_tools,
			"detail": "%d 个工具调用返回了错误" % error_tools.size(),
		})


## 规则7：Context 压力
static func _check_context_pressure(session_data: Dictionary, anomalies: Array) -> void:
	var ctx: Dictionary = session_data.get("context_health", {})
	var pressures: Array = ctx.get("pressure_rounds", [])
	if pressures.size() >= 2:
		anomalies.append({
			"rule": "context_pressure",
			"severity": "low",
			"pressure_rounds": pressures,
			"detail": "%d 轮出现 context 压力（用量 > 60%%)" % pressures.size(),
		})


# ============ 内部工具 ============

static func _extract_rounds(calls: Array) -> Array:
	var r: Array = []
	for c in calls:
		r.append(c.get("round", 0))
	return r


static func _build_result(anomalies: Array, session_data: Dictionary) -> Dictionary:
	var high_count := 0
	var medium_count := 0
	var low_count := 0
	for a in anomalies:
		match a.get("severity", ""):
			"high": high_count += 1
			"medium": medium_count += 1
			"low": low_count += 1

	return {
		"anomalies": anomalies,
		"summary": {
			"total": anomalies.size(),
			"high": high_count,
			"medium": medium_count,
			"low": low_count,
			"healthy": anomalies.is_empty(),
		},
	}


## 将诊断结果写入 diagnostics.json
static func write_to_file(session_dir: String, diagnostics: Dictionary) -> void:
	var path := session_dir.path_join("diagnostics.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Diagnostics] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(diagnostics, "\t"))
	f.close()
