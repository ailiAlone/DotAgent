@tool
extends RefCounted
## 工具定义加载器 — 从 JSON 文件加载工具定义并缓存。
##
## 用法:
##   var loader := BanyanToolLoader.new()
##   var node_tools := loader.get_tools("node")
##
## 工具定义文件位于: res://addons/dotagent/banyan_agent/tools/definitions/
##   - node_tools.json

const DEFINITIONS_DIR := "res://addons/dotagent/banyan_agent/tools/definitions/"

var _cache: Dictionary = {}  # layer → Array[tool_def]
var _logger: SessionLog = null


func _init(logger: SessionLog = null) -> void:
	_logger = logger if logger else SessionLog.instance()


## 获取指定层的工具定义列表（OpenAI function-calling 格式）
func get_tools(layer: String) -> Array:
	if _cache.has(layer):
		return _cache[layer]

	var file_path: String = DEFINITIONS_DIR + layer + "_tools.json"
	var tools: Array = _load_from_file(file_path)
	_cache[layer] = tools

	if _logger:
		_logger.append("TOOLS", "Loaded %d tools for layer '%s'" % [tools.size(), layer])
	return tools


## 获取指定层的工具名称列表
func get_tool_names(layer: String) -> Array:
	var tools: Array = get_tools(layer)
	var names: Array = []
	for t in tools:
		var fn: Dictionary = t.get("function", {})
		var name: String = fn.get("name", "")
		if not name.is_empty():
			names.append(name)
	return names


## 按名称过滤工具 — 从指定层中只返回匹配的工具
func filter_tools(layer: String, allowed_names: Array) -> Array:
	if allowed_names.is_empty():
		return get_tools(layer)

	var tools: Array = get_tools(layer)
	var filtered: Array = []
	for t in tools:
		var fn: Dictionary = t.get("function", {})
		if fn.get("name", "") in allowed_names:
			filtered.append(t)
	return filtered


## 从 Legacy ToolRegistry 中获取匹配的工具定义（桥接用）
func get_legacy_tools_matching(tool_registry, names: Array) -> Array:
	if tool_registry == null or names.is_empty():
		return []

	var all_defs: Array = tool_registry.get_tool_definitions()
	var matched: Array = []
	for d in all_defs:
		var fn: Dictionary = d.get("function", {})
		if fn.get("name", "") in names:
			matched.append(d)
	return matched


## 预加载所有层的工具定义
func preload_all() -> void:
	get_tools("root")
	get_tools("branch")
	get_tools("worker")


## 清除缓存
func clear_cache() -> void:
	_cache.clear()


# ============ 内部 ============

func _load_from_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		if _logger:
			_logger.append("TOOLS", "Definition file not found: %s" % path)
		return []

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		if _logger:
			_logger.append("TOOLS", "Failed to open: %s" % path)
		return []

	var text: String = f.get_as_text()
	f.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		if _logger:
			_logger.append("TOOLS", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return []

	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		if _logger:
			_logger.append("TOOLS", "Expected dictionary in %s" % path)
		return []

	var d: Dictionary = data
	var tools: Variant = d.get("tools", [])
	if typeof(tools) != TYPE_ARRAY:
		return []

	return tools
