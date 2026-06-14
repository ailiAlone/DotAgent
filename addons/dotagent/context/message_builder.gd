@tool
class_name MessageBuilder
extends RefCounted
## 消息压缩与构建 — 从完整历史构建发送给 LLM 的精简消息列表。
##
## 从 DockController 中拆分出来，保持 controller 文件可维护。

const MAX_USER_MSG_LEN := 3000  # 超过此长度的 user 消息会被截断,避免单条消息撑爆 context

var _messages: Array[Dictionary]
var _logger: SessionLog


func setup(messages: Array[Dictionary], logger: SessionLog) -> void:
	_messages = messages
	_logger = logger


## 同步 messages 引用 — 当 DockController 在 bootstrap 后重新赋值 _messages 时调用
func resync(messages: Array[Dictionary]) -> void:
	_messages = messages


## 构建发送给 LLM 的消息列表 — v3 简化版
## 对话内全量发送（无 L2/L3 压缩，旧对话已压缩为摘要）
func build() -> Array:
	var result: Array = []

	for msg in _messages:
		var role: String = msg.get("role", "")

		# system 消息全部保留（含边界标记、视觉分析注入、会话记忆）
		if role == "system":
			result.append(msg)
			continue

		# user 消息全量保留
		if role == "user":
			result.append({"role": "user", "content": _truncate_user(msg)})
			continue

		# assistant 消息全量保留（含 think，对话内 AI 需要看到自己的思考）
		if role == "assistant":
			result.append(msg)
			continue

		# tool 消息保留但截断大结果
		if role == "tool":
			var tc: Dictionary = msg.duplicate(true)
			var content: String = tc.get("content", "")
			if content.length() > 1000:
				tc["content"] = content.substr(0, 1000) + "…[%d chars]" % content.length()
			result.append(tc)
			continue

	_logger.append("LLM", "Send messages: %d (from %d total)" % [result.size(), _messages.size()])
	_logger.record_llm_request(result.size(), _messages.size(), 0, 1, 0, 0)
	return result


func _truncate_user(msg: Dictionary) -> String:
	var content = msg.get("content", "")
	if content == null:
		return ""
	var text: String = str(content)
	if text.length() > MAX_USER_MSG_LEN:
		text = text.substr(0, MAX_USER_MSG_LEN) + "…[user message truncated]"
	return text
