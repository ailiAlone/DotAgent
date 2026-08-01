@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 配置工具模块 — Cortex 写入基础设施
##
## 将结构化 JSON 翻译为 Godot 文件格式操作。
## LLM 输出意图，工具负责执行。
##
## Tools:
## - build_scene: 结构化 JSON → .tscn 场景文件
## - patch_scene: 批量修改已有场景
## - configure_resource: 创建/修改 .tres 资源文件（通用，支持自定义 Resource）
## - configure_project: 读写 project.godot 设置


func get_tool_definitions() -> Array:
	return [
		_td("build_scene",
			"Create a complete scene from structured JSON description. Handles node hierarchy, properties, sub-resources, scripts, and unique names in a single call. This is the WRITE counterpart to inspect_scene_structured.",
			"_tool_build_scene",
			{
				"path": {"type": "string", "description": "Scene file path, e.g. 'res://scenes/player.tscn'"},
				"scripts": {
					"type": "array",
					"description": "Optional script files to create before the scene",
					"items": {
						"type": "object",
						"properties": {
							"path": {"type": "string"},
							"content": {"type": "string"}
						}
					},
					"default": []
				},
				"sub_resources": {
					"type": "array",
					"description": "Sub-resources to embed in the scene",
					"items": {
						"type": "object",
						"properties": {
							"id": {"type": "string", "description": "Unique ID for referencing"},
							"type": {"type": "string", "description": "Resource class name"},
							"properties": {"type": "object"}
						}
					},
					"default": []
				},
				"root": {
					"type": "object",
					"description": "Root node definition",
					"properties": {
						"type": {"type": "string", "description": "Node class name"},
						"name": {"type": "string", "description": "Node name"},
						"script_path": {"type": "string", "description": "Optional script to attach"},
						"properties": {"type": "object", "description": "Node properties"}
					}
				},
				"children": {
					"type": "array",
					"description": "Child node definitions (recursive)",
					"default": []
				},
				"unique_names": {
					"type": "array",
					"description": "Node names to set as unique_name_in_owner",
					"items": {"type": "string"},
					"default": []
				},
				"open_in_editor": {
					"type": "boolean",
					"description": "Open the scene in editor after creation",
					"default": true
				},
			},
			["path", "root"]),
		_td("patch_scene",
			"Apply batch modifications to an existing scene. Supports: set properties, add/remove nodes, add sub-resources, connect signals. Partial commit on failure — failed operations are reported individually.",
			"_tool_patch_scene",
			{
				"path": {"type": "string", "description": "Scene file path to modify"},
				"operations": {
					"type": "array",
					"description": "List of operations to apply",
					"items": {
						"type": "object",
						"properties": {
							"op": {"type": "string", "enum": ["set", "add", "remove", "add_sub_resource", "connect_signal", "reparent"]},
							"node_path": {"type": "string"},
							"properties": {"type": "object"},
							"parent_path": {"type": "string"},
							"type": {"type": "string"},
							"name": {"type": "string"},
							"signal": {"type": "string"},
							"target_path": {"type": "string"},
							"method": {"type": "string"},
							"id": {"type": "string"}
						}
					}
				},
			},
			["path", "operations"]),
		_td("configure_resource",
			"Create or update a .tres resource file. Supports ALL Resource types including user-defined (extends Resource + class_name). Generic implementation — no per-type special handling needed.",
			"_tool_configure_resource",
			{
				"action": {"type": "string", "enum": ["create", "update", "create_or_update"], "description": "create=new file only, update=existing only, create_or_update=auto", "default": "create_or_update"},
				"path": {"type": "string", "description": "Resource file path (.tres)"},
				"type": {"type": "string", "description": "Resource class name (required for create)"},
				"properties": {"type": "object", "description": "Properties to set"},
			},
			["path", "properties"]),
		_td("configure_project",
			"Read/write project.godot settings: display, physics, autoloads, input actions, main scene.",
			"_tool_configure_project",
			{
				"settings": {"type": "object", "description": "ProjectSettings key-value pairs to set", "default": {}},
				"autoloads": {
					"type": "object",
					"description": "Autoload management",
					"properties": {
						"add": {"type": "array", "items": {"type": "object"}},
						"remove": {"type": "array", "items": {"type": "string"}}
					},
					"default": {}
				},
				"input_actions": {
					"type": "object",
					"description": "Input action management (持久化到 project.godot). add 条目必须含 name 字段，例: {\"add\": [{\"name\": \"sprint\", \"deadzone\": 0.5, \"events\": [{\"type\": \"key\", \"keycode\": \"KEY_SHIFT\"}]}]}",
					"properties": {
						"add": {"type": "array", "items": {"type": "object"}},
						"remove": {"type": "array", "items": {"type": "string"}}
					},
					"default": {}
				},
				"main_scene": {"type": "string", "description": "Set main scene path", "default": ""},
			},
			[]),
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_build_scene": return await _tool_build_scene(args)
		"_tool_patch_scene": return _tool_patch_scene(args)
		"_tool_configure_resource": return _tool_configure_resource(args)
		"_tool_configure_project": return _tool_configure_project(args)
	return _err("Unknown method: " + method_name)


# ============ Tool 1: build_scene ============

func _tool_build_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return _err("path must end with .tscn or .scn")
	if FileAccess.file_exists(path):
		return _err("Scene already exists: " + path + ". Use patch_scene to modify.")

	var root_def: Dictionary = args.get("root", {}) if args.get("root") is Dictionary else {}
	var children_defs: Array = _as_array(args.get("children", []))
	var sub_resources_defs: Array = _as_array(args.get("sub_resources", []))
	var scripts_defs: Array = _as_array(args.get("scripts", []))
	var unique_names: Array = _as_array(args.get("unique_names", []))
	var open_in_editor: bool = args.get("open_in_editor", true)

	# Phase 1: Create scripts first (scenes may reference them)
	var scripts_created: Array = []
	for sdef in scripts_defs:
		var spath: String = str(sdef.get("path", ""))
		var scontent: String = str(sdef.get("content", ""))
		if spath.is_empty() or scontent.is_empty():
			continue
		_ensure_dir(spath)
		var f := FileAccess.open(spath, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(scontent)
		f.close()
		scripts_created.append(spath)

	# Phase 2: Create sub-resources
	var sub_resources: Dictionary = {}  # id → Resource
	for sr_def in sub_resources_defs:
		var sr_id: String = str(sr_def.get("id", ""))
		var sr_type: String = str(sr_def.get("type", ""))
		var sr_props: Dictionary = sr_def.get("properties", {})
		if sr_id.is_empty() or sr_type.is_empty():
			continue
		if not ClassDB.class_exists(sr_type):
			continue
		if not ClassDB.is_parent_class(sr_type, "Resource"):
			continue
		var res = ClassDB.instantiate(sr_type)
		if res == null:
			continue
		for key in sr_props:
			var val = _parse_property_value(sr_props[key])
			# Handle sub_resource references
			if val is Dictionary and val.has("sub_resource"):
				var ref_id: String = val["sub_resource"]
				if sub_resources.has(ref_id):
					val = sub_resources[ref_id]
				else:
					continue
			res.set(key, val)
		sub_resources[sr_id] = res

	# Phase 3: Build node tree
	var root_type: String = root_def.get("type", "Node2D")
	var root_name: String = root_def.get("name", path.get_file().get_basename())
	if not ClassDB.class_exists(root_type):
		return _err("Unknown root node type: " + root_type)

	var root: Node = ClassDB.instantiate(root_type)
	root.name = root_name

	# Set root script
	var script_path: String = root_def.get("script_path", "")
	if not script_path.is_empty():
		if FileAccess.file_exists(script_path):
			root.set("script", load(script_path))

	# Set root properties
	var root_props: Dictionary = root_def.get("properties", {})
	for key in root_props:
		var val = _parse_property_value(root_props[key])
		if val is Dictionary and val.has("sub_resource"):
			var ref_id: String = val["sub_resource"]
			if sub_resources.has(ref_id):
				val = sub_resources[ref_id]
			else:
				continue
		root.set(key, val)

	# Add children recursively
	var nodes_created := 1  # root
	var props_set := 0
	props_set += root_props.size()
	var errors: Array = []
	var warnings: Array = []

	nodes_created += _build_children(root, root, children_defs, sub_resources, unique_names, errors, warnings)

	# Phase 4: Pack and save
	_ensure_dir(path)
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.queue_free()
		return _err("Failed to pack scene: " + error_string(pack_err))

	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		root.queue_free()
		return _err("Failed to save scene: " + error_string(save_err))

	# Phase 5: Open in editor
	if open_in_editor:
		var ei = _ei()
		if ei:
			ei.open_scene_from_path(path)

	root.queue_free()

	return _ok_json({
		"type": "build_result",
		"path": path,
		"nodes_created": nodes_created,
		"properties_set": props_set,
		"scripts_created": scripts_created,
		"sub_resources_created": sub_resources.size(),
		"errors": errors,
		"warnings": warnings,
	})


func _build_children(parent: Node, root: Node, children_defs: Array, sub_resources: Dictionary, unique_names: Array, errors: Array, warnings: Array) -> int:
	var count := 0
	for cdef in children_defs:
		var cname: String = str(cdef.get("name", ""))
		var ctype: String = str(cdef.get("type", ""))
		if cname.is_empty() or ctype.is_empty():
			errors.append("Child missing name or type")
			continue
		if not ClassDB.class_exists(ctype):
			errors.append("Unknown type: %s" % ctype)
			continue

		var child: Node = ClassDB.instantiate(ctype)
		if child == null:
			errors.append("Failed to instantiate: %s" % ctype)
			continue

		child.name = cname
		parent.add_child(child)
		child.owner = root
		count += 1

		# Unique name
		if unique_names.has(cname):
			child.unique_name_in_owner = true

		# Script
		var cscript: String = str(cdef.get("script_path", ""))
		if not cscript.is_empty() and FileAccess.file_exists(cscript):
			child.set("script", load(cscript))

		# Properties
		var cprops: Dictionary = cdef.get("properties", {})
		for key in cprops:
			var val = _parse_property_value(cprops[key])
			if val is Dictionary and val.has("sub_resource"):
				var ref_id: String = val["sub_resource"]
				if sub_resources.has(ref_id):
					val = sub_resources[ref_id]
				else:
					warnings.append("%s.%s: sub_resource '%s' not found" % [cname, key, ref_id])
					continue
			child.set(key, val)

		# Recursive children
		var grandchildren: Array = cdef.get("children", [])
		if not grandchildren.is_empty():
			count += _build_children(child, root, grandchildren, sub_resources, unique_names, errors, warnings)

	return count


# ============ Tool 2: patch_scene ============

func _tool_patch_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("Scene not found: " + path)

	var operations: Array = _as_array(args.get("operations", []))
	if operations.is_empty():
		# 附带原始输入预览 — 模型能看到自己发错了什么并自我修正（此前裸报错
		# "No operations provided"，R19 同一错误连犯 3 次）
		var raw_preview: String = str(args.get("operations", "")).substr(0, 300)
		return _err("No operations provided (operations must be an array of {op, ...} objects, NOT a JSON string). Received: %s" % raw_preview)

	# Load scene
	var packed = load(path) as PackedScene
	if packed == null:
		return _err("Failed to load scene: " + path)
	var scene := packed.instantiate()
	if scene == null:
		return _err("Failed to instantiate scene")

	# Backup before modification
	_get_backup().backup(path)

	var results: Array = []
	var op_index := 0

	for op_def in operations:
		var op: String = str(op_def.get("op", ""))
		var op_result := _apply_operation(scene, op_def, op_index)
		results.append(op_result)
		op_index += 1

	# Re-pack and save
	var new_packed := PackedScene.new()
	var pack_err := new_packed.pack(scene)
	if pack_err != OK:
		scene.queue_free()
		return _err("Failed to pack after modifications: " + error_string(pack_err))

	var save_err := ResourceSaver.save(new_packed, path)
	if save_err != OK:
		scene.queue_free()
		return _err("Failed to save: " + error_string(save_err))

	# Open in editor if available
	var ei = _ei()
	if ei:
		ei.open_scene_from_path(path)

	scene.queue_free()

	# Count results
	var ok_count := 0
	var fail_count := 0
	for r in results:
		if r.get("status", "") == "ok":
			ok_count += 1
		else:
			fail_count += 1

	var observations: Array = []
	if fail_count > 0:
		observations.append("%d/%d operations failed — check individual results" % [fail_count, results.size()])

	return _ok_json({
		"type": "patch_result",
		"path": path,
		"operations_applied": results.size(),
		"succeeded": ok_count,
		"failed": fail_count,
		"results": results,
		"observations": observations,
	})


func _apply_operation(scene: Node, op_def: Dictionary, op_index: int) -> Dictionary:
	var op: String = str(op_def.get("op", ""))

	match op:
		"set":
			return _op_set(scene, op_def, op_index)
		"add":
			return _op_add(scene, op_def, op_index)
		"remove":
			return _op_remove(scene, op_def, op_index)
		"add_sub_resource":
			return _op_add_sub_resource(scene, op_def, op_index)
		"connect_signal":
			return _op_connect_signal(scene, op_def, op_index)
		"reparent":
			return _op_reparent(scene, op_def, op_index)
		_:
			return {"op": op_index, "status": "error", "detail": "Unknown operation: " + op}


func _op_set(scene: Node, op_def: Dictionary, idx: int) -> Dictionary:
	var node_path: String = str(op_def.get("node_path", ""))
	var props: Dictionary = op_def.get("properties", {})
	var node := _resolve_node_in(scene, node_path)
	if node == null:
		return {"op": idx, "status": "error", "detail": "Node not found: " + node_path}

	var applied: Array = []
	var readback: Dictionary = {}
	for key in props:
		var perr: String = _apply_node_property(node, key, props[key])
		if not perr.is_empty():
			return {"op": idx, "status": "error", "detail": perr}
		applied.append(key)
		# 回读实际生效值 — 模型无需再花一轮 inspect 确认；
		# 设错属性路径（如 Label 颜色应是 theme_override_colors/font_color）时立即可见
		var rv = node.get(key)
		readback[key] = str(rv).substr(0, 80) if rv != null else "<null>"

	return {"op": idx, "status": "ok", "detail": "Set %s on %s" % [str(applied), node_path], "readback": readback}


## 统一的节点属性应用 — script 属性必须解析为 Script 资源。
## 直接把字符串/字典 set 进 script 会被场景序列化器原样落盘（Variant 文本），
## 场景从此挂空 — 实测全项目 17 个场景的 script 曾集体是 String/Dictionary。
## 返回 "" 成功，否则错误信息。
func _apply_node_property(node: Node, key: String, raw: Variant) -> String:
	if key == "script":
		var spath: String = ""
		if raw is String:
			spath = raw
		elif raw is Dictionary:
			spath = str(raw.get("path", ""))
		if spath.is_empty() or not FileAccess.file_exists(spath):
			return "script 需为存在的脚本路径（字符串或 {\"path\": ...}），收到: %s" % str(raw).substr(0, 120)
		var sres = load(spath)
		if sres == null or not (sres is Script):
			return "无法作为脚本加载: " + spath
		node.set_script(sres)
		return ""
	var val = _parse_property_value(raw)
	node.set(key, val)
	return ""


func _op_add(scene: Node, op_def: Dictionary, idx: int) -> Dictionary:
	var parent_path: String = str(op_def.get("parent_path", "."))
	var node_type: String = str(op_def.get("type", ""))
	var node_name: String = str(op_def.get("name", ""))
	var props: Dictionary = op_def.get("properties", {})

	if node_type.is_empty() or node_name.is_empty():
		return {"op": idx, "status": "error", "detail": "type and name required"}
	if not ClassDB.class_exists(node_type):
		return {"op": idx, "status": "error", "detail": "Unknown type: " + node_type}

	var parent := _resolve_node_in(scene, parent_path)
	if parent == null:
		return {"op": idx, "status": "error", "detail": "Parent not found: " + parent_path}

	var new_node: Node = ClassDB.instantiate(node_type)
	new_node.name = node_name
	parent.add_child(new_node)
	new_node.owner = scene

	for key in props:
		var perr: String = _apply_node_property(new_node, key, props[key])
		if not perr.is_empty():
			new_node.free()
			return {"op": idx, "status": "error", "detail": perr}

	return {"op": idx, "status": "ok", "detail": "Added %s '%s' under '%s'" % [node_type, node_name, parent.name]}


func _op_remove(scene: Node, op_def: Dictionary, idx: int) -> Dictionary:
	var node_path: String = str(op_def.get("node_path", ""))
	var node := _resolve_node_in(scene, node_path)
	if node == null:
		return {"op": idx, "status": "error", "detail": "Node not found: " + node_path}
	if node == scene:
		return {"op": idx, "status": "error", "detail": "Cannot remove root node"}
	node.get_parent().remove_child(node)
	node.free()
	return {"op": idx, "status": "ok", "detail": "Removed: " + node_path}


func _op_add_sub_resource(_scene: Node, op_def: Dictionary, idx: int) -> Dictionary:
	# Sub-resources are handled at the PackedScene level during save.
	# For runtime modification, we attach the resource to the target node's property.
	var node_path: String = str(op_def.get("node_path", ""))
	var prop_name: String = str(op_def.get("property", ""))
	var res_type: String = str(op_def.get("type", ""))
	var props: Dictionary = op_def.get("properties", {})

	if res_type.is_empty():
		return {"op": idx, "status": "error", "detail": "type required"}
	if not ClassDB.class_exists(res_type):
		return {"op": idx, "status": "error", "detail": "Unknown resource type: " + res_type}

	var res = ClassDB.instantiate(res_type)
	if res == null:
		return {"op": idx, "status": "error", "detail": "Failed to instantiate: " + res_type}

	for key in props:
		res.set(key, _parse_property_value(props[key]))

	# If node_path and property specified, attach directly
	if not node_path.is_empty() and not prop_name.is_empty():
		var node := _resolve_node_in(_scene, node_path)
		if node == null:
			return {"op": idx, "status": "error", "detail": "Node not found: " + node_path}
		node.set(prop_name, res)
		return {"op": idx, "status": "ok", "detail": "Set %s.%s = new %s" % [node_path, prop_name, res_type]}

	return {"op": idx, "status": "ok", "detail": "Created sub_resource %s" % res_type}


func _op_connect_signal(scene: Node, op_def: Dictionary, idx: int) -> Dictionary:
	var node_path: String = str(op_def.get("node_path", ""))
	var signal_name: String = str(op_def.get("signal", ""))
	var target_path: String = str(op_def.get("target_path", "."))
	var method_name: String = str(op_def.get("method", ""))

	if signal_name.is_empty() or method_name.is_empty():
		return {"op": idx, "status": "error", "detail": "signal and method required"}

	var source := _resolve_node_in(scene, node_path)
	var target := _resolve_node_in(scene, target_path)
	if source == null:
		return {"op": idx, "status": "error", "detail": "Source node not found: " + node_path}
	if target == null:
		return {"op": idx, "status": "error", "detail": "Target node not found: " + target_path}

	if not source.has_signal(signal_name):
		return {"op": idx, "status": "error", "detail": "Signal '%s' not found on %s" % [signal_name, node_path]}

	source.connect(signal_name, Callable(target, method_name))
	return {"op": idx, "status": "ok", "detail": "%s.%s → %s.%s" % [node_path, signal_name, target_path, method_name]}


func _op_reparent(scene: Node, op_def: Dictionary, idx: int) -> Dictionary:
	var node_path: String = str(op_def.get("node_path", ""))
	var new_parent_path: String = str(op_def.get("new_parent_path", ""))
	var node := _resolve_node_in(scene, node_path)
	var new_parent := _resolve_node_in(scene, new_parent_path)
	if node == null:
		return {"op": idx, "status": "error", "detail": "Node not found: " + node_path}
	if new_parent == null:
		return {"op": idx, "status": "error", "detail": "New parent not found: " + new_parent_path}
	node.reparent(new_parent)
	return {"op": idx, "status": "ok", "detail": "Reparented '%s' under '%s'" % [node.name, new_parent.name]}


func _resolve_node_in(scene: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == "/":
		return scene
	if path == scene.name:
		return scene
	if path.contains("/"):
		return scene.get_node_or_null(NodePath(path))
	return scene.find_child(path, true, false)


# ============ Tool 3: configure_resource ============

func _tool_configure_resource(args: Dictionary) -> Dictionary:
	var action: String = args.get("action", "create_or_update")
	var path: String = args.get("path", "")
	var type_name: String = args.get("type", "")
	var props: Dictionary = args.get("properties", {})

	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".tres") and not path.ends_with(".res"):
		return _err("path must end with .tres or .res")

	var file_exists := FileAccess.file_exists(path)

	# Determine create vs update
	if action == "create" and file_exists:
		return _err("File already exists: " + path)
	if action == "update" and not file_exists:
		return _err("File not found: " + path)

	var res: Resource = null

	if file_exists and (action == "update" or action == "create_or_update"):
		# Load existing with cache bypass
		res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			return _err("Failed to load existing resource: " + path)
	else:
		# Create new
		if type_name.is_empty():
			return _err("type is required for new resources")
		if not ClassDB.class_exists(type_name):
			return _err("Unknown class: " + type_name)
		if not ClassDB.is_parent_class(type_name, "Resource"):
			return _err(type_name + " is not a Resource type")
		res = ClassDB.instantiate(type_name)
		if res == null:
			return _err("Failed to instantiate: " + type_name)

	# Apply properties
	var applied: Array = []
	var failed: Array = []
	for key in props:
		var val = _parse_property_value(props[key])
		# Check if property exists
		var found := false
		for pinfo in res.get_property_list():
			if pinfo.get("name", "") == key:
				found = true
				break
		if not found:
			failed.append({"name": key, "reason": "property not found on " + res.get_class()})
			continue
		res.set(key, val)
		applied.append(key)

	# Save
	_ensure_dir(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return _err("Failed to save: " + error_string(err))

	_refresh_filesystem()

	var result := {
		"type": "configure_result",
		"path": path,
		"resource_class": res.get_class(),
		"action_taken": "updated" if file_exists else "created",
		"properties_applied": applied,
		"properties_failed": failed,
	}

	if not failed.is_empty():
		return _err_json("Some properties could not be set", result)

	return _ok_json(result)


# ============ Tool 4: configure_project ============

func _tool_configure_project(args: Dictionary) -> Dictionary:
	var settings: Dictionary = args.get("settings", {})
	var autoloads: Dictionary = args.get("autoloads", {})
	var input_actions: Dictionary = args.get("input_actions", {})
	var main_scene: String = args.get("main_scene", "")

	var applied: Array = []
	var errors: Array = []
	var warnings: Array = []

	# Project settings
	for key in settings:
		var val = _parse_property_value(settings[key])
		ProjectSettings.set_setting(key, val)
		applied.append("setting:" + key)

	# Main scene
	if not main_scene.is_empty():
		if FileAccess.file_exists(main_scene):
			ProjectSettings.set_setting("run/main_scene", main_scene)
			applied.append("main_scene:" + main_scene)
		else:
			errors.append("Main scene not found: " + main_scene)

	# Autoloads — add
	var autoload_add: Array = autoloads.get("add", [])
	for entry in autoload_add:
		var aname: String = str(entry.get("name", ""))
		var apath: String = str(entry.get("path", ""))
		if aname.is_empty() or apath.is_empty():
			errors.append("Autoload add: name and path required")
			continue
		if not FileAccess.file_exists(apath):
			errors.append("Autoload script not found: " + apath)
			continue
		ProjectSettings.set_setting("autoload/" + aname, "*" + apath)
		applied.append("autoload_add:" + aname)

	# Autoloads — remove
	var autoload_remove: Array = autoloads.get("remove", [])
	for aname in autoload_remove:
		var key: String = "autoload/" + str(aname)
		if ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, null)
			applied.append("autoload_remove:" + str(aname))
		else:
			errors.append("Autoload not found: " + str(aname))

	# Input actions — add
	var input_add: Array = input_actions.get("add", [])
	for entry in input_add:
		var action_name: String = str(entry.get("name", ""))
		if action_name.is_empty():
			# 兼容模型常用别名 "action"（曾因此连续失败 2 轮后绕过工具手改 project.godot）
			action_name = str(entry.get("action", ""))
		if action_name.is_empty():
			errors.append("Input action add: name required — 例: {\"name\": \"sprint\", \"events\": [{\"type\": \"key\", \"keycode\": \"KEY_SHIFT\"}]}")
			continue
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_set_deadzone(action_name, float(entry.get("deadzone", 0.5)))
		# Add events
		var persist_events: Array = []
		var events: Array = entry.get("events", [])
		var unparsed_events: int = 0
		for ev_def in events:
			# 大小写/风格宽容：type 可能是 "Key"/"key"，也可能用 "class": "InputEventKey"
			#（R13 实测模型给 "type": "Key" 导致按键被静默丢弃，持久化出空 events）
			var ev_type: String = str(ev_def.get("type", ev_def.get("class", ""))).to_lower()
			var ev: InputEvent = null
			if ev_type == "key" or ev_type == "inputeventkey":
				var key_ev := InputEventKey.new()
				var keycode_val: int = 0
				var keycode_str: String = str(ev_def.get("keycode", ""))
				if keycode_str.begins_with("KEY_"):
					keycode_val = OS.find_keycode_from_string(keycode_str)
				elif not keycode_str.is_empty():
					keycode_val = int(keycode_str)
				if keycode_val != 0:
					key_ev.keycode = keycode_val
				elif int(ev_def.get("physical_keycode", 0)) != 0:
					# 兼容物理键位字段（模型偶尔给 key_label/physical_keycode）
					key_ev.physical_keycode = int(ev_def.get("physical_keycode", 0))
				elif int(ev_def.get("key_label", 0)) != 0:
					key_ev.keycode = int(ev_def.get("key_label", 0))
				ev = key_ev
			elif ev_type == "mouse_button" or ev_type == "inputeventmousebutton":
				var mouse_ev := InputEventMouseButton.new()
				mouse_ev.button_index = int(ev_def.get("button_index", 1))
				ev = mouse_ev
			if ev != null:
				InputMap.action_add_event(action_name, ev)
				persist_events.append(ev)
			else:
				unparsed_events += 1
		# 提供了 events 却一个都没解析出来 → 警告而非静默成功
		#（否则模型以为按键已绑定，实际持久化了空 events）
		if not events.is_empty() and persist_events.is_empty():
			warnings.append("input_add:%s — %d 个 events 未能解析（type 需为 \"key\"/\"mouse_button\"），动作已创建但没有绑定按键" % [action_name, unparsed_events])
		# 持久化到 project.godot — InputMap 只活在本进程，仅 ProjectSettings.save() 才会落盘
		#（此前只写 InputMap，动作重启即丢，模型被迫绕过工具直接改 project.godot）
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": float(entry.get("deadzone", 0.5)),
			"events": persist_events,
		})
		applied.append("input_add:" + action_name)

	# Input actions — remove
	var input_remove: Array = input_actions.get("remove", [])
	for action_name in input_remove:
		var name_str: String = str(action_name)
		if InputMap.has_action(name_str):
			InputMap.erase_action(name_str)
			applied.append("input_remove:" + name_str)
		if ProjectSettings.has_setting("input/" + name_str):
			ProjectSettings.set_setting("input/" + name_str, null)

	# Save project settings
	ProjectSettings.save()

	var result := {
		"type": "configure_project_result",
		"applied": applied,
		"errors": errors,
		"warnings": warnings,
	}

	if not errors.is_empty():
		return _err_json("Some operations failed", result)

	return _ok_json(result)
