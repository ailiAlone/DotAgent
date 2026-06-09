@tool
class_name SessionLog
extends RefCounted
## 会话日志收集器
##
## 每次用户发消息时:
## 1. start_session() — 在 res://logs/<时间戳>/ 建目录
## 2. 期间所有 append() 调用同时 print 到 Godot console + 存 buffer
## 3. 结束时 end_session(messages) — 写 conversation.md / editor_output.txt / meta.json
##
## **类名不能用 "Logger",方法名不能用 "log"** — Godot 4.5 有 native 类 Logger 自带 .log(float) 方法,
## 会让 GDScript 类型推断错乱。所以这里用 SessionLog / append

const LOG_ROOT := "res://addons/dotagent/logs"

var _buffer: Array[String] = []
var _session_dir: String = ""
var _session_id: String = ""

static var _instance: SessionLog = null

## 单例入口
static func instance() -> SessionLog:
	if _instance == null:
		_instance = SessionLog.new()
	return _instance


## 开始新会话(用户发消息时调用)
func start_session() -> String:
	var dt := Time.get_datetime_string_from_system(false).replace(":", "-").replace("T", "_")
	# 把小数秒去掉(YYYY-MM-DD_HH-MM-SS 长度固定)
	# Time 格式: 2026-06-07T14:30:25.123 → 2026-06-07_14-30-25
	# 但 .123 还在,需要截断
	if dt.contains("."):
		dt = dt.split(".")[0]
	_session_id = dt
	_session_dir = LOG_ROOT.path_join(dt)
	DirAccess.make_dir_recursive_absolute(_session_dir)
	_buffer.clear()
	append("SESSION", "=== Session started: %s ===" % dt)
	return _session_id


## 结束会话,写入文件
## messages: _messages 数组(Dictionary 列表,role+content+tool_calls)
## meta_extra: 额外元信息(消息数、工具数等)
func end_session(messages: Array, meta_extra: Dictionary = {}) -> void:
	append("SESSION", "=== Session ended ===")
	_write_editor_output()
	_write_conversation_md(messages)
	_write_messages_json(messages)
	_write_meta(messages, meta_extra)
	_buffer.clear()
	_session_dir = ""
	_session_id = ""


## 一行 log:同时 print 到 Godot console + 写 buffer + 实时落盘 editor_output.txt
## 每行立即 flush 到磁盘，确保崩溃时不丢日志。
func append(source: String, text: String) -> void:
	var t := Time.get_time_string_from_system()
	var line := "%s [%s] %s" % [t, source, text]
	if _session_id.is_empty():
		print(line)
		return
	_buffer.append(line)
	print(line)
	# 实时追加写入 editor_output.txt，每次只追加一行
	_flush_line(line)


## 警告:同时 push_warning(让 Godot 红色标) + 写 log
func warn(text: String) -> void:
	push_warning(text)
	append("WARN", text)


## 错误:同时 push_error(让 Godot 红色标) + 写 log
func error(text: String) -> void:
	push_error(text)
	append("ERROR", text)


## 当前 session 目录(空字符串 = 不在 session 里)
func get_session_dir() -> String:
	return _session_dir


# ============ 内部:写文件 ============

func _write_editor_output() -> void:
	var path := _session_dir.path_join("editor_output.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Logger] Cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string("\n".join(_buffer))
	f.store_string("\n\n# 注意：Godot 引擎级错误(push_error)无法被插件捕获，请查看 Godot 编辑器的 Output 面板")
	f.close()


## 实时写入 editor_output.txt（每行 log 触发一次，确保崩溃时不丢日志）
func _flush_line(_line: String) -> void:
	var path := _session_dir.path_join("editor_output.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(_buffer))
	f.close()


func _write_conversation_md(messages: Array) -> void:
	var path := _session_dir.path_join("conversation.md")
	var lines: Array[String] = []
	lines.append("# AI Panel Session — %s" % _session_id)
	lines.append("")
	lines.append("Started: %s" % _session_id.replace("_", " "))
	lines.append("")
	lines.append("---")
	lines.append("")
	for msg in messages:
		var role: String = msg.get("role", "?")
		# 关键:不能用 msg.get("content", "") 然后 typed 赋值
		# 当 LLM 返回 content=null 时,get 不会触发 default,直接拿到 null → 崩
		# 用 Variant 中间变量判断 nil
		var content_raw = msg.get("content", null)
		var content: String = str(content_raw) if content_raw != null else ""
		match role:
			"system":
				lines.append("## system")
				lines.append("")
				lines.append("```")
				lines.append(content)
				lines.append("```")
				lines.append("")
			"user":
				lines.append("## 👤 User")
				lines.append("")
				lines.append(content)
				lines.append("")
			"assistant":
				lines.append("## 🤖 Assistant")
				lines.append("")
				if content != "":
					lines.append(content)
					lines.append("")
				# tool_calls
				var tool_calls: Array = msg.get("tool_calls", [])
				if not tool_calls.is_empty():
					for tc in tool_calls:
						var name: String = tc.get("function", {}).get("name", "?")
						var args_raw: String = tc.get("function", {}).get("arguments", "{}")
						lines.append("**🔧 %s**" % name)
						lines.append("")
						lines.append("```json")
						lines.append(args_raw)
						lines.append("```")
						lines.append("")
			"tool":
				var tool_call_id: String = msg.get("tool_call_id", "?")
				lines.append("**⬅️ Tool result** (`%s`)" % tool_call_id)
				lines.append("")
				lines.append("```")
				lines.append(content)
				lines.append("```")
				lines.append("")
			_:
				lines.append("## %s" % role)
				lines.append("")
				lines.append(content)
				lines.append("")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Logger] Cannot write %s" % path)
		return
	f.store_string("\n".join(lines))
	f.close()


func _write_meta(messages: Array, extra: Dictionary) -> void:
	var path := _session_dir.path_join("meta.json")
	var user_count := 0
	var assistant_count := 0
	var tool_call_count := 0
	for msg in messages:
		match msg.get("role", ""):
			"user": user_count += 1
			"assistant":
				assistant_count += 1
				tool_call_count += msg.get("tool_calls", []).size()
	var meta := {
		"session_id": _session_id,
		"started_at": _session_id.replace("_", " "),
		"message_count": messages.size(),
		"user_messages": user_count,
		"assistant_messages": assistant_count,
		"tool_calls": tool_call_count,
	}
	for k in extra.keys():
		meta[k] = extra[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Logger] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(meta, "  "))
	f.close()


# ============ 内部 ============

func _write_messages_json(messages: Array) -> void:
	# 写一个 messages.json 给 load_session 工具和 UI 用
	# 不写 conversation.md 那套 markdown 格式(对机器不友好)
	var path := _session_dir.path_join("messages.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[Logger] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(messages))
	f.close()
