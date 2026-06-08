@tool
extends "res://addons/dotagent/core/tool_base.gd"
## 脚本工具集
##
## 工具:
## - read_script
## - create_script
## - update_script (危险 - 覆盖)
## - list_scripts
## - search_in_scripts
## - replace_in_scripts




func get_tool_definitions() -> Array:
	return [
		{
			"name": "read_script",
			"description": "Read the full content of a .gd or .cs script file at the given res:// path.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Script path, e.g. 'res://scripts/player.gd'"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_read_script",
			"dangerous": false,
		},
		{
			"name": "create_script",
			"description": "Create a new script file with the given content. Fails if file already exists (use update_script for that).",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path for the new script, e.g. 'res://scripts/health_bar.gd'"},
					"content": {"type": "string", "description": "Full file content"},
				},
				"required": ["path", "content"],
			},
			"method_name": "_tool_create_script",
			"dangerous": false,
		},
		{
			"name": "update_script",
			"description": "Update an existing script. mode: 'overwrite' (replace all) or 'append' (add to end). Will create backup before overwriting.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Script path"},
					"content": {"type": "string", "description": "New content (or content to append)"},
					"mode": {"type": "string", "description": "'overwrite' or 'append'", "default": "overwrite"},
				},
				"required": ["path", "content"],
			},
			"method_name": "_tool_update_script",
			"dangerous": true,
		},
		{
			"name": "list_scripts",
			"description": "List all .gd scripts in the project (or under a subdirectory). Returns array of res:// paths.",
			"parameters": {
				"type": "object",
				"properties": {
					"directory": {"type": "string", "description": "Optional subdirectory, e.g. 'res://scripts'. Default: whole project"},
				},
			},
			"method_name": "_tool_list_scripts",
			"dangerous": false,
		},
		{
			"name": "search_in_scripts",
			"description": "Search for a string (function name, variable, etc) across all scripts. Returns matching paths with line numbers.",
			"parameters": {
				"type": "object",
				"properties": {
					"query": {"type": "string", "description": "String to search for"},
					"directory": {"type": "string", "description": "Optional subdirectory to limit search"},
				},
				"required": ["query"],
			},
			"method_name": "_tool_search_in_scripts",
			"dangerous": false,
		},
		{
			"name": "replace_in_scripts",
			"description": "Search and replace text across all scripts. Dangerous — modifies files. Always backed up before changes.",
			"parameters": {
				"type": "object",
				"properties": {
					"query": {"type": "string", "description": "Text to search for"},
					"replacement": {"type": "string", "description": "Replacement text"},
					"directory": {"type": "string", "description": "Optional subdirectory to limit scope"},
				},
				"required": ["query", "replacement"],
			},
			"method_name": "_tool_replace_in_scripts",
			"dangerous": true,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_read_script": return _tool_read_script(args)
		"_tool_create_script": return _tool_create_script(args)
		"_tool_update_script": return _tool_update_script(args)
		"_tool_list_scripts": return _tool_list_scripts(args)
		"_tool_search_in_scripts": return _tool_search_in_scripts(args)
		"_tool_replace_in_scripts": return _tool_replace_in_scripts(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_read_script(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot open: " + path + " (" + error_string(FileAccess.get_open_error()) + ")")
	var content := f.get_as_text()
	f.close()
	return _ok(content)


func _tool_create_script(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var content: String = args.get("content", "")
	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".gd") and not path.ends_with(".cs"):
		return _err("Script must end with .gd or .cs")
	if FileAccess.file_exists(path):
		return _err("File already exists. Use update_script to modify.")

	# 确保目录存在
	_ensure_dir(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err("Cannot create: " + error_string(FileAccess.get_open_error()))
	f.store_string(content)
	f.close()

	# 不调 _refresh_filesystem() — 新建 .gd 文件会触发 Godot 全局脚本重载，
	# 重载会杀掉所有挂起的协程（包括 _run_react_loop），导致 session 被截断。
	# 文件已落盘，编辑器稍后会自然发现。
	return _ok("Created: " + path + " (" + str(content.length()) + " bytes)")


func _tool_update_script(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var content: String = args.get("content", "")
	var mode: String = args.get("mode", "overwrite")
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("File not found. Use create_script for new files.")
	if mode != "overwrite" and mode != "append":
		return _err("mode must be 'overwrite' or 'append'")

	# 备份
	_backup.backup(path)

	var new_content: String
	if mode == "append":
		var f := FileAccess.open(path, FileAccess.READ)
		var old := f.get_as_text() if f else ""
		if f:
			f.close()
		new_content = old + "\n" + content
	else:
		new_content = content

	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw == null:
		return _err("Cannot write: " + error_string(FileAccess.get_open_error()))
	fw.store_string(new_content)
	fw.close()

	_refresh_filesystem()
	return _ok("Updated (%s): %s" % [mode, path])


func _tool_list_scripts(args: Dictionary) -> Dictionary:
	var dir: String = args.get("directory", "res://")
	var paths: Array = []
	_walk_dir(dir, paths, [".gd", ".cs"])
	return _ok(JSON.stringify(paths, "  "))


func _tool_search_in_scripts(args: Dictionary) -> Dictionary:
	var query: String = args.get("query", "")
	var dir: String = args.get("directory", "res://")
	if query.is_empty():
		return _err("query is required")
	var paths: Array = []
	_walk_dir(dir, paths, [".gd", ".cs"])
	var results := []
	for p in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		var lines := content.split("\n")
		for i in lines.size():
			if lines[i].contains(query):
				results.append({
					"path": p,
					"line": i + 1,
					"text": lines[i].strip_edges(),
				})
	return _ok(JSON.stringify(results, "  "))


# script_tools 辅助方法已移至 ToolBase 基类


func _tool_replace_in_scripts(args: Dictionary) -> Dictionary:
	var query: String = args.get("query", "")
	var replacement: String = args.get("replacement", "")
	var dir: String = args.get("directory", "res://")
	if query.is_empty():
		return _err("query is required")
	var paths: Array = []
	_walk_dir(dir, paths, [".gd", ".cs"])
	var changed := 0
	for p in paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		if not content.contains(query):
			continue
		_backup.backup(p)
		var new_content := content.replace(query, replacement)
		var fw := FileAccess.open(p, FileAccess.WRITE)
		if fw == null:
			continue
		fw.store_string(new_content)
		fw.close()
		changed += 1
	_refresh_filesystem()
	return _ok("Replaced '%s' → '%s' in %d files" % [query, replacement, changed])
