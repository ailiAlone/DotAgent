@tool
class_name SessionLog
extends RefCounted
## 会话日志收集器 — v2 结构化日志
##
## 两种记录方式:
## 1. append(source, text) — 自由文本，print 到 console + 写 timeline_event buffer
## 2. record_*(data)       — 结构化事件，用于生成 session.json + timeline.md + diagnostics.json
##
## 结束时 end_session() 生成:
##   session.json      — 结构化数据（单一真相来源）
##   timeline.md       — 人类可读报告（错误优先，轮次表格）
##   messages.json     — Pretty-print 完整消息数组
##   diagnostics.json  — 自动诊断报告
##
## **类名不能用 "Logger",方法名不能用 "log"** — Godot 4.5 有 native 类 Logger 自带 .log(float) 方法

const LOG_ROOT := "res://addons/dotagent/logs"

# ============ 自由文本 ============
var _raw_lines: Array[String] = []  # "HH:MM:SS [SOURCE] text" 格式，实时落盘 + console 输出

# ============ 结构化数据 ============
var _session_data: Dictionary = {}
var _current_round: Dictionary = {}
var _tool_index: int = 0
var _round_start_ticks: int = 0

# ============ 基础状态 ============
var _session_dir: String = ""
var _session_id: String = ""
var _started_at: String = ""

static var _instance: SessionLog = null


## 单例入口
static func instance() -> SessionLog:
	if _instance == null:
		_instance = SessionLog.new()
	return _instance


## 开始新会话（用户发消息时调用）
func start_session() -> String:
	var dt := Time.get_datetime_string_from_system(false).replace(":", "-").replace("T", "_")
	if dt.contains("."):
		dt = dt.split(".")[0]
	_session_id = dt
	_started_at = dt.replace("_", " ")
	_session_dir = LOG_ROOT.path_join(dt)
	DirAccess.make_dir_recursive_absolute(_session_dir)

	_raw_lines.clear()
	_session_data = {
		"session_id": _session_id,
		"started_at": _started_at,
		"model": "",
		"rounds": [],
		"user_messages": [],
		"statistics": {},
		"context_health": {"pressure_rounds": []},
	}
	_current_round = {}
	_tool_index = 0

	append("SESSION", "=== Session started: %s ===" % dt)
	return _session_id


## 结束会话，写入全部文件
func end_session(messages: Array, meta_extra: Dictionary = {}) -> void:
	append("SESSION", "=== Session ended ===")

	# 补全统计
	_compute_statistics(messages, meta_extra)

	# 运行诊断
	var diagnostics := SessionDiagnostics.analyze(_session_data)

	# 写文件
	_write_session_json()
	_write_timeline_md(diagnostics)
	_write_messages_json(messages)
	SessionDiagnostics.write_to_file(_session_dir, diagnostics)

	# 清理
	_raw_lines.clear()
	_session_data = {}
	_current_round = {}
	_session_dir = ""
	_session_id = ""


# ============ 自由文本日志（兼容旧接口）============

## 一行 log：同时 print 到 Godot console + 写 raw_lines + 实时落盘 event_log.txt
func append(source: String, text: String) -> void:
	var t := Time.get_time_string_from_system()
	var line := "%s [%s] %s" % [t, source, text]
	if _session_id.is_empty():
		print(line)
		return
	_raw_lines.append(line)
	print(line)
	_flush_raw_lines()


func warn(text: String) -> void:
	push_warning(text)
	append("WARN", text)


func error(text: String) -> void:
	push_error(text)
	append("ERROR", text)


func get_session_dir() -> String:
	return _session_dir


# ============ 结构化事件记录 ============

## Reactor 每轮开始时调用
func record_round_start(round_num: int) -> void:
	_round_start_ticks = Time.get_ticks_msec()
	_current_round = {
		"round": round_num,
		"started_at": Time.get_time_string_from_system(),
		"llm": {},
		"tools": [],
		"ai_text": "",
	}


## MessageBuilder.build() 后调用，记录本轮发送的消息情况
func record_llm_request(sent_count: int, total_count: int, body_kb: int, l1: int, l2: int, l3: int) -> void:
	var llm: Dictionary = _current_round.get("llm", {})
	llm["messages_sent"] = sent_count
	llm["messages_total"] = total_count
	llm["body_kb"] = body_kb
	llm["l1_rounds"] = l1
	llm["l2_rounds"] = l2
	llm["l3_rounds"] = l3
	llm["request_ticks"] = Time.get_ticks_msec()
	_current_round["llm"] = llm


## Reactor LLM 流式响应完成后调用
func record_llm_response(finish_reason: String, tool_call_count: int, content_len: int) -> void:
	var llm: Dictionary = _current_round.get("llm", {})
	var req_ticks: int = llm.get("request_ticks", _round_start_ticks)
	llm["finish_reason"] = finish_reason
	llm["tool_call_count"] = tool_call_count
	llm["content_len"] = content_len
	llm["duration_ms"] = Time.get_ticks_msec() - req_ticks
	llm.erase("request_ticks")
	_current_round["llm"] = llm


## ToolRegistry 执行完一个工具后调用
func record_tool_result(tool_name: String, ok: bool, duration_ms: int, args: Dictionary, result_text: String) -> void:
	var summary := _summarize_result(result_text)
	_current_round["tools"].append({
		"name": tool_name,
		"ok": ok,
		"duration_ms": duration_ms,
		"args": _safe_args(args),
		"summary": summary,
	})


## Reactor 每轮结束时调用
func record_round_end(ai_text: String) -> void:
	_current_round["ai_text"] = _truncate_text(ai_text, 300)
	var duration_ms := Time.get_ticks_msec() - _round_start_ticks
	_current_round["duration_ms"] = duration_ms
	_session_data["rounds"].append(_current_round.duplicate(true))
	_current_round = {}


## 记录 context 压力（ContextBuilder 在 estimate 后调用）
func record_context_pressure(used_k: int, max_k: int, pct: int) -> void:
	var pressures: Array = _session_data.get("context_health", {}).get("pressure_rounds", [])
	if pct > 60:
		pressures.append({
			"round": _session_data["rounds"].size() + 1,
			"used_k": used_k,
			"max_k": max_k,
			"pct": pct,
		})
		_session_data["context_health"]["pressure_rounds"] = pressures


## 记录用户消息（供 timeline.md 展示）
func record_user_message(text: String) -> void:
	var user_msgs: Array = _session_data.get("user_messages", [])
	user_msgs.append({
		"time": Time.get_time_string_from_system(),
		"text": _truncate_text(text, 500),
	})
	_session_data["user_messages"] = user_msgs


## 设置模型名（从 config 读）
func set_model(model: String) -> void:
	_session_data["model"] = model


# ============ 内部：写文件 ============

## 实时落盘 raw_lines（崩溃时尽量不丢日志）
func _flush_raw_lines() -> void:
	var path := _session_dir.path_join("event_log.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(_raw_lines))
	f.close()


## 写 session.json — 结构化单一真相来源
func _write_session_json() -> void:
	var path := _session_dir.path_join("session.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SessionLog] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(_session_data, "\t"))
	f.close()


## 写 timeline.md — 人类可读报告
func _write_timeline_md(diagnostics: Dictionary) -> void:
	var path := _session_dir.path_join("timeline.md")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SessionLog] Cannot write %s" % path)
		return

	var lines: Array[String] = []
	var sd := _session_data

	# 标题
	lines.append("# 🤖 DotAgent Session Report")
	lines.append("**Session**: %s | **Model**: %s | **Rounds**: %d" % [
		sd.get("session_id", "?"),
		sd.get("model", "?"),
		sd["rounds"].size(),
	])
	var duration := 0
	for rd in sd["rounds"]:
		duration += rd.get("duration_ms", 0)
	lines.append("**Total Duration**: %.1fs | **Started**: %s" % [duration / 1000.0, sd.get("started_at", "?")])
	lines.append("")

	# 诊断摘要（放最前面！）
	_write_diagnostics_summary_md(lines, diagnostics)

	# 统计概览
	_write_stats_md(lines, sd)

	# 每轮详情
	lines.append("---")
	lines.append("")
	for rd in sd["rounds"]:
		_write_round_md(lines, rd, sd)
		lines.append("")

	# 用户消息
	_write_user_messages_md(lines, sd)

	# 工具使用统计
	_write_tool_stats_md(lines, sd)

	f.store_string("\n".join(lines))
	f.close()


func _write_diagnostics_summary_md(lines: Array, diagnostics: Dictionary) -> void:
	var summary: Dictionary = diagnostics.get("summary", {})
	var anomalies: Array = diagnostics.get("anomalies", [])

	if summary.get("healthy", true):
		lines.append("## ✅ 诊断：未发现异常")
		lines.append("")
		return

	lines.append("## ⚠️ 诊断发现（%d 个问题）" % summary.get("total", 0))
	lines.append("")
	lines.append("| 级别 | 问题 |")
	lines.append("|------|------|")
	for a in anomalies:
		var sev_icon := _severity_icon(a.get("severity", ""))
		lines.append("| %s %s | %s |" % [sev_icon, a.get("severity", "?"), a.get("detail", "")])
	lines.append("")


func _write_stats_md(lines: Array, sd: Dictionary) -> void:
	var stats := sd.get("statistics", {})
	lines.append("## 📊 概览")
	lines.append("")
	lines.append("| 指标 | 值 |")
	lines.append("|------|-----|")
	lines.append("| 用户消息 | %d 条 |" % sd.get("user_messages", []).size())
	lines.append("| ReAct 轮次 | %d 轮 |" % sd["rounds"].size())
	lines.append("| 工具调用 | %d 次 |" % stats.get("total_tool_calls", 0))
	lines.append("| LLM 总耗时 | %.1fs |" % (stats.get("total_llm_ms", 0) / 1000.0))
	lines.append("| 工具总耗时 | %.1fs |" % (stats.get("total_tool_ms", 0) / 1000.0))
	lines.append("| 错误 | %d |" % stats.get("errors", 0))
	lines.append("| 警告 | %d |" % stats.get("warnings", 0))

	var redundant: Array = stats.get("redundant_tools", [])
	if not redundant.is_empty():
		lines.append("| ⚠️ 冗余工具 | %s |" % ", ".join(redundant))
	lines.append("")


func _write_round_md(lines: Array, rd: Dictionary, _sd: Dictionary) -> void:
	var rn: int = rd.get("round", 0)
	var ai_text: String = rd.get("ai_text", "")
	var llm: Dictionary = rd.get("llm", {})
	var tools: Array = rd.get("tools", [])
	var duration_ms: int = rd.get("duration_ms", 0)

	lines.append("## 📍 Round %d · %s · %.1fs" % [rn, rd.get("started_at", ""), duration_ms / 1000.0])
	if not ai_text.is_empty():
		lines.append("> 💬 *%s*" % ai_text.replace("\n", " "))
	lines.append("")

	# LLM 请求/响应
	var finish := llm.get("finish_reason", "?")
	var tool_count := llm.get("tool_call_count", 0)
	lines.append("| 事件 | 详情 |")
	lines.append("|------|------|")
	lines.append("| 📤 LLM 请求 | %d msgs / %d total, %dKB (L1=%d L2=%d L3=%d) |" % [
		llm.get("messages_sent", 0), llm.get("messages_total", 0), llm.get("body_kb", 0),
		llm.get("l1_rounds", 0), llm.get("l2_rounds", 0), llm.get("l3_rounds", 0),
	])
	lines.append("| 📥 LLM 响应 | finish=%s, tools=%d, content=%d chars, %dms |" % [
		finish, tool_count, llm.get("content_len", 0), llm.get("duration_ms", 0),
	])

	# 工具调用
	if not tools.is_empty():
		lines.append("| 🔧 工具调用 | 结果 | 耗时 |")
		lines.append("|------|------|------|")
		for tc in tools:
			var ok_mark := "✅" if tc.get("ok", true) else "❌"
			lines.append("| `%s` %s | %s | %dms |" % [
				tc.get("name", "?"), ok_mark, tc.get("summary", ""), tc.get("duration_ms", 0),
			])


func _write_user_messages_md(lines: Array, sd: Dictionary) -> void:
	var user_msgs: Array = sd.get("user_messages", [])
	if user_msgs.is_empty():
		return
	lines.append("---")
	lines.append("")
	lines.append("## 📝 用户消息")
	lines.append("")
	for i in range(user_msgs.size()):
		var um: Dictionary = user_msgs[i]
		lines.append("%d. **%s** — %s" % [i + 1, um.get("time", ""), um.get("text", "")])
	lines.append("")


func _write_tool_stats_md(lines: Array, sd: Dictionary) -> void:
	var stats := sd.get("statistics", {})
	var freq: Dictionary = stats.get("tool_frequency", {})
	if freq.is_empty():
		return
	lines.append("---")
	lines.append("")
	lines.append("## 🛠️ 工具使用统计")
	lines.append("")
	lines.append("| 工具 | 次数 |")
	lines.append("|------|------|")

	# 按次数降序排列
	var sorted := freq.keys()
	sorted.sort_custom(func(a, b): return freq[b] < freq[a])
	for tname in sorted:
		var cnt: int = freq[tname]
		var mark := ""
		if cnt >= 3:
			mark = " ⚠️ 冗余"
		lines.append("| `%s` | %d%s |" % [tname, cnt, mark])
	lines.append("")


# ============ 内部：写 messages.json ============

func _write_messages_json(messages: Array) -> void:
	var path := _session_dir.path_join("messages.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SessionLog] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(messages, "\t"))
	f.close()


# ============ 内部：统计计算 ============

func _compute_statistics(messages: Array, meta_extra: Dictionary) -> void:
	var stats: Dictionary = {
		"total_rounds": _session_data["rounds"].size(),
		"total_tool_calls": 0,
		"total_llm_ms": 0,
		"total_tool_ms": 0,
		"tool_frequency": {},
		"errors": 0,
		"warnings": 0,
		"redundant_tools": [],
	}

	# 从 rounds 汇总
	for rd in _session_data["rounds"]:
		stats["total_llm_ms"] += rd.get("llm", {}).get("duration_ms", 0)
		for tc in rd.get("tools", []):
			stats["total_tool_calls"] += 1
			stats["total_tool_ms"] += tc.get("duration_ms", 0)
			var tname: String = tc.get("name", "")
			stats["tool_frequency"][tname] = stats["tool_frequency"].get(tname, 0) + 1
			if not tc.get("ok", true):
				stats["errors"] += 1

	# 检测冗余工具（≥4 次）
	for tname in stats["tool_frequency"]:
		if stats["tool_frequency"][tname] >= 4:
			stats["redundant_tools"].append("%s×%d" % [tname, stats["tool_frequency"][tname]])

	# 合并外部元信息
	for k in meta_extra:
		stats[k] = meta_extra[k]

	_session_data["statistics"] = stats


# ============ 内部：工具 ============

func _summarize_result(text: String) -> String:
	if text.is_empty():
		return "(无返回)"
	# 找第一行有意义的内容
	var lines := text.split("\n")
	var first := ""
	for line in lines:
		var stripped := line.strip_edges()
		if not stripped.is_empty() and not stripped.begins_with("{"):
			first = stripped
			break
	if first.is_empty():
		first = text.substr(0, 120).replace("\n", " ")
	return _truncate_text(first, 150)


func _truncate_text(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len) + "…"


func _safe_args(args: Dictionary) -> Dictionary:
	var safe := {}
	for k in args:
		var v = args[k]
		if typeof(v) == TYPE_STRING:
			safe[k] = _truncate_text(v, 100)
		elif typeof(v) == TYPE_DICTIONARY:
			safe[k] = "(object)"
		elif typeof(v) == TYPE_ARRAY:
			safe[k] = "[%d items]" % v.size()
		else:
			safe[k] = v
	return safe


func _severity_icon(severity: String) -> String:
	match severity:
		"high": return "🔴"
		"medium": return "🟡"
		"low": return "🔵"
	return "⚪"
