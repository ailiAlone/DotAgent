@tool
extends RefCounted
## SSE 流式解析器 — 从原始字节流中提取完整的 SSE 事件并解析为结构化 chunk。
##
## 用法:
##   var parser := BanyanStreamParser.new()
##   parser.feed(raw_chunk_string)
##   var chunks := parser.drain()
##   for chunk in chunks:
##       match chunk.type:
##           "content": ...
##           "tool_call": ...
##           "done": ...
##
## 设计原则:
##   - 纯数据解析，不管理 HTTP 连接
##   - 支持跨 feed() 调用的不完整事件缓冲
##   - tool_call chunk 按 index 累积（OpenAI streaming 格式）
##   - 每个 chunk 结构: {type, content?, tool_call?, finish_reason?}

var _buffer: String = ""
var _accumulated_tool_calls: Array = []  # [{id, type, function: {name, arguments}}]


## 向缓冲区追加原始数据
func feed(data: String) -> void:
	_buffer += data


## 提取所有已完成的 SSE 事件，返回解析后的 chunk 数组
func drain() -> Array:
	var chunks: Array = []
	while "\n\n" in _buffer:
		var idx: int = _buffer.find("\n\n")
		var event_text: String = _buffer.substr(0, idx)
		_buffer = _buffer.substr(idx + 2)
		var chunk: Dictionary = _parse_event(event_text)
		if not chunk.is_empty():
			chunks.append(chunk)
	return chunks


## 是否还有未完成的缓冲数据
func has_pending() -> bool:
	return not _buffer.is_empty()


## 获取当前缓冲区内容（调试用）
func peek_buffer() -> String:
	return _buffer


## 重置解析器状态（新请求前调用）
func reset() -> void:
	_buffer = ""
	_accumulated_tool_calls = []
	_anthropic_tool_blocks = {}


## 获取累积的完整 tool_calls（在 stream 结束后调用）
func get_accumulated_tool_calls() -> Array:
	return _accumulated_tool_calls.duplicate(true)


# ============ 内部实现 ============

## Anthropic tool_call 跨事件追踪：content_block_start 提供 id/name，
## content_block_delta 提供 partial_json 参数，需要跨事件累积
var _anthropic_tool_blocks: Dictionary = {}  # {index: {id, name, arguments}}


func _parse_event(event_text: String) -> Dictionary:
	event_text = event_text.strip_edges()
	if event_text.is_empty():
		return {}

	# 提取 event: 行（Anthropic 格式使用，OpenAI 通常没有）
	var event_type: String = ""
	var data_lines: Array = []
	for line in event_text.split("\n", false):
		var s: String = line.strip_edges()
		if s.begins_with("event:"):
			event_type = s.substr(6).strip_edges()
		elif s.begins_with("data:"):
			var payload: String = s.substr(5).strip_edges()
			if payload == "[DONE]":
				return {"type": "done"}
			data_lines.append(payload)

	if data_lines.is_empty():
		return {}

	# 拼接多行 data（某些 API 会拆分 JSON 到多行 data:）
	var json_text: String = "\n".join(data_lines)
	var obj: Variant = JSON.parse_string(json_text)
	if obj == null or typeof(obj) != TYPE_DICTIONARY:
		return {}

	# ====== 格式自动检测 ======
	# Anthropic: JSON 有 "type" 字段（message_start, content_block_delta 等）
	# OpenAI:    JSON 有 "choices" 数组
	if not event_type.is_empty() or _is_anthropic_event(obj):
		return _parse_anthropic_event(event_type, obj)
	else:
		return _parse_openai_event(obj)


## 判断 JSON 是否是 Anthropic 格式
func _is_anthropic_event(obj: Dictionary) -> bool:
	if obj.has("type"):
		var t: String = str(obj.get("type", ""))
		if t in ["message_start", "content_block_start", "content_block_delta",
				"content_block_stop", "message_delta", "message_stop", "error", "ping"]:
			return true
	return false


# ============ OpenAI 格式解析 ============

func _parse_openai_event(obj: Dictionary) -> Dictionary:
	var choices: Array = obj.get("choices", [])
	if choices.is_empty():
		return {}

	var choice: Dictionary = choices[0]
	var delta: Dictionary = choice.get("delta", {})

	# finish_reason
	var fr_raw = choice.get("finish_reason", null)
	var fr: String = str(fr_raw) if fr_raw != null else ""

	var result: Dictionary = {"type": "content", "content": "", "reasoning": "", "tool_call": null, "finish_reason": fr}

	# content chunk
	var content_chunk: String = _get_string(delta, "content")
	if not content_chunk.is_empty():
		result.content = content_chunk

	# reasoning chunk — Kimi/DeepSeek 等推理模型把思考流放在 reasoning_content
	var reasoning_chunk: String = _get_string(delta, "reasoning_content")
	if not reasoning_chunk.is_empty():
		result.reasoning = reasoning_chunk

	# tool_calls chunks
	if delta.has("tool_calls"):
		var tcs: Array = delta.get("tool_calls", [])
		for tc in tcs:
			_accumulate_tool_call_chunk(tc)
		if not tcs.is_empty():
			var tc0: Dictionary = tcs[0]
			var fn: Dictionary = tc0.get("function", {})
			result.tool_call = {
				"index": int(tc0.get("index", 0)),
				"id": str(tc0.get("id", "")),
				"name": str(fn.get("name", "")),
				"arguments": str(fn.get("arguments", "")),
			}
			result.type = "tool_call"

	return result


# ============ Anthropic 格式解析 ============

func _parse_anthropic_event(event_type: String, obj: Dictionary) -> Dictionary:
	var obj_type: String = str(obj.get("type", ""))
	# event_type 来自 event: 行，obj_type 来自 JSON 的 type 字段，两者通常相同
	if event_type.is_empty():
		event_type = obj_type

	match event_type:
		"message_start":
			return {}  # 元数据，不需要处理

		"content_block_start":
			var block: Dictionary = obj.get("content_block", {})
			var block_type: String = str(block.get("type", ""))
			if block_type == "tool_use":
				var idx: int = int(obj.get("index", 0))
				var tool_id: String = str(block.get("id", ""))
				var tool_name: String = str(block.get("name", ""))
				# 记录到跨事件追踪表
				_anthropic_tool_blocks[idx] = {
					"id": tool_id,
					"name": tool_name,
					"arguments": "",
				}
				# 同时累积到 _accumulated_tool_calls（与 OpenAI 格式兼容）
				_ensure_tool_call_slot(idx)
				_accumulated_tool_calls[idx]["id"] = tool_id
				_accumulated_tool_calls[idx]["function"]["name"] = tool_name
				return {
					"type": "tool_call",
					"content": "",
					"reasoning": "",
					"tool_call": {
						"index": idx,
						"id": tool_id,
						"name": tool_name,
						"arguments": "",
					},
					"finish_reason": "",
				}
			return {}

		"content_block_delta":
			var delta: Dictionary = obj.get("delta", {})
			var delta_type: String = str(delta.get("type", ""))
			var idx: int = int(obj.get("index", 0))

			if delta_type == "text_delta":
				var text: String = str(delta.get("text", ""))
				return {
					"type": "content",
					"content": text,
					"reasoning": "",
					"tool_call": null,
					"finish_reason": "",
				}

			elif delta_type == "input_json_delta":
				# 工具参数增量 JSON
				var partial: String = str(delta.get("partial_json", ""))
				# 累积到跨事件追踪表
				if _anthropic_tool_blocks.has(idx):
					_anthropic_tool_blocks[idx]["arguments"] += partial
				# 累积到 _accumulated_tool_calls
				_ensure_tool_call_slot(idx)
				_accumulated_tool_calls[idx]["function"]["arguments"] += partial
				return {
					"type": "tool_call",
					"content": "",
					"reasoning": "",
					"tool_call": {
						"index": idx,
						"id": "",
						"name": "",
						"arguments": partial,
					},
					"finish_reason": "",
				}

			elif delta_type == "thinking_delta":
				# Anthropic 扩展思考（extended thinking）
				var thinking: String = str(delta.get("thinking", ""))
				return {
					"type": "content",
					"content": "",
					"reasoning": thinking,
					"tool_call": null,
					"finish_reason": "",
				}

			return {}

		"content_block_stop":
			return {}  # 块结束，不需要特殊处理

		"message_delta":
			# 包含 stop_reason
			var delta2: Dictionary = obj.get("delta", {})
			var stop_reason: String = str(delta2.get("stop_reason", ""))
			if not stop_reason.is_empty():
				# 映射 Anthropic stop_reason 到 OpenAI finish_reason
				var fr: String = stop_reason
				if stop_reason == "end_turn":
					fr = "stop"
				elif stop_reason == "tool_use":
					fr = "tool_calls"
				return {
					"type": "content",
					"content": "",
					"reasoning": "",
					"tool_call": null,
					"finish_reason": fr,
				}
			return {}

		"message_stop":
			return {"type": "done"}

		"error":
			return {}  # 错误事件，由上层 HTTP 状态码处理

		"ping":
			return {}  # 心跳

		_:
			return {}


## 确保 _accumulated_tool_calls 在指定 index 处有槽位
func _ensure_tool_call_slot(idx: int) -> void:
	while _accumulated_tool_calls.size() <= idx:
		_accumulated_tool_calls.append({
			"id": "",
			"type": "function",
			"function": {"name": "", "arguments": ""},
		})


func _accumulate_tool_call_chunk(tc: Dictionary) -> void:
	var idx: int = int(tc.get("index", 0))
	while _accumulated_tool_calls.size() <= idx:
		_accumulated_tool_calls.append({
			"id": "",
			"type": "function",
			"function": {"name": "", "arguments": ""},
		})
	var acc: Dictionary = _accumulated_tool_calls[idx]
	if tc.has("id") and tc.get("id", "") != "":
		acc["id"] = tc.get("id")
	var fn: Dictionary = tc.get("function", {})
	var fn_name: String = _get_string(fn, "name")
	if fn_name != "":
		acc["function"]["name"] = fn_name
	if fn.has("arguments") and fn.get("arguments") != null:
		acc["function"]["arguments"] += str(fn.get("arguments", ""))


func _get_string(d: Dictionary, key: String, default: String = "") -> String:
	if not d.has(key):
		return default
	var v = d[key]
	if v == null:
		return default
	return str(v)
