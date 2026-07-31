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
		return _fuzzy_replace(path, content, old_text, new_text)

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


## old_text 精确匹配失败时的自愈路径。
## 实测 LLM 高频失败原因是缩进写错（空格/制表符/层级），文件内容其实是对的。
## 策略：按行去空白归一化后滑动窗口匹配 ——
##   唯一命中 → 以文件实际缩进为基准重写 new_text 并应用（省一整轮重试）
##   多义/未命中 → 返回最相似区域的真实文本（含行号），下轮替换即可精确命中（省一次 read）
func _fuzzy_replace(path: String, content: String, old_text: String, new_text: String) -> Dictionary:
	var file_lines: Array = Array(content.split("\n"))
	var old_lines := old_text.strip_edges().split("\n")
	var norm_old: Array = []
	for l in old_lines:
		norm_old.append(l.strip_edges())
	var n := norm_old.size()
	if n == 0:
		return _err("old_text not found in file (check whitespace / indentation / line endings)")

	# 滑动窗口：归一化后逐行全等的连续区间（空行不参与比较）
	var matches: Array = []
	for i in range(maxi(file_lines.size() - n + 1, 0)):
		var same := true
		for j in range(n):
			if norm_old[j].is_empty():
				continue
			if file_lines[i + j].strip_edges() != norm_old[j]:
				same = false
				break
		if same:
			matches.append(i)

	if matches.size() == 1:
		var start: int = matches[0]
		# 目标区域基准缩进 = 首个非空行的前导空白
		var base_indent := ""
		for j in range(n):
			if not file_lines[start + j].strip_edges().is_empty():
				base_indent = _leading_ws(file_lines[start + j])
				break
		# 缩进单位探测：文件区域 vs new_text 各自的单级缩进（如 "\t" vs "    "），
		# 按"层级"重建 new_text — 模型用错缩进风格时自动转换成文件风格
		var region_lines: Array = file_lines.slice(start, start + n)
		var file_unit: String = _indent_unit(region_lines, base_indent)
		var new_lines := new_text.strip_edges().split("\n")
		var new_origin := ""
		for l in new_lines:
			if not l.strip_edges().is_empty():
				new_origin = _leading_ws(l)
				break
		var new_unit: String = _indent_unit(Array(new_lines), new_origin)
		var rebuilt: Array = []
		for l in new_lines:
			var stripped: String = l.strip_edges()
			if stripped.is_empty():
				rebuilt.append("")
				continue
			var ws: String = _leading_ws(l)
			var indent := ws
			if not file_unit.is_empty() and not new_unit.is_empty():
				# 把 new_text 的层级（以其自身单位计）翻译成文件的单位
				var level := 0
				var rest := ws
				while rest.begins_with(new_unit):
					level += 1
					rest = rest.substr(new_unit.length())
				indent = file_unit.repeat(level) + rest  # rest 通常是空；混合缩进时保留残余
			elif ws.begins_with(new_origin):
				indent = ws.substr(new_origin.length())
			rebuilt.append(base_indent + indent + stripped)
		var final_lines: Array = []
		final_lines.append_array(file_lines.slice(0, start))
		final_lines.append_array(rebuilt)
		final_lines.append_array(file_lines.slice(start + n))

		_backup.backup(path)
		var fw := FileAccess.open(path, FileAccess.WRITE)
		if fw == null:
			return _err("Cannot write: " + error_string(FileAccess.get_open_error()))
		fw.store_string("\n".join(final_lines))
		fw.close()
		if path.ends_with(".gd"):
			var err_msg := _validate_gdscript(path)
			if not err_msg.is_empty():
				_restore_from_backup(path)
				return _err("Fuzzy replace reverted — script has parse error: " + err_msg)
		return _ok("Replaced in %s via fuzzy match (%d lines, indentation auto-corrected to file's actual style). No retry needed." % [path, n])

	# 未命中或多义：找相似度最高的窗口，把真实文本喂回去
	var best_start := 0
	var best_score := -1
	for i in range(maxi(file_lines.size() - n + 1, 1)):
		var score := 0
		for j in range(n):
			if norm_old[j].is_empty():
				continue
			if i + j < file_lines.size() and file_lines[i + j].strip_edges() == norm_old[j]:
				score += 1
		if score > best_score:
			best_score = score
			best_start = i
	var lo := maxi(best_start - 2, 0)
	var hi := mini(best_start + n + 2, file_lines.size())
	var snippet: Array = []
	for i in range(lo, hi):
		snippet.append("%4d: %s" % [i + 1, file_lines[i]])
	var hint := "old_text not found verbatim. Closest region (%d/%d lines match after whitespace normalization). ACTUAL FILE CONTENT:\n%s\nRetry with old_text copied EXACTLY from above (tabs included)." % [best_score, n, "\n".join(snippet)]
	if matches.size() > 1:
		hint = "old_text matches %d regions after whitespace normalization — ambiguous, add more context lines to disambiguate. " % matches.size() + hint
	return _err(hint)


## 提取行前导空白（空格/制表符）
func _leading_ws(s: String) -> String:
	var i := 0
	while i < s.length() and (s[i] == " " or s[i] == "\t"):
		i += 1
	return s.substr(0, i)


## 探测一组行的单级缩进单位：首条比 base 更深的行的前导空白差值
func _indent_unit(lines: Array, base: String) -> String:
	for l in lines:
		var s := str(l)
		if s.strip_edges().is_empty():
			continue
		var ws: String = _leading_ws(s)
		if ws.length() > base.length() and ws.begins_with(base):
			return ws.substr(base.length())
	return ""


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

	# reload() only returns error codes (e.g. "Parse error") — no line numbers,
	# 且编辑器内 dummy reload 可能受全局 class_name 注册状态干扰产生误报。
	# 用子进程 --check-only 对磁盘文件做权威解析（只解析不执行，不要求 SceneTree 继承）。
	var detail := _subprocess_compile_check(path)
	if not detail.is_empty():
		return detail
	if detail != "__UNAVAILABLE__":
		# 子进程解析通过 — 信任干净进程的结果，忽略编辑器态误报
		return ""
	return error_string(err)


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
