@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 文件操作工具集 — 从 project_tools.gd 拆分
##
## 工具:
## - list_files, list_scenes, list_resources
## - read_resource_as_text, read_multiple_files, read_file_tail
## - write_file, peek_scene
## - create_resource, preview_backup, cleanup_backups


func get_tool_definitions() -> Array:
	return [
		{
			"name": "list_files",
			"description": "List files under a directory. Returns array of res:// paths.",
			"parameters": {"type": "object", "properties": {
				"directory": {"type": "string", "description": "Directory to list (default 'res://')", "default": "res://"},
				"pattern": {"type": "string", "description": "Optional filter, e.g. '.tscn' or '.gd'"},
			}},
			"method_name": "_tool_list_files", "dangerous": false,
		},
		{
			"name": "list_scenes",
			"description": "List all .tscn scene files in the project.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_scenes", "dangerous": false,
		},
		{
			"name": "list_resources",
			"description": "List all custom resource files (.tres, .res) in the project.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_resources", "dangerous": false,
		},
		{
			"name": "read_resource_as_text",
			"description": "Read any text-based resource file and return its raw content.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "res:// path to the file"},
				"max_chars": {"type": "integer", "description": "Max chars to return (default 50000)", "default": 50000},
			}, "required": ["path"]},
			"method_name": "_tool_read_resource_as_text", "dangerous": false,
		},
		{
			"name": "read_multiple_files",
			"description": "Read multiple files at once. Returns JSON {path: content}. Use this for batch reading scripts — default limit reads most files in full.",
			"parameters": {"type": "object", "properties": {
				"paths": {"type": "array", "items": {"type": "string"}, "description": "Array of res:// paths"},
				"max_chars_per_file": {"type": "integer", "description": "Max chars per file (default 50000 — reads most files in full)", "default": 50000},
			}, "required": ["paths"]},
			"method_name": "_tool_read_multiple_files", "dangerous": false,
		},
		{
			"name": "read_file_tail",
			"description": "Read the last N characters or lines of a file.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "res:// path"},
				"max_chars": {"type": "integer", "description": "Max chars from end (default 3000)", "default": 3000},
				"max_lines": {"type": "integer", "description": "Max lines from end (default 0 = disabled)", "default": 0},
			}, "required": ["path"]},
			"method_name": "_tool_read_file_tail", "dangerous": false,
		},
		{
			"name": "write_file",
			"description": "Write a text file (.md, .txt, .json, .cfg, .csv, etc). Creates parent directories if needed.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "res:// path"},
				"content": {"type": "string", "description": "File content to write"},
			}, "required": ["path", "content"]},
			"method_name": "_tool_write_file", "dangerous": false,
		},
		{
			"name": "peek_scene",
			"description": "Lightweight scene reader — returns only the node tree structure without property values.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Path to .tscn file"},
				"max_depth": {"type": "integer", "description": "Max tree depth (0=unlimited, default=0)", "default": 0},
			}, "required": ["path"]},
			"method_name": "_tool_peek_scene", "dangerous": false,
		},
		{
			"name": "describe_scene",
			"description": "Convert a .tscn scene file to SCD (Scene Compact Description) format. Outputs a semantic node tree with translated enums, named colors, dereferenced paths, and flattened dimensions. The format adapts to scene type (UI/2D/3D) — UI scenes show layout/theme/interaction properties, 2D scenes show position/z-index/collision, 3D scenes show transform/material/lighting. Used for LLM-efficient scene understanding instead of raw .tscn.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Scene file path, e.g. res://scenes/game.tscn"},
				"max_depth": {"type": "integer", "description": "Max tree depth (0=unlimited, default=0)", "default": 0},
			}, "required": ["path"]},
			"method_name": "_tool_describe_scene", "dangerous": false,
		},
		{
			"name": "create_resource",
			"description": "Create a .tres or .res resource file of any Resource type.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Path, e.g. 'res://ui/red_panel.tres'"},
				"type": {"type": "string", "description": "Resource class name, e.g. 'StyleBoxFlat'"},
				"properties": {"type": "object", "description": "Initial properties as {name: value} dict."},
			}, "required": ["path", "type"]},
			"method_name": "_tool_create_resource", "dangerous": false,
		},
		{
			"name": "preview_backup",
			"description": "Preview recent backups for a file. Shows timestamp + first 400 chars.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Target file path"},
			}, "required": ["path"]},
			"method_name": "_tool_preview_backup", "dangerous": false,
		},
		{
			"name": "cleanup_backups",
			"description": "Delete backup directories exceeding the retention limit (keeps 10 newest).",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_cleanup_backups", "dangerous": true,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_list_files": return _tool_list_files(args)
		"_tool_list_scenes": return _tool_list_scenes(args)
		"_tool_list_resources": return _tool_list_resources(args)
		"_tool_read_resource_as_text": return _tool_read_resource_as_text(args)
		"_tool_read_multiple_files": return _tool_read_multiple_files(args)
		"_tool_read_file_tail": return _tool_read_file_tail(args)
		"_tool_write_file": return _tool_write_file(args)
		"_tool_peek_scene": return _tool_peek_scene(args)
		"_tool_describe_scene": return _tool_describe_scene(args)
		"_tool_create_resource": return _tool_create_resource(args)
		"_tool_preview_backup": return _tool_preview_backup(args)
		"_tool_cleanup_backups": return _tool_cleanup_backups(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 实现（从 project_tools.gd 迁移） ============

func _tool_list_files(args: Dictionary) -> Dictionary:
	var dir: String = args.get("directory", "res://")
	var pattern: String = args.get("pattern", "")
	var paths: Array = []
	_walk_dir(dir, paths, [], pattern)
	return _ok(JSON.stringify(paths, "  "))


func _tool_list_scenes(_args: Dictionary) -> Dictionary:
	var paths: Array = []
	_walk_dir("res://", paths, [".tscn"], "")
	return _ok(JSON.stringify(paths, "  "))


func _tool_list_resources(_args: Dictionary) -> Dictionary:
	var paths: Array = []
	_walk_dir("res://", paths, [".tres", ".res"], "")
	return _ok(JSON.stringify(paths, "  "))


func _tool_read_resource_as_text(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _err("Cannot open: " + error_string(FileAccess.get_open_error()))
	var content := f.get_as_text(); f.close()
	var max_chars: int = int(args.get("max_chars", 2000))
	if content.length() > max_chars:
		content = content.substr(0, max_chars) + "\n... (truncated, total %d chars)" % content.length()
	return _ok(content)


func _tool_read_multiple_files(args: Dictionary) -> Dictionary:
	var paths: Array = args.get("paths", [])
	var max_chars_per_file: int = int(args.get("max_chars_per_file", 2500))
	if paths.is_empty(): return _err("paths is required")
	var results := {}; var errors := []
	for p in paths:
		var path: String = str(p)
		if not FileAccess.file_exists(path): errors.append("Not found: " + path); continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null: errors.append("Cannot read: " + path); continue
		var content := f.get_as_text(); f.close()
		if content.length() > max_chars_per_file:
			content = content.substr(0, max_chars_per_file) + "\n... [truncated]"
		results[path] = content
	var summary := "Read %d files" % results.size()
	if not errors.is_empty(): summary += " (%d errors: %s)" % [errors.size(), ", ".join(errors)]
	return _ok(summary + "\n\n" + JSON.stringify(results, "  "))


func _tool_read_file_tail(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var max_chars: int = int(args.get("max_chars", 3000))
	var max_lines: int = int(args.get("max_lines", 0))
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _err("Cannot open: " + path)
	var full := f.get_as_text(); f.close()
	if max_lines > 0:
		var all_lines := full.split("\n")
		var start := max(0, all_lines.size() - max_lines)
		var tail_lines: Array = []; for i in range(start, all_lines.size()): tail_lines.append(all_lines[i])
		return _ok("[last %d lines]\n%s" % [tail_lines.size(), "\n".join(tail_lines)])
	if full.length() <= max_chars: return _ok(full)
	var tail := full.substr(full.length() - max_chars)
	return _ok("[last %d chars of %d]\n%s" % [tail.length(), full.length(), tail])


func _tool_write_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var content: String = args.get("content", "")
	if path.is_empty(): return _err("path is required")
	if FileAccess.file_exists(path): _get_backup().backup(path)
	_ensure_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return _err("Cannot open file for writing: " + path)
	f.store_string(content); f.close()
	return _ok("Wrote %d bytes to %s" % [content.length(), path])


func _tool_peek_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var max_depth: int = int(args.get("max_depth", 0))
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("File not found: " + path)
	if not path.ends_with(".tscn") and not path.ends_with(".scn"): return _err("Only .tscn/.scn files supported")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _err("Cannot read file")
	var text := f.get_as_text(); f.close()
	var nodes: Array = []
	var re := RegEx.new(); re.compile("\\[node name=\"([^\"]+)\" type=\"([^\"]+)\"(?: parent=\"([^\"]+)\")?")
	for m in re.search_all(text):
		var nname := m.get_string(1); var ntype := m.get_string(2); var nparent := m.get_string(3)
		var depth := 0
		if not nparent.is_empty() and nparent != ".":
			for existing in nodes:
				if existing.get("name") == nparent:
					depth = existing.get("depth", 0) + 1; break
		if max_depth > 0 and depth >= max_depth: continue
		nodes.append({"name": nname, "type": ntype, "parent": nparent, "depth": depth})
	if nodes.is_empty(): return _ok(path.get_file() + " (0 nodes)")
	var lines: Array = [path.get_file() + " (%d nodes):" % nodes.size()]
	for nd in nodes:
		var indent := "  ".repeat(nd.get("depth", 0))
		lines.append(indent + "%s (%s)" % [nd.get("name", "?"), nd.get("type", "?")])
	return _ok("\n".join(lines))


func _tool_create_resource(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", ""); var type: String = args.get("type", "")
	var properties: Dictionary = args.get("properties", {})
	if path.is_empty(): return _err("path is required")
	if type.is_empty(): return _err("type is required")
	if not path.ends_with(".tres") and not path.ends_with(".res"): return _err("path must end with .tres or .res")
	if not ClassDB.class_exists(type): return _err("Unknown class: " + type)
	if not ClassDB.is_parent_class(type, "Resource"): return _err(type + " is not a Resource type")
	if FileAccess.file_exists(path): return _err("File already exists: " + path)
	var res = ClassDB.instantiate(type)
	if res == null: return _err("Failed to instantiate: " + type)
	for key in properties.keys(): res.set(key, _parse_property_value(properties[key]))
	_ensure_dir(path)
	var err := ResourceSaver.save(res, path)
	if err != OK: return _err("Failed to save: " + error_string(err))
	return _ok("Created: " + path + " (" + type + ")")


func _tool_preview_backup(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty(): return _err("path is required")
	if not path.begins_with("res://"): return _err("path must start with res://")
	var rel := path.trim_prefix("res://")
	var bm := _get_backup()
	var backup_dirs := bm.list_backups()
	if backup_dirs.is_empty(): return _ok("(no backups found)")
	var found: Array = []
	for i in range(backup_dirs.size() - 1, -1, -1):
		if found.size() >= 3: break
		var ts: String = backup_dirs[i]
		var backup_file := "res://.dotagent_backups/" + ts + "/" + rel
		if not FileAccess.file_exists(backup_file): continue
		var f := FileAccess.open(backup_file, FileAccess.READ)
		if f == null: continue
		var content := f.get_as_text(); f.close()
		var preview := content
		if preview.length() > 400: preview = preview.substr(0, 400) + "\n... [%d more chars]" % (content.length() - 400)
		found.append({"timestamp": ts, "size": content.length(), "preview": preview})
	if found.is_empty(): return _ok("No backup found for: " + path)
	var lines: Array = ["%d backup(s) for %s:" % [found.size(), path]]
	for item in found:
		lines.append("\n--- Backup @ %s (%d bytes) ---" % [item["timestamp"], item["size"]])
		lines.append(item["preview"])
	return _ok("\n".join(lines))


func _tool_cleanup_backups(_args: Dictionary) -> Dictionary:
	var bm := _get_backup()
	var before := bm.list_backups().size()
	bm._cleanup_old()
	var after := bm.list_backups().size()
	return _ok("Backup cleanup: %d → %d directories" % [before, after])


# ============ SCD: Scene Compact Description ============

func _tool_describe_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var max_depth: int = int(args.get("max_depth", 0))
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("File not found: " + path)
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return _err("Must be a .tscn or .scn file")
	
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _err("Cannot read file")
	var text := f.get_as_text(); f.close()
	
	var scd := _tscn_to_scd(text, path, max_depth)
	if scd.is_empty():
		return _err("Failed to parse scene")
	return _ok(scd)


const _ENUM_MAPS := {
	"layout_mode": {"0": "position", "1": "anchors", "2": "uncontrolled", "3": "container"},
	"anchors_preset": {
		"0": "custom", "1": "top_left", "2": "top_right", "3": "bottom_left", "4": "bottom_right",
		"5": "center_left", "6": "center_top", "7": "center_right", "8": "center_bottom", "9": "center",
		"10": "left_wide", "11": "top_wide", "12": "right_wide", "13": "bottom_wide", "14": "vcenter_left",
		"15": "full_rect"
	},
	"grow_horizontal": {"0": "begin", "1": "end", "2": "both"},
	"grow_vertical": {"0": "begin", "1": "end", "2": "both"},
	"mouse_filter": {"0": "stop", "1": "pass", "2": "ignore"},
	"horizontal_alignment": {"0": "left", "1": "center", "2": "right", "3": "fill"},
	"vertical_alignment": {"0": "top", "1": "center", "2": "bottom", "3": "fill"},
	"focus_mode": {"0": "none", "1": "click", "2": "all"},
	"button_pressed": {"true": "pressed", "false": "released"},
	"disabled": {"true": "disabled", "false": "enabled"},
	"editable": {"true": "editable", "false": "read_only"},
	"visible": {"true": "visible", "false": "hidden"},
	"playing": {"true": "playing", "false": "stopped"},
	"monitoring": {"true": "monitoring", "false": "idle"},
	"monitorable": {"true": "monitorable", "false": "hidden"},
	"one_way_collision": {"true": "one_way", "false": "normal"},
	"pressed": {"true": "pressed", "false": "released"},
	"toggled": {"true": "on", "false": "off"},
	"autostart": {"true": "autostart", "false": ""},
	"unique_name_in_owner": {"true": "unique_name", "false": ""},
	"z_as_relative": {"true": "relative", "false": "absolute"},
}


func _tscn_to_scd(text: String, path: String, max_depth: int) -> String:
	var lines := text.split("\n")
	var ext_resources: Dictionary = _parse_ext_resources(lines)
	var sub_resources: Dictionary = _parse_sub_resources(lines)
	var nodes: Array = _parse_nodes(lines, ext_resources, sub_resources)
	_build_tree(nodes)
	
	var root_type: String = ""
	if not nodes.is_empty():
		root_type = nodes[0].get("type", "")
	var scene_type: String = _detect_scene_type(root_type)
	
	return _generate_scd(nodes, scene_type, max_depth, path)


func _parse_ext_resources(lines: PackedStringArray) -> Dictionary:
	var out := {}
	for line in lines:
		line = line.strip_edges()
		if not line.begins_with("[ext_resource"): continue
		var id_match := _extract_kv(line, "id")
		var path_match := _extract_kv(line, "path")
		if id_match != "" and path_match != "":
			out[id_match] = path_match
	return out


func _parse_sub_resources(lines: PackedStringArray) -> Dictionary:
	var out := {}
	var current_id: String = ""
	var current_type: String = ""
	var current_props: Dictionary = {}
	
	for line in lines:
		line = line.strip_edges()
		if line.begins_with("[sub_resource"):
			current_id = _extract_kv(line, "id")
			current_type = _extract_kv(line, "type")
			current_props = {}
		elif line.begins_with("[resource]"):
			if current_id != "" and current_type != "":
				out[current_id] = {"type": current_type, "properties": current_props}
			current_id = ""
		elif current_id != "" and "=" in line:
			var eq := line.find("=")
			var key := line.substr(0, eq).strip_edges()
			var val := line.substr(eq + 1).strip_edges()
			current_props[key] = val
	
	if current_id != "" and current_type != "":
		out[current_id] = {"type": current_type, "properties": current_props}
	return out


func _parse_nodes(lines: PackedStringArray, ext: Dictionary, sub: Dictionary) -> Array:
	var nodes: Array = []
	var current_node: Dictionary = {}
	var in_node := false
	
	for line in lines:
		var stripped := line.strip_edges()
		
		if stripped.begins_with("[node name="):
			if in_node and not current_node.is_empty():
				nodes.append(current_node)
			current_node = _parse_node_header(stripped)
			current_node["properties"] = {}
			in_node = true
		elif stripped.begins_with("[sub_resource") or stripped.begins_with("[ext_resource") or stripped.begins_with("[gd_scene"):
			if in_node and not current_node.is_empty():
				nodes.append(current_node)
			in_node = false
			current_node = {}
		elif in_node and stripped.contains("="):
			var eq := stripped.find("=")
			var key := stripped.substr(0, eq).strip_edges()
			var val := stripped.substr(eq + 1).strip_edges()
			# Dereference ext_resource
			if val.begins_with("ExtResource("):
				var ext_id := _extract_id_from_ref(val)
				val = ext.get(ext_id, val)
			elif val.begins_with("SubResource("):
				var sub_id := _extract_id_from_ref(val)
				var sub_info = sub.get(sub_id, {})
				if sub_info is Dictionary:
					var sub_type = sub_info.get("type", "")
					var sub_props = sub_info.get("properties", {})
					val = _sub_resource_to_summary(sub_type, sub_props)
			current_node["properties"][key] = val
	
	if in_node and not current_node.is_empty():
		nodes.append(current_node)
	return nodes


func _parse_node_header(line: String) -> Dictionary:
	var out := {}
	out["name"] = _extract_kv(line, "name")
	out["type"] = _extract_kv(line, "type")
	out["parent"] = _extract_kv(line, "parent")
	out["instance"] = _extract_kv(line, "instance")
	out["children"] = []
	out["depth"] = 0
	return out


func _extract_kv(line: String, key: String) -> String:
	var pattern := key + "=\""
	var idx := line.find(pattern)
	if idx < 0:
		# Try instance=ExtResource("...") format without quotes
		var alt_pattern := key + "="
		idx = line.find(alt_pattern)
		if idx < 0: return ""
		var start := idx + alt_pattern.length()
		# Find the end of the value (space before next key or end of bracket)
		var end := line.find(" ", start)
		if end < 0:
			end = line.find("]", start)
			if end < 0: end = line.length()
		return line.substr(start, end - start).strip_edges()
	
	var start := idx + pattern.length()
	var end := line.find("\"", start)
	if end < 0: return ""
	return line.substr(start, end - start)


func _extract_id_from_ref(ref: String) -> String:
	# Extract "1_ga" from ExtResource("1_ga") or SubResource("1")
	var open := ref.find("(")
	var close := ref.find(")")
	if open < 0 or close < 0 or close <= open: return ""
	var inner := ref.substr(open + 1, close - open - 1)
	inner = inner.strip_edges()
	if inner.begins_with("\"") and inner.ends_with("\""):
		return inner.substr(1, inner.length() - 2)
	return inner


func _sub_resource_to_summary(sub_type: String, props: Dictionary) -> String:
	if sub_type == "RectangleShape2D":
		var sz = props.get("size", "")
		if sz != "": return "RectangleShape2D " + sz
		return "RectangleShape2D"
	elif sub_type == "CircleShape2D":
		var r = props.get("radius", "")
		if r != "": return "CircleShape2D radius=" + r
		return "CircleShape2D"
	elif sub_type == "CapsuleShape2D":
		var r = props.get("radius", "")
		var h = props.get("height", "")
		if r != "" and h != "": return "CapsuleShape2D r=" + r + " h=" + h
		return "CapsuleShape2D"
	elif sub_type == "StyleBoxFlat":
		var bg = props.get("bg_color", "")
		if bg != "": return "StyleBoxFlat " + _convert_color(bg)
		return "StyleBoxFlat"
	elif sub_type == "ShaderMaterial":
		var shader = props.get("shader", "")
		if shader != "": return "ShaderMaterial shader=" + shader
		return "ShaderMaterial"
	return sub_type


func _build_tree(nodes: Array) -> void:
	var name_to_index := {}
	for i in range(nodes.size()):
		name_to_index[nodes[i].get("name", "")] = i
	
	for i in range(nodes.size()):
		var parent_name: String = nodes[i].get("parent", "")
		if parent_name.is_empty():
			continue
		# Handle nested paths like "Center/ButtonRow" → "ButtonRow"
		if parent_name.contains("/"):
			parent_name = parent_name.get_file()
		if parent_name == ".":
			# Parent is root
			nodes[0]["children"].append(i)
			nodes[i]["depth"] = 1
		elif name_to_index.has(parent_name):
			var parent_idx := int(name_to_index[parent_name])
			nodes[parent_idx]["children"].append(i)
			nodes[i]["depth"] = nodes[parent_idx].get("depth", 0) + 1


func _detect_scene_type(root_type: String) -> String:
	var ui_types := ["Control", "Panel", "MarginContainer", "VBoxContainer", "HBoxContainer", "GridContainer", "CenterContainer", "ScrollContainer", "TabContainer", "SplitContainer", "AspectRatioContainer", "CanvasLayer", "Button", "Label", "LineEdit", "TextEdit", "RichTextLabel", "CheckBox", "CheckButton", "OptionButton", "MenuButton", "ColorRect", "TextureRect", "NinePatchRect", "ProgressBar", "Slider", "SpinBox", "ColorPicker", "FileDialog", "AcceptDialog", "ConfirmationDialog", "Popup", "PopupPanel", "PopupMenu", "Window", "SubViewportContainer"]
	var two_d_types := ["Node2D", "Area2D", "CharacterBody2D", "RigidBody2D", "StaticBody2D", "AnimatableBody2D", "CollisionObject2D", "PhysicsBody2D", "Sprite2D", "AnimatedSprite2D", "Camera2D", "TileMap", "TileMapLayer", "ParallaxBackground", "ParallaxLayer", "Path2D", "PathFollow2D", "Line2D", "Polygon2D", "MeshInstance2D", "MultiMeshInstance2D", "Marker2D", "VisibleOnScreenNotifier2D", "RayCast2D", "ShapeCast2D", "NavigationAgent2D", "NavigationObstacle2D", "NavigationRegion2D"]
	var three_d_types := ["Node3D", "Area3D", "CharacterBody3D", "RigidBody3D", "StaticBody3D", "AnimatableBody3D", "CollisionObject3D", "PhysicsBody3D", "MeshInstance3D", "MultiMeshInstance3D", "AnimatedSprite3D", "Camera3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D", "WorldEnvironment", "FogVolume", "Decal", "ReflectionProbe", "LightmapGI", "VoxelGI", "NavigationAgent3D", "NavigationObstacle3D", "NavigationRegion3D", "NavigationLink3D", "Path3D", "PathFollow3D", "Marker3D", "VisibleOnScreenNotifier3D", "RayCast3D", "ShapeCast3D", "SpringArm3D", "BoneAttachment3D", "Skeleton3D", "XRNode3D", "XRCamera3D", "XRController3D"]
	
	if root_type in ui_types: return "ui"
	if root_type in two_d_types: return "2d"
	if root_type in three_d_types: return "3d"
	return "2d"  # default


func _generate_scd(nodes: Array, scene_type: String, max_depth: int, path: String) -> String:
	if nodes.is_empty(): return "scene: (empty)"
	
	var root: Dictionary = nodes[0]
	var lines: Array = []
	
	# Scene header
	var header: String = "scene: " + root.get("name", "") + " (" + root.get("type", "") + ")"
	lines.append(header)
	
	# Root properties (filtered by scene type)
	var root_props: Dictionary = root.get("properties", {})
	var root_scd_props := _filter_properties(root_props, scene_type, root.get("type", ""))
	for prop in root_scd_props:
		lines.append("  " + prop)
	
	# Children
	if not root.get("children", []).is_empty():
		lines.append("children:")
		for child_idx in root.get("children", []):
			lines.append_array(_node_to_scd(nodes, child_idx, scene_type, max_depth, 1))
	
	return "\n".join(lines)


func _node_to_scd(nodes: Array, idx: int, scene_type: String, max_depth: int, depth: int) -> Array:
	var lines: Array = []
	var node: Dictionary = nodes[idx]
	var name: String = node.get("name", "")
	var type: String = node.get("type", "")
	var instance: String = node.get("instance", "")
	var props: Dictionary = node.get("properties", {})
	var indent := "  ".repeat(depth)
	var children: Array = node.get("children", [])
	
	# Build node line (always output, even if truncated)
	var is_instance := not instance.is_empty()
	var line := indent
	if is_instance:
		line += name + " [instance: " + instance.get_file() + "]"
	else:
		line += name + " (" + type + ")"
	
	# Position / location
	var pos = props.get("position", "")
	if pos != "":
		line += " @ " + pos
	
	# Markers
	var markers: Array = []
	if props.get("unique_name_in_owner", "") == "true":
		markers.append("unique_name")
	if props.get("autostart", "") == "true":
		markers.append("autostart")
	if props.get("visible", "") == "false":
		markers.append("hidden")
	if props.get("disabled", "") == "true":
		markers.append("disabled")
	
	if not markers.is_empty():
		line += " [" + ", ".join(markers) + "]"
	
	lines.append(line)
	
	# Properties (always output for current node)
	var scd_props := _filter_properties(props, scene_type, type)
	for prop in scd_props:
		lines.append(indent + "  " + prop)
	
	# Children: check truncation
	if not children.is_empty():
		if max_depth > 0 and depth >= max_depth:
			lines.append(indent + "  ... " + str(children.size()) + " 个子节点被截断（max_depth=" + str(max_depth) + "）")
		else:
			var child_indent := "  ".repeat(depth + 1)
			lines.append(child_indent + "children:")
			for child_idx in children:
				lines.append_array(_node_to_scd(nodes, child_idx, scene_type, max_depth, depth + 1))
	
	return lines


func _filter_properties(props: Dictionary, scene_type: String, node_type: String) -> Array:
	var out: Array = []
	
	# UI-specific properties
	if scene_type == "ui":
		# Layout
		for key in ["layout_mode", "anchors_preset", "anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "grow_horizontal", "grow_vertical", "offset_left", "offset_top", "offset_right", "offset_bottom", "custom_minimum_size", "size"]:
			if props.has(key):
				var val = props[key]
				var scd := _convert_ui_property(key, val)
				if not scd.is_empty(): out.append(scd)
		
		# Theme
		for key in props.keys():
			if key.begins_with("theme_override_colors/"):
				var color_key = key.trim_prefix("theme_override_colors/")
				out.append("color_" + color_key + ": " + _convert_color(props[key]))
			elif key.begins_with("theme_override_font_sizes/"):
				var font_key = key.trim_prefix("theme_override_font_sizes/")
				out.append("font_size_" + font_key + ": " + props[key])
			elif key.begins_with("theme_override_constants/"):
				var const_key = key.trim_prefix("theme_override_constants/")
				out.append("const_" + const_key + ": " + props[key])
			elif key.begins_with("theme_override_styles/"):
				var style_key = key.trim_prefix("theme_override_styles/")
				out.append("style_" + style_key + ": " + props[key])
		
		# Text and interaction
		for key in ["text", "placeholder_text", "editable", "caret_blink", "pressed", "toggled", "button_pressed", "mouse_filter", "focus_mode", "disabled", "visible", "separation", "alignment", "expand", "margin_left", "margin_top", "margin_right", "margin_bottom", "texture", "expand_mode", "stretch_mode"]:
			if props.has(key):
				var scd := _convert_ui_property(key, props[key])
				if not scd.is_empty(): out.append(scd)
	
	# 2D-specific properties
	elif scene_type == "2d":
		for key in ["z_index", "z_as_relative", "visible", "modulate", "self_modulate", "texture", "region_rect", "centered", "offset", "flip_h", "flip_v", "hframes", "vframes", "frame", "frame_coords", "playing", "speed_scale", "animation", "collision_layer", "collision_mask", "monitoring", "monitorable", "shape", "gravity", "gravity_scale", "linear_velocity", "angular_velocity", "velocity", "floor_constant_speed", "mass", "physics_material_override", "one_way_collision"]:
			if props.has(key):
				var scd := _convert_2d_property(key, props[key])
				if not scd.is_empty(): out.append(scd)
		
		# Sub-resource shape (for CollisionShape2D)
		if node_type == "CollisionShape2D" and props.has("shape"):
			out.append("shape: " + props["shape"])
		
		# Script
		if props.has("script"):
			out.append("script: " + props["script"].get_file())
	
	# 3D-specific properties
	elif scene_type == "3d":
		for key in ["position", "rotation", "scale", "quaternion", "visible", "mesh", "material", "material_override", "collision_shape", "collision_layer", "collision_mask", "light_color", "light_energy", "light_indirect_energy", "light_volumetric_fog_energy", "shadow_enabled", "shadow_bias", "fov", "near", "far", "projection", "environment", "sky", "gravity", "velocity", "angular_velocity"]:
			if props.has(key):
				var scd := _convert_3d_property(key, props[key])
				if not scd.is_empty(): out.append(scd)
		
		if props.has("script"):
			out.append("script: " + props["script"].get_file())
	
	# Common properties (all types)
	if props.has("script") and not (scene_type == "2d" or scene_type == "3d"):
		var script_path = props["script"]
		if script_path is String and not script_path.is_empty():
			out.append("script: " + script_path.get_file())
	
	return out


func _convert_ui_property(key: String, val: String) -> String:
	match key:
		"layout_mode": return "layout: " + _convert_enum("layout_mode", val)
		"anchors_preset": return "anchors: " + _convert_enum("anchors_preset", val)
		"grow_horizontal": return "grow_h: " + _convert_enum("grow_horizontal", val)
		"grow_vertical": return "grow_v: " + _convert_enum("grow_vertical", val)
		"offset_left", "offset_top", "offset_right", "offset_bottom":
			# These are handled together as a rect
			return ""  # handled by parent-level rect aggregation
		"custom_minimum_size": return "min_size: " + val
		"size": return "size: " + val
		"text": return "text: \"" + val + "\""
		"placeholder_text": return "placeholder: \"" + val + "\""
		"editable": return _convert_enum("editable", val)
		"caret_blink": return "caret_blink" if val == "true" else ""
		"pressed": return "pressed" if val == "true" else ""
		"toggled": return "toggled" if val == "true" else ""
		"button_pressed": return _convert_enum("button_pressed", val)
		"mouse_filter": return "mouse: " + _convert_enum("mouse_filter", val)
		"focus_mode": return "focus: " + _convert_enum("focus_mode", val)
		"disabled": return "disabled" if val == "true" else ""
		"visible": return "" if val == "true" else "hidden"
		"separation": return "separation: " + val
		"alignment": return "align: " + val
		"expand": return "expand" if val == "true" else ""
		"margin_left": return ""
		"margin_top": return ""
		"margin_right": return ""
		"margin_bottom": return ""
		"texture": return "texture: " + val.get_file() if val.begins_with("res://") else "texture: " + val
		"expand_mode": return "expand_mode: " + val
		"stretch_mode": return "stretch: " + val
		_: return key + ": " + val


func _convert_2d_property(key: String, val: String) -> String:
	match key:
		"z_index": return "z: " + val
		"z_as_relative": return "z_relative" if val == "true" else ""
		"visible": return "" if val == "true" else "hidden"
		"modulate": return "modulate: " + _convert_color(val)
		"self_modulate": return "self_modulate: " + _convert_color(val)
		"texture": return "texture: " + val.get_file() if val.begins_with("res://") else "texture: " + val
		"region_rect": return "region: " + val
		"centered": return "centered" if val == "true" else ""
		"offset": return "offset: " + val
		"flip_h": return "flip_h" if val == "true" else ""
		"flip_v": return "flip_v" if val == "true" else ""
		"hframes": return "hframes: " + val
		"vframes": return "vframes: " + val
		"frame": return "frame: " + val
		"frame_coords": return "frame_coords: " + val
		"playing": return "playing" if val == "true" else ""
		"speed_scale": return "speed: " + val
		"animation": return "anim: \"" + val + "\""
		"collision_layer": return "layer: " + val
		"collision_mask": return "mask: " + val
		"monitoring": return "monitoring" if val == "true" else ""
		"monitorable": return "monitorable" if val == "true" else ""
		"shape": return "shape: " + val
		"gravity": return "gravity: " + val
		"gravity_scale": return "gravity_scale: " + val
		"linear_velocity": return "velocity: " + val
		"angular_velocity": return "angular_vel: " + val
		"velocity": return "velocity: " + val
		"floor_constant_speed": return "floor_speed" if val == "true" else ""
		"mass": return "mass: " + val
		"physics_material_override": return "physics_mat: " + val
		"one_way_collision": return "one_way" if val == "true" else ""
		_: return key + ": " + val


func _convert_3d_property(key: String, val: String) -> String:
	match key:
		"position": return "pos: " + val
		"rotation": return "rot: " + val
		"scale": return "scale: " + val
		"quaternion": return "quat: " + val
		"visible": return "" if val == "true" else "hidden"
		"mesh": return "mesh: " + val.get_file() if val.begins_with("res://") else "mesh: " + val
		"material": return "material: " + val.get_file() if val.begins_with("res://") else "material: " + val
		"material_override": return "mat_override: " + val
		"collision_shape": return "collider: " + val
		"collision_layer": return "layer: " + val
		"collision_mask": return "mask: " + val
		"light_color": return "color: " + _convert_color(val)
		"light_energy": return "energy: " + val
		"light_indirect_energy": return "indirect: " + val
		"light_volumetric_fog_energy": return "fog_energy: " + val
		"shadow_enabled": return "shadows" if val == "true" else ""
		"shadow_bias": return "shadow_bias: " + val
		"fov": return "fov: " + val
		"near": return "near: " + val
		"far": return "far: " + val
		"projection": return "projection: " + val
		"environment": return "env: " + val
		"sky": return "sky: " + val
		"gravity": return "gravity: " + val
		"velocity": return "velocity: " + val
		"angular_velocity": return "angular_vel: " + val
		_: return key + ": " + val


func _convert_enum(prop_name: String, value: String) -> String:
	var map = _ENUM_MAPS.get(prop_name, {})
	var result: String = map.get(value, "")
	if not result.is_empty():
		return result
	# Also try string "true"/"false" mappings
	if value == "true" or value == "false":
		var bool_map = _ENUM_MAPS.get(prop_name + "_bool", {})
		result = bool_map.get(value, "")
		if not result.is_empty(): return result
	return value


func _convert_color(rgba_str: String) -> String:
	if not rgba_str.begins_with("Color("): return rgba_str
	var inner = rgba_str.trim_prefix("Color(").trim_suffix(")")
	var parts = inner.split(",")
	if parts.size() < 3: return rgba_str
	
	var r = float(parts[0].strip_edges())
	var g = float(parts[1].strip_edges())
	var b = float(parts[2].strip_edges())
	var a = 1.0
	if parts.size() >= 4:
		a = float(parts[3].strip_edges())
	
	var hex = "#%02x%02x%02x" % [int(r*255), int(g*255), int(b*255)]
	var name = _approximate_color_name(r, g, b)
	if name.is_empty():
		name = hex
	
	if a < 1.0:
		return "%s (a=%.1f)" % [name, a]
	return name


func _approximate_color_name(r: float, g: float, b: float) -> String:
	var epsilon := 0.15
	
	# Named colors (exact or near-exact)
	if _color_match(r, g, b, 1.0, 1.0, 1.0, epsilon): return "white"
	if _color_match(r, g, b, 0.0, 0.0, 0.0, epsilon): return "black"
	if _color_match(r, g, b, 1.0, 0.0, 0.0, epsilon): return "red"
	if _color_match(r, g, b, 0.0, 1.0, 0.0, epsilon): return "green"
	if _color_match(r, g, b, 0.0, 0.0, 1.0, epsilon): return "blue"
	if _color_match(r, g, b, 1.0, 1.0, 0.0, epsilon): return "yellow"
	if _color_match(r, g, b, 0.0, 1.0, 1.0, epsilon): return "cyan"
	if _color_match(r, g, b, 1.0, 0.0, 1.0, epsilon): return "magenta"
	if _color_match(r, g, b, 1.0, 0.5, 0.0, epsilon): return "orange"
	if _color_match(r, g, b, 0.5, 0.0, 0.5, epsilon): return "purple"
	if _color_match(r, g, b, 1.0, 0.75, 0.8, epsilon): return "pink"
	if _color_match(r, g, b, 0.6, 0.3, 0.0, epsilon): return "brown"
	if _color_match(r, g, b, 0.5, 0.5, 0.5, epsilon): return "gray"
	if _color_match(r, g, b, 0.8, 0.8, 0.8, epsilon): return "light_gray"
	if _color_match(r, g, b, 0.2, 0.2, 0.2, epsilon): return "dark_gray"
	
	# Approximate ranges
	if r > 0.8 and g > 0.8 and b < 0.5: return "yellow"
	if r > 0.8 and g > 0.5 and b < 0.3: return "orange"
	if r > 0.8 and g < 0.5 and b < 0.5: return "red"
	if r < 0.5 and g > 0.8 and b > 0.5: return "mint"
	if r < 0.5 and g > 0.8 and b < 0.5: return "green"
	if r < 0.5 and g > 0.5 and b > 0.8: return "sky_blue"
	if r < 0.5 and g < 0.5 and b > 0.8: return "blue"
	if r > 0.5 and g < 0.5 and b > 0.8: return "purple"
	if r > 0.5 and g > 0.5 and b > 0.8: return "light_blue"
	if r > 0.8 and g > 0.5 and b > 0.5: return "pink"
	if r > 0.5 and g > 0.5 and b < 0.5: return "olive"
	if r > 0.8 and g > 0.8 and b > 0.8: return "white"
	if r < 0.3 and g < 0.3 and b < 0.3: return "dark_gray"
	if r > 0.6 and g > 0.6 and b > 0.6: return "light_gray"
	if abs(r - g) < 0.1 and abs(g - b) < 0.1 and r > 0.3 and r < 0.7:
		return "gray"
	
	return ""


func _color_match(r: float, g: float, b: float, tr: float, tg: float, tb: float, eps: float) -> bool:
	return abs(r - tr) <= eps and abs(g - tg) <= eps and abs(b - tb) <= eps

