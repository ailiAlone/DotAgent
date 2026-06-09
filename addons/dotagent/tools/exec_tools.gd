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
## - read_editor_output
## - screenshot_editor (2d/3d)
## - screenshot_runtime (subprocess)


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
		{
			"name": "focus_editor_view",
			"description": "Switch the editor's main viewport between 2D, 3D, Script, or AssetLib. Use this to show the developer which scene you're working on.\n\nBest practice: call this FIRST when you start editing a scene — focus_editor_view('2d') for 2D scenes, focus_editor_view('3d') for 3D scenes. Also use before screenshot_editor to ensure the right viewport is active.\n\nExample: focus_editor_view('2d')",
			"parameters": {
				"type": "object",
				"properties": {
					"view": {"type": "string", "description": "'2d', '3d', 'script', or 'assetlib'"},
				},
				"required": ["view"],
			},
			"method_name": "_tool_focus_editor_view",
			"dangerous": false,
		},
		{
			"name": "screenshot_editor",
			"description": "Capture a screenshot of the editor's 2D or 3D viewport. Instant. Use focus_editor_view first to switch to the right view.\n\nSaves to res://.dotagent_screenshots/2d/ or res://.dotagent_screenshots/3d/ with timestamp filename.",
			"parameters": {
				"type": "object",
				"properties": {
					"viewport": {"type": "string", "description": "'2d' or '3d' — which viewport to capture"},
				},
				"required": ["viewport"],
			},
			"method_name": "_tool_screenshot_editor",
			"dangerous": false,
		},
		{
			"name": "screenshot_runtime",
			"description": "Run a scene in a subprocess and capture its rendered output (~2s). Saves to res://.dotagent_screenshots/runtime/ with timestamp filename.",
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {"type": "string", "description": "Scene to run. Omit to use the currently edited scene."},
				},
			},
			"method_name": "_tool_screenshot_runtime",
			"dangerous": false,
		},
		{
			"name": "analyze_image",
			"description": "Send a screenshot to a vision model (e.g. MiniMax-M3) for visual analysis. The image is attached to the next LLM request automatically.\n\nWorkflow: screenshot_editor → analyze_image(path, question) → model replies with visual feedback.\n\nExample: analyze_image(path='res://.dotagent_screenshots/2d/2026-06-10_00-00-00.png', question='Check button alignment and color')",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path to the PNG screenshot"},
					"question": {"type": "string", "description": "Question about the image for the vision model"},
				},
				"required": ["path", "question"],
			},
			"method_name": "_tool_analyze_image",
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
		"_tool_focus_editor_view": return _tool_focus_editor_view(args)
		"_tool_screenshot_editor": return _tool_screenshot_editor(args)
		"_tool_screenshot_runtime": return _tool_screenshot_runtime(args)
		"_tool_analyze_image": return _tool_analyze_image(args)
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
	var error_lines := _extract_error_lines(full_output)

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


# exec_tools 辅助方法已移至 ToolBase 基类


func _tool_read_editor_output(args: Dictionary) -> Dictionary:
	var max_lines: int = int(args.get("max_lines", 50))
	return _ok(EditorLogBuffer.get_recent(max_lines))


## Switch the editor's main viewport to 2D, 3D, Script, or AssetLib.
func _tool_focus_editor_view(args: Dictionary) -> Dictionary:
	var view: String = args.get("view", "").to_lower()
	if view.is_empty():
		return _err("view is required: '2d', '3d', 'script', or 'assetlib'")

	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")

	var screen_name: String
	match view:
		"2d": screen_name = "2D"
		"3d": screen_name = "3D"
		"script": screen_name = "Script"
		"assetlib": screen_name = "AssetLib"
		_: return _err("Unknown view: '%s'. Use '2d', '3d', 'script', or 'assetlib'." % view)

	if not ei.has_method("set_main_screen_editor"):
		return _err("EditorInterface.set_main_screen_editor not available in this Godot version")
	ei.set_main_screen_editor(screen_name)
	return _ok("Switched editor view to: " + screen_name)


## Capture a screenshot of the editor's 2D or 3D viewport.
func _tool_screenshot_editor(args: Dictionary) -> Dictionary:
	var vp: String = args.get("viewport", "").to_lower()
	if vp != "2d" and vp != "3d":
		return _err("viewport must be '2d' or '3d'")

	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")

	var viewport: Viewport = null
	if vp == "2d" and ei.has_method("get_editor_viewport_2d"):
		viewport = ei.get_editor_viewport_2d()
	elif vp == "3d" and ei.has_method("get_editor_viewport_3d"):
		viewport = ei.get_editor_viewport_3d()

	if viewport == null:
		return _err("Could not access %s editor viewport. Try focus_editor_view('%s') first, then retry." % [vp, vp])

	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return _err("Viewport returned no image — it may not have rendered yet. Try again.")

	var out_dir := "res://.dotagent_screenshots/" + vp
	_ensure_dir(out_dir)
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var out_path := out_dir.path_join(timestamp + ".png")
	var err := img.save_png(out_path)
	if err != OK:
		return _err("Failed to save screenshot: " + error_string(err))

	var size := img.get_size()
	var file := FileAccess.open(out_path, FileAccess.READ)
	var file_size := 0
	if file:
		file_size = file.get_length()
		file.close()

	return _ok("📸 Editor %s screenshot: %s (%dx%d, %d bytes)" % [vp, out_path, size.x, size.y, file_size])


## Run a scene in a subprocess and capture its rendered output.
func _tool_screenshot_runtime(args: Dictionary) -> Dictionary:
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

	var godot_exe: String = OS.get_executable_path()
	if godot_exe.is_empty() or not FileAccess.file_exists(godot_exe):
		return _err("Godot executable not found")

	# Temp runner script: loads scene, waits for render, captures viewport, quits
	var runner_path := "res://.dotagent_screenshot_runner.gd"
	var out_dir := "res://.dotagent_screenshots/runtime"
	_ensure_dir(out_dir)
	var runner_src := """extends SceneTree

func _init():
	var scene := load("%s") as PackedScene
	if scene == null:
		print("Failed to load scene")
		quit(1)
		return
	var root := scene.instantiate()
	self.root.add_child(root)

	await process_frame
	await process_frame
	await process_frame

	var img := get_root().get_texture().get_image()
	if img:
		img.save_png("%s")
	quit()
""" % [scene_path, out_dir.path_join("_temp.png")]
	var rf := FileAccess.open(runner_path, FileAccess.WRITE)
	if rf == null:
		return _err("Cannot write runner script")
	rf.store_string(runner_src)
	rf.close()

	var project_path: String = ProjectSettings.globalize_path("res://")
	var output: Array = []
	# NOT --headless — needs real GPU rendering for viewport capture
	var exit_code := OS.execute(godot_exe, ["--path", project_path, "--script", ProjectSettings.globalize_path(runner_path)], output, true, false)

	# Clean up runner
	DirAccess.remove_absolute(ProjectSettings.globalize_path(runner_path))

	var temp_path := out_dir.path_join("_temp.png")
	if not FileAccess.file_exists(temp_path):
		var stderr := "\n".join(output).strip_edges()
		if stderr.length() > 500:
			stderr = stderr.substr(0, 500)
		return _err("Runtime screenshot failed (exit=%d). No image produced.\nStderr: %s" % [exit_code, stderr])

	# Rename with timestamp
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var final_path := out_dir.path_join(timestamp + ".png")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(final_path))

	var img := Image.new()
	img.load(final_path)
	var size := img.get_size()
	var file := FileAccess.open(final_path, FileAccess.READ)
	var file_size := 0
	if file:
		file_size = file.get_length()
		file.close()

	return _ok("📸 Runtime screenshot: %s (%dx%d, %d bytes)" % [final_path, size.x, size.y, file_size])


## Queue an image for vision analysis in the next LLM call.
## Writes a pending-image marker that the controller picks up and injects
## as a user message with image attachment.
func _tool_analyze_image(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var question: String = args.get("question", "")
	if path.is_empty() or question.is_empty():
		return _err("path and question are required")
	if not FileAccess.file_exists(path):
		return _err("Image not found: " + path)

	# Write pending-image marker for the controller to pick up
	var marker := {
		"path": path,
		"question": question,
	}
	var f := FileAccess.open("res://.dotagent_pending_image.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(marker))
	f.close()

	return _ok("📸 Image queued for analysis: %s\nQuestion: %s\n\nThe vision model will analyze this in the next response." % [path, question])
