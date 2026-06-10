@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 脚本文件管理 + 搜索工具 — 从 script_tools.gd 拆分
##
## 工具:
## - delete_file, delete_files, rename_file
## - search_in_scripts, replace_in_scripts
## - check_script_syntax, get_script_references


func get_tool_definitions() -> Array:
	return [
		{
			"name": "delete_file",
			"description": "Delete a file (.gd, .tscn, .md, etc). Backs up the file before deleting.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "File to delete"},
			}, "required": ["path"]},
			"method_name": "_tool_delete_file", "dangerous": true,
		},
		{
			"name": "delete_files",
			"description": "Batch delete multiple files at once. Backs up each file before deleting.",
			"parameters": {"type": "object", "properties": {
				"paths": {"type": "array", "items": {"type": "string"}, "description": "Array of res:// paths to delete"},
			}, "required": ["paths"]},
			"method_name": "_tool_delete_files", "dangerous": true,
		},
		{
			"name": "rename_file",
			"description": "Rename a file. Updates references in other scripts. Backs up original.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Current file path"},
				"new_path": {"type": "string", "description": "New file path"},
			}, "required": ["path", "new_path"]},
			"method_name": "_tool_rename_file", "dangerous": false,
		},
		{
			"name": "search_in_scripts",
			"description": "Search for a string across all scripts. Returns matching paths with line numbers.",
			"parameters": {"type": "object", "properties": {
				"query": {"type": "string", "description": "String to search for"},
				"directory": {"type": "string", "description": "Optional subdirectory to limit search"},
				"context_lines": {"type": "integer", "description": "Lines of context before/after each match (default 2)", "default": 2},
			}, "required": ["query"]},
			"method_name": "_tool_search_in_scripts", "dangerous": false,
		},
		{
			"name": "replace_in_scripts",
			"description": "Search and replace text across all scripts. Always backed up before changes.",
			"parameters": {"type": "object", "properties": {
				"query": {"type": "string", "description": "Text to search for"},
				"replacement": {"type": "string", "description": "Replacement text"},
				"directory": {"type": "string", "description": "Optional subdirectory to limit scope"},
			}, "required": ["query", "replacement"]},
			"method_name": "_tool_replace_in_scripts", "dangerous": false,
		},
		{
			"name": "check_script_syntax",
			"description": "Quickly check if a .gd script has syntax errors. Returns 'Syntax OK' or error description.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Script path, e.g. 'res://player.gd'"},
			}, "required": ["path"]},
			"method_name": "_tool_check_script_syntax", "dangerous": false,
		},
		{
			"name": "get_script_references",
			"description": "Find all files that reference a given script or resource.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Target script/resource path"},
			}, "required": ["path"]},
			"method_name": "_tool_get_script_references", "dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_delete_file": return _tool_delete_file(args)
		"_tool_delete_files": return _tool_delete_files(args)
		"_tool_rename_file": return _tool_rename_file(args)
		"_tool_search_in_scripts": return _tool_search_in_scripts(args)
		"_tool_replace_in_scripts": return _tool_replace_in_scripts(args)
		"_tool_check_script_syntax": return _tool_check_script_syntax(args)
		"_tool_get_script_references": return _tool_get_script_references(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 实现 ============

func _tool_delete_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("File not found: " + path)

	# 场景文件：先在编辑器中关闭再删除
	var extra := ""
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		var closed := _close_scene_if_open(path)
		if closed:
			extra = " (closed in editor first)"

	_get_backup().backup(path)
	var err := DirAccess.remove_absolute(path)
	if err != OK: return _err("Failed to delete: " + error_string(err))
	return _ok("Deleted: " + path + extra)


func _tool_delete_files(args: Dictionary) -> Dictionary:
	var paths: Array = args.get("paths", [])
	if paths.is_empty(): return _err("paths is required (array of res:// paths)")
	var results: Array = []
	for p in paths:
		var path: String = str(p)
		if not FileAccess.file_exists(path):
			results.append("SKIP (not found): " + path); continue

		# 场景文件：先在编辑器中关闭再删除
		var extra := ""
		if path.ends_with(".tscn") or path.ends_with(".scn"):
			if _close_scene_if_open(path):
				extra = " (closed in editor first)"

		_get_backup().backup(path)
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			results.append("FAIL: " + path + " (" + error_string(err) + ")")
		else:
			results.append("OK: " + path + extra)
	return _ok("\n".join(results))


## 如果场景在编辑器中打开，保存并关闭它。返回 true 表示执行了关闭
func _close_scene_if_open(path: String) -> bool:
	var ei = _ei()
	if ei == null:
		return false
	var open_scenes: Array = ei.get_open_scenes()
	var normalized := path.trim_prefix("res://")

	var target_tab := -1
	for i in range(open_scenes.size()):
		if str(open_scenes[i]).trim_prefix("res://") == normalized:
			target_tab = i
			break

	if target_tab < 0:
		return false  # 未打开，无需处理

	# 找到场景标签栏
	var base: Control = ei.get_base_control()
	var tab_bar: TabBar = _find_scene_tab_bar(base)
	if tab_bar == null:
		return false

	# 切到该标签，保存，然后触发标准关闭
	tab_bar.set_current_tab(target_tab)
	ei.save_scene()
	tab_bar.emit_signal("tab_close_pressed", target_tab)
	return true


func _find_scene_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		return node
	for child in node.get_children():
		var found: TabBar = _find_scene_tab_bar(child)
		if found:
			return found
	return null


func _tool_rename_file(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var new_path: String = args.get("new_path", "")
	if path.is_empty() or new_path.is_empty(): return _err("path and new_path are required")
	if not FileAccess.file_exists(path): return _err("Source not found: " + path)
	if FileAccess.file_exists(new_path): return _err("Target already exists: " + new_path)
	_get_backup().backup(path)
	_ensure_dir(new_path)
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null: return _err("Cannot read: " + path)
	var content := src.get_as_text(); src.close()
	var dst := FileAccess.open(new_path, FileAccess.WRITE)
	if dst == null: return _err("Cannot write: " + new_path)
	dst.store_string(content); dst.close()
	DirAccess.remove_absolute(path)
	return _ok("Renamed: %s → %s" % [path, new_path])


func _tool_search_in_scripts(args: Dictionary) -> Dictionary:
	var query: String = args.get("query", "")
	if query.is_empty(): return _err("query is required")
	var directory: String = args.get("directory", "")
	var context_lines: int = int(args.get("context_lines", 2))
	var all_scripts: Array = []
	_walk_dir("res://", all_scripts, [".gd"], "")
	var matches: Array = []
	for path in all_scripts:
		var spath: String = str(path)
		if not directory.is_empty() and not spath.begins_with(directory): continue
		var f := FileAccess.open(spath, FileAccess.READ)
		if f == null: continue
		var lines := f.get_as_text().split("\n"); f.close()
		for i in range(lines.size()):
			if query.to_lower() in lines[i].to_lower():
				var ctx: Array = []
				for j in range(max(0, i - context_lines), min(lines.size(), i + context_lines + 1)):
					var marker := ">>> " if j == i else "    "
					ctx.append("%s%4d: %s" % [marker, j + 1, lines[j]])
				matches.append({"path": spath, "line": i + 1, "text": lines[i], "context": "\n".join(ctx)})
	if matches.is_empty(): return _ok("No matches found for: " + query)
	var out: Array = ["Found %d match(es) for '%s'" % [matches.size(), query]]
	for m in matches: out.append("\n" + m["context"])
	return _ok("\n".join(out))


func _tool_replace_in_scripts(args: Dictionary) -> Dictionary:
	var query: String = args.get("query", "")
	var replacement: String = args.get("replacement", "")
	if query.is_empty(): return _err("query is required")
	var directory: String = args.get("directory", "")
	var all_scripts: Array = []
	_walk_dir("res://", all_scripts, [".gd"], "")
	var changed: Array = []
	for path in all_scripts:
		var spath: String = str(path)
		if not directory.is_empty() and not spath.begins_with(directory): continue
		var f := FileAccess.open(spath, FileAccess.READ)
		if f == null: continue
		var content := f.get_as_text(); f.close()
		if query in content:
			_get_backup().backup(spath)
			var new_content := content.replace(query, replacement)
			var fw := FileAccess.open(spath, FileAccess.WRITE)
			if fw == null: continue
			fw.store_string(new_content); fw.close()
			changed.append(spath)
	if changed.is_empty(): return _ok("No matches found for: " + query)
	return _ok("Replaced '%s' → '%s' in %d file(s):\n%s" % [query, replacement, changed.size(), "\n".join(changed)])


func _tool_check_script_syntax(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("File not found: " + path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _err("Cannot read: " + path)
	var source := f.get_as_text(); f.close()
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	if err == OK: return _ok("Syntax OK")
	return _ok("Syntax error in %s: %s" % [path, error_string(err)])


func _tool_get_script_references(args: Dictionary) -> Dictionary:
	var target: String = args.get("path", "")
	if target.is_empty(): return _err("path is required")
	var refs: Array = []
	var all_scripts: Array = []
	_walk_dir("res://", all_scripts, [".gd"], "")
	for path in all_scripts:
		var spath: String = str(path)
		var f := FileAccess.open(spath, FileAccess.READ)
		if f == null: continue
		var content := f.get_as_text(); f.close()
		if target in content:
			refs.append({"file": spath, "type": "gd_reference"})
	var all_scenes: Array = []
	_walk_dir("res://", all_scenes, [".tscn"], "")
	for path in all_scenes:
		var spath: String = str(path)
		var f := FileAccess.open(spath, FileAccess.READ)
		if f == null: continue
		var content := f.get_as_text(); f.close()
		if target in content:
			refs.append({"file": spath, "type": "tscn_reference"})
	if refs.is_empty(): return _ok("No references found for: " + target)
	var out: Array = ["Found %d reference(s) to %s:" % [refs.size(), target]]
	for r in refs: out.append("  [%s] %s" % [r["type"], r["file"]])
	return _ok("\n".join(out))
