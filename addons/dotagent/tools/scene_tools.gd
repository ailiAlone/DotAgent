@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## Scene/Node Tools
##
## Tools:
## - create_scene
## - set_node_property
## - add_node
## - remove_node
## - reparent_node
## - undo_last




func get_tool_definitions() -> Array:
	return [
		{
			"name": "create_scene",
			"description": "Create a NEW scene file (.tscn) and open it in the editor immediately. Use this BEFORE add_node to create an empty scene with a root node. NEVER use execute_gdscript + FileAccess to write .tscn by hand — it's slow and the editor won't show changes in real-time. After create_scene succeeds, use add_node to build the scene node by node.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path for the new scene, e.g. 'res://player_stats.tscn'"},
					"root_type": {"type": "string", "description": "Root node class (default 'Control'). Use 'Control' for UI scenes, 'Node2D' for 2D games.", "default": "Control"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_create_scene",
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
		{
			"name": "undo_last",
			"description": "Undo the last scene operation by restoring the most recent backup. Safe — this tool REVERSES damage, not causes it.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_undo_last",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_create_scene": return _tool_create_scene(args)
		"_tool_set_node_property": return _tool_set_node_property(args)
		"_tool_add_node": return _tool_add_node(args)
		"_tool_remove_node": return _tool_remove_node(args)
		"_tool_reparent_node": return _tool_reparent_node(args)
		"_tool_undo_last": return _tool_undo_last(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_create_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var root_type: String = args.get("root_type", "Control")

	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return _err("path must end with .tscn or .scn")
	if FileAccess.file_exists(path):
		return _err("Scene already exists: " + path + ". Use open_scene to open it.")
	if not ClassDB.class_exists(root_type):
		return _err("Unknown class: " + root_type)

	# ensure directory exists
	_ensure_dir(path)

	# create root node
	var root: Node = ClassDB.instantiate(root_type)
	var scene_name := path.get_file().get_basename()
	root.name = scene_name

	# pack into PackedScene
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return _err("Failed to pack scene (err=%d). Try a different root_type." % err)

	# save to disk
	err = ResourceSaver.save(packed, path)
	if err != OK:
		return _err("Failed to save: " + error_string(err))

	# open in editor immediately
	var ei = _ei()
	if ei:
		ei.open_scene_from_path(path)
	else:
		return _ok("Created: " + path + " (EditorInterface unavailable, open it manually)")

	return _ok("Created and opened: " + path + " (root: " + root_type + "). Now use add_node to build it node by node.")


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

	# 特殊处理 script 属性：字符串路径 → load Resource
	if prop_name == "script" and typeof(value) == TYPE_STRING:
		var script_path: String = _strip_quotes(str(value))
		if script_path.ends_with(".gd") and FileAccess.file_exists(script_path):
			var res := load(script_path)
			if res != null:
				node.set("script", res)
				_emit_change()
				return _ok("Set %s.script = %s" % [node.name, script_path])
		# fall through to normal set（让 node.set 处理其他类型）

	# 解析值并设置属性
	var parsed := _parse_property_value(value)
	node.set(prop_name, parsed)
	_emit_change()
	return _ok("Set %s.%s = %s" % [node.name, prop_name, str(value)])


## 去掉字符串外层引号（LLM 有时多包一层 "\"text\"" → "text"）
func _strip_quotes(s: String) -> String:
	var t := s.strip_edges()
	if t.begins_with('"') and t.ends_with('"') and t.length() >= 2:
		return t.substr(1, t.length() - 2)
	return t


func _tool_add_node(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root = ei.get_edited_scene_root()
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

	# unique_name_in_owner (set before or after add_child)
	if bool(args.get("unique_name", false)):
		node.unique_name_in_owner = true

	parent.add_child(node)
	node.owner = root  # 确保保存进场景

	# 设置属性 — 必须在 add_child + owner 之后，否则 transform 类属性会被重置
	var properties: Dictionary = args.get("properties", {})
	for k in properties.keys():
		node.set(k, _parse_property_value(properties[k]))

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
	node.reparent(new_parent)
	_emit_change()
	return _ok("Reparented '%s' under '%s'" % [node.name, new_parent.name])


func _tool_undo_last(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root = ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open")
	var scene_path: String = root.scene_file_path
	if scene_path.is_empty():
		return _err("Scene not saved yet")
	var backups := _backup.list_backups()
	if backups.is_empty():
		return _err("No backups found")
	# get latest backup
	var latest: String = backups[backups.size() - 1]
	var backup_file: String = "res://.dotagent_backups/" + latest + "/" + scene_path.trim_prefix("res://")
	if not FileAccess.file_exists(backup_file):
		return _err("Backup file not found: " + backup_file)
	var f := FileAccess.open(backup_file, FileAccess.READ)
	if f == null:
		return _err("Cannot read backup")
	var content := f.get_as_text()
	f.close()
	var fw := FileAccess.open(scene_path, FileAccess.WRITE)
	if fw == null:
		return _err("Cannot write scene")
	fw.store_string(content)
	fw.close()
	if ei:
		ei.open_scene_from_path(scene_path)
	return _ok("Restored scene from backup: " + latest)


# ============ Helpers ============

func _resolve_node(path: String) -> Node:
	var ei = _ei()
	if ei == null:
		return null
	var root = ei.get_edited_scene_root()
	if root == null:
		return null
	# root node path variants
	if path.is_empty() or path == "." or path == "/":
		return root
	# AI often uses root node name, has_node doesn't recognize self
	if path == root.name:
		return root
	if not root.has_node(path):
		return null
	return root.get_node(path)


func _reown(node: Node, root: Node) -> void:
	if node == root:
		return
	node.owner = root
	for child in node.get_children():
		_reown(child, root)


func _emit_change() -> void:
	var ei = _ei()
	if ei == null:
		return
	var root = ei.get_edited_scene_root()
	if root == null:
		return
	if root.scene_file_path.is_empty():
		_log_act("log_warning", "Scene has no file path (new scene). Save it manually first.")
		return
	# 保存前先备份磁盘上的旧版本
	_get_backup().backup(root.scene_file_path)
	# 直接同步保存，不依赖 call_deferred（在异步 ReAct 流程中可能被丢弃）
	ei.save_scene()
	_log_act("log_info", "✅ Auto-saved: " + root.scene_file_path)
	_logger.append("SCENE", "Auto-saved: " + root.scene_file_path)


func _type_name(v: Variant) -> String:
	if v == null:
		return "null"
	return type_string(typeof(v))
