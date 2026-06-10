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
			"dangerous": false,
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
			"dangerous": false,
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
		{
			"name": "preview_backup",
			"description": "Preview recent backups for a file. Shows timestamp + first 400 chars of each backup. Use before undo_last to see what you're restoring. Returns up to 3 most recent backups.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Target file path, e.g. 'res://main_menu.tscn' or 'res://player.gd'"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_preview_backup",
			"dangerous": false,
		},
		{
			"name": "create_resource",
			"description": "Create a .tres or .res resource file of any Resource type (StyleBoxFlat, PlaceholderTexture2D, ShaderMaterial, Theme, Curve, etc). Set initial properties via the properties dict. Use for UI themes, placeholder textures, materials — anything that needs a .tres file.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path, e.g. 'res://ui/red_panel.tres'"},
					"type": {"type": "string", "description": "Resource class name, e.g. 'StyleBoxFlat', 'PlaceholderTexture2D', 'ShaderMaterial'"},
					"properties": {"type": "object", "description": "Initial properties as {name: value} dict. Values are parsed as JSON."},
				},
				"required": ["path", "type"],
			},
			"method_name": "_tool_create_resource",
			"dangerous": false,
		},
		{
			"name": "get_input_actions",
			"description": "List all input actions defined in the project's Input Map (project.godot). Returns action names and their bound events (key, mouse button, joypad).",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_get_input_actions",
			"dangerous": false,
		},
		{
			"name": "add_input_action",
			"description": "Add a new input action to the project Input Map. Events are simple objects: {\"type\": \"key\", \"code\": \"KEY_SPACE\"} or {\"type\": \"mouse\", \"button\": 1}. Persists to project.godot.",
			"parameters": {
				"type": "object",
				"properties": {
					"name": {"type": "string", "description": "Action name, e.g. 'jump', 'shoot'"},
					"events": {"type": "array", "description": "Event objects, e.g. [{\"type\":\"key\", \"code\":\"KEY_SPACE\"}]"},
				},
				"required": ["name"],
			},
			"method_name": "_tool_add_input_action",
			"dangerous": false,
		},
		{
			"name": "cleanup_backups",
			"description": "Delete backup directories exceeding the retention limit (keeps 10 newest). Use to silence 'Failed parse script' noise from the GDScript Language Server scanning old broken backups.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_cleanup_backups",
			"dangerous": true,
		},
		{
			"name": "list_skills",
			"description": "List all available scene-type skills (2D game, UI, 3D game) with their trigger keywords. Skills are auto-matched based on your message, but you can call this to see what's available or if you need a specific skill not auto-matched.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_skills",
			"dangerous": false,
		},
		{
			"name": "create_skill",
			"description": "Create a new skill file in res://addons/dotagent/skills/custom/. Skills auto-load next session and are matched by trigger keywords against user messages.\n\nParameters:\n- name: kebab-case filename without .md, e.g. 'tilemap-platformer'\n- triggers: lowercase keywords, 5-15 recommended, e.g. ['tilemap', 'platformer', 'level']\n- content: markdown body. Recommended sections: Root & Structure, Key Nodes table, Mandatory Checklist, Common Mistakes (see existing skills in builtin/ for examples)\n\nAfter creating, call list_skills to verify. Overlapping triggers are OK — all matching skills get injected, they don't override each other.",
			"parameters": {
				"type": "object",
				"properties": {
					"name": {"type": "string", "description": "Skill filename (without .md), kebab-case, e.g. 'tilemap-platformer'"},
					"triggers": {"type": "array", "items": {"type": "string"}, "description": "Trigger keywords (lowercase), e.g. ['tilemap', 'tileset', 'platformer', 'level']"},
					"content": {"type": "string", "description": "Markdown body — sections: Root & Structure, Key Nodes, Mandatory Checklist, Common Mistakes"},
				},
				"required": ["name", "triggers", "content"],
			},
			"method_name": "_tool_create_skill",
			"dangerous": false,
		},
		{
			"name": "peek_scene",
			"description": "Lightweight scene reader — returns only the node tree structure (names, types, parents, scripts) WITHOUT property values. Much smaller than read_resource_as_text of a .tscn (~500 chars vs 10,000+). Use this instead of read_resource_as_text to understand scene structure.\n\nParameters:\n- path: res:// path to .tscn file\n- max_depth: 0=full tree, 1=root only, 2=root+direct children, etc. (default 0)",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path to .tscn file"},
					"max_depth": {"type": "integer", "description": "Max tree depth (0=unlimited, default=0)", "default": 0},
				},
				"required": ["path"],
			},
			"method_name": "_tool_peek_scene",
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
		"_tool_preview_backup": return _tool_preview_backup(args)
		"_tool_create_resource": return _tool_create_resource(args)
		"_tool_get_input_actions": return _tool_get_input_actions(args)
		"_tool_add_input_action": return _tool_add_input_action(args)
		"_tool_cleanup_backups": return _tool_cleanup_backups(args)
		"_tool_list_skills": return _tool_list_skills(args)
		"_tool_create_skill": return _tool_create_skill(args)
		"_tool_peek_scene": return _tool_peek_scene(args)
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
	var value = _parse_setting_value(args.get("value"))
	ProjectSettings.set_setting(key, value)
	ProjectSettings.save()
	return _ok("Set %s = %s (saved to project.godot)" % [key, str(value)])


## 将 AI 传入的字符串值解析为正确的 Variant 类型。
## AI 在 JSON 中只能传字符串，但 ProjectSettings 需要正确类型（Color、int、float 等）。
func _parse_setting_value(raw):
	if typeof(raw) != TYPE_STRING:
		return raw
	var s: String = str(raw).strip_edges()
	# Color: "Color(0.02, 0.02, 0.06, 1)" → Color object
	if s.begins_with("Color(") and s.ends_with(")"):
		var inner := s.substr(6, s.length() - 7).strip_edges()
		var parts := inner.split(",", false)
		if parts.size() >= 3:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() >= 4 else 1.0)
	# Vector2: "(640, 360)"
	if s.begins_with("(") and s.ends_with(")"):
		var inner := s.substr(1, s.length() - 2).strip_edges()
		var parts := inner.split(",", false)
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
		if parts.size() == 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	# float
	if s.is_valid_float():
		return s.to_float()
	# int
	if s.is_valid_int():
		return s.to_int()
	# bool
	if s == "true":
		return true
	if s == "false":
		return false
	return s


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
	# 不调 _refresh_filesystem() — 新建文件会触发 Godot 全局脚本重载，
	# 重载会杀掉所有挂起的协程（包括 _run_react_loop），导致 session 被截断。
	# 文件已落盘，编辑器稍后会自然发现。
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


## 创建 .tres / .res 资源文件
func _tool_create_resource(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var type: String = args.get("type", "")
	var properties: Dictionary = args.get("properties", {})

	if path.is_empty():
		return _err("path is required")
	if type.is_empty():
		return _err("type is required (e.g. 'StyleBoxFlat', 'PlaceholderTexture2D')")
	if not path.ends_with(".tres") and not path.ends_with(".res"):
		return _err("path must end with .tres or .res")
	if not ClassDB.class_exists(type):
		return _err("Unknown class: " + type)
	if not ClassDB.is_parent_class(type, "Resource"):
		return _err(type + " is not a Resource type. Use a class that inherits from Resource.")
	if FileAccess.file_exists(path):
		return _err("File already exists: " + path + ". Use a different path or delete the existing file first.")

	var res = ClassDB.instantiate(type)
	if res == null:
		return _err("Failed to instantiate: " + type + " (may not be directly instantiable)")

	for key in properties.keys():
		res.set(key, _parse_property_value(properties[key]))

	_ensure_dir(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return _err("Failed to save: " + error_string(err))

	# 不调 _refresh_filesystem() — 新建 .tres 文件会触发 Godot 全局脚本重载，
	# 重载会杀掉所有挂起的协程（包括 _run_react_loop），导致 session 被截断。
	# 文件已落盘，编辑器稍后会自然发现。
	return _ok("Created: " + path + " (" + type + ")")


## 列出所有 Input Map 动作
func _tool_get_input_actions(args: Dictionary) -> Dictionary:
	var actions: Array = InputMap.get_actions()
	var result: Array = []
	for action_name in actions:
		var events: Array = []
		for ev in InputMap.action_get_events(action_name):
			var ev_info := _describe_input_event(ev)
			if not ev_info.is_empty():
				events.append(ev_info)
		result.append({"name": action_name, "events": events})
	return _ok(JSON.stringify(result, "  "))


## 将 InputEvent 转为可读的字典
func _describe_input_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var ek := ev as InputEventKey
		return {"type": "key", "keycode": OS.get_keycode_string(ek.keycode), "physical": OS.get_keycode_string(ek.physical_keycode)}
	elif ev is InputEventMouseButton:
		var emb := ev as InputEventMouseButton
		var btn_names := ["", "left", "right", "middle", "wheel_up", "wheel_down", "wheel_left", "wheel_right", "x1", "x2"]
		var btn: String = btn_names[emb.button_index] if emb.button_index < btn_names.size() else "button_%d" % emb.button_index
		return {"type": "mouse", "button": btn, "pressed": emb.pressed}
	elif ev is InputEventJoypadButton:
		var ejb := ev as InputEventJoypadButton
		return {"type": "joypad_button", "button": ejb.button_index, "pressed": ejb.pressed}
	elif ev is InputEventJoypadMotion:
		var ejm := ev as InputEventJoypadMotion
		return {"type": "joypad_axis", "axis": ejm.axis, "value": ejm.axis_value}
	return {}


## 添加新的 Input Map 动作
func _tool_add_input_action(args: Dictionary) -> Dictionary:
	var name: String = args.get("name", "")
	var events: Array = args.get("events", [])

	if name.is_empty():
		return _err("name is required")
	if InputMap.has_action(name):
		return _err("Action already exists: " + name + ". Use a different name.")

	InputMap.add_action(name)

	for ev_desc in events:
		var ev_type: String = ev_desc.get("type", "")
		if ev_type == "key":
			var code: String = ev_desc.get("code", "")
			if code.is_empty():
				continue
			var kc := OS.find_keycode_from_string(code)
			if kc == KEY_NONE and code != "None":
				push_warning("Unknown keycode: " + code)
				continue
			var ev := InputEventKey.new()
			ev.keycode = kc
			InputMap.action_add_event(name, ev)
		elif ev_type == "mouse":
			var btn: int = int(ev_desc.get("button", 1))
			var ev := InputEventMouseButton.new()
			ev.button_index = btn
			InputMap.action_add_event(name, ev)

	ProjectSettings.save()
	var count := InputMap.action_get_events(name).size()
	return _ok("Added action '%s' with %d event(s). Saved to project.godot." % [name, count])


## 手动清理旧备份目录
func _tool_cleanup_backups(args: Dictionary) -> Dictionary:
	var bm := _get_backup()
	var before := bm.list_backups().size()
	# 强制触发清理（内部会删掉超过 MAX_BACKUP_DIRS 的旧目录）
	bm._cleanup_old()
	var after := bm.list_backups().size()
	return _ok("Backup cleanup: %d → %d directories" % [before, after])


## 预览文件最近的备份（最多 3 个），返回时间戳 + 内容预览
## 让 AI 在 undo_last 之前知道自己要恢复什么
func _tool_preview_backup(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not path.begins_with("res://"):
		return _err("path must start with res://")

	var rel := path.trim_prefix("res://")
	var bm := _get_backup()
	var backup_dirs := bm.list_backups()
	if backup_dirs.is_empty():
		return _ok("(no backups found — backups are created automatically when write tools modify files)")

	# 从最新往旧找，最多返回 3 个匹配的备份
	var found: Array = []
	for i in range(backup_dirs.size() - 1, -1, -1):
		if found.size() >= 3:
			break
		var ts: String = backup_dirs[i]
		var backup_file := "res://.dotagent_backups/" + ts + "/" + rel
		if not FileAccess.file_exists(backup_file):
			continue
		var f := FileAccess.open(backup_file, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		var preview := content
		if preview.length() > 400:
			preview = preview.substr(0, 400) + "\n... [%d more chars]" % (content.length() - 400)
		found.append({
			"timestamp": ts,
			"size": content.length(),
			"preview": preview,
		})

	if found.is_empty():
		return _ok("No backup found for: " + path + "\n(backups exist for other files — try undo_last if you modified a scene)")

	var lines: Array = []
	lines.append("%d backup(s) for %s:" % [found.size(), path])
	for item in found:
		lines.append("\n--- Backup @ %s (%d bytes) ---" % [item["timestamp"], item["size"]])
		lines.append(item["preview"])
	return _ok("\n".join(lines))


## List all available scene-type skills with their trigger keywords.
func _tool_list_skills(args: Dictionary) -> Dictionary:
	var sm := SkillManager.new()
	var skills := sm.list_skills()
	if skills.is_empty():
		return _ok("(no skills found in res://addons/dotagent/skills/)")
	var lines: Array = []
	lines.append("Available skills (%d):" % skills.size())
	for s in skills:
		var triggers := ", ".join(s.get("triggers", []))
		var source := "builtin" if "builtin" in s.get("path", "") else "custom"
		lines.append("  [%s] %s — triggers: %s" % [source, s.get("name", "?"), triggers])
	return _ok("\n".join(lines))


## Create a new skill file. Validates format, checks for trigger conflicts.
func _tool_create_skill(args: Dictionary) -> Dictionary:
	var skill_name: String = args.get("name", "")
	var triggers: Array = args.get("triggers", [])
	var content: String = args.get("content", "")

	if skill_name.is_empty():
		return _err("name is required (kebab-case, without .md)")
	if triggers.is_empty():
		return _err("triggers is required (array of lowercase keywords)")
	if content.is_empty():
		return _err("content is required")

	if " " in skill_name or "/" in skill_name:
		return _err("name must be kebab-case, no spaces or slashes: " + skill_name)

	var triggers_line := "# triggers: " + ", ".join(triggers)
	var file_content := triggers_line + "\n\n" + content

	var dir := "res://addons/dotagent/skills/custom"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var path := dir.path_join(skill_name + ".md")
	if FileAccess.file_exists(path):
		return _err("Skill already exists: " + path + ". Use replace_in_file to update it.")

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err("Cannot write: " + path)
	f.store_string(file_content)
	f.close()

	# Check for trigger overlaps with existing skills
	var sm := SkillManager.new()
	var overlap_warning := ""
	for s in sm.list_skills():
		if s.get("name") == skill_name:
			continue
		var existing: Array = s.get("triggers", [])
		var shared: Array = []
		for t in triggers:
			if t in existing:
				shared.append(t)
		if not shared.is_empty():
			if overlap_warning.is_empty():
				overlap_warning = "\n\n⚠️ Trigger overlaps detected:"
			overlap_warning += "\n  '%s' shares: %s" % [s.get("name", "?"), ", ".join(shared)]

	var lines: Array = []
	lines.append("✅ Skill '%s' created at %s" % [skill_name, path])
	lines.append("Triggers: %s" % ", ".join(triggers))
	lines.append("Content: %d chars" % content.length())
	if not overlap_warning.is_empty():
		lines.append(overlap_warning)
		lines.append("\nMultiple skills with same triggers ALL get injected — they don't override each other. If they conflict, merge them into one skill.")
	lines.append("\nCall list_skills to verify. Auto-injection available after session restart.")
	return _ok("\n".join(lines))


## Lightweight .tscn reader — returns only node tree structure, no property values.
func _tool_peek_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var max_depth: int = int(args.get("max_depth", 0))
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return _err("Only .tscn/.scn files supported")

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot read file")
	var text := f.get_as_text()
	f.close()

	# Parse node entries
	var nodes: Array[Dictionary] = []
	var node_re := RegEx.new()
	node_re.compile('\\[node name="([^"]*)" type="([^"]*)"(?: parent="([^"]*)")?')
	for m in node_re.search_all(text):
		nodes.append({"name": m.get_string(1), "type": m.get_string(2), "parent": m.get_string(3)})

	# Parse script assignments
	var scripts: Dictionary = {}
	var script_re := RegEx.new()
	script_re.compile('script\\s*=\\s*ExtResource\\("([^"]*)"\\)')
	# Map node→ExtResource ID
	var node_res_id: Dictionary = {}
	for line in text.split("\n"):
		if '[node name="' in line and "script" in line:
			var nm := line.substr(line.find('name="') + 6)
			nm = nm.substr(0, nm.find('"'))
			for m2 in script_re.search_all(line):
				node_res_id[nm] = m2.get_string(1)
		# Direct script="res://..." format
		if '[node name="' in line and 'script="res://' in line:
			var nm := line.substr(line.find('name="') + 6)
			nm = nm.substr(0, nm.find('"'))
			var sp := line.find('script="') + 8
			var se := line.find('"', sp)
			scripts[nm] = line.substr(sp, se - sp)

	# Parse ExtResource mappings
	var ext_res: Dictionary = {}
	var res_re := RegEx.new()
	res_re.compile('\\[ext_resource type="Script"[^\\]]*path="([^"]*)" id="([^"]*)"')
	for m in res_re.search_all(text):
		ext_res[m.get_string(2)] = m.get_string(1)
	# Resolve
	for node_name in node_res_id:
		var rid: String = node_res_id[node_name]
		if ext_res.has(rid):
			scripts[node_name] = ext_res[rid]

	# Build tree
	if nodes.is_empty():
		return _ok("(no nodes in %s)" % path)

	var children: Dictionary = {}
	for n in nodes:
		var p := n.get("parent", "")
		if p.is_empty(): p = "."
		if not children.has(p):
			children[p] = []
		children[p].append(n)

	var lines: Array = []
	lines.append("%s (%d nodes):" % [path.get_file(), nodes.size()])

	var _build: Callable
	var _children := children
	var _scripts := scripts
	_build = func(node: Dictionary, depth: int) -> void:
		if max_depth > 0 and depth > max_depth:
			return
		var indent := "  ".repeat(depth)
		var name: String = node.get("name")
		var type: String = node.get("type")
		var st := ""
		if _scripts.has(name):
			st = " [%s]" % _scripts[name].get_file()
		lines.append("%s%s (%s)%s" % [indent, name, type, st])
		var cn := node.get("name")
		if _children.has(cn):
			for child in _children[cn]:
				_build.call(child, depth + 1)

	if children.has("."):
		for node in children["."]:
			_build.call(node, 0)

	return _ok("\n".join(lines))
