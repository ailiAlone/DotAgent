@tool
## 所有工具模块的共享基类（无 class_name，路径引用避免 Opcode 68）
##
## 提供:
## - editor_plugin / activity_panel 注入
## - _ei() — 获取 EditorInterface（无返回类型标注，避免 class_name 脚本中 EditorInterface 引用触发 Opcode 68）
## - _ok() / _err() — 统一的工具返回值格式
## - _walk_dir() — 递归文件遍历（跳过 addons / logs / 隐藏目录）
## - _ensure_dir() — 确保目录存在
## - _refresh_filesystem() — 触发编辑器文件系统重扫
## - _log_act() — 调用 activity_panel 的方法（有则调，无则忽略）
## - _logger — 共享的 SessionLog 实例
## - _backup — 共享的 BackupManager 实例（首次使用时 lazy init）

var editor_plugin: Object = null
var activity_panel: Object = null
var _logger: SessionLog = null
var _backup: BackupManager = null


func set_editor_context(plugin: Object, activity: Object) -> void:
	editor_plugin = plugin
	activity_panel = activity
	if _logger == null:
		_logger = SessionLog.instance()
	if _backup == null:
		_backup = BackupManager.new()


## 获取 EditorInterface。不用类型标注 — class_name 脚本中 EditorInterface 类型引用会触发 Godot Opcode 68。
func _ei():  # returns EditorInterface or null
	if editor_plugin:
		return editor_plugin.get_editor_interface()
	return null


func _ok(content: String) -> Dictionary:
	return {"ok": true, "content": content}


func _err(content: String) -> Dictionary:
	return {"ok": false, "content": content}


## 递归遍历目录，收集匹配的文件路径
## dir: 起始目录（如 "res://"）
## out: 输出数组
## extensions: 文件扩展名列表（如 [".gd", ".tscn"]），空=所有文件
## pattern: 可选的 glob 匹配（如 "player.*"），空=不过滤
func _walk_dir(dir: String, out: Array, extensions: Array, pattern: String = "") -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
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
			if matched and not pattern.is_empty():
				matched = name.match(pattern)
			if matched:
				out.append(full)
		name = d.get_next()
	d.list_dir_end()


## 确保文件路径的所有父目录都存在
func _ensure_dir(path: String) -> void:
	var last_slash := path.rfind("/")
	if last_slash <= 0:
		return
	var dir := path.substr(0, last_slash)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


## 触发编辑器文件系统扫描（让新创建的文件立刻可见）
func _refresh_filesystem() -> void:
	var ei = _ei()
	if ei:
		var fs = ei.get_resource_filesystem()
		if fs:
			fs.scan()


## 调用 activity_panel 的日志方法（有 activity_panel 才调，无则忽略）
func _log_act(method: String, arg1 = null, arg2 = null, arg3 = null) -> void:
	if activity_panel == null or not activity_panel.has_method(method):
		return
	if arg3 != null:
		activity_panel.call(method, arg1, arg2, arg3)
	elif arg2 != null:
		activity_panel.call(method, arg1, arg2)
	else:
		activity_panel.call(method, arg1)


## 获取共享的 BackupManager（lazy init）
func _get_backup() -> BackupManager:
	if _backup == null:
		_backup = BackupManager.new()
	return _backup
