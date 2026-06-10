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
const DEFAULT_MAX_TOKENS_K := 128  # max_tokens 单位 K
const DEFAULT_TEMPERATURE := 0.2
const DEFAULT_CONTEXT_LIMIT := 1024  # K tokens 上限

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
	return OS.get_environment("DOTAGENT_API_KEY")


func get_model() -> String:
	_load()
	return _config.get_value("llm", "model", DEFAULT_MODEL)


func get_max_tokens_k() -> int:
	_load()
	return int(_config.get_value("llm", "max_tokens_k", DEFAULT_MAX_TOKENS_K))


func get_max_tokens() -> int:
	return get_max_tokens_k()


func get_temperature() -> float:
	_load()
	return float(_config.get_value("llm", "temperature", DEFAULT_TEMPERATURE))


func get_context_limit() -> int:
	_load()
	return int(_config.get_value("llm", "context_limit", DEFAULT_CONTEXT_LIMIT))


func get_language() -> String:
	_load()
	return str(_config.get_value("llm", "language", "en"))


func get_vision_enabled() -> bool:
	_load()
	return bool(_config.get_value("llm", "vision_enabled", false))


func is_configured() -> bool:
	return not get_api_key().is_empty() and not get_base_url().is_empty()


func save(base_url: String, api_key: String, model: String, temperature: float, context_limit: int = DEFAULT_CONTEXT_LIMIT, language: String = "zh", max_tokens_k: int = DEFAULT_MAX_TOKENS_K, vision_enabled: bool = false) -> Error:
	_load()
	_config.set_value("llm", "base_url", base_url)
	_config.set_value("llm", "model", model)
	_config.set_value("llm", "temperature", temperature)
	_config.set_value("llm", "context_limit", context_limit)
	_config.set_value("llm", "language", language)
	_config.set_value("llm", "max_tokens_k", max_tokens_k)
	_config.set_value("llm", "vision_enabled", vision_enabled)
	# api_key 不写入 config 文件 — 只从环境变量 DOTAGENT_API_KEY 读取
	var err := _config.save(CONFIG_PATH)
	if err == OK:
		_loaded = false  # 下次 get_xxx() 重读磁盘
	return err
