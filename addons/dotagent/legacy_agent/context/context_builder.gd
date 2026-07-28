@tool
class_name ContextBuilder
extends RefCounted
## 动态上下文构建 — 编辑器状态、最新消息、context 用量估算。
##
## 从 DockController 中拆分出来，保持 controller 文件可维护。

var plugin: Object = null
var _messages: Array[Dictionary]
var _config_manager: ConfigManager
var _tool_registry: ToolRegistry
var _active_skill_content: String = ""
var _static_prompt: String = ""


func setup(p_plugin: Object, messages: Array[Dictionary], config: ConfigManager, tools: ToolRegistry, static_prompt: String) -> void:
	plugin = p_plugin
	_messages = messages
	_config_manager = config
	_tool_registry = tools
	_static_prompt = static_prompt


func set_skill_content(content: String) -> void:
	_active_skill_content = content


## 同步 messages 引用 — 当 DockController 在 bootstrap 后重新赋值 _messages 时调用
func resync(messages: Array[Dictionary]) -> void:
	_messages = messages


## 更新 _messages[0] 的 system 内容为完整的 system prompt + 动态上下文
func update_system_message() -> void:
	var dynamic := build_dynamic_context()
	var combined := _system_prompt_with_model() + "\n\n[当前上下文]\n" + dynamic
	if not _active_skill_content.is_empty():
		combined += "\n\n[场景技能 — 开发规范]\n" + _active_skill_content
	if _messages.size() > 0 and _messages[0].get("role", "") == "system":
		_messages[0]["content"] = combined
	else:
		_messages.push_front({"role": "system", "content": combined})


func _system_prompt_with_model() -> String:
	var base := _static_prompt + "\n\n当前模型: " + _config_manager.get_model()
	if _config_manager.get_vision_enabled():
		base += "\n🖼️ 视觉能力: 支持图片输入"
	return base


func build_dynamic_context() -> String:
	var lines: Array = []
	if plugin == null:
		lines.append("(plugin not available)")
		return "\n".join(lines)

	var last_user_msg := ""
	for idx in range(_messages.size() - 1, -1, -1):
		if _messages[idx].get("role") == "user":
			last_user_msg = str(_messages[idx].get("content", ""))
			break
	if last_user_msg != "":
		lines.append("⚠️ 用户最新指令（你必须回应这一条，不要回应历史消息）：")
		lines.append(last_user_msg)

	var ei = plugin.get_editor_interface()
	if ei == null:
		lines.append("(EditorInterface unavailable)")
		return "\n".join(lines)

	var root = ei.get_edited_scene_root()
	if root == null:
		lines.append("- 当前场景: (未打开)")
	else:
		lines.append("- 当前场景: %s" % root.scene_file_path)
		var tree := _summarize_scene(root, 1, 0)
		lines.append("  结构:")
		lines.append(tree)

	var sel = ei.get_selection().get_selected_nodes()
	if sel.is_empty():
		lines.append("- 选中节点: (无)")
	else:
		var sel_desc: Array = []
		for n in sel:
			sel_desc.append("%s (%s)" % [n.name, n.get_class()])
		lines.append("- 选中节点: " + ", ".join(sel_desc))

	lines.append("- Godot 版本: %s" % Engine.get_version_info().get("string", "unknown"))

	var stats := estimate_context_usage()
	lines.append("- Context 用量: ~%dK / %dK (%d%%)" % [stats.used_k, stats.max_k, stats.pct])
	if stats.pct > 60:
		lines.append("⚠️ Context 已用 %d%%，建议本任务尽量精简输出" % stats.pct)

	return "\n".join(lines)


func estimate_context_usage() -> Dictionary:
	var total_chars := 0
	for msg in _messages:
		total_chars += str(msg.get("content", "")).length()
		for tc in msg.get("tool_calls", []):
			total_chars += str(tc.get("function", {}).get("arguments", "")).length()
	total_chars += _count_tool_def_chars()
	var tokens := max(1, int(total_chars / 2.2))
	var max_k: int = _config_manager.get_context_limit()
	var used_k: int = max(1, tokens / 1000)
	var pct := int(min(100, float(tokens) / (max_k * 1000) * 100))
	SessionLog.instance().record_context_pressure(used_k, max_k, pct)
	return {"used_k": used_k, "max_k": max_k, "pct": pct, "tokens": tokens}


func _count_tool_def_chars() -> int:
	if _tool_registry == null:
		return 0
	var defs := _tool_registry.get_tool_definitions()
	if defs.is_empty():
		return 0
	return JSON.stringify(defs).length()


func _summarize_scene(node: Node, max_depth: int, depth: int) -> String:
	if depth >= max_depth:
		return ""
	var indent := "  ".repeat(depth + 1)
	var s := "%s- %s (%s)" % [indent, node.name, node.get_class()]
	var children_strs: Array = []
	for child in node.get_children():
		var child_s := _summarize_scene(child, max_depth, depth + 1)
		if child_s != "":
			children_strs.append(child_s)
	if not children_strs.is_empty():
		s += "\n" + "\n".join(children_strs)
	return s
