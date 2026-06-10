@tool
class_name EditorLogBuffer
extends RefCounted
## 编辑器日志拦截器 —— 用 Godot 4.5 的 Logger API 在内存中缓冲 Output 面板消息
##
## 用法:
##   plugin.gd:  EditorLogBuffer.start()
##   exec_tools: EditorLogBuffer.get_recent(50)

const MAX_LINES := 1000

static var _lines: Array[String] = []
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


static func _append(msg: String) -> void:
	_lines.append(msg)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()


static func start() -> void:
	if _logger != null:
		return
	_logger = RingBufferLogger.new()
	OS.add_logger(_logger)


static func stop() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


static func get_recent(max_lines: int = 50) -> String:
	if _lines.is_empty():
		return "(no editor output captured yet)"
	var start := max(0, _lines.size() - max_lines)
	var result: Array = []
	for i in range(start, _lines.size()):
		result.append(_lines[i])
	return "[last %d of %d captured lines]\n%s" % [result.size(), _lines.size(), "\n".join(result)]
