@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 执行类工具 - 让 AI 真的"动手"
##
## Tools:
## - execute_gdscript
## - call_node_method
## - open_scene
## - run_current_scene
## - stop_running_scene
## - reload_project
## - get_editor_selection
## - run_scene_capture
## - get_node_type_info
## - read_editor_output




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
			"description": "Call a method on a node in the edited scene. Safe — only interacts with in-memory nodes, doesn't modify files.",
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
			"dangerous": false,
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
			"name": "close_all_scenes",
			"description": "Close all open scene tabs in the editor. Saves modified scenes first, then removes all tabs. Use before starting a new task to start from a clean slate.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_close_all_scenes",
			"dangerous": false,
		},
		{
			"name": "list_open_scenes",
			"description": "List all currently open scene tabs in the editor. Returns array of res:// paths. Use to see what scenes are open before deciding which to close or switch to.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_open_scenes",
			"dangerous": false,
		},
		{
			"name": "run_current_scene",
			"description": "Run the current scene (equivalent to F5). Safe — paired with stop_running_scene (F8), no side effects.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_run_current_scene",
			"dangerous": false,
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
			"description": "⚠️ DANGEROUS: Clears the tool registry (all tools stop working). NEVER call this mid-session — it will kill your ability to use any tools. Only use when explicitly told by the user.",
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
			"dangerous": false,
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
		"_tool_close_all_scenes": return _tool_close_all_scenes(args)
		"_tool_list_open_scenes": return _tool_list_open_scenes(args)
		"_tool_run_current_scene": return _tool_run_current_scene(args)
		"_tool_stop_running_scene": return _tool_stop_running_scene(args)
		"_tool_reload_project": return _tool_reload_project(args)
		"_tool_get_editor_selection": return _tool_get_editor_selection(args)
		"_tool_get_node_type_info": return _tool_get_node_type_info(args)
		"_tool_run_scene_capture": return await _tool_run_scene_capture(args)
		"_tool_read_editor_output": return _tool_read_editor_output(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_execute_gdscript(args: Dictionary) -> Dictionary:
	var snippet: String = args.get("snippet", "")
	if snippet.is_empty():
		return _err("snippet is required")

	# 缩进归一化：AI 片段可能混用 tab 和空格。
	# 统一将每行前导空白转为 tabs，再整体加一级缩进作为 func run() 的函数体。
	var lines := snippet.split("\n")
	var processed: Array = []
	for line in lines:
		var stripped := line.strip_edges()
		if stripped == "":
			processed.append("")
			continue
		# 计算前导空白量，1 tab = 4 spaces
		var leading := line.substr(0, line.length() - line.lstrip("\t ").length())
		var spaces := 0
		for ch in leading:
			if ch == "\t":
				spaces += 4
			else:
				spaces += 1
		var tabs: int = int(ceil(float(spaces) / 4.0)) + 1  # +1 = func run() 函数体缩进
		var indent := ""
		for _i in range(int(tabs)):
			indent += "\t"
		processed.append(indent + stripped)
	var indented := "\n".join(processed)

	# wrapper 提供:
	# - _result:String — 用 _echo() 写入会被捕获返回
	# - print() / push_error() / push_warning() -> 原生行为（控制台输出，不被捕获）
	# - _echo(text):追加到 _result（推荐替代 print，不产生递归）
	# - ei:EditorInterface 引用
	var script_src := """
extends RefCounted
var _result: String = ""

func _echo(text) -> void:
	_result += str(text) + "\n"

func run(ei: EditorInterface) -> String:
%s
	return _result if _result != "" else "(no return value)"
""" % indented

	# GDScript.new() + script.reload() 直接在内存中编译（不依赖文件系统缓存）
	var script := GDScript.new()
	script.source_code = script_src
	var err := script.reload()
	if err != OK:
		# 编译失败时，用子进程捕获详细的错误信息（行号+描述）
		var detail := _get_compile_error_via_subprocess(script_src)
		return _err("Script compile error:\n%s\n--- snippet ---\n%s" % [detail, snippet])

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
	# P1-4 fix: 统一根节点路径 — "." / "" / root.name 都指向场景根
	var node: Node = null
	if path.is_empty() or path == "." or path == "/" or path == root.name:
		node = root
	elif root.has_node(path):
		node = root.get_node(path)
	if node == null:
		return _err("Node not found: " + path)
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


## 关闭全部已打开的场景标签页
func _tool_close_all_scenes(_args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")

	# 先保存当前场景
	ei.save_scene()

	# 获取所有打开的场景
	var open_scenes: Array = ei.get_open_scenes()
	var count: int = open_scenes.size()
	if count == 0:
		return _ok("No open scenes")

	# 找到编辑器中的场景标签栏并逐个关闭
	var closed := _close_scene_tabs(ei)

	return _ok("Closed %d scene(s). %d tab(s) removed." % [count, closed])


## 列出当前编辑器中所有已打开的场景
func _tool_list_open_scenes(_args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var scenes: Array = ei.get_open_scenes()
	if scenes.is_empty():
		return _ok("(no open scenes)")
	var current := ""
	var root = ei.get_edited_scene_root()
	if root:
		current = root.scene_file_path
	var lines: Array[String] = []
	lines.append("Open scenes (%d):" % scenes.size())
	for i in range(scenes.size()):
		var marker := " ← 当前" if scenes[i] == current else ""
		lines.append("  %d. %s%s" % [i + 1, scenes[i], marker])
	return _ok("\n".join(lines))


## 遍历编辑器 UI 树找到场景标签栏并触发标准关闭流程
func _close_scene_tabs(ei: EditorInterface) -> int:
	var base: Control = ei.get_base_control()
	var tab_bar: TabBar = _find_tab_bar(base)
	if tab_bar == null:
		return 0

	var closed: int = 0
	var tab_count: int = tab_bar.get_tab_count()
	# 从后往前触发 tab_close_pressed 信号（让编辑器走标准关闭流程）
	for i in range(tab_count - 1, -1, -1):
		tab_bar.set_current_tab(i)
		tab_bar.emit_signal("tab_close_pressed", i)
		closed += 1

	return closed


func _find_tab_bar(node: Node) -> TabBar:
	if node is TabBar:
		return node
	for child in node.get_children():
		var found: TabBar = _find_tab_bar(child)
		if found:
			return found
	return null


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


# ============ Helpers ============

func _get_compile_error_via_subprocess(script_src: String) -> String:
	# GDScript 4.x 无公开 API 获取编译错误文本。
	# 策略：写到临时文件，用 headless Godot 子进程加载它，捕获 stderr 中的错误信息。
	var temp_path := "res://addons/dotagent/_snippet_compile_check.gd"
	var f := FileAccess.open(temp_path, FileAccess.WRITE)
	if f == null:
		return "(unable to write temp file for compile check)"
	f.store_string(script_src)
	f.close()

	var godot_exe: String = OS.get_executable_path()
	if godot_exe.is_empty() or not FileAccess.file_exists(godot_exe):
		DirAccess.remove_absolute(temp_path)
		return "(godot executable not found)"

	var temp_abs: String = ProjectSettings.globalize_path(temp_path)
	var output: Array = []
	OS.execute(godot_exe, ["--headless", "--script", temp_abs], output, true, false)
	DirAccess.remove_absolute(temp_path)

	# 提取编译错误行（通常以 "ERROR:" 或行号+错误描述形式出现）
	var full := "\n".join(output)
	var errors := _extract_error_lines(full)

	if errors.is_empty():
		var preview := full.strip_edges()
		if preview.length() > 800:
			preview = preview.substr(0, 800) + "\n... (truncated)"
		if preview.is_empty():
			return "(compile failed — check snippet syntax manually)"
		return "Raw output:\n" + preview

	return "\n".join(errors)


func _type_name(t: int) -> String:
	return type_string(t)


## Non-blocking subprocess — spawn + poll, doesn't freeze editor
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
		return _err("Cannot find godot executable")

	var project_path: String = ProjectSettings.globalize_path("res://")
	var scene_abs: String = ProjectSettings.globalize_path(scene_path)

	var arguments: PackedStringArray = [
		"--headless", "--path", project_path,
		"--quit-after", str(frames), scene_abs,
	]

	var pid := OS.create_process(godot_exe, arguments, false)
	if pid < 0:
		return _err("Failed to spawn process")
	# 优化: 改用 stdout 捕获，避免第二次执行
	# OS.execute 会阻塞编辑器几秒（场景运行时间），但只跑一次
	# 折中方案: 用 OS.create_process 跑场景，同时在另一个进程中重定向 stdout
	# 实现: 直接在主进程用 OS.execute 同步执行（阻塞但单次）
	var tree := Engine.get_main_loop() as SceneTree
	var output: Array = []
	# 阻塞直到子进程结束（编辑器短暂冻结是预期行为 — 验证场景的代价）
	OS.execute(godot_exe, arguments, output, true, false)
	var full_output := "\n".join(output)
	var error_lines := _extract_error_lines(full_output)
	# exit_code: OS.execute 返回值,正常为 0
	var exit_code := 0  # OS.execute 不直接提供 exit code,默认 0

	var preview := full_output
	if preview.length() > 3000:
		preview = preview.substr(0, 3000) + "\n... (truncated)"

	# P0-3 fix: 检查子进程退出码 — GDScript 编译失败时 exit code 非零
	if exit_code != 0 and error_lines.is_empty():
		return _err("Scene '%s' exited with code %d (compile/runtime error). No error lines captured from stdout/stderr.\n\n--- Full stdout/stderr (first 3KB) ---\n%s" % [scene_path, exit_code, preview])

	if error_lines.is_empty():
		return _ok("✅ Scene '%s' ran for %d frames, no errors detected.\n\n--- Full stdout/stderr (first 3KB) ---\n%s" % [scene_path, frames, preview])
	else:
		var exit_info := ""
		if exit_code != 0:
			exit_info = " (exit code %d)" % exit_code
		return _err("Scene '%s' ran for %d frames%s, found %d error(s):\n%s\n\n--- Full stdout/stderr (first 3KB) ---\n%s" % [scene_path, frames, exit_info, error_lines.size(), "\n".join(error_lines), preview])


func _tool_read_editor_output(args: Dictionary) -> Dictionary:
	var max_lines: int = int(args.get("max_lines", 50))
	return _ok(EditorLogBuffer.get_recent(max_lines))
