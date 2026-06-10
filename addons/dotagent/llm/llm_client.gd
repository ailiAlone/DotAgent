@tool
class_name LLMClient
extends Node
## OpenAI-compatible LLM client with TRUE streaming via HTTPClient polling.
##
## Usage:
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
signal progress_remaining(seconds: float)
signal progress_done()

const REQUEST_TIMEOUT := 120.0
const TEST_WATCHDOG_TIMEOUT := 10.0
const CHAT_WATCHDOG_TIMEOUT := 20.0  # 流式响应应该持续有输出，20s 无数据 = 连接僵死
const MAX_RETRIES := 3  # 僵死后自动重试

var tool_registry: ToolRegistry
var _logger: SessionLog = SessionLog.instance()
var _config: ConfigManager = null
var _client: HTTPClient = null
var _host: String = ""
var _port: int = 443
var _request_data: PackedByteArray = PackedByteArray()
var _request_path: String = "/"
var _sse_buf: String = ""
var _stream_done: bool = false

var _accumulated_content: String = ""
var _accumulated_tool_calls: Array = []
var _accumulated_finish_reason: String = ""
var _abort: bool = false
var _active: bool = false
var _watchdog_id: int = 0
var _watchdog_timeout: float = CHAT_WATCHDOG_TIMEOUT
var _last_activity: float = 0.0
var _retry_count: int = 0  # 当前已重试次数


func _init() -> void:
	_config = ConfigManager.instance()


func _ready() -> void:
	pass


func chat_stream(messages: Array, tools: Array, timeout: float = -1.0) -> Error:
	if _active:
		stream_error.emit("已有请求在进行中")
		request_completed.emit()
		return ERR_BUSY

	_active = true
	_abort = false
	_retry_count = 0
	_accumulated_content = ""
	_accumulated_tool_calls = []
	_accumulated_finish_reason = ""
	_sse_buf = ""
	_stream_done = false
	_last_activity = Time.get_ticks_msec() / 1000.0
	_poll_state = PollState.IDLE
	_poll_timer = 0.0

	var url := _normalize_url(_config.get_base_url())
	if not _config.is_configured():
		stream_error.emit("API not configured (Base URL or API Key)")
		_cleanup()
		request_completed.emit()
		return ERR_UNCONFIGURED

	_parse_url(url)
	_request_data = _build_request_body(messages, tools, true).to_utf8_buffer()

	# 动态超时：body 越大，首次响应给越多时间；后续重试用基础超时
	var dynamic_timeout: float = timeout
	if dynamic_timeout <= 0.0:
		var body_kb := _request_data.size() / 1024
		if body_kb > 150:
			dynamic_timeout = 60.0
		elif body_kb > 80:
			dynamic_timeout = 40.0
		elif body_kb > 40:
			dynamic_timeout = 30.0
		else:
			dynamic_timeout = CHAT_WATCHDOG_TIMEOUT
	_start_watchdog(dynamic_timeout)
	_client = HTTPClient.new()

	_logger.append("LLM", "POST %s" % url)
	_logger.append("LLM", "model=%s messages=%d tools=%d body=%dKB" % [_config.get_model(), messages.size(), tools.size(), _request_data.size() / 1024])

	_connect_and_send()
	return OK


## 发起连接并发送请求（首次 + 重试共用）
func _connect_and_send() -> void:
	if _client == null:
		_client = HTTPClient.new()
	var err := _client.connect_to_host(_host, _port, TLSOptions.client())
	if err != OK:
		_on_http_error("Failed to connect: %d" % err)
		return
	_logger.append("LLM", "Waiting for connection...")
	_poll_state = PollState.CONNECTING
	_poll_timer = 0.0
	set_process(true)


# ============ _process() 驱动的状态机（免疫脚本重载） ============
# 不用 await / 协程，不存在 suspended state，脚本重载不会杀流程。

enum PollState { IDLE, CONNECTING, SENDING, WAITING_RESPONSE, READING_BODY, DONE }

var _poll_state: int = PollState.IDLE
var _poll_timer: float = 0.0
const POLL_INTERVAL := 0.05


func _process(delta: float) -> void:
	if not _active or _abort:
		return

	# Watchdog check (merged into _process, no coroutine needed)
	if _watchdog_active:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _last_activity
		if elapsed > _watchdog_timeout:
			_on_watchdog()
			return
		progress_remaining.emit(max(0.0, _watchdog_timeout - elapsed))

	_poll_timer += delta
	if _poll_timer < POLL_INTERVAL:
		return
	_poll_timer = 0.0

	match _poll_state:
		PollState.CONNECTING: _poll_connecting()
		PollState.SENDING: _poll_sending()
		PollState.WAITING_RESPONSE: _poll_waiting_response()
		PollState.READING_BODY: _poll_reading_body()


func _poll_connecting() -> void:
	if _client == null:
		_on_http_error("Client lost during connect")
		return
	_client.poll()
	var status := _client.get_status()
	if status == HTTPClient.STATUS_CONNECTING or status == HTTPClient.STATUS_RESOLVING:
		return  # still connecting
	if status != HTTPClient.STATUS_CONNECTED:
		_on_http_error("Connection failed: status=%d" % status)
		return
	_logger.append("LLM", "Connected, sending request (%d bytes)" % _request_data.size())
	_poll_state = PollState.SENDING
	_poll_timer = 0.0


func _poll_sending() -> void:
	var err := _client.request(HTTPClient.METHOD_POST, _request_path, _headers(), _request_data.get_string_from_utf8())
	if err != OK:
		_on_http_error("Request send failed: %d" % err)
		return
	_poll_state = PollState.WAITING_RESPONSE


func _poll_waiting_response() -> void:
	if _client == null:
		_on_http_error("Client lost")
		return
	_client.poll()
	var status := _client.get_status()
	if status == HTTPClient.STATUS_REQUESTING or status == HTTPClient.STATUS_CONNECTED:
		return  # still waiting
	if status == HTTPClient.STATUS_DISCONNECTED:
		_on_http_error("Server disconnected before response")
		return
	if status != HTTPClient.STATUS_BODY:
		return  # try again next frame

	# Got response body
	_logger.append("LLM", "Response body started (code=%d)" % _client.get_response_code())
	_note_activity()  # HTTP 响应开始也是活动信号，防止 MiniMax 思考超时
	if _client.get_response_code() >= 400:
		var err_body := PackedByteArray()
		while _client.get_status() == HTTPClient.STATUS_BODY:
			err_body.append_array(_client.read_response_body_chunk())
		_on_http_error("HTTP %d: %s" % [_client.get_response_code(), err_body.get_string_from_utf8().substr(0, 500)])
		return

	_stream_done = false
	_read_available_chunks()
	_poll_state = PollState.READING_BODY


func _poll_reading_body() -> void:
	if _abort or _client == null:
		return
	_client.poll()
	_read_available_chunks()
	if _stream_done or not _accumulated_finish_reason.is_empty():
		_try_parse_sse()
		_logger.append("LLM", "Done. content_len=%d, tool_calls=%d" % [_accumulated_content.length(), _accumulated_tool_calls.size()])
		set_process(false)
		_poll_state = PollState.DONE
		stream_finished.emit(_accumulated_content, _accumulated_tool_calls, _accumulated_finish_reason)
		_cleanup()
		request_completed.emit()


func _read_available_chunks() -> void:
	var count := 0
	while _client != null and _client.get_status() == HTTPClient.STATUS_BODY:
		var chunk := _client.read_response_body_chunk()
		if chunk.size() > 0:
			_sse_buf += chunk.get_string_from_utf8()
			_try_parse_sse()
			_note_activity()
		if _stream_done:
			break
		count += 1
		if count > 64:
			return  # yield, continue next frame


func _headers() -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _config.get_api_key(),
		"Accept: text/event-stream",
	]


func _parse_url(url: String) -> void:
	var u := url.trim_prefix("https://").trim_prefix("http://")
	var slash := u.find("/")
	if slash > 0:
		_host = u.substr(0, slash)
		_request_path = u.substr(slash)
	else:
		_host = u
		_request_path = "/"


## Try to extract complete SSE events from buffer.
func _try_parse_sse() -> void:
	while "\n\n" in _sse_buf:
		var idx := _sse_buf.find("\n\n")
		var event_text := _sse_buf.substr(0, idx)
		_sse_buf = _sse_buf.substr(idx + 2)
		_dispatch_sse_event(event_text)
	# If we have data but no complete event, log a peek
	if _sse_buf.length() > 0 and "\n\n" not in _sse_buf:
		var peek := _sse_buf.substr(0, min(200, _sse_buf.length())).replace("\n", "\\n")
		_logger.append("LLM", "SSE buf waiting: %s..." % peek)


func _dispatch_sse_event(event_text: String) -> void:
	event_text = event_text.strip_edges()
	if event_text.is_empty():
		return

	var data_lines: Array = []
	for line in event_text.split("\n", false):
		var s := line.strip_edges()
		if s.begins_with("data:"):
			var payload := s.substr(5).strip_edges()
			if payload == "[DONE]":
				_logger.append("LLM", "SSE [DONE] received, closing stream")
				_stream_done = true
				return
			data_lines.append(payload)

	if data_lines.is_empty():
		return

	var json_text := "\n".join(data_lines)
	var json := JSON.new()
	if json.parse(json_text) != OK:
		_logger.warn("SSE JSON parse error: %s" % json_text.substr(0, 200))
		return

	var obj: Variant = json.data
	if typeof(obj) != TYPE_DICTIONARY:
		return
	var choices: Array = obj.get("choices", [])
	if choices.is_empty():
		return
	var choice: Dictionary = choices[0]
	var delta: Dictionary = choice.get("delta", {})

	var fr: String = str(choice.get("finish_reason", ""))
	if fr != "":
		_accumulated_finish_reason = fr

	var content_chunk := _get_string(delta, "content")
	if content_chunk != "":
		_accumulated_content += content_chunk
		chunk_received.emit(content_chunk)

	if delta.has("tool_calls"):
		for tc in delta.get("tool_calls", []):
			_accumulate_tool_call_chunk(tc)


# ============ Watchdog ============

func _note_activity() -> void:
	_last_activity = Time.get_ticks_msec() / 1000.0
	_retry_count = 0  # 收到数据 → 连接正常，重置重试计数


var _watchdog_active: bool = false

func _start_watchdog(timeout: float = CHAT_WATCHDOG_TIMEOUT) -> void:
	_watchdog_id += 1
	_watchdog_timeout = timeout
	_watchdog_active = true
	progress_remaining.emit(timeout)


func _on_watchdog() -> void:
	if not _active:
		return

	if _retry_count < MAX_RETRIES:
		_retry_count += 1
		_logger.warn("Watchdog timeout — 重试 %d/%d（%.0fs 无数据，连接可能僵死）" % [_retry_count, MAX_RETRIES, _watchdog_timeout])
		# 关闭旧连接，重新发起
		if _client:
			_client.close()
			_client = null
		_accumulated_content = ""
		_accumulated_tool_calls = []
		_accumulated_finish_reason = ""
		_sse_buf = ""
		_stream_done = false
		_last_activity = Time.get_ticks_msec() / 1000.0
		# 重试用基础超时
		_start_watchdog(CHAT_WATCHDOG_TIMEOUT)
		_connect_and_send()
		return

	_logger.warn("Watchdog timeout — %.0fs 内无任何数据，已重试 %d 次" % [_watchdog_timeout, MAX_RETRIES])
	stream_error.emit("Watchdog: %.0f 秒内未收到任何响应数据。\n" % _watchdog_timeout +
		"  • 已自动重试 %d 次仍无响应\n" % MAX_RETRIES +
		"  • 网络或 API 问题 — 检查 Settings 里的 Base URL 和 API Key\n" +
		"  • 也可以试试 Compact 按钮压缩上下文")
	set_process(false)
	_watchdog_active = false
	_active = false
	if _client:
		_client.close()
		_client = null
	progress_done.emit()
	request_completed.emit()


func abort() -> void:
	_abort = true
	if _client:
		_client.close()
	_cleanup()
	request_completed.emit()


func _on_http_error(msg: String) -> void:
	_logger.append("LLM", "HTTP ERROR: " + msg)
	stream_error.emit(msg)
	_cleanup()
	request_completed.emit()


# ============ SSE Helpers ============

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


# ============ Request Builder ============

func _build_request_body(messages: Array, tools: Array, stream: bool) -> String:
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
		var brief_tools: Array = []
		for t in tools:
			var bt: Dictionary = t.duplicate()
			if t.has("description_brief") and not t.get("description_brief", "").is_empty():
				bt["description"] = t.get("description_brief")
			else:
				var desc: String = t.get("description", "")
				var dot := desc.find(". ")
				if dot > 0 and dot < 150:
					bt["description"] = desc.substr(0, dot + 1)
				elif desc.length() > 150:
					bt["description"] = desc.substr(0, 150) + "…"
			bt.erase("description_brief")
			brief_tools.append(bt)
		body["tools"] = brief_tools
		body["tool_choice"] = "auto"
	return JSON.stringify(body)


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


# ============ Lifecycle ============

func _cleanup() -> void:
	if not _active:
		return
	_active = false
	_watchdog_active = false
	set_process(false)
	progress_done.emit()
	if _client:
		_client.close()
		_client = null


func _get_string(d: Dictionary, key: String, default: String = "") -> String:
	if not d.has(key):
		return default
	var v = d[key]
	if v == null:
		return default
	return str(v)
