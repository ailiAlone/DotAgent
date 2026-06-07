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

# 注入的上下文
var editor_plugin: EditorPlugin = null
var activity_panel: Control = null


func set_editor_context(plugin: EditorPlugin, activity: Control) -> void:
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
	# 注入上下文(让工具能拿到 EditorInterface 和活动面板)
	if module.has_method("set_editor_context"):
		module.set_editor_context(editor_plugin, activity_panel)
	_modules.append(module)


## 返回 OpenAI tools 字段格式的工具定义
func get_tool_definitions() -> Array:
	var out: Array = []
	for mod in _modules:
		var defs: Array = mod.get_tool_definitions()
		for d in defs:
			var name: String = d.get("name", "")
			var description: String = d.get("description", "")
			var parameters: Dictionary = d.get("parameters", {"type": "object", "properties": {}})
			if name.is_empty():
				continue
			out.append({
				"type": "function",
				"function": {
					"name": name,
					"description": description,
					"parameters": parameters,
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
	# 找工具
	var target: Dictionary = {}
	for mod in _modules:
		var defs: Array = mod.get_tool_definitions()
		for d in defs:
			if d.get("name", "") == tc_name:
				target = {"module": mod, "def": d}
				break
		if not target.is_empty():
			break

	if target.is_empty():
		return {"content": "❌ Tool not found: %s" % tc_name}

	var d: Dictionary = target["def"]
	var mod: Object = target["module"]
	var method_name: String = d.get("method_name", "")
	var dangerous: bool = d.get("dangerous", false)

	# 解析参数
	var args: Dictionary = {}
	if not args_raw.is_empty():
		var parsed: Variant = JSON.parse_string(args_raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			args = parsed
		else:
			return {"content": "❌ Invalid JSON arguments: %s" % args_raw.substr(0, 200)}

	# 活动日志
	if activity_panel and activity_panel.has_method("log_tool_call"):
		activity_panel.log_tool_call(tc_name, args, "running")

	# 危险操作:不再弹窗,直接执行,但在 Activity 面板显著标记
	# 备份机制(.ai_panel_backups)兜底
	if dangerous:
		if activity_panel and activity_panel.has_method("log_warning"):
			activity_panel.log_warning("⚠️ Dangerous tool auto-executing: %s" % tc_name)
		else:
			_logger.warn("Dangerous tool auto-executing: %s" % tc_name)
		_logger.append("TOOL", "⚠️ Dangerous: %s args=%s" % [tc_name, str(args).substr(0, 200)])

	# 执行
	var result: Dictionary
	if mod.has_method(method_name):
		result = await mod.call_method(method_name, args)
	else:
		result = {"ok": false, "content": "❌ Method not found: %s" % method_name}

	if activity_panel and activity_panel.has_method("log_tool_result"):
		activity_panel.log_tool_result(tc_name, result)

	return result


func _confirm_dangerous(name: String, args: Dictionary, description: String) -> bool:
	var base := _get_base_control()
	if base == null:
		push_error("[AI Panel] No base control to show confirmation dialog")
		return false

	var dialog := ConfirmationDialog.new()
	dialog.title = "⚠️ Dangerous Operation: " + name
	dialog.ok_button_text = "Allow"
	dialog.cancel_button_text = "Deny"
	dialog.size = Vector2(500, 300)

	var summary := "[b]%s[/b]\n\n%s\n\n" % [name, description]
	summary += "[color=#ffcc66]Arguments:[/color]\n"
	for k in args.keys():
		var v := str(args[k])
		if v.length() > 200:
			v = v.substr(0, 200) + "..."
		summary += "  • %s: %s\n" % [k, v]
	dialog.dialog_text = summary

	# 数组包装让 lambda 可写
	var choice := [false]
	var dialog_ref := [dialog]
	dialog.confirmed.connect(func():
		choice[0] = true
		if dialog_ref[0] and is_instance_valid(dialog_ref[0]):
			dialog_ref[0].queue_free()
	)
	dialog.canceled.connect(func():
		choice[0] = false
		if dialog_ref[0] and is_instance_valid(dialog_ref[0]):
			dialog_ref[0].queue_free()
	)
	dialog.close_requested.connect(func():
		choice[0] = false
		if dialog_ref[0] and is_instance_valid(dialog_ref[0]):
			dialog_ref[0].queue_free()
	)

	base.add_child(dialog)
	dialog.popup_centered()

	# 等待 dialog 消失
	while is_instance_valid(dialog) and dialog.is_inside_tree():
		await Engine.get_main_loop().process_frame

	return choice[0]


func _get_base_control() -> Node:
	if editor_plugin:
		return editor_plugin.get_editor_interface().get_base_control()
	# Fallback: 取当前场景根
	var tree := Engine.get_main_loop()
	if tree and tree is SceneTree:
		var st := tree as SceneTree
		if st.root:
			return st.root
	return null
