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
				"max_chars": {"type": "integer", "description": "Max chars to return (default 2000)", "default": 2000},
			}, "required": ["path"]},
			"method_name": "_tool_read_resource_as_text", "dangerous": false,
		},
		{
			"name": "read_multiple_files",
			"description": "Read multiple files at once. Returns JSON {path: content}.",
			"parameters": {"type": "object", "properties": {
				"paths": {"type": "array", "items": {"type": "string"}, "description": "Array of res:// paths"},
				"max_chars_per_file": {"type": "integer", "description": "Max chars per file (default 2500)", "default": 2500},
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
