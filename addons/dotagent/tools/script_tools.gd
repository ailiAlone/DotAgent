@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## Script Tools
##
## Tools:
## - read_script
## - create_script
## - update_script
## - list_scripts
## - replace_in_file




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
			"dangerous": false,
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
			"name": "replace_in_file",
			"description": "Replace a specific text block in a single file. Only pass the old_text and new_text — NOT the entire file. Safer than update_script for large files and precise edits. Backs up before writing and validates GDScript syntax (reverts on error).",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "File path, e.g. 'res://scripts/player.gd'"},
					"old_text": {"type": "string", "description": "Exact text to replace (must appear exactly once in the file)"},
					"new_text": {"type": "string", "description": "Replacement text"},
				},
				"required": ["path", "old_text", "new_text"],
			},
			"method_name": "_tool_replace_in_file",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_read_script": return _tool_read_script(args)
		"_tool_create_script": return _tool_create_script(args)
		"_tool_update_script": return _tool_update_script(args)
		"_tool_list_scripts": return _tool_list_scripts(args)
		"_tool_replace_in_file": return _tool_replace_in_file(args)
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

	# 校验语法：如果写入了损坏的 .gd，Godot 脚本重载会崩溃
	if path.ends_with(".gd"):
		var err_msg := _validate_gdscript(path)
		if not err_msg.is_empty():
			# 恢复备份
			_restore_from_backup(path)
			return _err("Write reverted — script has parse error: " + err_msg)

	return _ok("Updated (%s): %s" % [mode, path])


func _tool_list_scripts(args: Dictionary) -> Dictionary:
	var dir: String = args.get("directory", "res://")
	var paths: Array = []
	_walk_dir(dir, paths, [".gd", ".cs"])
	return _ok(JSON.stringify(paths, "  "))


## 单文件精确文本块替换。只传 old_text + new_text，不传整个文件
## 适用于大文件（15KB+）的精确修改，避免 JSON 参数超大报错
func _tool_replace_in_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var old_text: String = args.get("old_text", "")
	var new_text: String = args.get("new_text", "")
	if path.is_empty():
		return _err("path is required")
	if old_text.is_empty():
		return _err("old_text is required (use update_script if you want to overwrite the whole file)")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot read: " + path)
	var content := f.get_as_text()
	f.close()

	if not content.contains(old_text):
		return _err("old_text not found in file (check whitespace / indentation / line endings)")

	_backup.backup(path)

	var new_content := content.replace(old_text, new_text)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw == null:
		return _err("Cannot write: " + error_string(FileAccess.get_open_error()))
	fw.store_string(new_content)
	fw.close()

	if path.ends_with(".gd"):
		var err_msg := _validate_gdscript(path)
		if not err_msg.is_empty():
			_restore_from_backup(path)
			return _err("Replace reverted — script has parse error: " + err_msg)

	return _ok("Replaced in %s (%d — %d chars)" % [path, old_text.length(), new_text.length()])


## Validate GDScript syntax. Fast path: GDScript.new() + reload() from temp file.
## On failure, falls back to headless subprocess for line-level error messages.
## Returns "" if OK, otherwise the error description with line numbers.
func _validate_gdscript(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "File not found"

	# Fast path: compile from source directly (bypasses Godot resource cache)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Cannot read file"
	var source := f.get_as_text()
	f.close()

	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()

	if err == OK:
		return ""

	# reload() only returns error codes (e.g. "Parse error") — no line numbers.
	# Fall back to headless subprocess for detailed line-level error output.
	var detail := _subprocess_compile_check(path)
	if not detail.is_empty():
		return detail
	return error_string(err)


## Run Godot --headless --script to compile a script and capture line-level errors.
## Returns empty string on success, or the extracted error lines.
func _subprocess_compile_check(path: String) -> String:
	var godot_exe: String = OS.get_executable_path()
	if godot_exe.is_empty() or not FileAccess.file_exists(godot_exe):
		return ""

	var project_path: String = ProjectSettings.globalize_path("res://")
	var script_abs: String = ProjectSettings.globalize_path(path)

	var output: Array = []
	var exit_code := OS.execute(godot_exe, [
		"--headless", "--path", project_path,
		"--script", script_abs, "--quit-after", "1",
	], output, true, false)

	var full := "\n".join(output)
	var errors := _extract_error_lines(full)

	if errors.is_empty() and exit_code != 0:
		var preview := full.strip_edges()
		if preview.length() > 1200:
			preview = preview.substr(0, 1200) + "\n... (truncated)"
		return "Compilation failed (exit %d). Output:\n%s" % [exit_code, preview]

	if errors.is_empty():
		return ""

	return "\n".join(errors)


## 从备份恢复文件（回退写入）
func _restore_from_backup(path: String) -> void:
	var backups := _backup.list_backups()
	if backups.is_empty():
		return
	var latest: String = backups[backups.size() - 1]
	var rel := path.trim_prefix("res://")
	var backup_file := "res://.dotagent_backups/" + latest + "/" + rel
	if not FileAccess.file_exists(backup_file):
		return
	var src := FileAccess.open(backup_file, FileAccess.READ)
	if src == null:
		return
	var content := src.get_as_text()
	src.close()
	var dst := FileAccess.open(path, FileAccess.WRITE)
	if dst == null:
		return
	dst.store_string(content)
	dst.close()
