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


## 获取累积的完整 tool_calls（在 stream 结束后调用）
func get_accumulated_tool_calls() -> Array:
	return _accumulated_tool_calls.duplicate(true)


# ============ 内部实现 ============

func _parse_event(event_text: String) -> Dictionary:
	event_text = event_text.strip_edges()
	if event_text.is_empty():
		return {}

	# 提取所有 data: 行
	var data_lines: Array = []
	for line in event_text.split("\n", false):
		var s: String = line.strip_edges()
		if s.begins_with("data:"):
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

	# reasoning chunk — Kimi/DeepSeek 等推理模型把思考流放在 reasoning_content，
	# 不解析会导致上层误判"无推理盲动"（每个工具轮白跑一次 nudge）
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
