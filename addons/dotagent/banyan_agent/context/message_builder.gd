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

var _messages: Array  # 对 Worker 独立 messages 数组的引用
var _logger: SessionLog


func setup(messages: Array, logger: SessionLog) -> void:
	_messages = messages
	_logger = logger


## 同步 messages 引用
func resync(messages: Array) -> void:
	_messages = messages


## 构建发送给 LLM 的消息列表
## 对 Worker 来说，messages 本身就是聚焦的，只需做轻度截断
func build() -> Array:
	var result: Array = []

	for msg in _messages:
		var role: String = msg.get("role", "")

		match role:
			"system":
				result.append(msg)
			"user":
				result.append({"role": "user", "content": _truncate(msg.get("content", ""), MAX_USER_MSG_LEN)})
			"assistant":
				# 完整保留 — Worker 需要看到自己的思考链和 tool_calls
				result.append(msg)
			"tool":
				var tc: Dictionary = msg.duplicate(true)
				# 管理工具结果（wait_for_children 报告等）是蒸馏信息，不截断
				var no_truncate: bool = tc.get("_no_truncate", false)
				tc.erase("_no_truncate")  # 内部标记，不发给 API
				var content: String = str(tc.get("content", ""))
				if not no_truncate and content.length() > MAX_TOOL_RESULT_LEN:
					tc["content"] = content.substr(0, MAX_TOOL_RESULT_LEN) + "…[%d chars]" % content.length()
				result.append(tc)

	if _logger:
		_logger.append("CTX", "Banyan send: %d messages (from %d total)" % [result.size(), _messages.size()])
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
