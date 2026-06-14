@tool
class_name OpenAIProvider
extends LLMProvider
## OpenAI 兼容提供商（OpenAI / DeepSeek / Moonshot / Qwen / MiniMax / 等）
##
## 凡是兼容 /v1/models 和 /v1/chat/completions 的都走这里。

var _base_url: String
var _api_key: String


func _init(base_url: String, api_key: String) -> void:
	_base_url = base_url
	_api_key = api_key


func get_format() -> String:
	return FORMAT_OPENAI


func get_base_url() -> String:
	return _base_url


func get_api_key() -> String:
	return _api_key


func get_auth_headers() -> PackedStringArray:
	return _with_default_headers([
		"Authorization: Bearer " + _api_key,
	])


func get_chat_endpoint() -> String:
	return "/chat/completions"


func fetch_models(host_node: Node, on_complete: Callable) -> void:
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 10
	_apply_proxy(http)

	var url := _base_url.trim_suffix("/") + "/models"
	var key := _api_key

	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		var body_str: String = body.get_string_from_utf8()
		http.queue_free()
		if code == 0:
			on_complete.call(false, [], "无法连接 %s（超时或网络不通）" % url)
		elif code == 401 or code == 403:
			on_complete.call(false, [], "认证失败 (HTTP %d) — 请检查 API Key" % code)
		elif code != 200:
			on_complete.call(false, [], "HTTP %d — %s" % [code, body_str.substr(0, 100)])
		else:
			var json := JSON.new()
			if json.parse(body_str) != OK:
				on_complete.call(false, [], "返回数据解析失败")
			else:
				var data: Dictionary = json.data
				var models: Array = data.get("data", [])
				if models.is_empty():
					models = data.get("models", [])
				var infos := _extract_model_infos(models)
				if infos.is_empty():
					on_complete.call(false, [], "API 返回了空模型列表")
				else:
					on_complete.call(true, infos, "")
	)

	var headers := PackedStringArray()
	headers.append("Content-Type: application/json")
	if not key.is_empty():
		headers.append("Authorization: Bearer " + key)
	http.request(url, headers, HTTPClient.METHOD_GET)


func normalize_messages(messages: Array) -> Dictionary:
	# OpenAI 格式：messages 原样传递，system 消息也放在 messages 数组
	return {"messages": messages.duplicate(true), "system": ""}


func build_request_body(model: String, messages: Array, tools: Array, stream: bool, temperature: float, max_tokens: int) -> Dictionary:
	var body := {
		"model": model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens,
		"stream": stream,
	}
	if not tools.is_empty():
		body["tools"] = tools
		body["tool_choice"] = "auto"
	return {"body": JSON.stringify(body), "extra": {}}


## 解析 OpenAI 兼容格式的 SSE 事件（实例方法，覆盖基类）
func parse_sse_event(event_text: String) -> Dictionary:
	return parse_sse_static(event_text)


## 静态版: 解析 OpenAI 兼容格式的 SSE 事件
## 避免每条事件都 new OpenAIProvider 实例
static func parse_sse_static(event_text: String) -> Dictionary:
	# OpenAI SSE: 多行 "data: {json}\n"  (可能多行 data: 拼接)
	var data_lines: Array = []
	for line in event_text.split("\n", false):
		var s: String = line.strip_edges()
		if s.begins_with("data:"):
			var payload := s.substr(5).strip_edges()
			if payload == "[DONE]":
				return {"type": "done"}
			data_lines.append(payload)
	if data_lines.is_empty():
		return {"type": "ignore"}

	var json_text := "\n".join(data_lines)
	var obj: Variant = JSON.parse_string(json_text)
	if obj == null or typeof(obj) != TYPE_DICTIONARY:
		return {"type": "ignore"}
	var choices: Array = obj.get("choices", [])
	if choices.is_empty():
		return {"type": "ignore"}
	var choice: Dictionary = choices[0]
	var delta: Dictionary = choice.get("delta", {})

	var fr: String = str(choice.get("finish_reason", ""))
	var result := {"type": "content", "content": "", "tool_call": null, "finish_reason": ""}

	var content_chunk := str(delta.get("content", ""))
	if not content_chunk.is_empty():
		result.content = content_chunk

	if delta.has("tool_calls"):
		var tcs: Array = delta.get("tool_calls", [])
		if not tcs.is_empty():
			var tc: Dictionary = tcs[0]
			var fn: Dictionary = tc.get("function", {})
			result.tool_call = {
				"index": int(tc.get("index", 0)),
				"id": str(tc.get("id", "")),
				"name": str(fn.get("name", "")),
				"arguments": str(fn.get("arguments", "")),
			}
			result.type = "tool_call"

	if not fr.is_empty():
		result.finish_reason = fr

	return result


func _extract_model_infos(models: Array) -> Array[Dictionary]:
	var infos: Array[Dictionary] = []
	for m in models:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = m
		var mid: String = str(d.get("id", ""))
		if mid.is_empty():
			mid = str(d.get("name", ""))
		if mid.is_empty():
			mid = str(d.get("model", ""))
		if mid.is_empty():
			continue
		if mid.contains("-audio-") or mid.contains("-tts-") or mid.contains("-whisper-"):
			continue
		infos.append(_normalize_model_info(d))
	return infos


func _normalize_model_info(raw: Variant) -> Dictionary:
	var d: Dictionary
	if typeof(raw) == TYPE_DICTIONARY:
		d = raw
	else:
		d = {"id": str(raw)}

	var id: String = str(d.get("id", ""))
	if id.is_empty():
		id = str(d.get("name", ""))
	if id.is_empty():
		id = str(d.get("model", ""))

	return {
		"id": id,
		"name": id,
	}



func _apply_proxy(http: HTTPRequest) -> void:
	var cfg := ConfigManager.instance()
	if not cfg.is_proxy_enabled():
		return
	var host := cfg.get_effective_proxy_host()
	var port := cfg.get_proxy_port()
	http.set_http_proxy(host, port)
	http.set_https_proxy(host, port)
