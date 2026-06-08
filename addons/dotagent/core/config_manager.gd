@tool
class_name ConfigManager
extends RefCounted
## 配置管理:base_url, api_key, model, 采样参数
##
## 存储位置:res://addons/dotagent/config.cfg
## 该文件不进 git(写入 .gitignore)

const CONFIG_PATH := "res://addons/dotagent/config.cfg"

const DEFAULT_BASE_URL := "https://api.openai.com/v1"
const DEFAULT_MODEL := "gpt-4o"
const DEFAULT_MAX_TOKENS := 4  # K tokens, UI 显示 "Max Tokens (K)"
const DEFAULT_TEMPERATURE := 0.2
const DEFAULT_CONTEXT_LIMIT := 1024  # K tokens, DeepSeek v4 支持 1M

var _config := ConfigFile.new()
var _loaded := false

static var _instance: ConfigManager = null

static func instance() -> ConfigManager:
	if _instance == null:
		_instance = ConfigManager.new()
	return _instance


func _load() -> void:
	if _loaded:
		return
	var err := _config.load(CONFIG_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[AI Panel] Failed to load config: %d" % err)
	_loaded = true


func get_base_url() -> String:
	_load()
	return _config.get_value("llm", "base_url", DEFAULT_BASE_URL)


func get_api_key() -> String:
	_load()
	# 优先读 config.cfg 里的"用户填入"的 key — 这是正常运行时路径(Settings 对话框填入)
	var cfg_key: String = str(_config.get_value("llm", "api_key", ""))
	if not cfg_key.is_empty():
		return cfg_key
	# Fallback: 从环境变量读。Windows 上用户在"用户变量"里设的 DeepSeek_APIKEY
	# 会被 Godot 进程继承,作为"防着 config 丢了/没填"的兜底。
	var env_key: String = OS.get_environment("DeepSeek_APIKEY")
	if not env_key.is_empty():
		return env_key
	return ""


func get_model() -> String:
	_load()
	return _config.get_value("llm", "model", DEFAULT_MODEL)


func get_max_tokens() -> int:
	return DEFAULT_MAX_TOKENS  # 不在 UI 配置，硬编码默认值


func get_temperature() -> float:
	_load()
	return float(_config.get_value("llm", "temperature", DEFAULT_TEMPERATURE))


func get_context_limit() -> int:
	_load()
	return int(_config.get_value("llm", "context_limit", DEFAULT_CONTEXT_LIMIT))


func get_language() -> String:
	_load()
	return str(_config.get_value("llm", "language", "en"))


func is_configured() -> bool:
	return not get_api_key().is_empty() and not get_base_url().is_empty()


func save(base_url: String, api_key: String, model: String, temperature: float, context_limit: int = DEFAULT_CONTEXT_LIMIT, language: String = "zh") -> Error:
	_load()
	_config.set_value("llm", "base_url", base_url)
	_config.set_value("llm", "api_key", api_key)
	_config.set_value("llm", "model", model)
	_config.set_value("llm", "temperature", temperature)
	_config.set_value("llm", "context_limit", context_limit)
	_config.set_value("llm", "language", language)
	var err := _config.save(CONFIG_PATH)
	if err == OK:
		_loaded = false  # 下次 get_xxx() 重读磁盘
	return err
