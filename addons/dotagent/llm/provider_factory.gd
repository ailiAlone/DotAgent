@tool
class_name ProviderFactory
extends RefCounted
## Provider 工厂 — 根据配置自动选择正确的 LLMProvider 实例
##
## 选择逻辑:
##   1. URL 包含 /anthropic/ 或 host 是 api.anthropic.com → AnthropicProvider
##   2. URL 包含 localhost:11434 → OllamaProvider
##   3. 其他所有（OpenAI / DeepSeek / Kimi / MiniMax / Qwen 等）→ OpenAIProvider
##
## 用法:
##   var provider: LLMProvider = ProviderFactory.create_from_config()
##   # 或显式指定:
##   var provider: LLMProvider = ProviderFactory.create_for_url("https://api.minimaxi.com/v1", "sk-xxx")

## 已知 Anthropic API 主机
const ANTHROPIC_HOSTS := ["api.anthropic.com"]

## 已知使用 /anthropic/ 端点的提供商（如 MiniMax 的 anthropic 兼容端点）
const ANTHROPIC_PATH_MARKER := "/anthropic/"


## 从当前 ConfigManager 配置创建 provider
static func create_from_config() -> LLMProvider:
	var cfg := ConfigManager.instance()
	return create_for_url(cfg.get_base_url(), cfg.get_api_key())


## 根据 URL + API Key 创建对应的 provider 实例
static func create_for_url(base_url: String, api_key: String) -> LLMProvider:
	var url_lower := base_url.to_lower().strip_edges()
	var fmt := detect_format(url_lower)

	match fmt:
		"anthropic":
			# 提取真正的 base URL（去掉 /v1/messages 等尾部路径）
			var host_url := _extract_anthropic_base(url_lower)
			return AnthropicProvider.new(api_key, host_url)
		"ollama":
			return OllamaProvider.new(base_url.strip_edges().trim_suffix("/"))
		_:
			# OpenAI 兼容：去掉多余的 /chat/completions 尾部
			var clean_url := _clean_openai_base(base_url.strip_edges())
			return OpenAIProvider.new(clean_url, api_key)


## 检测 URL 对应的 API 格式
static func detect_format(url: String) -> String:
	# Anthropic 原生
	for host in ANTHROPIC_HOSTS:
		if host in url:
			return "anthropic"
	if ANTHROPIC_PATH_MARKER in url:
		return "anthropic"
	# Ollama
	if "localhost:11434" in url or "127.0.0.1:11434" in url:
		return "ollama"
	# 默认 OpenAI 兼容
	return "openai"


## 从 Anthropic 端点 URL 提取 base URL（保留路径前缀）
## "https://api.minimaxi.com/anthropic/v1" → "https://api.minimaxi.com/anthropic/v1"
## "https://api.anthropic.com/v1/messages" → "https://api.anthropic.com/v1"
## "https://api.anthropic.com" → "https://api.anthropic.com"
static func _extract_anthropic_base(url: String) -> String:
	var clean := url.trim_suffix("/")
	# 去掉可能的 chat 端点后缀
	if clean.ends_with("/messages"):
		clean = clean.substr(0, clean.length() - "/messages".length())
	if clean.ends_with("/v1/messages"):
		clean = clean.substr(0, clean.length() - "/v1/messages".length())
	return clean


## 清理 OpenAI base URL — 去掉可能的 /chat/completions 尾部
static func _clean_openai_base(url: String) -> String:
	var clean := url.trim_suffix("/")
	if clean.ends_with("/chat/completions"):
		clean = clean.substr(0, clean.length() - "/chat/completions".length())
	return clean
