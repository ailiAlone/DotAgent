@tool
class_name Reactor
extends RefCounted
## ReAct 循环核心
##
## 职责: LLM 流式请求 ↔ 工具执行 ↔ 结果反馈的闭环循环。
## 不持有 messages — 通过参数接收,直接修改(引用传递)。
##
## 使用方式:
##   reactor.setup(plugin, messages, logger, context_builder, tool_registry, host_node)
##   await reactor.run(messages)

signal stream_started()
signal stream_chunk(chunk: String)
signal round_complete(content: String, tool_calls: Array, tool_results: Array)
signal stream_error(error: String)
signal progress_remaining(seconds: float)
signal progress_done()
signal tool_started(tool_name: String)
signal tool_finished(tool_name: String, ok: bool)
signal loop_finished()

var _llm_client: LLMClient
var _tool_registry: ToolRegistry
var _message_builder: MessageBuilder
var _context_builder: ContextBuilder
var _logger: SessionLog
var _plugin: Object

var _running: bool = false
var _abort_requested: bool = false
var _stream_content: String = ""
var _pending_tool_calls: Array = []
var _pending_finish_reason: String = ""
var _round_tool_results: Array = []
var _round_num: int = 0


func setup(p_plugin: Object, p_messages: Array[Dictionary], p_logger: SessionLog, p_context_builder: ContextBuilder, p_tool_registry: ToolRegistry, p_host_node: Node) -> void:
	_plugin = p_plugin
	_logger = p_logger
	_context_builder = p_context_builder
	_tool_registry = p_tool_registry

	_llm_client = LLMClient.new()
	p_host_node.add_child(_llm_client)
	_llm_client.tool_registry = _tool_registry

	_message_builder = MessageBuilder.new()
	_message_builder.setup(p_messages, _logger)

	_llm_client.chunk_received.connect(_on_stream_chunk)
	_llm_client.stream_finished.connect(_on_stream_finished)
	_llm_client.stream_error.connect(_on_stream_error)
	_llm_client.progress_remaining.connect(_on_progress_remaining)
	_llm_client.progress_done.connect(_on_progress_done)


func run(messages: Array[Dictionary]) -> void:
	_running = true
	_abort_requested = false
	_round_num = 0

	while true:
		if _abort_requested:
			break

		# 同步 messages 引用（DockController 在 bootstrap 后可能重新赋值了 _messages）
		_message_builder.resync(messages)
		_context_builder.resync(messages)
		_context_builder.update_system_message()

		_round_num += 1
		_logger.record_round_start(_round_num)

		_stream_content = ""
		_pending_tool_calls = []
		_pending_finish_reason = ""
		_round_tool_results = []

		stream_started.emit()

		# 构建压缩发送消息，然后调 LLM
		var send_msgs := _message_builder.build()
		var tools_def := _tool_registry.get_tool_definitions()
		var err: int = _llm_client.chat_stream(send_msgs, tools_def)
		if err != OK:
			stream_error.emit("chat_stream failed: %d" % err)
			_logger.record_round_end("")
			break
		await _llm_client.request_completed

		if _abort_requested:
			_logger.record_round_end("")
			break

		# 处理响应 — 用 finish_reason 判断，不是 tool_calls 判空
		_logger.append("LLM", "finish_reason=%s tool_calls=%d" % [_pending_finish_reason, _pending_tool_calls.size()])
		if _pending_finish_reason == "tool_calls" or _pending_tool_calls.size() > 0:
			messages.append({
				"role": "assistant",
				"content": _stream_content if _stream_content != "" else null,
				"tool_calls": _pending_tool_calls.duplicate(true),
			})
			await _execute_tool_round(messages)
			# 稳定延迟
			await Engine.get_main_loop().create_timer(0.3).timeout
			_logger.record_round_end(_stream_content)
			round_complete.emit(_stream_content, _pending_tool_calls.duplicate(true), _round_tool_results.duplicate(true))
			continue
		else:
			# 无 tool call，纯文本
			if _stream_content != "":
				messages.append({"role": "assistant", "content": _stream_content})
			_logger.record_round_end(_stream_content)
			round_complete.emit(_stream_content, [], [])
			break

	_running = false
	loop_finished.emit()
	progress_done.emit()
	_deferred_filesystem_refresh()


func abort() -> void:
	_abort_requested = true
	_llm_client.abort()
	_running = false
	progress_done.emit()


func is_running() -> bool:
	return _running


# ============ 工具执行 ============

func _execute_tool_round(messages: Array[Dictionary]) -> void:
	for tc in _pending_tool_calls:
		if _abort_requested:
			break
		var tc_id: String = tc.get("id", "")
		var fn: Dictionary = tc.get("function", {})
		var tc_name: String = fn.get("name", "")
		var tc_args_raw: String = fn.get("arguments", "{}")
		tool_started.emit(tc_name)
		var result: Dictionary = await _tool_registry.execute_tool(tc_name, tc_args_raw)
		var ok: bool = result.get("ok", true)
		tool_finished.emit(tc_name, ok)
		_round_tool_results.append({"name": tc_name, "ok": ok})
		messages.append({"role": "tool", "tool_call_id": tc_id, "content": result.get("content", "")})

		# analyze_image 即时注入：图片在下一轮 ReAct 就会被视觉模型分析
		if tc_name == "analyze_image" and ok:
			_inject_image_for_next_round(messages, result.get("content", ""))


## 检测 analyze_image 返回的即时编码结果，注入 system 消息供下轮 LLM 分析
func _inject_image_for_next_round(messages: Array[Dictionary], tool_content: String) -> void:
	var parsed: Variant = JSON.parse_string(tool_content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if d.get("type", "") != "analyze_image_inline":
		return
	var data_uri: String = d.get("data_uri", "")
	if data_uri.is_empty():
		return
	messages.append({
		"role": "user",
		"content": "[视觉分析回调 — 这不是用户的新指令，是 analyze_image 工具的返回结果]\n" + d.get("question", ""),
		"images": [data_uri],
	})
	_logger.append("IMAGE", "Injected image for next round: %s" % d.get("path", "?").get_file())


# ============ 图片处理 ============

# ============ 文件系统刷新 ============

func _deferred_filesystem_refresh() -> void:
	if _plugin == null:
		return
	var ei = _plugin.get_editor_interface()
	if ei == null:
		return
	var fs = ei.get_resource_filesystem()
	if fs == null:
		return
	# 延迟一帧再 scan，避免与编辑器自身文件监控冲突
	await Engine.get_main_loop().create_timer(0.5).timeout
	fs.scan()
	_logger.append("LLM", "Deferred filesystem scan complete")


# ============ LLM 流式回调 ============

func _on_stream_chunk(chunk: String) -> void:
	_stream_content += chunk
	stream_chunk.emit(chunk)


func _on_stream_finished(content: String, tool_calls: Array, finish_reason: String) -> void:
	_stream_content = content
	_pending_tool_calls = tool_calls
	_pending_finish_reason = finish_reason
	_logger.record_llm_response(finish_reason, tool_calls.size(), content.length())


func _on_stream_error(error: String) -> void:
	stream_error.emit(error)
	_running = false


func _on_progress_remaining(seconds: float) -> void:
	progress_remaining.emit(seconds)


func _on_progress_done() -> void:
	progress_done.emit()
