@tool
class_name ConfigManager
extends RefCounted
## 配置管理:base_url, api_key, model, 采样参数
##
## 存储位置:res://addons/ai_panel/config.cfg
## 该文件不进 git(写入 .gitignore)

const CONFIG_PATH := "res://addons/ai_panel/config.cfg"

const DEFAULT_BASE_URL := "https://api.openai.com/v1"
const DEFAULT_MODEL := "gpt-4o"
const DEFAULT_MAX_TOKENS := 4096
const DEFAULT_TEMPERATURE := 0.2

var _config := ConfigFile.new()
var _loaded := false


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
	return _config.get_value("llm", "api_key", "")


func get_model() -> String:
	_load()
	return _config.get_value("llm", "model", DEFAULT_MODEL)


func get_max_tokens() -> int:
	_load()
	return int(_config.get_value("llm", "max_tokens", DEFAULT_MAX_TOKENS))


func get_temperature() -> float:
	_load()
	return float(_config.get_value("llm", "temperature", DEFAULT_TEMPERATURE))


func is_configured() -> bool:
	return not get_api_key().is_empty() and not get_base_url().is_empty()


func save(base_url: String, api_key: String, model: String, max_tokens: int, temperature: float) -> Error:
	_load()
	_config.set_value("llm", "base_url", base_url)
	_config.set_value("llm", "api_key", api_key)
	_config.set_value("llm", "model", model)
	_config.set_value("llm", "max_tokens", max_tokens)
	_config.set_value("llm", "temperature", temperature)
	var err := _config.save(CONFIG_PATH)
	if err == OK:
		_loaded = true
	return err
