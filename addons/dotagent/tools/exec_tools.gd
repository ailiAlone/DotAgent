@tool
extends "res://addons/dotagent/core/tool_base.gd"
## 执行类工具 - 让 AI 真的"动手"
##
## 工具:
## - execute_gdscript     (危险 - eval 任意代码)
## - call_node_method     (危险 - 在指定节点上调方法)
## - run_current_scene    (危险 - F5)
## - stop_running_scene
## - reload_project       (危险)
## - get_editor_selection
## - get_node_type_info


func get_tool_definitions() -> Array:
	return [
		{
			"name": "execute_gdscript",
			"description": "Execute a snippet of GDScript in the editor context. Has full editor API access. Use for complex operations no other tool supports. Returns stdout captured during execution.",
			"parameters": {
				"type": "object",
				"properties": {
					"snippet": {"type": "string", "description": "GDScript code to execute. Can reference editor APIs like EditorInterface."},
				},
				"required": ["snippet"],
			},
			"method_name": "_tool_execute_gdscript",
			"dangerous": true,
		},
		{
			"name": "call_node_method",
			"description": "Call a method on a node in the edited scene. args is an array of positional arguments (JSON-parseable).",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path"},
					"method": {"type": "string", "description": "Method name to call"},
					"args": {"type": "array", "description": "Positional arguments (default [])", "default": []},
				},
				"required": ["path", "method"],
			},
			"method_name": "_tool_call_node_method",
			"dangerous": true,
		},
		{
			"name": "open_scene",
			"description": "Open a scene in the editor (equivalent to File > Open Scene). Use this to switch the edited scene — do NOT use execute_gdscript to call EditorInterface.open_scene_from_path() (the RefCounted wrapper has no editor API access).",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Scene path, e.g. 'res://main_menu.tscn'"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_open_scene",
			"dangerous": false,
		},
		{
			"name": "run_current_scene",
			"description": "Run the current scene (equivalent to F5).",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_run_current_scene",
			"dangerous": true,
		},
		{
			"name": "stop_running_scene",
			"description": "Stop the running scene (equivalent to F8).",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_stop_running_scene",
			"dangerous": false,
		},
		{
			"name": "reload_project",
			"description": "Force the project to reload from disk. Use after major file changes outside the editor.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_reload_project",
			"dangerous": true,
		},
		{
			"name": "get_editor_selection",
			"description": "Get the currently selected nodes in the scene editor. Returns array of {name, path, type}.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_get_editor_selection",
			"dangerous": false,
		},
		{
			"name": "run_scene_capture",
			"description": "Run a scene in headless mode and capture all stdout (including errors). Blocks the editor for a few seconds. Returns errors found + full output. Use this to autonomously detect and fix script errors. frames: how many frames to run before quit (default 60 = 1 second at 60fps).",
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {"type": "string", "description": "Scene to run, e.g. 'res://scenes/main.tscn'. Empty = current edited scene."},
					"frames": {"type": "integer", "description": "Frames to run before quitting (default 60)", "default": 60},
				},
			},
			"method_name": "_tool_run_scene_capture",
			"dangerous": true,
		},
		{
			"name": "get_node_type_info",
			"description": "Get information about a Godot class: inheritance, properties, methods, signals. Useful before calling or setting things on a type.",
			"parameters": {
				"type": "object",
				"properties": {
					"type": {"type": "string", "description": "Class name, e.g. 'CharacterBody2D'"},
				},
				"required": ["type"],
			},
			"method_name": "_tool_get_node_type_info",
			"dangerous": false,
		},
		{
			"name": "read_editor_output",
			"description": "Read the last N lines from the Godot editor's Output panel. Use when open_scene or other editor operations fail silently — the error messages often appear here.",
			"parameters": {
				"type": "object",
				"properties": {
					"max_lines": {"type": "integer", "description": "Max lines to return (default 50)", "default": 50},
				},
			},
			"method_name": "_tool_read_editor_output",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_execute_gdscript": return await _tool_execute_gdscript(args)
		"_tool_call_node_method": return _tool_call_node_method(args)
		"_tool_open_scene": return _tool_open_scene(args)
		"_tool_run_current_scene": return _tool_run_current_scene(args)
		"_tool_stop_running_scene": return _tool_stop_running_scene(args)
		"_tool_reload_project": return _tool_reload_project(args)
		"_tool_get_editor_selection": return _tool_get_editor_selection(args)
		"_tool_get_node_type_info": return _tool_get_node_type_info(args)
		"_tool_run_scene_capture": return _tool_run_scene_capture(args)
		"_tool_read_editor_output": return _tool_read_editor_output(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_execute_gdscript(args: Dictionary) -> Dictionary:
	var snippet: String = args.get("snippet", "")
	if snippet.is_empty():
		return _err("snippet is required")

	# 关键:snippet 每一行加 1 个 tab 作为 func run() 函数体的基础缩进,
	# 但**保留用户原有的相对缩进** — 否则 if/else、for 等嵌套块的缩进会错位
	# (比如用户写"if x:\n  body",我只加 1 tab,变成"\tif x:\n\t  body",if 体内多 1 级缩进,匹配)
	var lines := snippet.split("\n")
	var processed: Array = []
	for line in lines:
		if line.strip_edges() == "":
			processed.append("")  # 空行不加 tab,保持空行
		else:
			processed.append("\t" + line)
	var indented := "\n".join(processed)

	# wrapper 提供:
	# - _result:String — 自动累积所有 print/push_error/push_warning 输出
	# - _echo(text):同 print 但强制写 _result
	# - ei:EditorInterface 引用
	# print/push_error/push_warning 被局部 shadow，输出自动进入 _result
	var script_src := """
extends RefCounted
var _result: String = ""

func _echo(text) -> void:
	_result += str(text) + "\n"
	print(text)

func print(text) -> void:
	_echo(text)

func push_error(text) -> void:
	_echo("ERROR: " + str(text))

func push_warning(text) -> void:
	_echo("WARNING: " + str(text))

func run(ei: EditorInterface) -> String:
%s
	return _result if _result != \"\" else \"(no return value)\"
""" % indented

	var script := GDScript.new()
	script.source_code = script_src
	var err := script.reload()
	if err != OK:
		return _err("Script compile error (line in source: " + _get_compile_error(script) + ")\n--- snippet ---\n" + snippet)

	# Bug #2: script.new() can return null if runtime init fails
	var obj = script.new()
	if obj == null:
		return _err("Script instantiated but new() returned null")
	var ei = _ei()
	# Bug #2 fix: support user snippets with `await` by awaiting obj.run()
	# (this makes _tool_execute_gdscript a coroutine; tool_registry already awaits mod.call_method)
	var result = await obj.run(ei)
	return _ok(str(result))


func _tool_call_node_method(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root = ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open")
	var path: String = args.get("path", "")
	if not root.has_node(path):
		return _err("Node not found: " + path)
	var node: Node = root.get_node(path)
	var method: String = args.get("method", "")
	if method.is_empty():
		return _err("method is required")
	if not node.has_method(method):
		return _err("Method not found: " + method)
	var call_args: Array = args.get("args", [])
	var result = node.callv(method, call_args)
	return _ok("Called %s.%s(%s) -> %s" % [node.name, method, str(call_args), str(result)])


func _tool_run_current_scene(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root = ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open in editor")
	if ei.has_method("play_custom_scene"):
		ei.play_custom_scene(root.scene_file_path)
	else:
		ei.play_main_scene()
	return _ok("Running scene: " + root.scene_file_path)


## 打开场景(等价 File > Open Scene)
## 之前 AI 用 execute_gdscript 调 EditorInterface.open_scene_from_path() 会失败
## 因为 RefCounted wrapper 没有 EditorInterface 访问权,直接走这个工具
##
## Godot 4.5 的 EditorInterface.open_scene_from_path() 返回 void
## 成功/失败依赖 Godot 内部 — 失败时 Godot 在 console 推 error
## 简单验证:对比 edited_scene_root 的 scene_file_path 是否变了
func _tool_open_scene(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("Scene file not found: " + path)
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return _err("Path must be a scene file (.tscn / .scn)")

	var prev_root = ei.get_edited_scene_root()
	var prev_path = prev_root.scene_file_path if prev_root else ""

	ei.open_scene_from_path(path)

	# void return — 验证一下 edited_scene_root 是不是新场景
	# 路径比对:EditorInterface 可能用 "res://foo.tscn" 或 absolute,统一 normalize
	var new_root = ei.get_edited_scene_root()
	var new_path = new_root.scene_file_path if new_root else ""
	if new_path == path and new_path != prev_path:
		return _ok("Opened scene: " + path)
	if new_path == prev_path and prev_path != path:
		return _err("Failed to open scene: edited scene root unchanged (check Godot Output panel)")
	return _ok("Requested open: " + path)


func _tool_stop_running_scene(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	ei.stop_playing_scene()
	return _ok("Scene stopped")


func _tool_reload_project(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	ei.get_resource_filesystem().scan()
	return _ok("Project filesystem rescanned")


func _tool_get_editor_selection(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var sel = ei.get_selection().get_selected_nodes()
	var result := []
	for n in sel:
		result.append({
			"name": n.name,
			"type": n.get_class(),
			"path": str(n.get_path()),
		})
	return _ok(JSON.stringify(result, "  "))


func _tool_get_node_type_info(args: Dictionary) -> Dictionary:
	var type: String = args.get("type", "")
	if not ClassDB.class_exists(type):
		return _err("Unknown class: " + type)
	var info := {
		"type": type,
		"inherits": ClassDB.get_parent_class(type),
		"properties": [],
		"methods": [],
		"signals": [],
	}
	for prop in ClassDB.class_get_property_list(type, true):
		if prop.usage & PROPERTY_USAGE_STORAGE:
			info["properties"].append({"name": prop.name, "type": _type_name(prop.type)})
	for m in ClassDB.class_get_method_list(type, true):
		info["methods"].append({"name": m.name, "args": m.args.size()})
	for s in ClassDB.class_get_signal_list(type, true):
		info["signals"].append(s.name)
	return _ok(JSON.stringify(info, "  "))


# ============ 辅助 ============

func _get_compile_error(script: GDScript) -> String:
	# GDScript 编译错误的获取在不同版本 API 不一样
	# 简化处理
	return "see Godot output for details"


func _type_name(t: int) -> String:
	return type_string(t)


## 用 OS.execute 同步跑 headless 场景,捕获 stdout(包含错误)
## frames: 跑多少帧后 --quit-after 退出
func _tool_run_scene_capture(args: Dictionary) -> Dictionary:
	var scene_path: String = args.get("scene_path", "")
	if scene_path.is_empty():
		var ei = _ei()
		if ei:
			var root = ei.get_edited_scene_root()
			if root:
				scene_path = root.scene_file_path
	if scene_path.is_empty():
		return _err("scene_path is required (or open a scene first)")
	if not FileAccess.file_exists(scene_path):
		return _err("Scene not found: " + scene_path)

	var frames: int = int(args.get("frames", 60))
	frames = clamp(frames, 1, 600)

	var godot_exe: String = OS.get_executable_path()
	if godot_exe.is_empty() or not FileAccess.file_exists(godot_exe):
		return _err("Cannot find godot executable at: " + str(godot_exe))

	var project_path: String = ProjectSettings.globalize_path("res://")
	var scene_abs: String = ProjectSettings.globalize_path(scene_path)

	# Bug #3 caveat: OS.execute spawns a NEW Godot process using the editor's exe.
	# 默认 frames=60 已在 0.5s(30 帧)到 1s(60 帧)内,场景 hang 不会永久卡编辑器
	# 但每个调用会开一个 200MB+ 的新进程,频繁调用(>10 次/分钟)会吃内存
	# 未来:换成 OS.create_process 异步 + polling,但目前 OK
	var arguments: PackedStringArray = [
		"--headless",
		"--path", project_path,
		"--quit-after", str(frames),
		scene_abs,
	]

	var output: Array = []
	# read_stderr=true 捕获 stderr(错误信息通常在这)
	var exit_code: int = OS.execute(godot_exe, arguments, output, true, false)
	var full_output := "\n".join(output)

	# 找 ERROR / SCRIPT ERROR / Parse Error / push_error
	# Bug #5 fix: 用 starts_with 锚定行首,避免 "MY_ERROR_VAR" / "no errors found" / "error handling..." 等误报
	var error_lines: Array = []
	for line in full_output.split("\n"):
		var l := line as String
		var stripped := l.strip_edges()
		if stripped.begins_with("ERROR:") \
				or stripped.begins_with("SCRIPT ERROR:") \
				or stripped.begins_with("Parse Error:") \
				or stripped.begins_with("USER ERROR:") \
				or stripped.contains("push_error(") \
				or stripped.contains("push_critical("):
			error_lines.append(stripped)

	var preview := full_output
	if preview.length() > 3000:
		preview = preview.substr(0, 3000) + "\n... (truncated)"

	if error_lines.is_empty():
		return _ok("✅ Scene '%s' ran for %d frames, no errors detected.\n\n--- Full stdout/stderr (first 3KB) ---\n%s" % [scene_path, frames, preview])
	else:
		# Bug #1: errors found → return ok=false so LLM sees it failed
		return _err("Scene '%s' ran for %d frames, found %d error(s):\n%s\n\n--- Full stdout/stderr (first 3KB) ---\n%s" % [scene_path, frames, error_lines.size(), "\n".join(error_lines), preview])


# exec_tools 辅助方法已移至 ToolBase 基类


func _tool_read_editor_output(args: Dictionary) -> Dictionary:
	var max_lines: int = int(args.get("max_lines", 50))
	# Godot editor log 路径因 OS 不同：
	# Windows: %APPDATA%/Godot/editor_data/editor_log.txt
	# Linux: ~/.local/share/godot/editor_data/editor_log.txt
	# macOS: ~/Library/Application Support/Godot/editor_data/editor_log.txt
	# get_user_data_dir() 返回项目专用路径，需要上溯到 Godot 配置根目录
	var candidates := [
		OS.get_user_data_dir().get_base_dir().path_join("editor_data/editor_log.txt"),
		OS.get_user_data_dir().get_base_dir().get_base_dir().path_join("editor_data/editor_log.txt"),
	]
	var log_path := ""
	for c in candidates:
		if FileAccess.file_exists(c):
			log_path = c
			break
	if log_path.is_empty():
		return _err("Cannot find editor_log.txt. Candidates: %s" % str(candidates))
	var f := FileAccess.open(log_path, FileAccess.READ)
	if f == null:
		return _err("Cannot open: " + log_path)
	var full := f.get_as_text()
	f.close()
	var lines := full.split("\n")
	var start := max(0, lines.size() - max_lines)
	var tail_lines: Array = []
	for i in range(start, lines.size()):
		tail_lines.append(lines[i])
	return _ok("[last %d lines of %s]\n%s" % [tail_lines.size(), log_path, "\n".join(tail_lines)])
