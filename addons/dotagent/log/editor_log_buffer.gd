@tool
class_name EditorLogBuffer
extends RefCounted
## 编辑器日志拦截器 —— 用 Godot 4.5 的 Logger API 在内存中缓冲 Output 面板消息
##
## 用法:
##   plugin.gd:  EditorLogBuffer.start()
##   exec_tools: EditorLogBuffer.get_recent(50)
##
## 优化: 使用循环缓冲区（head/tail 索引）避免 Array.pop_front() 的 O(n)

const MAX_LINES := 1000

static var _ring: Array[String] = []  # 固定 MAX_LINES 大小,空槽位保留
static var _head: int = 0  # 下一个写入位置
static var _count: int = 0  # 当前已填充行数
static var _logger: Logger = null


class RingBufferLogger extends Logger:
	func _log_message(message: String, error: bool) -> void:
		var prefix := "[stderr] " if error else ""
		EditorLogBuffer._append(prefix + message)

	func _log_error(
			function: String,
			file: String,
			line: int,
			code: String,
			rationale: String,
			editor_notify: bool,
			error_type: int,
			script_backtraces: Array[ScriptBacktrace]
	) -> void:
		var type_name := "UNKNOWN"
		match error_type:
			ERROR_TYPE_ERROR: type_name = "ERROR"
			ERROR_TYPE_WARNING: type_name = "WARNING"
			ERROR_TYPE_SCRIPT: type_name = "SCRIPT"
			ERROR_TYPE_SHADER: type_name = "SHADER"
		var msg := "[%s] %s" % [type_name, rationale]
		if not file.is_empty():
			msg += " (%s:%d)" % [file, line]
		EditorLogBuffer._append(msg)


## O(1) 写入,满时覆盖最旧
static func _append(msg: String) -> void:
	if _ring.size() < MAX_LINES:
		_ring.append(msg)
		_count = _ring.size()
		_head = (_head + 1) % MAX_LINES
	else:
		_ring[_head] = msg
		_head = (_head + 1) % MAX_LINES


static func start() -> void:
	if _logger != null:
		return
	_logger = RingBufferLogger.new()
	OS.add_logger(_logger)


static func stop() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


## 按时间顺序返回最近 max_lines 行(最早的在最前)
static func get_recent(max_lines: int = 50) -> String:
	if _count == 0:
		return "(no editor output captured yet)"
	var n := min(max_lines, _count)
	# 计算起点: 最早的 n 条
	var start := 0
	if _count > MAX_LINES:
		# 已满,_head 是下一个写入位置(即最旧)
		start = _head
	# 取最后 n 条
	var result: Array = []
	var total := min(_count, MAX_LINES)
	var from := max(0, total - n)
	for i in range(n):
		var idx: int = (start + from + i) % MAX_LINES
		result.append(_ring[idx])
	return "[last %d of %d captured lines]\n%s" % [result.size(), _count, "\n".join(result)]
