@tool
class_name ToolRegistry
extends RefCounted

var _logger: SessionLog = SessionLog.instance()
## 工具注册中心
##
## 每个工具模块提供一个 get_tool_definitions() + call_method(method_name, args) 接口。
## Registry 负责把它们聚合成 OpenAI 工具定义,并在 LLM 真正调用时执行。
##
## 危险工具(dangerous=true)执行前会通过 ConfirmationDialog 弹一次确认。

var _modules: Array = []
var _tool_cache: Dictionary = {}  # name → {module, def, method_name, dangerous}

# 注入的上下文
var editor_plugin: Object = null  # 实际是 EditorPlugin,但用 Object 允许 headless stub 注入
var activity_panel: Object = null  # 实际是 Control,同上


func set_editor_context(plugin: Object, activity: Object) -> void:
	editor_plugin = plugin
	activity_panel = activity


## 注册一个工具模块(对象)。模块必须有 get_tool_definitions() 和 call_method(name, args)。
## 如果模块实现了 set_editor_context(plugin, activity),会被调用以注入上下文。
func register_module(module: Object) -> void:
	if not module.has_method("get_tool_definitions"):
		push_error("[AI Panel] Tool module missing get_tool_definitions(): %s" % module)
		return
	if not module.has_method("call_method"):
		push_error("[AI Panel] Tool module missing call_method(): %s" % module)
		return
	if module.has_method("set_editor_context"):
		module.set_editor_context(editor_plugin, activity_panel)
	_modules.append(module)
	# 建缓存
	for d in module.get_tool_definitions():
		var name: String = d.get("name", "")
		if not name.is_empty():
			_tool_cache[name] = {"module": module, "def": d, "method_name": d.get("method_name", ""), "dangerous": d.get("dangerous", false)}


## 返回 OpenAI tools 字段格式的工具定义
func get_tool_definitions() -> Array:
	# 使用 _tool_cache（后注册覆盖）确保定义与执行一致
	var out: Array = []
	for name in _tool_cache.keys():
		var entry: Dictionary = _tool_cache[name]
		var d: Dictionary = entry["def"]
		out.append({
			"type": "function",
			"function": {
				"name": name,
				"description": d.get("description", ""),
				"parameters": d.get("parameters", {"type": "object", "properties": {}}),
			},
		})
	return out


## 执行一个工具调用。
## tc_name: 工具名
## args_raw: 工具参数(JSON 字符串,来自 LLM)
## ui_log: 可选回调,用于把执行状态展示到 UI(目前没用,保留)
##
## 返回 {content: String} - 直接喂回 LLM 的 tool message content
func execute_tool(tc_name: String, args_raw: String) -> Dictionary:
	var entry: Dictionary = _tool_cache.get(tc_name, {})
	if entry.is_empty():
		return {"content": "❌ Tool not found: %s" % tc_name}

	var mod: Object = entry["module"]
	var method_name: String = entry["method_name"]
	var dangerous: bool = entry["dangerous"]

	# 解析参数
	var args: Dictionary = {}
	if not args_raw.is_empty():
		var parsed: Variant = JSON.parse_string(args_raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			args = parsed
		else:
			return {"content": "❌ Invalid JSON arguments: %s" % args_raw.substr(0, 200)}

	_log_act("log_tool_call", tc_name, args, "running")
	if dangerous:
		_log_act("log_warning", "⚠️ Dangerous: %s" % tc_name)
		_logger.append("TOOL", "⚠️ Dangerous: %s args=%s" % [tc_name, str(args).substr(0, 200)])

	var result: Dictionary
	var start_ticks := Time.get_ticks_msec()
	if mod.has_method(method_name):
		result = await mod.call_method(method_name, args)
	else:
		result = {"ok": false, "content": "❌ Method not found: %s" % method_name}
	var elapsed_ms := Time.get_ticks_msec() - start_ticks

	_logger.record_tool_result(tc_name, result.get("ok", true), elapsed_ms, args, result.get("content", ""))

	_log_act("log_tool_result", tc_name, result)
	if not result.get("ok", true) and str(result.get("content", "")).contains("Node not found"):
		result = await _augment_with_scene_tree(tc_name, result)

	return result


func _augment_with_scene_tree(tc_name: String, result: Dictionary) -> Dictionary:
	var entry: Dictionary = _tool_cache.get("get_scene_tree", {})
	if entry.is_empty():
		return result
	var mod: Object = entry["module"]
	var tree_result: Dictionary = await mod.call_method(entry["method_name"], {"max_depth": 2})
	var content: String = result.get("content", "") + "\n\n📋 当前场景结构(帮你定位节点):\n" + tree_result.get("content", "")
	return {"ok": false, "content": content}


## 调用 activity_panel 的日志方法（有则调，无则忽略）
func _log_act(method: String, arg1 = null, arg2 = null, arg3 = null) -> void:
	if activity_panel == null or not activity_panel.has_method(method):
		return
	if arg3 != null:
		activity_panel.call(method, arg1, arg2, arg3)
	elif arg2 != null:
		activity_panel.call(method, arg1, arg2)
	else:
		activity_panel.call(method, arg1)
