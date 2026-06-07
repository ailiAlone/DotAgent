@tool
extends RefCounted
## 项目工具集 - 文件系统、项目设置、配置
##
## 工具:
## - list_files
## - list_scenes
## - list_resources
## - get_project_info
## - get_project_setting
## - set_project_setting
## - get_console_output

var editor_plugin: EditorPlugin = null
var activity_panel: Control = null
var _logger: SessionLog = SessionLog.instance()


func set_editor_context(plugin: EditorPlugin, activity: Control) -> void:
	editor_plugin = plugin
	activity_panel = activity


func _ei() -> EditorInterface:
	if editor_plugin:
		return editor_plugin.get_editor_interface()
	return null


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


# ============ 辅助 ============

func _walk_dir(dir: String, out: Array, extensions: Array, pattern: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		# 跳过:隐藏目录 / addons(插件自己) / logs(每次 AI session 都产生几千行
		# 历史 log,列进项目树会污染 LLM context 而且 AI 用不上)
		if name.begins_with(".") \
				or (name == "addons" and dir == "res://") \
				or (name == "logs" and dir == "res://"):
			name = d.get_next()
			continue
		var full := dir.path_join(name)
		if d.current_is_dir():
			_walk_dir(full, out, extensions, pattern)
		else:
			var matched := extensions.is_empty()
			if not matched:
				for ext in extensions:
					if name.ends_with(ext):
						matched = true
						break
			# pattern 用 String.match 做 glob(* 任意, ? 单字符),不是字面 contains
			if matched and not pattern.is_empty():
				matched = name.match(pattern)
			if matched:
				out.append(full)
		name = d.get_next()
	d.list_dir_end()


func _ok(content: String) -> Dictionary:
	return {"ok": true, "content": content}


func _err(content: String) -> Dictionary:
	return {"ok": false, "content": "❌ " + content}
