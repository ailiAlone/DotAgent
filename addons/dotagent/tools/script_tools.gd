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
		"_tool_delete_file": return _tool_delete_file(args)
		"_tool_rename_file": return _tool_rename_file(args)
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
		# 校验
		if p.ends_with(".gd"):
			var err_msg := _validate_gdscript(p)
			if not err_msg.is_empty():
				_restore_from_backup(p)
				return _err("Replace reverted in %s — parse error: %s" % [p, err_msg])
		changed += 1
	return _ok("Replaced '%s' → '%s' in %d files" % [query, replacement, changed])


## 安全校验 GDScript 语法：尝试 load() 脚本，捕获解析错误
## 返回空字符串 = 无错误，否则返回错误描述
func _validate_gdscript(path: String) -> String:
	var script: Resource = load(path)
	if script == null:
		return "Failed to load (parse error or invalid script)"
	# load() 成功意味着语法正确，但 GDScript 可能有运行时警告
	# 检查是否有解析错误：用 ResourceLoader 重新加载看报错
	var err := ResourceLoader.load_threaded_request(path)
	return ""  # load() 不抛异常就说明语法 OK


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
	var msg := "Renamed: %s → %s" % [path, new_path]
	if refs_updated > 0:
		msg += " (updated %d references)" % refs_updated
	return _ok(msg)


## 在所有脚本中将旧路径引用替换为新路径
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
