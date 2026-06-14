@tool
class_name AnthropicProvider
extends LLMProvider
## Anthropic Claude API 提供商
##
## 差异点:
##   - 端点: /v1/messages  (不是 /v1/chat/completions)
##   - 认证: x-api-key header + anthropic-version header
##   - system 消息: 顶层字段，不在 messages 数组
##   - max_tokens: 必填
##   - 流式: SSE 但格式不同 (event: + data: 两行)
##   - 工具: 名称限定 ≤ 64 字符，描述可能需截断

const ANTHROPIC_VERSION := "2023-06-01"
const ANTHROPIC_DEFAULT_BASE := "https://api.anthropic.com"
const ANTHROPIC_MAX_TOKENS_DEFAULT := 8192  # 必填，给个合理默认

const ANTHROPIC_MODELS := [
	{
		"id": "claude-opus-4-20250514",
		"name": "Claude Opus 4",
		"context_length": 200000,
		"vision": true,
	},
	{
		"id": "claude-sonnet-4-20250514",
		"name": "Claude Sonnet 4",
		"context_length": 200000,
		"vision": true,
	},
	{
		"id": "claude-3-7-sonnet-20250219",
		"name": "Claude 3.7 Sonnet",
		"context_length": 200000,
		"vision": true,
	},
	{
		"id": "claude-3-5-sonnet-20241022",
		"name": "Claude 3.5 Sonnet (new)",
		"context_length": 200000,
		"vision": true,
	},
	{
		"id": "claude-3-5-sonnet-20240620",
		"name": "Claude 3.5 Sonnet",
		"context_length": 200000,
		"vision": true,
	},
	{
		"id": "claude-3-5-haiku-20241022",
		"name": "Claude 3.5 Haiku",
		"context_length": 200000,
		"vision": false,
	},
	{
		"id": "claude-3-opus-20240229",
		"name": "Claude 3 Opus",
		"context_length": 200000,
		"vision": true,
	},
	{
		"id": "claude-3-haiku-20240307",
		"name": "Claude 3 Haiku",
		"context_length": 200000,
		"vision": false,
	},
]

var _base_url: String
var _api_key: String


func _init(api_key: String, base_url: String = ANTHROPIC_DEFAULT_BASE) -> void:
	_api_key = api_key
	_base_url = base_url


func get_format() -> String:
	return FORMAT_ANTHROPIC


func get_base_url() -> String:
	return _base_url


func get_api_key() -> String:
	return _api_key


func get_auth_headers() -> PackedStringArray:
	return _with_default_headers([
		"x-api-key: " + _api_key,
		"anthropic-version: " + ANTHROPIC_VERSION,
	])


func get_chat_endpoint() -> String:
	return "/v1/messages"


## Anthropic 没有 /v1/models 端点，直接返回静态列表
func fetch_models(_host_node: Node, on_complete: Callable) -> void:
	var infos: Array[Dictionary] = []
	for m in ANTHROPIC_MODELS:
		infos.append(m.duplicate(true))
	on_complete.call(true, infos, "")


## 把 OpenAI 风格 messages 转换为 Anthropic 格式
## system 消息提取到顶层；assistant 消息中如果有 tool_calls，转换为 content 块
func normalize_messages(messages: Array) -> Dictionary:
	var system_parts: Array[String] = []
	var converted: Array = []

	for msg in messages:
		var role: String = str(msg.get("role", "user"))
		if role == "system":
			var c: String = str(msg.get("content", ""))
			if not c.is_empty():
				system_parts.append(c)
			continue

		if role == "tool":
			# 工具结果：转成 user 消息的 tool_result content 块
			var tool_call_id: String = str(msg.get("tool_call_id", ""))
			var content_text: String = str(msg.get("content", ""))
			converted.append({
				"role": "user",
				"content": [
					{
						"type": "tool_result",
						"tool_use_id": tool_call_id,
						"content": content_text,
					}
				]
			})
			continue

		if role == "assistant" and msg.has("tool_calls"):
			# 把 tool_calls 转成 content 块
			var blocks: Array = []
			var text_content: String = str(msg.get("content", ""))
			if not text_content.is_empty():
				blocks.append({"type": "text", "text": text_content})
			for tc in msg.get("tool_calls", []):
				var fn: Dictionary = tc.get("function", {})
				blocks.append({
					"type": "tool_use",
					"id": str(tc.get("id", "")),
					"name": str(fn.get("name", "")),
					"input": _parse_arguments(str(fn.get("arguments", "{}"))),
				})
			converted.append({"role": "assistant", "content": blocks})
			continue

		# user / assistant 普通消息
		var content: Variant = msg.get("content", "")

		# 处理多模态：OpenAI 风格的 images 数组转 Anthropic image content 块
		var images: Array = msg.get("images", [])
		if not images.is_empty():
			var parts: Array = []
			if content != null and not str(content).is_empty():
				parts.append({"type": "text", "text": str(content)})
			for img in images:
				var img_str: String = str(img)
				var media_type := "image/png"
				var data_b64 := ""
				if img_str.begins_with("data:"):
					# data:image/png;base64,XXX
					var semi := img_str.find(";")
					if semi > 5:
						media_type = img_str.substr(5, semi - 5)
					var comma := img_str.find(",")
					if comma > 0:
						data_b64 = img_str.substr(comma + 1)
				parts.append({
					"type": "image",
					"source": {
						"type": "base64",
						"media_type": media_type,
						"data": data_b64,
					}
				})
			converted.append({"role": role, "content": parts})
		else:
			converted.append({"role": role, "content": str(content) if content != null else ""})

	return {
		"messages": converted,
		"system": "\n\n".join(system_parts),
	}


func build_request_body(model: String, messages: Array, tools: Array, stream: bool, temperature: float, max_tokens: int) -> Dictionary:
	var normalized := normalize_messages(messages)
	var body := {
		"model": model,
		"max_tokens": max_tokens if max_tokens > 0 else ANTHROPIC_MAX_TOKENS_DEFAULT,
		"messages": normalized.messages,
		"stream": stream,
	}
	var sys: String = normalized.system
	if not sys.is_empty():
		body["system"] = sys
	# temperature 在 0..1 之间
	body["temperature"] = clampf(temperature, 0.0, 1.0)
	if not tools.is_empty():
		body["tools"] = _adapt_tools(tools)
	return {"body": JSON.stringify(body), "extra": {}}


## Anthropic 工具：name 必须是 ^[a-zA-Z0-9_-]{1,64}$
## 描述: input_schema 必填（不能只用 description）
func _adapt_tools(tools: Array) -> Array:
	var adapted: Array = []
	for t in tools:
		var name: String = str(t.get("name", ""))
		if name.is_empty():
			continue
		# 清洗名称: 只保留字母数字下划线连字符
		var clean_name := ""
		for ch in name:
			var s := str(ch)
			if s.is_valid_identifier() or s == "-" or s == "_":
				clean_name += s
			else:
				clean_name += "_"
		if clean_name.length() > 64:
			clean_name = clean_name.substr(0, 64)
		if clean_name.is_empty():
			continue

		var at: Dictionary = {
			"name": clean_name,
			"description": str(t.get("description", "")),
		}
		# 尝试使用原始 schema
		if t.has("parameters") and typeof(t.get("parameters")) == TYPE_DICTIONARY:
			at["input_schema"] = t.get("parameters")
		else:
			# Anthropic 要求 input_schema；给最小可用结构
			at["input_schema"] = {
				"type": "object",
				"properties": {},
			}
		adapted.append(at)
	return adapted


## 解析 Anthropic SSE 事件
## 事件格式: "event: <type>\ndata: <json>\n" (可能多 data 行)
func parse_sse_event(event_text: String) -> Dictionary:
	var event_type := ""
	var data_lines: Array = []

	for line in event_text.split("\n", false):
		var s: String = line.strip_edges()
		if s.begins_with("event:"):
			event_type = s.substr(6).strip_edges()
		elif s.begins_with("data:"):
			data_lines.append(s.substr(5).strip_edges())

	if data_lines.is_empty():
		return {"type": "ignore"}

	var json_text := "\n".join(data_lines)
	if json_text == "[DONE]":
		return {"type": "done"}

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return {"type": "ignore"}

	var obj: Variant = json.data
	if typeof(obj) != TYPE_DICTIONARY:
		return {"type": "ignore"}
	var d: Dictionary = obj

	match event_type:
		"message_start":
			return {"type": "ignore"}
		"content_block_start":
			# 工具调用开始: data 里含 tool_use block
			var block: Dictionary = d.get("content_block", {})
			if str(block.get("type", "")) == "tool_use":
				return {
					"type": "tool_call",
					"tool_call": {
						"index": int(d.get("index", 0)),
						"id": str(block.get("id", "")),
						"name": str(block.get("name", "")),
						"arguments": "",
					},
					"content": "",
					"finish_reason": "",
				}
			return {"type": "ignore"}
		"content_block_delta":
			var delta: Dictionary = d.get("delta", {})
			var delta_type: String = str(delta.get("type", ""))
			if delta_type == "text_delta":
				return {
					"type": "content",
					"content": str(delta.get("text", "")),
					"tool_call": null,
					"finish_reason": "",
				}
			elif delta_type == "input_json_delta":
				return {
					"type": "tool_call",
					"tool_call": {
						"index": int(d.get("index", 0)),
						"id": "",
						"name": "",
						"arguments": str(delta.get("partial_json", "")),
					},
					"content": "",
					"finish_reason": "",
				}
			return {"type": "ignore"}
		"content_block_stop":
			return {"type": "ignore"}
		"message_delta":
			# 包含 stop_reason / stop_sequence
			var delta2: Dictionary = d.get("delta", {})
			var stop_reason: String = str(delta2.get("stop_reason", ""))
			if not stop_reason.is_empty():
				return {"type": "content", "content": "", "tool_call": null, "finish_reason": stop_reason}
			return {"type": "ignore"}
		"message_stop":
			return {"type": "done"}
		"error":
			return {"type": "error", "error": json_text}
		_:
			return {"type": "ignore"}


func _parse_arguments(s: String) -> Variant:
	var json := JSON.new()
	if json.parse(s) == OK:
		return json.data
	return {}
