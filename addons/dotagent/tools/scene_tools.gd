@tool
extends RefCounted
## 场景/节点工具集
##
## 工具:
## - get_scene_tree
## - get_node
## - get_node_properties
## - set_node_property
## - add_node
## - remove_node
## - duplicate_node
## - reparent_node

const _Logger := preload("res://addons/dotagent/logger.gd")

var editor_plugin: EditorPlugin = null
var activity_panel: Control = null
var _logger: SessionLog = SessionLog.instance()


func set_editor_context(plugin: EditorPlugin, activity: Control) -> void:
	editor_plugin = plugin
	activity_panel = activity


func _ei() -> EditorInterface:
	if editor_plugin:
		return editor_plugin.get_editor_interface()
	return null


func get_tool_definitions() -> Array:
	return [
		{
			"name": "get_scene_tree",
			"description": "Get the current edited scene tree as nested JSON. Each node includes name, type, script path, and a list of children. Use this to understand scene structure before making changes.",
			"parameters": {
				"type": "object",
				"properties": {
					"max_depth": {"type": "integer", "description": "Max recursion depth (default 3, max 10)", "default": 3},
				},
			},
			"method_name": "_tool_get_scene_tree",
			"dangerous": false,
		},
		{
			"name": "get_node",
			"description": "Get detailed info about a specific node at a path. Path is relative to the edited scene root (e.g. 'Player' or 'UI/HealthBar').",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path relative to scene root"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_get_node",
			"dangerous": false,
		},
		{
			"name": "get_node_properties",
			"description": "List all properties and current values of a node. Useful for inspecting before modification.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path relative to scene root"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_get_node_properties",
			"dangerous": false,
		},
		{
			"name": "set_node_property",
			"description": "Set a property on a node. Value is parsed as JSON (string/number/bool/Vector2/etc).",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path"},
					"name": {"type": "string", "description": "Property name"},
					"value": {"description": "New value (JSON)"},
				},
				"required": ["path", "name", "value"],
			},
			"method_name": "_tool_set_node_property",
			"dangerous": false,
		},
		{
			"name": "add_node",
			"description": "Add a child node to a parent. type is a class name (e.g. 'Sprite2D', 'Button', 'CharacterBody2D'). properties is a dict of {name: value} pairs. If unique_name is true, the node is registered for % access from the scene root (recommended for nodes referenced by @onready %Name).",
			"parameters": {
				"type": "object",
				"properties": {
					"parent_path": {"type": "string", "description": "Parent node path (use '.' or '' for scene root)"},
					"type": {"type": "string", "description": "Node class name (e.g. 'Sprite2D', 'Button')"},
					"name": {"type": "string", "description": "Name for the new node"},
					"properties": {"type": "object", "description": "Optional initial properties as {name: value} dict"},
					"unique_name": {"type": "boolean", "description": "Set unique_name_in_owner=true (for @onready %Name access)", "default": false},
				},
				"required": ["parent_path", "type", "name"],
			},
			"method_name": "_tool_add_node",
			"dangerous": false,
		},
		{
			"name": "remove_node",
			"description": "Remove a node and its children from the scene. DANGEROUS - cannot be undone via this tool.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path to remove"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_remove_node",
			"dangerous": true,
		},
		{
			"name": "reparent_node",
			"description": "Move a node to a new parent. The node keeps its name and all children.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path to move"},
					"new_parent_path": {"type": "string", "description": "New parent path"},
				},
				"required": ["path", "new_parent_path"],
			},
			"method_name": "_tool_reparent_node",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_get_scene_tree": return _tool_get_scene_tree(args)
		"_tool_get_node": return _tool_get_node(args)
		"_tool_get_node_properties": return _tool_get_node_properties(args)
		"_tool_set_node_property": return _tool_set_node_property(args)
		"_tool_add_node": return _tool_add_node(args)
		"_tool_remove_node": return _tool_remove_node(args)
		"_tool_reparent_node": return _tool_reparent_node(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_get_scene_tree(args: Dictionary) -> Dictionary:
	var ei := _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root := ei.get_edited_scene_root()
	if root == null:
		return _ok("No scene currently open in editor.")

	var depth: int = int(args.get("max_depth", 3))
	depth = clamp(depth, 1, 10)
	var tree := _serialize_node(root, depth, 0)
	return _ok(JSON.stringify(tree, "  "))


func _tool_get_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found: " + str(args.get("path", "")))
	return _ok(JSON.stringify(_serialize_node(node, 0, 0), "  "))


func _tool_get_node_properties(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var props := []
	for prop in node.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var pname: String = prop.name
		# 过滤掉 AI 几乎不关心的"噪音"属性,避免返回超长列表
		if not _is_important_prop(pname):
			continue
		var val = node.get(pname)
		if val is Resource and val != null and val.resource_path != "":
			props.append({"name": pname, "type": _type_name(val), "value": val.resource_path})
		else:
			props.append({"name": pname, "type": _type_name(val), "value": str(val)})
	return _ok(JSON.stringify(props, "  "))


## 过滤 _tool_get_node_properties 的输出:只保留 AI 真正关心的属性
## 之前返回所有 storage 属性,动辄 100+ 行,AI 看着头大
func _is_important_prop(pname: String) -> bool:
	# 内部 / 隐藏
	if pname.begins_with("_"):
		return false
	# process / physics 调度
	if pname in ["process_mode", "process_priority", "process_physics_priority", "process_thread_group",
				 "physics_interpolation_mode"]:
		return false
	# 国际化 / 翻译
	if pname in ["auto_translate_mode", "localize_numeral_system"]:
		return false
	# 渲染层 / mask
	if pname in ["visibility_layer", "light_mask", "visibility_behavior_recursive"]:
		return false
	# mouse / focus / accessibility — 用户几乎不通过 AI 改
	if pname.begins_with("mouse_") or pname.begins_with("focus_") or pname.begins_with("accessibility_"):
		return false
	# 渲染细节
	if pname in ["top_level", "clip_children", "clip_contents",
				 "show_behind_parent", "y_sort_enabled", "use_parent_material",
				 "texture_filter", "texture_repeat", "material",
				 "editor_description"]:
		return false
	# tooltip / shortcut — 偶尔关心,但默认跳过
	if pname.begins_with("shortcut_") or pname == "tooltip_auto_translate_mode":
		return false
	# 默认:保留
	return true


func _tool_set_node_property(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var prop_name: String = args.get("name", "")
	if prop_name.is_empty():
		return _err("Missing 'name' parameter")
	if not args.has("value"):
		return _err("Missing 'value' parameter")
	var value = args["value"]
	node.set(prop_name, value)
	_emit_change()
	return _ok("Set %s.%s = %s" % [node.name, prop_name, str(value)])


func _tool_add_node(args: Dictionary) -> Dictionary:
	var ei := _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root := ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open. Open a scene first.")

	var parent_path: String = args.get("parent_path", ".")
	var type_name: String = args.get("type", "")
	var node_name: String = args.get("name", "")

	if type_name.is_empty() or node_name.is_empty():
		return _err("type and name are required")

	var parent: Node = root if parent_path in [".", "", "/"] else _resolve_node(parent_path)
	if parent == null:
		return _err("Parent not found: " + parent_path)

	if not ClassDB.class_exists(type_name):
		return _err("Unknown class: " + type_name)

	var node := ClassDB.instantiate(type_name)
	if node == null:
		return _err("Failed to instantiate: " + type_name)
	node.name = node_name

	# unique_name_in_owner(必须在 add_child 之前或之后马上设)
	if bool(args.get("unique_name", false)):
		node.unique_name_in_owner = true

	# 设置属性
	var properties: Dictionary = args.get("properties", {})
	for k in properties.keys():
		node.set(k, properties[k])

	parent.add_child(node)
	node.owner = root  # 确保保存进场景

	_emit_change()
	return _ok("Added %s '%s' under '%s'%s. New path: %s" % [type_name, node_name, parent.name, " (unique_name)" if node.unique_name_in_owner else "", root.get_path_to(node)])


func _tool_remove_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var path := node.get_path()
	node.queue_free()
	_emit_change()
	return _ok("Removed: " + str(path))


func _tool_reparent_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var new_parent := _resolve_node(args.get("new_parent_path", ""))
	if new_parent == null:
		return _err("New parent not found")
	var ei := _ei()
	var root: Node = ei.get_edited_scene_root() if ei else null
	if root == null:
		return _err("No scene open")
	# 重新设 owner
	var old_data := node.duplicate()
	new_parent.add_child(node)
	_reown(node, root)
	_emit_change()
	return _ok("Reparented '%s' under '%s'" % [node.name, new_parent.name])


# ============ 辅助 ============

func _resolve_node(path: String) -> Node:
	var ei := _ei()
	if ei == null:
		return null
	var root := ei.get_edited_scene_root()
	if root == null:
		return null
	# 根节点自身的几种写法
	if path.is_empty() or path == "." or path == "/":
		return root
	# AI 经常用根节点名(比如 "MainMenu")访问,has_node 不认 self
	if path == root.name:
		return root
	if not root.has_node(path):
		return null
	return root.get_node(path)


func _serialize_node(node: Node, max_depth: int, current_depth: int) -> Dictionary:
	var data := {
		"name": node.name,
		"type": node.get_class(),
		"script": (node.get_script().resource_path if node.get_script() else ""),
	}
	if max_depth > 0 and current_depth < max_depth:
		var children := []
		for child in node.get_children():
			children.append(_serialize_node(child, max_depth, current_depth + 1))
		if not children.is_empty():
			data["children"] = children
	return data


func _reown(node: Node, root: Node) -> void:
	if node == root:
		return
	node.owner = root
	for child in node.get_children():
		_reown(child, root)


func _emit_change() -> void:
	# 关键:每个写操作后自动调 EditorInterface.save_scene()
	# 之前只是 log 提示,导致 AI 改了场景但磁盘没存 → run_scene_capture 跑旧版本报错
	# 现在:写 → 立刻存,内存和磁盘同步
	var ei := _ei()
	if ei == null:
		return
	var root := ei.get_edited_scene_root()
	if root == null:
		return
	# 跳过没保存过的新场景(没文件路径)
	if root.scene_file_path.is_empty():
		if activity_panel and activity_panel.has_method("log_warning"):
			activity_panel.log_warning("Scene has no file path (new scene). Save it manually first.")
		return
	var err := ei.save_scene()
	if err == OK:
		if activity_panel and activity_panel.has_method("log_info"):
			activity_panel.log_info("✅ Auto-saved: " + root.scene_file_path)
		_logger.append("SCENE", "Auto-saved: " + root.scene_file_path)
	else:
		var msg := "Auto-save failed: " + error_string(err)
		if activity_panel and activity_panel.has_method("log_warning"):
			activity_panel.log_warning(msg)
		_logger.warn(msg)


func _type_name(v: Variant) -> String:
	if v == null:
		return "null"
	return type_string(typeof(v))


func _ok(content: String) -> Dictionary:
	return {"ok": true, "content": content}


func _err(content: String) -> Dictionary:
	return {"ok": false, "content": "❌ " + content}
