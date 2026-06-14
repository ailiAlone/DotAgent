@tool
class_name ProviderFactory
extends RefCounted
## 根据提供商名称或 base_url 自动选择合适的 Provider 实现

const PROVIDERS := [
	{name = "OpenAI",              	url = "https://api.openai.com/v1",                      format = "openai"},
	{name = "DeepSeek",            	url = "https://api.deepseek.com",                       format = "openai"},
	{name = "Moonshot (Kimi)",     	url = "https://api.moonshot.cn/v1",                     format = "openai"},
	{name = "MiniMax",             	url = "https://api.minimaxi.com/v1",                    format = "openai"},
	{name = "Zhipu AI (GLM)",      	url = "https://open.bigmodel.cn/api/paas/v4",           format = "openai"},
	{name = "Qwen (DashScope)",    	url = "https://dashscope.aliyuncs.com/compatible-mode/v1", format = "openai"},
	{name = "Doubao (Volcengine)", 	url = "https://ark.cn-beijing.volces.com/api/v3",       format = "openai"},
	{name = "xAI (Grok)",          	url = "https://api.x.ai/v1",                            format = "openai"},
	# API 中转商 — 暂不在 UI 展示（用户可通过 Custom 自行填 base_url）
	# {name = "Together AI",         	url = "https://api.together.xyz/v1",                    format = "openai"},
	# {name = "OpenRouter",          	url = "https://openrouter.ai/api/v1",                   format = "openai"},
	# {name = "SiliconFlow",         	url = "https://api.siliconflow.cn/v1",                  format = "openai"},
	# Anthropic (Claude) — 暂不在 UI 展示（format 抽象已就位，需要时取消注释即可）
	# {name = "Anthropic (Claude)",  	url = "https://api.anthropic.com",                      format = "anthropic"},
	{name = "Custom",              	url = "",                                               format = "openai"},
]


## 获取所有提供商定义
static func get_all() -> Array:
	return PROVIDERS.duplicate(true)


## 根据名称查找提供商定义
static func find(name: String) -> Dictionary:
	for p in PROVIDERS:
		if p.name == name:
			return p
	return {}


## 根据 base_url 启发式判断格式
## - 包含 anthropic.com → anthropic
## - 其他 → openai (默认)
static func detect_format_by_url(base_url: String) -> String:
	var u: String = base_url.to_lower()
	if "anthropic.com" in u:
		return "anthropic"
	return "openai"


## 创建一个 Provider 实例
## provider_name: 来自 ProviderFactory.PROVIDERS 的 name 字段，或 "Custom"
## base_url: 用于 Custom 或 Ollama 自定义端口
## api_key: 可选
static func create(provider_name: String, base_url: String = "", api_key: String = "") -> LLMProvider:
	var p := find(provider_name)
	var format_id: String = p.get("format", "openai") if not p.is_empty() else "openai"

	# Custom 走 base_url 启发式
	if provider_name == "Custom" and not base_url.is_empty():
		format_id = detect_format_by_url(base_url)
		var inferred: String = _infer_provider_name_from_url(base_url)
		if not inferred.is_empty() and find(inferred).is_empty():
			# 静态 PROVIDERS 里没有的自定义 base_url，仍然按 format 创建
			pass

	match format_id:
		"anthropic":
			var url := base_url if not base_url.is_empty() else p.get("url", "https://api.anthropic.com")
			return AnthropicProvider.new(api_key, url)
		_:
			var url := base_url if not base_url.is_empty() else p.get("url", "")
			return OpenAIProvider.new(url, api_key)


## 根据 base_url 推测友好的提供商名（用于 Custom 场景下拉框里自动匹配）
static func _infer_provider_name_from_url(base_url: String) -> String:
	var u: String = base_url.to_lower()
	if "openai.com" in u: return "OpenAI"
	if "deepseek.com" in u: return "DeepSeek"
	if "moonshot.cn" in u: return "Moonshot (Kimi)"
	if "minimaxi.com" in u: return "MiniMax"
	if "bigmodel.cn" in u: return "Zhipu AI (GLM)"
	if "dashscope" in u: return "Qwen (DashScope)"
	if "volces.com" in u: return "Doubao (Volcengine)"
	if "x.ai" in u: return "xAI (Grok)"
	if "anthropic.com" in u: return "Anthropic (Claude)"
	return ""
