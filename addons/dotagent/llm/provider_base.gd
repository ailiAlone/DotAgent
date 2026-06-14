@tool
class_name LLMProvider
extends RefCounted
## LLM 提供商抽象基类
##
## 所有具体提供商（OpenAI / Anthropic / Ollama 等）都继承该类。
## 统一接口:
##   - get_format()            返回格式标识 ("openai" | "anthropic" | "ollama")
##   - get_base_url()          API 根 URL
##   - get_api_key()           API Key
##   - get_auth_headers()      认证相关的 HTTP headers
##   - get_chat_endpoint()     chat/completions 端点路径（不含 base_url）
##   - fetch_models()          拉取该提供商下的模型列表
##   - normalize_messages()    把统一消息结构转换为提供商格式
##   - build_request_body()    构造请求 JSON
##   - parse_sse_event()       解析单条 SSE 事件 → 标准 chunk

const FORMAT_OPENAI := "openai"
const FORMAT_ANTHROPIC := "anthropic"
const FORMAT_OLLAMA := "ollama"


## ===== 必须由子类实现 =====

func get_format() -> String:
	push_error("LLMProvider subclass must override get_format()")
	return FORMAT_OPENAI


func get_base_url() -> String:
	push_error("LLMProvider subclass must override get_base_url()")
	return ""


func get_api_key() -> String:
	return ""


func get_auth_headers() -> PackedStringArray:
	return PackedStringArray()


func get_chat_endpoint() -> String:
	return "/chat/completions"


## 拉取模型列表
## on_complete 回调签名: func(success: bool, models: Array[Dictionary], error_msg: String)
## 每个模型字典: id, name, context_length, vision
func fetch_models(_host_node: Node, _on_complete: Callable) -> void:
	push_error("LLMProvider subclass must override fetch_models()")


## ===== 默认实现（多数提供商可复用，子类可重写） =====

## 把统一消息结构转换为提供商格式
## 标准消息: {role: "system"|"user"|"assistant"|"tool", content: String, images?: Array, tool_call_id?: String, tool_calls?: Array}
## 返回: {messages: Array, system: String}  system 仅 anthropic 使用
func normalize_messages(messages: Array) -> Dictionary:
	return {"messages": messages.duplicate(true), "system": ""}


## 构造请求 JSON 字符串
## messages + tools + stream + system 由 normalize_messages 提供
## 返回值: {body: String, extra: Dictionary}  extra 可包含 max_tokens 等强制参数
func build_request_body(model: String, messages: Array, tools: Array, stream: bool, temperature: float, max_tokens: int) -> Dictionary:
	push_error("LLMProvider subclass must override build_request_body()")
	return {"body": "", "extra": {}}


## 解析一条 SSE 事件文本，返回标准 chunk 字典
## 事件文本可能包含多行（"event: x\ndata: y\n\n"）
## 返回: {type: "content"|"tool_call"|"done"|"error", content?: String, tool_call?: Dictionary, finish_reason?: String, error?: String}
func parse_sse_event(event_text: String) -> Dictionary:
	push_error("LLMProvider subclass must override parse_sse_event()")
	return {"type": "error", "error": "not implemented"}


## 工具：将 PackedStringArray 转为附加 headers
func _with_default_headers(extra: PackedStringArray) -> PackedStringArray:
	var h := PackedStringArray()
	h.append("Content-Type: application/json")
	for e in extra:
		h.append(e)
	return h
