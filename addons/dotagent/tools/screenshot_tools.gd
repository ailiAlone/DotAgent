@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 截图与视觉分析工具集 — 从 exec_tools.gd 拆分
##
## 工具:
## - focus_editor_view, screenshot_editor, screenshot_runtime, analyze_image


func get_tool_definitions() -> Array:
	return [
		{
			"name": "focus_editor_view",
			"description": "Switch the editor's 2D/3D viewport. Use before screenshot_editor so the screenshot shows the right view. Args: view='2d' or '3d'.",
			"parameters": {"type": "object", "properties": {
				"view": {"type": "string", "description": "'2d' or '3d'"},
			}, "required": ["view"]},
			"method_name": "_tool_focus_editor_view", "dangerous": false,
		},
		{
			"name": "screenshot_editor",
			"description": "Take a screenshot of the Godot editor's 2D or 3D viewport. Saves to res://.dotagent_screenshots/<viewport>/<timestamp>.png. Returns the file path.",
			"parameters": {"type": "object", "properties": {
				"viewport": {"type": "string", "description": "'2d' or '3d' (default '2d')", "default": "2d"},
			}},
			"method_name": "_tool_screenshot_editor", "dangerous": false,
		},
		{
			"name": "screenshot_runtime",
			"description": "Launch the project, capture the game window after N frames, then close. Saves to res://.dotagent_screenshots/runtime/<timestamp>.png.",
			"parameters": {"type": "object", "properties": {
				"scene_path": {"type": "string", "description": "Scene to run (e.g. 'res://main.tscn')"},
				"frames": {"type": "integer", "description": "Frames to wait before capture (default 30)", "default": 30},
			}, "required": ["scene_path"]},
			"method_name": "_tool_screenshot_runtime", "dangerous": false,
		},
		{
			"name": "analyze_image",
			"description": "Queue a screenshot for visual analysis by the vision model. The image will be injected as a user message in the next round.",
			"parameters": {"type": "object", "properties": {
				"path": {"type": "string", "description": "Path to screenshot, e.g. 'res://.dotagent_screenshots/2d/xxx.png'"},
				"question": {"type": "string", "description": "What to analyze (e.g. '检查按钮位置')"},
			}, "required": ["path", "question"]},
			"method_name": "_tool_analyze_image", "dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_focus_editor_view": return _tool_focus_editor_view(args)
		"_tool_screenshot_editor": return _tool_screenshot_editor(args)
		"_tool_screenshot_runtime": return await _tool_screenshot_runtime(args)
		"_tool_analyze_image": return _tool_analyze_image(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 实现（从 exec_tools.gd 迁移） ============

func _tool_focus_editor_view(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var view: String = args.get("view", "2d").to_lower()
	if view == "2d":
		ei.set_main_screen_editor("2D")
	elif view == "3d":
		ei.set_main_screen_editor("3D")
	else:
		return _err("view must be '2d' or '3d'")
	return _ok("Switched editor view to: " + view.to_upper())


func _tool_screenshot_editor(args: Dictionary) -> Dictionary:
	var view: String = args.get("viewport", "2d").to_lower()
	var ei = _ei()
	if ei == null: return _err("EditorInterface unavailable")
	var vp: Viewport = null
	if view == "2d":
		vp = ei.get_editor_viewport_2d()
	elif view == "3d":
		vp = ei.get_editor_viewport_3d()
	else:
		return _err("viewport must be '2d' or '3d'")
	if vp == null: return _err("Viewport not available")
	var img := vp.get_texture().get_image()
	if img == null: return _err("Failed to capture viewport image")
	var dir := "res://.dotagent_screenshots/" + view + "/"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := dir.path_join(ts + ".png")
	var err := img.save_png(path)
	if err != OK: return _err("Failed to save PNG: " + error_string(err))
	return _ok("📸 Editor %s screenshot: %s (%dx%d, %d bytes)" % [view, path, img.get_width(), img.get_height(), FileAccess.open(path, FileAccess.READ).get_length()])


func _tool_screenshot_runtime(args: Dictionary) -> Dictionary:
	var scene_path: String = args.get("scene_path", "")
	var frames: int = int(args.get("frames", 30))
	if scene_path.is_empty(): return _err("scene_path is required")
	if not FileAccess.file_exists(scene_path): return _err("Scene not found: " + scene_path)
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var out_dir := "res://.dotagent_screenshots/runtime/"
	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	var out_path := out_dir.path_join(ts + ".png")
	var out_abs := ProjectSettings.globalize_path(out_path)

	# 使用 --screenshot 让 Godot 在启动时截图；--quit-after 控制帧数
	var exe := OS.get_executable_path()
	var run_args := ["--headless", "--screenshot", out_abs, "--quit-after", str(frames), scene_path]
	var output: Array = []
	var exit_code := OS.execute(exe, run_args, output, true)
	if exit_code != 0:
		return _err("Runtime screenshot failed (exit code %d). Scene may have crashed." % exit_code)

	# 优化: 改用文件存在轮询代替 create_timer
	await _await_file(out_path, 2000)

	var img := Image.new()
	var err := img.load(out_path)
	if err != OK:
		# 回退：尝试不带 headless
		run_args = ["--screenshot", out_abs, "--quit-after", str(frames), scene_path]
		exit_code = OS.execute(exe, run_args, output, true)
		if exit_code != 0:
			return _err("Runtime screenshot failed — no image produced. Scene may have crashed.")
		await _await_file(out_path, 2000)
		err = img.load(out_path)
		if err != OK:
			return _err("Runtime screenshot failed — no image produced. Scene may have crashed.")
	return _ok("📸 Runtime screenshot: %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])


## 优化: 改用文件存在轮询代替 create_timer,避免 @tool 脚本中的 timer 失效
func _await_file(path: String, max_wait_ms: int = 2000) -> void:
	var deadline := Time.get_ticks_msec() + max_wait_ms
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return
		await Engine.get_main_loop().process_frame


func _tool_analyze_image(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var question: String = args.get("question", "")
	if path.is_empty(): return _err("path is required")
	if not FileAccess.file_exists(path): return _err("Image not found: " + path)

	# 读取图片并编码为 base64 data URI
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return _err("Cannot read image: " + path)
	var img_data := f.get_buffer(f.get_length())
	f.close()
	var data_uri := "data:image/png;base64," + Marshalls.raw_to_base64(img_data)

	# 返回结构化结果，由 _execute_tool_round 检测并即时注入
	return _ok(JSON.stringify({
		"type": "analyze_image_inline",
		"path": path,
		"question": question,
		"data_uri": data_uri,
	}))
