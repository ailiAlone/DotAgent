@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 节点查询工具 — 从 scene_tools.gd 拆分
##
## 工具:
## - get_scene_tree, get_node, get_node_properties
## - list_nodes, get_signal_connections


func get_tool_definitions() -> Array:
	return [
		{
			"name": "get_scene_tree",
			"description": "Get the scene tree structure of the currently edited scene. Returns node names, types, and child relationships.",
			"parameters": {"type": "object", "properties": {
				"max_depth": {"type": "integer", "description": "Max recursive depth (0=unlimited)", "default": 0},
				"scene_path": {"type": "string", "description": "Optional scene to inspect (default: current scene)"},
			}},
			"method_name": "_tool_get_scene_tree", "dangerous": false,
		},
		{
			"name": "get_node",
			"description": "Get basic info about a specific node by path. Returns name, type, script.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Node path relative to scene root"},
			}, "required": ["path"]},
			"method_name": "_tool_get_node", "dangerous": false,
		},
		{
			"name": "get_node_properties",
			"description": "Get all properties of a specific node. Returns name, type, and current value.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Node path relative to scene root"},
			}, "required": ["path"]},
			"method_name": "_tool_get_node_properties", "dangerous": false,
		},
		{
			"name": "list_nodes",
			"description": "Flat list of all nodes in a scene (name, type, path, child_count). Compact alternative to get_scene_tree.",
			"parameters": {"type": "object", "properties": {
				"scene_path": {"type": "string", "description": "Scene to inspect (default: current scene)"},
			}},
			"method_name": "_tool_list_nodes", "dangerous": false,
		},
		{
			"name": "get_signal_connections",
			"description": "List all signal connections for a node — both editor-bound and script .connect() calls.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Node path relative to scene root"},
			}, "required": ["path"]},
			"method_name": "_tool_get_signal_connections", "dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_get_scene_tree": return _tool_get_scene_tree(args)
		"_tool_get_node": return _tool_get_node(args)
		"_tool_get_node_properties": return _tool_get_node_properties(args)
		"_tool_list_nodes": return _tool_list_nodes(args)
		"_tool_get_signal_connections": return _tool_get_signal_connections(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 实现 ============

func _tool_get_scene_tree(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var root: Node
	var scene_path: String = args.get("scene_path", "")
	if not scene_path.is_empty():
		if not FileAccess.file_exists(scene_path): return _err("Scene not found: " + scene_path)
		var packed := load(scene_path) as PackedScene
		if packed == null: return _err("Failed to load scene: " + scene_path)
		root = packed.instantiate()
		if root == null: return _err("Failed to instantiate: " + scene_path)
	else:
		root = ei.get_edited_scene_root()
		if root == null: return _err("No scene open")
	var max_depth: int = int(args.get("max_depth", 0))
	var result := _tree_to_string(root, max_depth, 0)
	if not scene_path.is_empty(): root.free()
	return _ok(result)


func _tree_to_string(node: Node, max_depth: int, depth: int) -> String:
	if max_depth > 0 and depth >= max_depth: return ""
	var indent := "  ".repeat(depth)
	var line := "%s%s (%s)" % [indent, node.name, node.get_class()]
	var script := node.get_script()
	if script: line += " [%s]" % script.resource_path.get_file()
	var lines: Array = [line]
	for child in node.get_children():
		var sub := _tree_to_string(child, max_depth, depth + 1)
		if sub != "": lines.append(sub)
	return "\n".join(lines)


func _tool_get_node(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var root: Node = ei.get_edited_scene_root()
	if root == null: return _err("No scene open")
	var path: String = args.get("path", "")
	var node: Node
	if path.is_empty() or path == ".":
		node = root
	elif root.has_node(path):
		node = root.get_node(path)
	else:
		var children: Array = []
		for c in root.get_children(): children.append("  %s (%s)" % [c.name, c.get_class()])
		return _err("Node not found: %s\nRoot direct children:\n%s" % [path, "\n".join(children)])
	var info := {"name": node.name, "type": node.get_class()}
	var script := node.get_script()
	if script: info["script"] = script.resource_path
	return _ok(JSON.stringify(info, "  "))


func _tool_get_node_properties(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var root: Node = ei.get_edited_scene_root()
	if root == null: return _err("No scene open")
	var path: String = args.get("path", "")
	var node: Node
	if path.is_empty() or path == ".":
		node = root
	elif root.has_node(path):
		node = root.get_node(path)
	else:
		return _err("Node not found: " + path)
	var props: Array = []
	for prop in node.get_property_list():
		var pname: String = prop.name
		if pname.begins_with("_"): continue
		if not (pname in node): continue  # 跳过不存在的属性（如 Node2D 无 resource_path）
		var val = node.get(pname)
		var ptype := _type_name(typeof(val))
		var pval: String
		if typeof(val) == TYPE_OBJECT and val != null:
			if "resource_path" in val:
				pval = val.resource_path
			else:
				pval = "<" + val.get_class() + ">"
		else:
			pval = str(val)
		props.append({"name": pname, "type": ptype, "value": pval})
	return _ok(JSON.stringify(props, "  "))


func _type_name(t: int) -> String:
	match t:
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_COLOR: return "Color"
		TYPE_OBJECT: return "Object"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "type_%d" % t


func _tool_list_nodes(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var root: Node
	var scene_path: String = args.get("scene_path", "")
	if not scene_path.is_empty():
		if not FileAccess.file_exists(scene_path): return _err("Scene not found: " + scene_path)
		var packed := load(scene_path) as PackedScene
		if packed == null: return _err("Failed to load: " + scene_path)
		root = packed.instantiate()
	else:
		root = ei.get_edited_scene_root()
	if root == null: return _err("No scene available")
	var nodes: Array = []
	_collect_nodes_flat(root, "", nodes)
	if not scene_path.is_empty(): root.free()
	var lines: Array = ["%d nodes:" % nodes.size()]
	for nd in nodes:
		lines.append("%-24s %-20s %s" % [nd["name"], nd["type"], nd["path"]])
	return _ok("\n".join(lines))


func _collect_nodes_flat(node: Node, parent_path: String, out: Array) -> void:
	var path := parent_path + "/" + node.name if parent_path != "" else node.name
	out.append({"name": node.name, "type": node.get_class(), "path": path, "child_count": node.get_child_count()})
	for child in node.get_children():
		_collect_nodes_flat(child, path, out)


func _tool_get_signal_connections(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var root: Node = ei.get_edited_scene_root()
	if root == null: return _err("No scene open")
	var path: String = args.get("path", "")
	var node: Node
	if path.is_empty() or path == ".":
		node = root
	elif root.has_node(path):
		node = root.get_node(path)
	else:
		return _err("Node not found: " + path)
	var connections: Array = []
	for sig in node.get_signal_list():
		var sname: String = sig.name
		for conn in node.get_signal_connection_list(sname):
			connections.append({
				"signal": sname,
				"target": conn.signal.get_object().name if conn.signal.get_object() else "?",
				"method": conn.callable.get_method() if conn.callable else "?",
			})
	if connections.is_empty(): return _ok("No signal connections on '%s'" % node.name)
	var lines: Array = ["Signal connections on '%s':" % node.name]
	for c in connections:
		lines.append("  %s → %s.%s" % [c["signal"], c["target"], c["method"]])
	return _ok("\n".join(lines))
