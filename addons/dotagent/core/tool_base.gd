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


## 确保目录存在（递归创建）
## 如果传的是文件路径，自动取目录部分
## 跳过根目录 res:/ res:// 避免 "Could not create directory" 错误
func _ensure_dir(path: String) -> void:
	var dir_path := path
	# 如果是文件路径（有扩展名），取目录部分
	var last_dot := dir_path.rfind(".")
	if last_dot > dir_path.rfind("/"):
		dir_path = dir_path.get_base_dir()
	# 如果是根目录，跳过
	var trimmed := dir_path.strip_edges()
	if trimmed == "res:" or trimmed == "res:/" or trimmed == "res://" or trimmed == "res:///":
		return
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## 将 JSON 基本类型自动转换为 Godot 原生类型
## 解决 JSON 传 Color / Vector2 / Rect2 等复杂类型的问题
## {"r":1,"g":0.5,"b":0} → Color(1, 0.5, 0)
## {"x":64, "y":64} → Vector2(64, 64)
## "#ff8800" → Color("#ff8800")
func _parse_property_value(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY and typeof(raw) != TYPE_STRING:
		return raw
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		# Color: 必须有 r + g + b（a 可选）
		if d.has("r") and d.has("g") and d.has("b"):
			return Color(float(d.get("r", 0)), float(d.get("g", 0)), float(d.get("b", 0)), float(d.get("a", 1.0)))
		# Vector2: 必须有 x + y
		if d.has("x") and d.has("y") and not d.has("z"):
			return Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
		# Vector3: x + y + z
		if d.has("x") and d.has("y") and d.has("z"):
			return Vector3(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("z", 0)))
		# Rect2: position + size
		if d.has("position") and d.has("size"):
			var pos = _parse_property_value(d["position"])
			var sz = _parse_property_value(d["size"])
			if pos is Vector2 and sz is Vector2:
				return Rect2(pos, sz)
	if typeof(raw) == TYPE_STRING:
		var s: String = raw
		if s.begins_with("#") and s.length() >= 7:
			return Color(s)
	return raw


## 触发编辑器文件系统扫描（让新创建的文件立刻可见）
## ⚠️ EditorFileSystem.scan() 会触发全局脚本重载，杀死所有 GDScript 协程。
## 因此所有工具不再在写操作后立即调用此方法。
## 改为由 dock_controller 在 ReAct 循环完全结束后统一刷新。
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


## Build a tool definition dict. props = parameters.properties, required = top-level "required" array.
## Usage: _td("my_tool", "Does X", "_tool_my_tool", {"arg": {"type":"string","description":"..."}}, ["arg"])
func _td(name: String, desc: String, method: String, props: Dictionary = {}, required: Array = [], dangerous: bool = false) -> Dictionary:
	var p := {"type": "object", "properties": props}
	if not required.is_empty():
		p["required"] = required
	return {"name": name, "description": desc, "parameters": p, "method_name": method, "dangerous": dangerous}


## 获取共享的 BackupManager（lazy init）
func _get_backup() -> BackupManager:
	if _backup == null:
		_backup = BackupManager.new()
	return _backup


## Extract error lines from Godot subprocess stdout/stderr.
## Used by script_tools (syntax check) and exec_tools (scene capture).
func _extract_error_lines(text: String) -> Array:
	var out: Array = []
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.is_empty():
			continue
		var lo := s.to_lower()
		if s.begins_with("ERROR:") or s.begins_with("SCRIPT ERROR:") \
				or s.begins_with("Parse Error:") or s.begins_with("USER ERROR:") \
				or s.contains("push_error(") or s.contains("push_critical(") \
				or (s.contains(".gd:") and (lo.contains("error") or lo.contains("parse"))):
			out.append(s)
	return out
