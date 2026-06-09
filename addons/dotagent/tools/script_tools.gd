@tool
extends "res://addons/dotagent/core/tool_base.gd"
## 脚本工具 — ##
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
			"name": "search_in_scripts",
			"description": "Search for a string across all scripts. Returns matching paths with line numbers and 2-line context around each match.",
			"parameters": {
				"type": "object",
				"properties": {
					"query": {"type": "string", "description": "String to search for"},
					"directory": {"type": "string", "description": "Optional subdirectory to limit search"},
					"context_lines": {"type": "integer", "description": "Lines of context before/after each match (default 2)", "default": 2},
				},
				"required": ["query"],
			},
			"method_name": "_tool_search_in_scripts",
			"dangerous": false,
		},
		{
			"name": "replace_in_scripts",
			"description": "Search and replace text across all scripts. Dangerous  — modifies files. Always backed up before changes.",
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
			"dangerous": false,
		},
		{
			"name": "replace_in_file",
			"description": "Replace a specific text block in a single file. Only pass the old_text and new_text  — NOT the entire file. Safer than update_script for large files and precise edits. Backs up before writing and validates GDScript syntax (reverts on error).",
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
		{
			"name": "delete_file",
			"description": "Delete a file (.gd, .tscn, .md, etc). Backs up the file before deleting. Use with caution.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "File to delete"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_delete_file",
			"dangerous": true,
		},
		{
			"name": "rename_file",
			"description": "Rename a file. Updates references in other scripts (.gd) that point to the old path. Backs up original before renaming.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Current file path"},
					"new_path": {"type": "string", "description": "New file path"},
				},
				"required": ["path", "new_path"],
			},
			"method_name": "_tool_rename_file",
			"dangerous": false,
		},
		{
			"name": "check_script_syntax",
			"description": "Quickly check if a .gd script has syntax errors. Much lighter than run_scene_capture  — just validates the script file without running anything. Returns 'Syntax OK' or the error description.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Script path, e.g. 'res://player.gd'"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_check_script_syntax",
			"dangerous": false,
		},
		{
			"name": "get_script_references",
			"description": "Find all files that reference a given script or resource. Searches .gd (extends/preload/load), .tscn (ExtResource script mapping), and .tres (script property). Returns file paths and the type of reference found. Much more precise than search_in_scripts for dependency tracing.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Target script/resource path, e.g. 'res://player.gd' or 'res://ui/theme.tres'"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_get_script_references",
			"dangerous": false,
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
		"_tool_replace_in_file": return _tool_replace_in_file(args)
		"_tool_delete_file": return _tool_delete_file(args)
		"_tool_rename_file": return _tool_rename_file(args)
		"_tool_check_script_syntax": return _tool_check_script_syntax(args)
		"_tool_get_script_references": return _tool_get_script_references(args)
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
			return _err("Write reverted  — script has parse error: " + err_msg)

	return _ok("Updated (%s): %s" % [mode, path])


func _tool_list_scripts(args: Dictionary) -> Dictionary:
	var dir: String = args.get("directory", "res://")
	var paths: Array = []
	_walk_dir(dir, paths, [".gd", ".cs"])
	return _ok(JSON.stringify(paths, "  "))


func _tool_search_in_scripts(args: Dictionary) -> Dictionary:
	var query: String = args.get("query", "")
	var dir: String = args.get("directory", "res://")
	var context_lines: int = int(args.get("context_lines", 2))
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
				# 收集上下文行
				var context_arr: Array = []
				var ctx_start := max(0, i - context_lines)
				var ctx_end := min(lines.size() - 1, i + context_lines)
				for j in range(ctx_start, ctx_end + 1):
					var marker := ">>>" if j == i else "   "
					context_arr.append("%s %4d: %s" % [marker, j + 1, lines[j].strip_edges()])
				results.append({
					"path": p,
					"line": i + 1,
					"text": lines[i].strip_edges(),
					"context": "\n".join(context_arr),
				})
	# 去重：同文件同行的匹配只保留一个
	var seen := {}
	var deduped: Array = []
	for r in results:
		var key := "%s:%d" % [r.path, r.line]
		if not seen.has(key):
			seen[key] = true
			deduped.append(r)
	var summary := "Found %d match(es) for '%s'" % [deduped.size(), query]
	if deduped.size() > 0:
		summary += " (showing %d)" % min(deduped.size(), 50)
	return _ok(summary + "\n\n" + JSON.stringify(deduped.slice(0, 50), "  "))


# script_tools 辅助方法已移 — ToolBase 基类


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
		# 校验
		if p.ends_with(".gd"):
			var err_msg := _validate_gdscript(p)
			if not err_msg.is_empty():
				_restore_from_backup(p)
				return _err("Replace reverted in %s  — parse error: %s" % [p, err_msg])
		changed += 1
	return _ok("Replaced '%s'  — '%s' in %d files" % [query, replacement, changed])


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
			return _err("Replace reverted  — script has parse error: " + err_msg)

	return _ok("Replaced in %s (%d  — %d chars)" % [path, old_text.length(), new_text.length()])


## 轻量语法检查工 —  — 暴露已有 — _validate_gdscript 逻辑
func _tool_check_script_syntax(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".gd"):
		return _err("Only .gd scripts are supported")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)
	var err_msg := _validate_gdscript(path)
	if err_msg.is_empty():
		return _ok("Syntax OK: " + path)
	return _err("Syntax error in " + path + ": " + err_msg)



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


func _tool_delete_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)
	# 备份
	_get_backup().backup(path)
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return _err("Failed to delete: " + error_string(err))
	_refresh_filesystem()
	return _ok("Deleted: " + path)


func _tool_rename_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var new_path: String = args.get("new_path", "")
	if path.is_empty() or new_path.is_empty():
		return _err("path and new_path are required")
	if not FileAccess.file_exists(path):
		return _err("Source not found: " + path)
	if FileAccess.file_exists(new_path):
		return _err("Target already exists: " + new_path)
	# 备份原文件
	_get_backup().backup(path)
	# 确保目标目录存在
	_ensure_dir(new_path)
	# 复制内容到新路径
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		return _err("Cannot read: " + path)
	var content := src.get_as_text()
	src.close()
	var dst := FileAccess.open(new_path, FileAccess.WRITE)
	if dst == null:
		return _err("Cannot write: " + new_path)
	dst.store_string(content)
	dst.close()
	# 删除旧文件
	DirAccess.remove_absolute(path)
	# 更新引用：在其他 .gd 文件中将旧路径替换为新路径
	var refs_updated := _update_references(path, new_path)
	_refresh_filesystem()
	var msg := "Renamed: %s  — %s" % [path, new_path]
	if refs_updated > 0:
		msg += " (updated %d references)" % refs_updated
	return _ok(msg)


## 在所有脚本中将旧路径引用替换为新路径
## _update_references 实现在本文件末尾

## 查找所有引用目标脚本或资源的文件
func _tool_get_script_references(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not path.begins_with("res://"):
		path = "res://" + path.lstrip("/")

	var target_file := path.get_file()
	var results: Array = []

	# 1. 搜索 .gd 文件：extends / preload / load 引用
	var gd_paths: Array = []
	_walk_dir("res://", gd_paths, [".gd"])
	for p in gd_paths:
		var content := _read_file_content(p)
		if content.is_empty():
			continue
		var refs := _find_gd_references(content, path, target_file)
		if not refs.is_empty():
			results.append({"file": p, "type": ".gd", "matches": refs})

	# 2. 搜索 .tscn 文件：ExtResource script 引用
	var tscn_paths: Array = []
	_walk_dir("res://", tscn_paths, [".tscn"])
	for p in tscn_paths:
		var content := _read_file_content(p)
		if content.is_empty():
			continue
		var refs := _find_tscn_references(content, path, target_file)
		if not refs.is_empty():
			results.append({"file": p, "type": ".tscn", "matches": refs})

	# 3. 搜索 .tres 文件：script = "res://..." 引用
	var tres_paths: Array = []
	_walk_dir("res://", tres_paths, [".tres"])
	for p in tres_paths:
		var content := _read_file_content(p)
		if content.is_empty():
			continue
		if content.contains(target_file) and content.contains("script"):
			results.append({"file": p, "type": ".tres", "matches": ["script property"]})

	if results.is_empty():
		return _ok("No references found for: " + path)

	var lines: Array = []
	lines.append("%d file(s) reference '%s':" % [results.size(), path])
	for r in results:
		lines.append("  %s  (%s)" % [r["file"], r["type"]])
		for m in r["matches"]:
			lines.append("     — %s" % m)
	return _ok("\n".join(lines))


func _read_file_content(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var c := f.get_as_text()
	f.close()
	return c


func _find_gd_references(content: String, full_path: String, file_name: String) -> Array:
	var refs: Array = []
	for line in content.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue
		if s.contains(full_path):
			if s.contains("extends "):
				refs.append("extends: " + s.trim_prefix("extends "))
			elif s.contains("preload("):
				refs.append("preload: " + s)
			elif s.contains("load("):
				refs.append("load: " + s)
		elif s.contains(file_name) and s.contains("preload("):
			refs.append("preload: " + s)
	return refs


func _find_tscn_references(content: String, full_path: String, file_name: String) -> Array:
	var refs: Array = []
	# 先解 — ExtResource 映射 —  [ext_resource type="Script" path="res://..." id="1_xxx"]
	var ext_map := {}  # id  — path
	for line in content.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("[ext_resource") and s.contains("path=\"") and s.contains("id=\""):
			var ext_path := _extract_quoted(s, "path=")
			var ext_id := _extract_quoted(s, "id=")
			if not ext_path.is_empty() and not ext_id.is_empty():
				ext_map[ext_id] = ext_path
	# 再匹 — script 引用: script = ExtResource("id")
	if ext_map.has(full_path):
		var target_id := ""
		for id in ext_map.keys():
			if ext_map[id] == full_path:
				target_id = id
				break
		if not target_id.is_empty():
			for line in content.split("\n"):
				var s := line.strip_edges()
				if s.contains("ExtResource(\"%s\")" % target_id):
					refs.append("script = ExtResource: " + s)
	else:
		# 直接匹配路径
		for line in content.split("\n"):
			var s := line.strip_edges()
			if s.contains("script") and s.contains(full_path):
				refs.append("script: " + s)
	return refs


func _extract_quoted(line: String, key: String) -> String:
	var idx := line.find(key + "\"")
	if idx < 0:
		return ""
	var start := idx + key.length() + 1
	var end := line.find("\"", start)
	if end < 0:
		return ""
	return line.substr(start, end - start)


func _update_references(old_path: String, new_path: String) -> int:
	var count := 0
	var all_paths: Array = []
	_walk_dir("res://", all_paths, [".gd", ".tscn", ".tres"])
	for p in all_paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var c := f.get_as_text()
		f.close()
		if not c.contains(old_path):
			continue
		var updated := c.replace(old_path, new_path)
		var fw := FileAccess.open(p, FileAccess.WRITE)
		if fw == null:
			continue
		fw.store_string(updated)
		fw.close()
		count += 1
	return count
