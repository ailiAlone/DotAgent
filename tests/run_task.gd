@tool
extends EditorScript
## DotAgent Task Runner — 外部自动化入口
##
## 用法:
##   1. QoderWork 写任务到 res://dotagent_task.json
##   2. 运行: godot --script tests/run_task.gd
##   3. 结果写入 res://dotagent_result.json
##   4. QoderWork 读取结果
##
## 任务文件格式 (dotagent_task.json):
##   {"task": "用户消息文本", "max_rounds": 10}
##
## 结果文件格式 (dotagent_result.json):
##   {"ok": true, "content": "AI 最终回复", "rounds": 4, "tools_used": [...], "error": ""}

const TASK_PATH := "res://dotagent_task.json"
const RESULT_PATH := "res://dotagent_result.json"

# ============ Plugin Stub ============
# DockController 和 tools 需要一个有 get_editor_interface() 方法的对象
# EditorScript 自身就有这个方法，但我们不能直接传 self（EditorScript 不是 Node）
# 所以创建一个 RefCounted 代理

class PluginStub:
	var _ei: EditorInterface
	func _init(ei: EditorInterface) -> void:
		_ei = ei
	func get_editor_interface():
		return _ei


func _run() -> void:
	print("\n══════════════════════════════════════════════════")
	print("  DotAgent Task Runner")
	print("══════════════════════════════════════════════════\n")

	# 1. 读取任务
	var task_text := _read_task()
	if task_text.is_empty():
		_write_error("No task found at %s" % TASK_PATH)
		return

	print("  Task: %s\n" % task_text.substr(0, 200))

	# 2. 创建代理和宿主
	var ei := get_editor_interface()
	if ei == null:
		_write_error("EditorInterface not available")
		return

	var stub := PluginStub.new(ei)

	# 创建宿主 Node — LLMClient 需要在场景树中接收 _process()
	var host := Node.new()
	host.name = "TaskRunnerHost"
	# 添加到编辑器场景树
	var root = ei.get_edited_scene_root()
	if root:
		root.add_child(host)
		host.owner = root
	else:
		# 没有打开的场景 — 创建一个临时场景
		var temp_root := Node2D.new()
		temp_root.name = "TaskRunnerScene"
		var scene := PackedScene.new()
		scene.pack(temp_root)
		ei.open_scene_from_path("res://scenes/main.tscn")
		await Engine.get_main_loop().create_timer(0.2).timeout
		root = ei.get_edited_scene_root()
		if root:
			root.add_child(host)
			host.owner = root

	# 3. 初始化 DockController
	var controller := DockController.new()
	controller.setup(stub, null, host)
	controller.bootstrap_session()

	# 4. 连接信号用于追踪
	var rounds := 0
	var tools_used: Array = []
	var final_content := ""
	var error_msg := ""

	controller.round_complete.connect(func(content: String, tool_calls: Array, tool_results: Array):
		rounds += 1
		for tc in tool_calls:
			var fn: Dictionary = tc.get("function", {})
			var name: String = fn.get("name", "")
			if not name.is_empty() and name not in tools_used:
				tools_used.append(name)
		if not content.is_empty():
			final_content = content
		print("  Round %d: tools=%d content=%d chars" % [rounds, tool_calls.size(), content.length()])
	)

	controller.stream_error.connect(func(err: String):
		error_msg = err
		print("  ERROR: %s" % err)
	)

	# 5. 执行任务
	print("  Executing...\n")
	controller.send_user_message(task_text)

	# 6. 等待完成（send_user_message 是 async，但 EditorScript._run 不支持 await）
	# 用信号轮询等待
	var done := false
	controller.loop_finished.connect(func(): done = true)

	# EditorScript 的 _run() 不支持 await，所以用 process frame 轮询
	var max_wait := 300  # 最多等 300 秒
	var waited := 0.0
	while not done and waited < max_wait:
		await Engine.get_main_loop().create_timer(0.5).timeout
		waited += 0.5

	if not done:
		error_msg = "Timeout after %ds" % max_wait

	# 7. 清理
	host.queue_free()

	# 8. 写入结果
	var result := {
		"ok": error_msg.is_empty() and not final_content.is_empty(),
		"content": final_content,
		"rounds": rounds,
		"tools_used": tools_used,
		"error": error_msg,
		"duration": waited,
	}
	_write_result(result)

	print("\n══════════════════════════════════════════════════")
	print("  Done: %d rounds, %d tools, %.1fs" % [rounds, tools_used.size(), waited])
	print("  Result → %s" % RESULT_PATH)
	print("══════════════════════════════════════════════════\n")


# ============ I/O ============

func _read_task() -> String:
	if not FileAccess.file_exists(TASK_PATH):
		return ""
	var f := FileAccess.open(TASK_PATH, FileAccess.READ)
	if f == null:
		return ""
	var json_text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return str(parsed.get("task", ""))
	# 也支持纯文本文件
	return json_text.strip_edges()


func _write_result(result: Dictionary) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()
	else:
		push_error("Failed to write result: %s" % RESULT_PATH)


func _write_error(msg: String) -> void:
	print("  ERROR: %s" % msg)
	_write_result({"ok": false, "content": "", "rounds": 0, "tools_used": [], "error": msg, "duration": 0})
