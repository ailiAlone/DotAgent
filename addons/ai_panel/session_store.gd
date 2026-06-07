@tool
class_name SessionStore
extends RefCounted
## Session 业务存储
##
## Session 是一等公民 — 有 id、name、created_at、updated_at、parent_id,
## 可以 list / create / rename / delete / fork / switch。
## 这跟 logger 的 append-only 流水日志是两回事:
##   - logger:运行流水,被动记录,只用于审计
##   - session:业务对象,用户主动管理
##
## 存储位置:res://ai_sessions/<session_id>/
##   - session.json  元数据
##   - messages.json 消息数组(与 dock.gd 的 _messages 同结构)
##
## 消息写盘策略:每次写消息都 touch 一次(updated_at + 落盘),
## Godot 崩了也不丢最近的对话。

const SESSIONS_ROOT := "res://ai_sessions"


# ============ Public API ============

## 列出所有 session,按 updated_at 倒序(最新在前)
## 每个 entry 是 dict:{id, name, created_at, updated_at, model, message_count, parent_id, path}
func list_sessions(limit: int = 100) -> Array:
	var sessions: Array = []
	if not DirAccess.dir_exists_absolute(SESSIONS_ROOT):
		return sessions
	var d := DirAccess.open(SESSIONS_ROOT)
	if d == null:
		return sessions
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			var info := _read_session_meta(name)
			if not info.is_empty():
				sessions.append(info)
		name = d.get_next()
	d.list_dir_end()
	# updated_at 倒序
	sessions.sort_custom(func(a, b):
		return a.get("updated_at", "") > b.get("updated_at", ""))
	if limit > 0 and sessions.size() > limit:
		return sessions.slice(0, limit)
	return sessions


## 创建一个新 session(自动 generate id,默认 name 跟 id 一样)
## name:可选,用户给的名字;parent_id:可选,fork 时用
## 返回 session info dict(含 id)
func create_session(name: String = "", parent_id: String = "") -> Dictionary:
	var id := _generate_id()
	var now := _now_str()
	var info := {
		"id": id,
		"name": name if name != "" else _default_name(id),
		"created_at": now,
		"updated_at": now,
		"model": "",
		"message_count": 0,
		"parent_id": parent_id,
	}
	var dir_path := SESSIONS_ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir_path)
	_write_session_meta(id, info)
	# 写空 messages.json
	_write_messages_file(id, [])
	return info


## 重命名 session
func rename_session(id: String, new_name: String) -> bool:
	var info := _read_session_meta(id)
	if info.is_empty():
		return false
	info["name"] = new_name
	info["updated_at"] = _now_str()
	_write_session_meta(id, info)
	return true


## 删除 session(包括目录和所有文件,不可恢复)
func delete_session(id: String) -> bool:
	var dir_path := SESSIONS_ROOT.path_join(id)
	if not DirAccess.dir_exists_absolute(dir_path):
		return false
	# GDScript 没有 rm -rf 工具,用 OS.execute 跨平台删
	var abs_path := ProjectSettings.globalize_path(dir_path)
	var err: int
	if OS.get_name() == "Windows":
		err = OS.execute("cmd", ["/c", "rmdir", "/s", "/q", abs_path], [], true, false)
	else:
		err = OS.execute("rm", ["-rf", abs_path], [], true, false)
	return err == 0


## 读 session 的消息数组
func read_messages(id: String) -> Array:
	var path := SESSIONS_ROOT.path_join(id).path_join("messages.json")
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var content := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []


## 写 session 的消息数组 + 更新 message_count + updated_at
func write_messages(id: String, messages: Array) -> bool:
	var info := _read_session_meta(id)
	if info.is_empty():
		return false
	info["message_count"] = messages.size()
	info["updated_at"] = _now_str()
	_write_session_meta(id, info)
	_write_messages_file(id, messages)
	return true


## 从 source_id fork 出新 session(复制消息)
func fork_session(source_id: String, new_name: String = "") -> Dictionary:
	var src_msgs := read_messages(source_id)
	var new_info := create_session(new_name if new_name != "" else "Fork of " + source_id, source_id)
	# 复制消息(去掉 source 的 system prompt 里的动态上下文,避免老数据污染)
	var cleaned: Array = []
	for m in src_msgs:
		var copy: Dictionary = m.duplicate(true)
		cleaned.append(copy)
	write_messages(new_info["id"], cleaned)
	return new_info


## 读单个 session 的元数据
func get_session(id: String) -> Dictionary:
	return _read_session_meta(id)


## 搜索(按 name 或 id 包含 query)
func search_sessions(query: String, limit: int = 50) -> Array:
	query = query.to_lower()
	var all := list_sessions(0)
	var matched: Array = []
	for s in all:
		var n: String = s.get("name", "").to_lower()
		var i: String = s.get("id", "").to_lower()
		if n.contains(query) or i.contains(query):
			matched.append(s)
			if limit > 0 and matched.size() >= limit:
				break
	return matched


# ============ 内部 ============

func _read_session_meta(id: String) -> Dictionary:
	var path := SESSIONS_ROOT.path_join(id).path_join("session.json")
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var content := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) == TYPE_DICTIONARY:
		parsed["path"] = SESSIONS_ROOT.path_join(id)
		return parsed
	return {}


func _write_session_meta(id: String, info: Dictionary) -> void:
	var dir_path := SESSIONS_ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var path := dir_path.path_join("session.json")
	# 不存 path 字段(那是运行时算的)
	var to_write := info.duplicate()
	to_write.erase("path")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SessionStore] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(to_write, "  "))
	f.close()


func _write_messages_file(id: String, messages: Array) -> void:
	var dir_path := SESSIONS_ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var path := dir_path.path_join("messages.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SessionStore] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(messages))
	f.close()


func _generate_id() -> String:
	# 跟 logger 同样的格式:YYYY-MM-DD_HH-MM-SS,加 _NNNN 后缀防同秒冲突
	var base := Time.get_datetime_string_from_system(true).replace(":", "-").replace("T", "_")
	if base.contains("."):
		base = base.split(".")[0]
	var id := base
	var n := 1
	while DirAccess.dir_exists_absolute(SESSIONS_ROOT.path_join(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


func _now_str() -> String:
	var s := Time.get_datetime_string_from_system(true)
	if s.contains("."):
		s = s.split(".")[0]
	return s


func _default_name(id: String) -> String:
	# 把 YYYY-MM-DD_HH-MM-SS 转成 "Session @ MM-DD HH:MM"
	var parts := id.split("_")
	if parts.size() < 2:
		return id
	return "Session @ %s %s" % [parts[0].substr(5), parts[1].replace("-", ":")]
