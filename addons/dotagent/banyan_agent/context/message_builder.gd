@tool
extends RefCounted
## Banyan 消息构建器 — 为 Worker 节点构建发送给 LLM 的聚焦消息列表。
##
## 与 Legacy MessageBuilder 的区别:
##   - 每个 Worker 有独立的 messages 数组（不含其他 Worker 的消息）
##   - system prompt 由 .md 文件 + TaskTicket 动态注入构成
##   - 消息量天然小（2-5K tokens），不需要 Legacy 的压缩策略
##   - 工具消息截断阈值更高（结构化 JSON 输出本身就是高密度的）

const MAX_TOOL_RESULT_LEN := 16000  # 工具返回截断长度（4000 会把读文件结果拦腰截断，诱使模型反复重读）
const MAX_USER_MSG_LEN := 5000      # 用户消息截断长度
const MAX_MESSAGES := 60            # 滑动窗口：超过此数量时精简旧消息

var _messages: Array  # 对 Worker 独立 messages 数组的引用
var _logger: SessionLog


func setup(messages: Array, logger: SessionLog) -> void:
	_messages = messages
	_logger = logger


## 同步 messages 引用
func resync(messages: Array) -> void:
	_messages = messages


## 构建发送给 LLM 的消息列表
## 实现滑动窗口：消息超过 MAX_MESSAGES 时，保留 system 消息和最近的对话，
## 旧消息用精简摘要替代（防止上下文无限膨胀导致 LLM 响应变慢）
func build() -> Array:
	var system_msgs: Array = []
	var other_msgs: Array = []

	# 分离 system 消息和其他消息
	for msg in _messages:
		if msg.get("role", "") == "system":
			system_msgs.append(msg)
		else:
			other_msgs.append(msg)

	# 滑动窗口安全网（架构文档 §9 拒绝上下文压缩，但需要兜底）：
	# 如果节点长时间不 spawn（合法场景：小任务只需一个节点完成），
	# 消息会累积到数千条，滑动窗口防止 LLM 请求因 token 溢出而失败。
	# 理想情况下 spawn 会自然分流上下文，但实际中不是每个任务都需要 spawn。
	var trimmed_count: int = 0
	if other_msgs.size() > MAX_MESSAGES:
		trimmed_count = other_msgs.size() - MAX_MESSAGES
		# 防止切断 assistant+tool 配对：如果切点落在 tool 消息上，
		# 向后推进到下一个非 tool 消息，避免孤立的 tool_call_id 导致 HTTP 400
		while trimmed_count < other_msgs.size() and other_msgs[trimmed_count].get("role", "") == "tool":
			trimmed_count += 1
		# 统计旧消息中的工具调用
		var old_tool_counts: Dictionary = {}
		for i in range(trimmed_count):
			var msg: Dictionary = other_msgs[i]
			if msg.get("role", "") == "assistant":
				for tc in msg.get("tool_calls", []):
					var fn: Dictionary = tc.get("function", {})
					var tname: String = fn.get("name", "?")
					old_tool_counts[tname] = old_tool_counts.get(tname, 0) + 1
		var tool_summary_parts: Array = []
		for tname in old_tool_counts:
			tool_summary_parts.append("%s(%d)" % [tname, old_tool_counts[tname]])
		var summary_text: String = "Earlier in this conversation, %d messages were exchanged (trimmed for context). Tool usage: %s. Focus on recent messages below." % [trimmed_count, ", ".join(tool_summary_parts) if not tool_summary_parts.is_empty() else "none"]
		var recent: Array = other_msgs.slice(trimmed_count)
		other_msgs = [{"role": "system", "content": summary_text}] + recent

	var result: Array = []
	# 添加 system 消息
	for msg in system_msgs:
		result.append(msg)
	# 添加其他消息（含可能的摘要）
	for msg in other_msgs:
		var role: String = msg.get("role", "")
		match role:
			"system":
				result.append(msg)
			"user":
				result.append({"role": "user", "content": _truncate(msg.get("content", ""), MAX_USER_MSG_LEN)})
			"assistant":
				# 跳过空 assistant 消息（content 为空且无 tool_calls），Kimi API 会拒绝
				var has_content: bool = msg.get("content", "") != "" and msg.get("content", null) != null
				var has_tools: bool = msg.has("tool_calls") and not msg.get("tool_calls", []).is_empty()
				if has_content or has_tools:
					result.append(msg)
			"tool":
				var tc: Dictionary = msg.duplicate(true)
				var no_truncate: bool = tc.get("_no_truncate", false)
				tc.erase("_no_truncate")
				var content: String = str(tc.get("content", ""))
				if not no_truncate and content.length() > MAX_TOOL_RESULT_LEN:
					tc["content"] = content.substr(0, MAX_TOOL_RESULT_LEN) + "…[%d chars]" % content.length()
				result.append(tc)

	if _logger:
		_logger.append("CTX", "Banyan send: %d messages (from %d total, trimmed %d)" % [result.size(), _messages.size(), trimmed_count])
	return result


## 构建 Worker 的初始 system prompt
## 由三部分组成: 预定义 prompt(.md) + 动态上下文 + TaskTicket
static func build_system_prompt(base_prompt: String, ticket: Dictionary, tool_names: Array) -> String:
	var parts: Array = []

	# 1. 基础 system prompt（从 .md 加载）
	if not base_prompt.is_empty():
		parts.append(base_prompt)

	# 2. 动态上下文 — 当前任务信息
	var ticket_info: String = _format_ticket(ticket)
	if not ticket_info.is_empty():
		parts.append("\n## Current Task\n" + ticket_info)

	# 3. 可用工具列表
	if not tool_names.is_empty():
		parts.append("\n## Available Tools\n" + ", ".join(tool_names))

	return "\n".join(parts)


## 将 TaskTicket 格式化为可读文本（注入 system prompt 或 user 消息）
static func _format_ticket(ticket: Dictionary) -> String:
	if ticket.is_empty():
		return ""

	var lines: Array = []

	var scope: String = ticket.get("scope", "")
	if not scope.is_empty():
		lines.append("Scope: %s" % scope)

	var ticket_type: String = ticket.get("type", "")
	if not ticket_type.is_empty():
		lines.append("Type: %s" % ticket_type)

	var requirements: Array = ticket.get("requirements", [])
	if not requirements.is_empty():
		lines.append("Requirements:")
		for req in requirements:
			lines.append("  - %s" % str(req))

	var constraints: Array = ticket.get("constraints", [])
	if not constraints.is_empty():
		lines.append("Constraints:")
		for con in constraints:
			lines.append("  - %s" % str(con))

	var interfaces: Array = ticket.get("interfaces_expected", [])
	if not interfaces.is_empty():
		lines.append("Expected Interfaces:")
		for iface in interfaces:
			lines.append("  - %s" % JSON.stringify(iface))

	return "\n".join(lines)


func _truncate(text: String, max_len: int) -> String:
	if text == null:
		return ""
	if text.length() > max_len:
		return text.substr(0, max_len) + "…[truncated]"
	return text
