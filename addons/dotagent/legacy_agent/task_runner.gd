@tool
extends Node
## DotAgent Task Runner — 挂在场景中自动执行外部任务
##
## 用法:
##   1. 将此节点添加到已打开的场景中（或设为 autoload）
##   2. QoderWork 写任务到 res://dotagent_task.json
##   3. 节点检测到文件 → 自动执行 → 写结果到 res://dotagent_result.json
##   4. QoderWork 读取结果
##
## 首次使用: 在编辑器中打开任意场景，添加此节点，保存场景。
## 之后 QoderWork 可随时写入任务文件，编辑器会自动执行。

const TASK_PATH := "res://dotagent_task.json"
const RESULT_PATH := "res://dotagent_result.json"
const POLL_INTERVAL := 1.0  # 每秒检查一次任务文件

# ============ Plugin Stub ============

class PluginStub:
	var _ei: EditorInterface
	func _init(ei: EditorInterface) -> void:
		_ei = ei
	func get_editor_interface():
		return _ei

# ============ State ============

var _running := false
var _last_task_mtime := -1


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	print("[TaskRunner] Ready — watching for tasks at %s" % TASK_PATH)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _running:
		return

	# 检查任务文件是否存在且有更新
	if not FileAccess.file_exists(TASK_PATH):
		return

	var mtime := FileAccess.get_modified_time(TASK_PATH)
	if mtime == _last_task_mtime:
		return
	_last_task_mtime = mtime

	# 读取并执行任务
	_running = true
	await _execute_task()
	_running = false


func _execute_task() -> void:
	print("\n[TaskRunner] ══════════════════════════════════════")
	print("[TaskRunner] Task detected")

	# 读取任务
	var task_text := _read_task()
	if task_text.is_empty():
		_write_error("Empty task")
		return

	print("[TaskRunner] Task: %s" % task_text.substr(0, 150))

	# 获取 EditorInterface
	var ei: EditorInterface = null
	# 通过 EditorPlugin 获取
	for child in get_tree().root.get_children():
		if child is EditorPlugin:
			ei = child.get_editor_interface()
			break
	if ei == null:
		_write_error("EditorInterface not found")
		return

	var stub := PluginStub.new(ei)

	# 确保有场景打开
	var scene_root = ei.get_edited_scene_root()
	if scene_root == null:
		# 打开主场景
		ei.open_scene_from_path("res://scenes/main.tscn")
		await get_tree().create_timer(0.5).timeout
		scene_root = ei.get_edited_scene_root()
		if scene_root == null:
			_write_error("No scene available")
			return

	# 初始化 DockController
	var controller: DockController = DockController.new()
	controller.setup(stub, null, self)  # self 作为 host_node（已在场景树中）
	controller.bootstrap_session()

	# 追踪状态
	var rounds := 0
	var tools_used: Array = []
	var final_content := ""
	var error_msg := ""
	var done := false

	controller.round_complete.connect(func(content: String, tool_calls: Array, tool_results: Array):
		rounds += 1
		for tc in tool_calls:
			var fn: Dictionary = tc.get("function", {})
			var tname: String = fn.get("name", "")
			if not tname.is_empty() and tname not in tools_used:
				tools_used.append(tname)
		if not content.is_empty():
			final_content = content
		print("[TaskRunner] Round %d: tools=%d content=%d" % [rounds, tool_calls.size(), content.length()])
	)

	controller.stream_error.connect(func(err: String):
		error_msg = err
		print("[TaskRunner] ERROR: %s" % err)
	)

	controller.loop_finished.connect(func():
		done = true
	)

	# 执行
	print("[TaskRunner] Executing...\n")
	controller.send_user_message(task_text)

	# 等待完成（最多 5 分钟）
	var waited := 0.0
	while not done and waited < 300.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5

	if not done:
		error_msg = "Timeout after 300s"

	# 写结果
	var result := {
		"ok": error_msg.is_empty() and not final_content.is_empty(),
		"content": final_content,
		"rounds": rounds,
		"tools_used": tools_used,
		"error": error_msg,
		"duration": waited,
	}
	_write_result(result)

	print("\n[TaskRunner] Done: %d rounds, %.1fs" % [rounds, waited])
	print("[TaskRunner] Result → %s" % RESULT_PATH)
	print("[TaskRunner] ══════════════════════════════════════\n")

	# 删除任务文件，避免重复执行
	DirAccess.remove_absolute(TASK_PATH)


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
	return json_text.strip_edges()


func _write_result(result: Dictionary) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "\t"))
		f.close()


func _write_error(msg: String) -> void:
	print("[TaskRunner] ERROR: %s" % msg)
	_write_result({"ok": false, "content": "", "rounds": 0, "tools_used": [], "error": msg, "duration": 0})
