@tool
class_name BanyanRunLog
extends RefCounted
## Banyan 运行日志 — 结构化执行记录（JSON + Markdown）
##
## 每次 run_banyan() 生成一份运行日志，记录:
##   - 所有节点的 ReAct 轮次、LLM 响应、工具调用
##   - 子节点 spawn / 完成 / 失败
##   - 时间线和统计摘要
##
## 输出:
##   run_log.json   — 结构化数据（机器可读）
##   run_log.md     — 人类可读报告（Markdown）
##
## 存储路径: banyan_agent/sessions/{session_id}/

const LOG_DIR_BASE := "res://addons/dotagent/banyan_agent/sessions"

var _session_id: String = ""
var _logger = null


func _init(session_id: String, logger = null) -> void:
	_session_id = session_id
	_logger = logger


## 写入运行日志 — 从根 BanyanNode 收集完整执行轨迹
## trace_data: 根节点的 get_execution_trace() 返回
func write(trace_data: Dictionary) -> Dictionary:
	if _session_id.is_empty():
		return {"ok": false, "error": "No session_id"}

	var dir_path: String = LOG_DIR_BASE.path_join(_session_id)
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# 按运行开始时间命名，避免同一 session 内多次运行互相覆盖
	var stamp: String = str(trace_data.get("started_at", ""))
	if stamp.is_empty():
		stamp = Time.get_datetime_string_from_system()
	stamp = stamp.replace(":", "-").replace(" ", "_")
	var base_name: String = "run_" + stamp

	# 1. 写 JSON
	var json_path: String = dir_path.path_join(base_name + ".json")
	var json_ok: bool = _write_json(json_path, trace_data)

	# 2. 写 Markdown
	var md_path: String = dir_path.path_join(base_name + ".md")
	var md_ok: bool = _write_markdown(md_path, trace_data)

	if _logger:
		_logger.append("RUNLOG", "Run log written: %s (json=%s, md=%s)" % [dir_path, str(json_ok), str(md_ok)])

	return {"ok": json_ok and md_ok, "json_path": json_path, "md_path": md_path}


# ============ JSON ============

func _write_json(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


# ============ Markdown 报告 ============

func _write_markdown(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false

	var lines: Array[String] = []
	_build_markdown(data, lines, 0)

	f.store_string("\n".join(lines))
	f.close()
	return true


func _build_markdown(data: Dictionary, lines: Array[String], depth: int) -> void:
	var node_id: String = str(data.get("node_id", "Unknown"))
	var status: String = str(data.get("status", "UNKNOWN"))
	var model: String = str(data.get("model", ""))
	var started_at: String = str(data.get("started_at", ""))
	var duration_sec: float = float(data.get("duration_sec", 0.0))
	var rounds: Array = data.get("rounds", [])
	var summary: String = str(data.get("summary", ""))
	var children_traces: Array = data.get("children", [])

	# 标题
	var heading: String = "#"
	for d in range(depth):
		heading += "#"
	lines.append("%s %s — %s" % [heading, node_id, status])
	lines.append("")

	# 元信息
	lines.append("- **Model:** %s" % model)
	lines.append("- **Started:** %s" % started_at)
	lines.append("- **Duration:** %.1fs" % duration_sec)
	lines.append("- **Rounds:** %d" % rounds.size())

	# 统计
	var total_tools: int = 0
	var tool_errors: int = 0
	var tool_freq: Dictionary = {}
	for r in rounds:
		var tools: Array = r.get("tools", [])
		for t in tools:
			var tname: String = str(t.get("name", ""))
			tool_freq[tname] = int(tool_freq.get(tname, 0)) + 1
			total_tools += 1
			if not t.get("ok", true):
				tool_errors += 1

	lines.append("- **Tool calls:** %d (%d errors)" % [total_tools, tool_errors])
	if not tool_freq.is_empty():
		var freq_parts: Array = []
		for tname in tool_freq:
			freq_parts.append("%s(%d)" % [tname, tool_freq[tname]])
		lines.append("- **Tool frequency:** %s" % ", ".join(freq_parts))
	lines.append("")

	# 轮次详情
	if not rounds.is_empty():
		lines.append("## Rounds" if depth == 0 else "### Rounds")
		lines.append("")
		for i in range(rounds.size()):
			var r: Dictionary = rounds[i]
			var round_num: int = int(r.get("round", i + 1))
			var llm_preview: String = str(r.get("llm_preview", "")).substr(0, 120)
			var round_tools: Array = r.get("tools", [])

			lines.append("**Round %d**" % round_num)
			if not llm_preview.is_empty():
				lines.append("> %s" % llm_preview.replace("\n", " "))
				lines.append("")

			if not round_tools.is_empty():
				for t in round_tools:
					var tname: String = str(t.get("name", ""))
					var tok: bool = t.get("ok", true)
					var tresult: String = str(t.get("result_preview", "")).substr(0, 150)
					var icon: String = "OK" if tok else "FAIL"
					lines.append("- `%s` [%s]" % [tname, icon])
					if not tresult.is_empty():
						lines.append("  > %s" % tresult.replace("\n", " "))
				lines.append("")

	# 子节点
	if not children_traces.is_empty():
		lines.append("## Children" if depth == 0 else "### Children")
		lines.append("")
		for child_trace in children_traces:
			if child_trace is Dictionary:
				_build_markdown(child_trace, lines, depth + 1)
				lines.append("")

	# 总结
	if not summary.is_empty():
		lines.append("## Summary" if depth == 0 else "### Summary")
		lines.append("")
		lines.append(summary)
		lines.append("")


# ============ 内部 ============

func _log(msg: String) -> void:
	if _logger:
		_logger.append("RUNLOG", msg)
