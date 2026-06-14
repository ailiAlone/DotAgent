@tool
class_name OllamaProvider
extends LLMProvider
## Ollama 本地提供商
##
## 注意: Ollama 的 chat API 与 OpenAI 略有不同，但目前通过 OpenAI 兼容模式
## (http://localhost:11434/v1) 也能用 chat/completions。
## 这里保留独立的 /api/tags 模型列表端点 + OpenAI 兼容 chat 端点。

const OLLAMA_DEFAULT_BASE := "http://localhost:11434"
const _OpenAIProviderType = preload("res://addons/dotagent/llm/providers/openai_provider.gd")

var _base_url: String


func _init(base_url: String = OLLAMA_DEFAULT_BASE) -> void:
	_base_url = base_url


func get_format() -> String:
	# Ollama 通过 OpenAI 兼容端点暴露 chat 接口
	return FORMAT_OPENAI


func get_base_url() -> String:
	return _base_url


func get_api_key() -> String:
	return ""  # Ollama 不需要 key


func get_auth_headers() -> PackedStringArray:
	return _with_default_headers(PackedStringArray())


func get_chat_endpoint() -> String:
	return "/v1/chat/completions"  # 通过 OpenAI 兼容


func fetch_models(host_node: Node, on_complete: Callable) -> void:
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 5
	_apply_proxy(http)

	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code == 0:
			on_complete.call(false, [], "无法连接 Ollama（请确认已启动：ollama serve）")
		elif code != 200:
			on_complete.call(false, [], "Ollama HTTP %d — %s" % [code, body.get_string_from_utf8().substr(0, 80)])
		else:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) != OK:
				on_complete.call(false, [], "Ollama 返回数据解析失败")
			else:
				var data: Dictionary = json.data
				var models: Array = data.get("models", [])
				var infos: Array[Dictionary] = []
				for m in models:
					var mid: String = str(m.get("name", ""))
					infos.append({
						"id": mid,
						"name": mid,
						"context_length": 0,
						"vision": mid.to_lower().contains("vision") or mid.to_lower().contains("llava") or mid.to_lower().contains("minicpm-v"),
					})
				if infos.is_empty():
					on_complete.call(false, [], "Ollama 中暂无模型")
				else:
					on_complete.call(true, infos, "")
	)

	http.request(_base_url.trim_suffix("/") + "/api/tags", [], HTTPClient.METHOD_GET)


func normalize_messages(messages: Array) -> Dictionary:
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
	return {"body": JSON.stringify(body), "extra": {}}


func parse_sse_event(event_text: String) -> Dictionary:
	# Ollama OpenAI 兼容模式与 OpenAI 格式相同 — 直接调静态方法避免每条事件 new 实例
	return _OpenAIProviderType.parse_sse_static(event_text)


func _apply_proxy(http: HTTPRequest) -> void:
	var cfg := ConfigManager.instance()
	if not cfg.is_proxy_enabled():
		return
	var host := cfg.get_effective_proxy_host()
	var port := cfg.get_proxy_port()
	http.set_http_proxy(host, port)
	http.set_https_proxy(host, port)
