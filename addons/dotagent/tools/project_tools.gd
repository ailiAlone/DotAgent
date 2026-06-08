@tool
extends "res://addons/dotagent/core/tool_base.gd"
## 项目工具集 - 文件系统、项目设置、配置
##
## 工具:
## - list_files
## - list_scenes
## - list_resources
## - get_project_info
## - get_project_setting
## - set_project_setting
## - read_resource_as_text
## - remember
## - recall
## - export_session
## - write_file
## - read_file_tail
## - read_multiple_files




func get_tool_definitions() -> Array:
	return [
		{
			"name": "list_files",
			"description": "List files under a directory. Returns array of res:// paths.",
			"parameters": {
				"type": "object",
				"properties": {
					"directory": {"type": "string", "description": "Directory to list (default 'res://')", "default": "res://"},
					"pattern": {"type": "string", "description": "Optional filter, e.g. '.tscn' or '.gd'"},
				},
			},
			"method_name": "_tool_list_files",
			"dangerous": false,
		},
		{
			"name": "list_scenes",
			"description": "List all .tscn scene files in the project.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_scenes",
			"dangerous": false,
		},
		{
			"name": "list_resources",
			"description": "List all custom resource files (.tres, .res) in the project.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_resources",
			"dangerous": false,
		},
		{
			"name": "get_project_info",
			"description": "Get project name, version, main scene, autoloads, and other top-level info.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_get_project_info",
			"dangerous": false,
		},
		{
			"name": "get_project_setting",
			"description": "Get a project setting value. Examples: 'application/config/name', 'display/window/size/viewport_width'.",
			"parameters": {
				"type": "object",
				"properties": {
					"key": {"type": "string", "description": "Setting key"},
				},
				"required": ["key"],
			},
			"method_name": "_tool_get_project_setting",
			"dangerous": false,
		},
		{
			"name": "set_project_setting",
			"description": "Set a project setting. value is parsed as JSON. Will be saved when project is saved.",
			"parameters": {
				"type": "object",
				"properties": {
					"key": {"type": "string", "description": "Setting key"},
					"value": {"description": "New value (JSON)"},
				},
				"required": ["key", "value"],
			},
			"method_name": "_tool_set_project_setting",
			"dangerous": true,
		},
		{
			"name": "read_resource_as_text",
			"description": "Read any text-based resource file (.tscn / .tres / .gd / .cs / .json / .cfg / .godot) and return its raw content. Use this to inspect scene structure, project files, or any text file under res://. Default max_chars is conservative (2000) to avoid blowing up LLM context — bump it explicitly if you need more.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "res:// path to the file"},
					"max_chars": {"type": "integer", "description": "Max chars to return (default 2000, was 8000 — kept low to protect LLM context)", "default": 2000},
				},
				"required": ["path"],
			},
			"method_name": "_tool_read_resource_as_text",
			"dangerous": false,
		},
		{
			"name": "remember",
			"description": "Save a fact or convention to project memory (.dotagent_memory.md). Use for things like 'this project uses snake_case' or 'don't modify main_menu.tscn'.",
			"parameters": {
				"type": "object",
				"properties": {
					"fact": {"type": "string", "description": "The fact or convention to remember"},
				},
				"required": ["fact"],
			},
			"method_name": "_tool_remember",
			"dangerous": false,
		},
		{
			"name": "recall",
			"description": "Read project memory (.dotagent_memory.md). Use at the start of a new session to recall conventions and decisions.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_recall",
			"dangerous": false,
		},
		{
			"name": "export_session",
			"description": "Export current conversation as a Markdown file. Saves to res://session_export.md.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_export_session",
			"dangerous": false,
		},
		{
			"name": "write_file",
			"description": "Write a text file (.md, .txt, .json, .cfg, .csv, etc). Creates parent directories if needed.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "res:// path, e.g. 'res://docs/notes.md'"},
					"content": {"type": "string", "description": "File content to write"},
				},
				"required": ["path", "content"],
			},
			"method_name": "_tool_write_file",
			"dangerous": true,
		},
		{
			"name": "read_file_tail",
			"description": "Read the last N characters or lines of a file. Use for reading log tails, conversation endings, or large file ends without loading the whole file.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "res:// path"},
					"max_chars": {"type": "integer", "description": "Max chars from end (default 3000)", "default": 3000},
					"max_lines": {"type": "integer", "description": "Max lines from end (default 0 = disabled)", "default": 0},
				},
				"required": ["path"],
			},
			"method_name": "_tool_read_file_tail",
			"dangerous": false,
		},
		{
			"name": "read_multiple_files",
			"description": "Read multiple files at once. Much faster than calling read_script/read_resource_as_text one by one. Returns JSON {path: content}.",
			"parameters": {
				"type": "object",
				"properties": {
					"paths": {"type": "array", "items": {"type": "string"}, "description": "Array of res:// paths"},
					"max_chars_per_file": {"type": "integer", "description": "Max chars per file (default 2500)", "default": 2500},
				},
				"required": ["paths"],
			},
			"method_name": "_tool_read_multiple_files",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_list_files": return _tool_list_files(args)
		"_tool_list_scenes": return _tool_list_scenes(args)
		"_tool_list_resources": return _tool_list_resources(args)
		"_tool_get_project_info": return _tool_get_project_info(args)
		"_tool_get_project_setting": return _tool_get_project_setting(args)
		"_tool_set_project_setting": return _tool_set_project_setting(args)
		"_tool_read_resource_as_text": return _tool_read_resource_as_text(args)
		"_tool_remember": return _tool_remember(args)
		"_tool_recall": return _tool_recall(args)
		"_tool_export_session": return _tool_export_session(args)
		"_tool_write_file": return _tool_write_file(args)
		"_tool_read_file_tail": return _tool_read_file_tail(args)
		"_tool_read_multiple_files": return _tool_read_multiple_files(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_list_files(args: Dictionary) -> Dictionary:
	var dir: String = args.get("directory", "res://")
	var pattern: String = args.get("pattern", "")
	var paths: Array = []
	_walk_dir(dir, paths, [], pattern)
	return _ok(JSON.stringify(paths, "  "))


func _tool_list_scenes(args: Dictionary) -> Dictionary:
	var paths: Array = []
	_walk_dir("res://", paths, [".tscn"], "")
	return _ok(JSON.stringify(paths, "  "))


func _tool_list_resources(args: Dictionary) -> Dictionary:
	var paths: Array = []
	_walk_dir("res://", paths, [".tres", ".res"], "")
	return _ok(JSON.stringify(paths, "  "))


func _tool_get_project_info(args: Dictionary) -> Dictionary:
	var info := {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"autoloads": [],
	}
	# Autoloads 在 project.godot 的 [autoload] 段
	var project := ConfigFile.new()
	if project.load("res://project.godot") == OK:
		for section in project.get_sections():
			if section == "autoload":
				for k in project.get_section_keys("autoload"):
					info["autoloads"].append({"name": k, "path": project.get_value("autoload", k)})
	return _ok(JSON.stringify(info, "  "))


func _tool_get_project_setting(args: Dictionary) -> Dictionary:
	var key: String = args.get("key", "")
	if key.is_empty():
		return _err("key is required")
	if not ProjectSettings.has_setting(key):
		return _err("Setting does not exist: " + key)
	var value = ProjectSettings.get_setting(key)
	return _ok("%s = %s" % [key, str(value)])


func _tool_set_project_setting(args: Dictionary) -> Dictionary:
	var key: String = args.get("key", "")
	if key.is_empty():
		return _err("key is required")
	if not ProjectSettings.has_setting(key):
		return _err("Setting does not exist: " + key)
	var value = args.get("value")
	ProjectSettings.set_setting(key, value)
	ProjectSettings.save()
	return _ok("Set %s = %s (saved to project.godot)" % [key, str(value)])


func _tool_read_resource_as_text(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot open: " + error_string(FileAccess.get_open_error()))
	var content := f.get_as_text()
	f.close()
	var max_chars: int = int(args.get("max_chars", 2000))
	var truncated := false
	if content.length() > max_chars:
		content = content.substr(0, max_chars) + "\n\n... (truncated, total %d chars)" % content.length()
		truncated = true
	return _ok(content)


# project_tools 辅助方法已移至 ToolBase 基类

const MEMORY_PATH := "res://.dotagent_memory.md"


func _tool_remember(args: Dictionary) -> Dictionary:
	var fact: String = args.get("fact", "")
	if fact.is_empty():
		return _err("fact is required")
	var existing := ""
	if FileAccess.file_exists(MEMORY_PATH):
		var f := FileAccess.open(MEMORY_PATH, FileAccess.READ)
		if f:
			existing = f.get_as_text()
			f.close()
	var f := FileAccess.open(MEMORY_PATH, FileAccess.WRITE)
	if f == null:
		return _err("Cannot write memory file")
	f.store_string(existing + "- " + fact + "\n")
	f.close()
	return _ok("Remembered: " + fact)


func _tool_recall(args: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(MEMORY_PATH):
		return _ok("(no project memory yet — use remember to add facts)")
	var f := FileAccess.open(MEMORY_PATH, FileAccess.READ)
	if f == null:
		return _err("Cannot read memory")
	var content := f.get_as_text()
	f.close()
	return _ok(content)


func _tool_export_session(args: Dictionary) -> Dictionary:
	var logs_dir := "res://addons/dotagent/logs"
	var d := DirAccess.open(logs_dir)
	if d == null:
		return _err("Cannot access logs")
	var latest := ""
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and name > latest:
			latest = name
		name = d.get_next()
	d.list_dir_end()
	if latest == "":
		return _err("No sessions found")
	var src := logs_dir.path_join(latest).path_join("conversation.md")
	if not FileAccess.file_exists(src):
		return _err("No conversation found")
	var f := FileAccess.open(src, FileAccess.READ)
	var content := f.get_as_text()
	f.close()
	var dst := "res://session_export.md"
	var fw := FileAccess.open(dst, FileAccess.WRITE)
	fw.store_string(content)
	fw.close()
	return _ok("Exported to: " + dst)


func _tool_write_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var content: String = args.get("content", "")
	if path.is_empty():
		return _err("path is required")
	# 备份旧内容
	if FileAccess.file_exists(path):
		_get_backup().backup(path)
	# 确保目录存在
	_ensure_dir(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err("Cannot open file for writing: " + path)
	f.store_string(content)
	f.close()
	_refresh_filesystem()
	return _ok("Wrote %d bytes to %s" % [content.length(), path])


func _tool_read_file_tail(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var max_chars: int = int(args.get("max_chars", 3000))
	var max_lines: int = int(args.get("max_lines", 0))
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot open: " + path)
	var full := f.get_as_text()
	f.close()
	if max_lines > 0:
		var all_lines := full.split("\n")
		var start := max(0, all_lines.size() - max_lines)
		var tail_lines: Array = []
		for i in range(start, all_lines.size()):
			tail_lines.append(all_lines[i])
		var result := "\n".join(tail_lines)
		if result.length() > max_chars * 2:
			result = result.substr(result.length() - max_chars * 2)
		return _ok("[last %d lines]\n%s" % [tail_lines.size(), result])
	else:
		if full.length() <= max_chars:
			return _ok(full)
		var tail := full.substr(full.length() - max_chars)
		return _ok("[last %d chars of %d]\n%s" % [tail.length(), full.length(), tail])


func _tool_read_multiple_files(args: Dictionary) -> Dictionary:
	var paths: Array = args.get("paths", [])
	var max_chars_per_file: int = int(args.get("max_chars_per_file", 2500))
	if paths.is_empty():
		return _err("paths is required (array of res:// paths)")
	var results := {}
	var errors := []
	for p in paths:
		var path: String = str(p)
		if not FileAccess.file_exists(path):
			errors.append("Not found: " + path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			errors.append("Cannot read: " + path)
			continue
		var content := f.get_as_text()
		f.close()
		if content.length() > max_chars_per_file:
			content = content.substr(0, max_chars_per_file) + "\n... [truncated, %d more chars]" % (content.length() - max_chars_per_file)
		results[path] = content
	var summary := "Read %d files" % results.size()
	if not errors.is_empty():
		summary += " (%d errors: %s)" % [errors.size(), ", ".join(errors)]
	return _ok(summary + "\n\n" + JSON.stringify(results, "  "))
