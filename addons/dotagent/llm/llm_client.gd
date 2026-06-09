@tool
class_name LLMClient
extends RefCounted

var _logger: SessionLog = SessionLog.instance()
## OpenAI 兼容 LLM 客户端,支持流式响应 (SSE)
##
## 用法:
##   client = LLMClient.new()
##   client.tool_registry = some_tool_registry
##   client.chunk_received.connect(_on_chunk)
##   client.stream_finished.connect(_on_done)
##   client.chat_stream(messages, tools_definitions)
##   await client.request_completed

signal chunk_received(chunk: String)
signal stream_finished(content: String, tool_calls: Array, finish_reason: String)
signal stream_error(error: String)
signal request_completed
signal progress_remaining(seconds: float)  # watchdog 剩余时间,每秒 emit 一次
signal progress_done()  # 请求结束(成功/失败/取消)时 emit

const REQUEST_TIMEOUT := 120.0
const TEST_WATCHDOG_TIMEOUT := 10.0  # Test Connection 用,快速失败反馈
const CHAT_WATCHDOG_TIMEOUT := 120.0  # 正常对话用。大上下文下 LLM 首 token 可能 60-90s，留足余量

var tool_registry: ToolRegistry
var _host_node: Node = null  # 用来挂载 HTTPRequest 的宿主节点
var _http: HTTPRequest = null
var _config: ConfigManager = null
var _stream_buffer: PackedByteArray = PackedByteArray()
var _accumulated_content: String = ""
var _accumulated_tool_calls: Array = []
var _accumulated_finish_reason: String = ""  # LLM API 的 finish_reason:"stop"/"tool_calls"/"length"
var _abort: bool = false
var _active: bool = false
var _watchdog_id: int = 0
var _watchdog_timeout: float = CHAT_WATCHDOG_TIMEOUT
var _last_activity: float = 0.0  # 上次收到数据的时刻，动态看门狗用


func _init() -> void:
	_config = ConfigManager.instance()


## 设置宿主节点(HTTPRequest 必须挂在 SceneTree 上才能工作)。
## 通常在 Dock 里 set 调用,把 dock 自身作为 host。
func set_host(node: Node) -> void:
	_host_node = node


## 发起一次聊天请求。完成后通过 signal 通知。
## timeout: 自定义 watchdog 超时(秒)。<0 用 CHAT_WATCHDOG_TIMEOUT(60s),
##       Test Connection 传 10.0 走 TEST_WATCHDOG_TIMEOUT 行为。
func chat_stream(messages: Array, tools: Array, timeout: float = -1.0) -> Error:
	if _active:
		stream_error.emit("已有请求在进行中")
		request_completed.emit()  # 一定要 emit,否则调用方 await 死锁
		return ERR_BUSY
	if _host_node == null or not is_instance_valid(_host_node):
		stream_error.emit("Host node not set. Call set_host() first.")
		request_completed.emit()
		return ERR_UNCONFIGURED
	_active = true
	_abort = false
	_stream_buffer = PackedByteArray()
	_accumulated_content = ""
	_accumulated_tool_calls = []
	_accumulated_finish_reason = ""
	_last_activity = Time.get_ticks_msec() / 1000.0

	# 动态看门狗：每收到数据重置计时，只有数据完全停止 25s 才超时
	var watchdog_t: float = timeout if timeout > 0.0 else CHAT_WATCHDOG_TIMEOUT
	_start_watchdog(watchdog_t)

	# 创建 HTTPRequest(每次新建,避免状态污染)
	# Godot 4.5 没有 streaming_mode 字段 — 我们在 _on_request_completed 一次性拿完整 body
	# 然后切 SSE events 推给 UI,本身就是"逐段蹦出来"的体验
	_http = HTTPRequest.new()
	_host_node.add_child(_http)
	_http.timeout = REQUEST_TIMEOUT
	_http.request_completed.connect(_on_request_completed)

	var url := _normalize_url(_config.get_base_url())
	if not _config.is_configured():
		stream_error.emit("API 未配置(Base URL 或 API Key 为空)")
		_cleanup()
		request_completed.emit()
		return ERR_UNCONFIGURED

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _config.get_api_key(),
		"Accept: text/event-stream",
	]
	var body := _build_request_body(messages, tools, true)

	_logger.append("LLM", "POST %s" % url)
	_logger.append("LLM", "model=%s messages=%d tools=%d body=%dKB" % [_config.get_model(), messages.size(), tools.size(), body.length() / 1024])

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		stream_error.emit("HTTPRequest.request 失败: %d (可能 URL 格式错或网络问题)" % err)
		_cleanup()
		request_completed.emit()
	return err


func _note_activity() -> void:
	_last_activity = Time.get_ticks_msec() / 1000.0


func _start_watchdog(timeout: float = CHAT_WATCHDOG_TIMEOUT) -> void:
	_watchdog_id += 1
	_watchdog_timeout = timeout
	var my_id := _watchdog_id
	_countdown_loop(my_id, timeout)


## 每秒检查：距离上次收到数据是否超过 timeout 秒
func _countdown_loop(my_id: int, total: float = CHAT_WATCHDOG_TIMEOUT) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	progress_remaining.emit(total)
	while _active and not _abort:
		await tree.create_timer(1.0).timeout
		if not _active or _abort or my_id != _watchdog_id:
			return
		var elapsed := Time.get_ticks_msec() / 1000.0 - _last_activity
		var remaining := max(0.0, total - elapsed)
		if remaining <= 0.0:
			_on_watchdog()
			return
		progress_remaining.emit(remaining)


func _on_watchdog() -> void:
	if not _active:
		return
	_logger.warn("Watchdog timeout — %.0fs 内无任何数据" % _watchdog_timeout)
	stream_error.emit("Watchdog: %.0f 秒内未收到任何响应数据。\n" % _watchdog_timeout +
		"  • AI 可能在处理大量数据 — 试试 Compact 或简化请求\n" +
		"  • 网络或 API 问题 — 检查 Settings 里的 Base URL 和 API Key")
	# 主动 cancel
	if _http and is_instance_valid(_http):
		_http.cancel_request()
	_cleanup()
	request_completed.emit()


func abort() -> void:
	_abort = true
	if _http and is_instance_valid(_http):
		_http.cancel_request()
	_cleanup()
	request_completed.emit()


# ============ 内部 ============

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _abort:
		_cleanup()
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		var result_name := _result_name(result)
		stream_error.emit("网络错误: %s (result=%d)。可能:网络不通 / DNS 失败 / 证书问题 / URL 错" % [result_name, result])
		_cleanup()
		request_completed.emit()
		return

	if response_code < 200 or response_code >= 300:
		var err_text := body.get_string_from_utf8()
		stream_error.emit("HTTP %d: %s" % [response_code, err_text.substr(0, 500)])
		_cleanup()
		request_completed.emit()
		return

	_logger.append("LLM", "HTTP %d, body size=%d bytes" % [response_code, body.size()])
	_note_activity()  # 收到 HTTP 响应，重置看门狗

	# 解析 SSE 流
	# OpenAI 兼容 SSE 格式:
	#   data: {"choices":[{"delta":{...}}]}\n\n
	#   data: [DONE]\n\n
	_parse_sse(body)

	_logger.append("LLM", "SSE parsed: content_len=%d, tool_calls=%d" % [_accumulated_content.length(), _accumulated_tool_calls.size()])
	stream_finished.emit(_accumulated_content, _accumulated_tool_calls, _accumulated_finish_reason)
	_cleanup()
	request_completed.emit()


func _result_name(r: int) -> String:
	match r:
		HTTPRequest.RESULT_SUCCESS: return "SUCCESS"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: return "CHUNKED_BODY_SIZE_MISMATCH"
		HTTPRequest.RESULT_CANT_CONNECT: return "CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE: return "CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "CONNECTION_ERROR"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "TLS_HANDSHAKE_ERROR"
		HTTPRequest.RESULT_NO_RESPONSE: return "NO_RESPONSE"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "BODY_SIZE_LIMIT_EXCEEDED"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: return "BODY_DECOMPRESS_FAILED"
		HTTPRequest.RESULT_REQUEST_FAILED: return "REQUEST_FAILED"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: return "DOWNLOAD_FILE_CANT_OPEN"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: return "DOWNLOAD_FILE_WRITE_ERROR"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "REDIRECT_LIMIT_REACHED"
		HTTPRequest.RESULT_TIMEOUT: return "TIMEOUT"
		_: return "UNKNOWN"


func _parse_sse(body: PackedByteArray) -> void:
	# 把字节流转字符串
	var text := body.get_string_from_utf8()
	# SSE 用 \n\n 分隔事件,有时 \r\n\r\n
	var events := text.split("\n\n", false)
	for event_text in events:
		if _abort:
			break
		event_text = event_text.strip_edges()
		if event_text.is_empty():
			continue
		var data_lines := []
		for line in event_text.split("\n", false):
			if line.begins_with("data:"):
				var payload := line.substr(5).strip_edges()
				if payload == "[DONE]":
					continue
				data_lines.append(payload)
		if data_lines.is_empty():
			continue
		var json_text := "\n".join(data_lines)
		var json := JSON.new()
		if json.parse(json_text) != OK:
			_logger.warn("SSE JSON parse error: %s" % json_text.substr(0, 200))
			continue
		var obj: Variant = json.data
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var choices: Array = obj.get("choices", [])
		if choices.is_empty():
			continue
		var choice: Dictionary = choices[0]
		var delta: Dictionary = choice.get("delta", {})

		# finish_reason — LLM 告诉我们它是否结束了
		var fr: String = str(choice.get("finish_reason", ""))
		if fr != "":
			_accumulated_finish_reason = fr

		# content — LLM 流式时,空 delta 的 content 字段是 null 不是 ""
		var content_chunk := _get_string(delta, "content")
		if content_chunk != "":
			_accumulated_content += content_chunk
			chunk_received.emit(content_chunk)
			_note_activity()  # 收到流式数据，重置看门狗

		# tool_calls — accumulate streaming chunks into indexed array
		if delta.has("tool_calls"):
			for tc in delta.get("tool_calls", []):
				_accumulate_tool_call_chunk(tc)
				_note_activity()  # tool_calls data also resets watchdog


## Accumulate a streaming tool_calls chunk into _accumulated_tool_calls[index].
## Streaming format: id/name only in first chunk, arguments appended across chunks.
func _accumulate_tool_call_chunk(tc: Dictionary) -> void:
	var idx: int = int(tc.get("index", 0))
	while _accumulated_tool_calls.size() <= idx:
		_accumulated_tool_calls.append({"id": "", "type": "function", "function": {"name": "", "arguments": ""}})
	var acc: Dictionary = _accumulated_tool_calls[idx]
	if tc.has("id") and tc.get("id", "") != "":
		acc["id"] = tc.get("id")
	var fn: Dictionary = tc.get("function", {})
	var fn_name := _get_string(fn, "name")
	if fn_name != "":
		acc["function"]["name"] = fn_name
	if fn.has("arguments") and fn.get("arguments") != null:
		acc["function"]["arguments"] += str(fn.get("arguments", ""))


func _build_request_body(messages: Array, tools: Array, stream: bool) -> String:
	# Convert messages with images to multimodal format.
	# Images can be res:// paths (PNG files) — the client reads and base64-encodes them.
	var processed: Array = []
	for msg in messages:
		var images: Array = msg.get("images", [])
		if images.is_empty():
			processed.append(msg)
			continue

		var content_raw = msg.get("content", null)
		var text: String = str(content_raw) if content_raw != null else ""
		var parts: Array = [{"type": "text", "text": text}]

		for img in images:
			var img_str: String = str(img)
			# If it's a res:// path, read the file and encode to base64 data URI
			if img_str.begins_with("res://"):
				var uri := _file_to_data_uri(img_str)
				if not uri.is_empty():
					parts.append({"type": "image_url", "image_url": {"url": uri}})
			elif img_str.begins_with("data:"):
				parts.append({"type": "image_url", "image_url": {"url": img_str}})

		processed.append({"role": msg.get("role", "user"), "content": parts})

	var body := {
		"model": _config.get_model(),
		"messages": processed,
		"temperature": _config.get_temperature(),
		"max_tokens": _config.get_max_tokens() * 1000,
		"stream": stream,
	}
	if not tools.is_empty():
		# Auto-compress descriptions: first sentence only — cuts ~40% request size
		var brief_tools: Array = []
		for t in tools:
			var bt := t.duplicate()
			if t.has("description_brief") and not t.get("description_brief", "").is_empty():
				bt["description"] = t.get("description_brief")
			else:
				var desc: String = t.get("description", "")
				var dot := desc.find(". ")
				if dot > 0 and dot < 150:
					bt["description"] = desc.substr(0, dot + 1)  # first sentence
				elif desc.length() > 150:
					bt["description"] = desc.substr(0, 150) + "…"
			bt.erase("description_brief")
			brief_tools.append(bt)
		body["tools"] = brief_tools
		body["tool_choice"] = "auto"
	return JSON.stringify(body)


## Read a PNG file at res:// path and convert to data:image/png;base64,... URI.
func _file_to_data_uri(path: String) -> String:
	if not FileAccess.file_exists(path):
		_logger.warn("Image not found: " + path)
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var data := f.get_buffer(f.get_length())
	f.close()
	return "data:image/png;base64," + Marshalls.raw_to_base64(data)


func _normalize_url(base: String) -> String:
	var url := base.strip_edges()
	if url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	if not url.ends_with("/chat/completions"):
		url = url + "/chat/completions"
	return url


func _cleanup() -> void:
	if not _active:
		return  # 防止重复 emit
	_active = false
	progress_done.emit()
	if _http and is_instance_valid(_http):
		_http.queue_free()
		_http = null


## 安全的字典取值。LLM 返回的 JSON 里经常有 "content": null(不是 "" 不是缺 key),
## 用 .get(key, default) 不会触发 default — 会拿到存的 null,导致 typed 赋值崩。
## 这个 helper 统一处理:key 不存在 / 值为 null / 值为非字符串,都返回 default。
func _get_string(d: Dictionary, key: String, default: String = "") -> String:
	if not d.has(key):
		return default
	var v = d[key]
	if v == null:
		return default
	return str(v)
