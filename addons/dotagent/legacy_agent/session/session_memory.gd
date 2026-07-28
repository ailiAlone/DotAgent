@tool
class_name SessionMemory
extends RefCounted
## 会话级记忆 — 跨对话摘要存储
##
## 每次对话（用户提问 + AI 多轮回应）结束后，生成一段摘要存入此处。
## 下一次对话开始时，摘要被注入到 system prompt 中，替代原始历史消息。
##
## 数据流:
##   send_user_message() 结束 → _generate_summary() → add_summary()
##   send_user_message() 开始 → get_context() → 注入 system prompt

var summaries: Array[Dictionary] = []


## 追加一条摘要
func add_summary(user_message: String, summary_text: String) -> void:
	summaries.append({
		"time": Time.get_datetime_string_from_system(),
		"user_message": _truncate(user_message, 200),
		"summary": summary_text,
	})


## 生成注入 system prompt 的上下文文本
func get_context() -> String:
	if summaries.is_empty():
		return ""

	var lines: Array[String] = []
	lines.append("## 📋 会话记忆（本 Session 中之前的对话摘要）")
	lines.append("")
	for i in range(summaries.size()):
		var s := summaries[i]
		lines.append("### 对话 %d — %s" % [i + 1, s.get("time", "")])
		lines.append("> 用户要求: %s" % s.get("user_message", ""))
		lines.append("> 摘要: %s" % s.get("summary", ""))
		lines.append("")

	return "\n".join(lines)


func _truncate(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len) + "…"
