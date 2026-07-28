@tool
extends RefCounted
## 请求槽状态机 — 包装单个 HTTPClient 的完整生命周期。

const StreamParser = preload("res://addons/dotagent/banyan_agent/http/stream_parser.gd")
##
## 状态流转:
##   IDLE → CONNECTING → SENDING → WAITING_RESPONSE → READING_BODY → COMPLETED → IDLE
##   任意状态遇错 → FAILED → (reset) → IDLE
##
## 原子状态:
##   - READING_BODY（SSE 流接收中）不可被外部中断
##   - 由 WorkerExecutor 控制 TOOL_EXEC 阶段（不在本类管理）
##
## 设计原则:
##   - 纯 RefCounted，不是 Node — 由 HTTPClientPool._process() 驱动
##   - 每次 send() 创建新的 StreamParser 实例
##   - watchdog 计时器由 HTTPClientPool 统一管理

enum State {
	IDLE,
	CONNECTING,
	SENDING,
	WAITING_RESPONSE,
	READING_BODY,
	COMPLETED,
	FAILED,
}

const STATE_NAMES := ["IDLE", "CONNECTING", "SENDING", "WAITING_RESPONSE", "READING_BODY", "COMPLETED", "FAILED"]

# ============ 状态 ============

var state: State = State.IDLE
var slot_id: int = 0
var worker_id: String = ""

# ============ HTTP ============

var client: HTTPClient = null
var parser: StreamParser = null
var _host: String = ""
var _port: int = 443
var _request_path: String = "/"
var _request_body: String = ""
var _headers: PackedStringArray = PackedStringArray()

# ============ 累积结果 ============

var accumulated_content: String = ""
var accumulated_reasoning: String = ""
var accumulated_tool_calls: Array = []
var accumulated_finish_reason: String = ""

# ============ 计时 ============

var last_activity: float = 0.0
var request_start_time: float = 0.0

# ============ 错误信息 ============

var error_message: String = ""

# ============ 通知标记 ============

var _notified: bool = false  # 防止终态信号被重复发射


func _init(id: int = 0) -> void:
	slot_id = id


# ============ 状态查询 ============

func is_idle() -> bool:
	return state == State.IDLE


func is_atomic() -> bool:
	## 原子状态 — 不可被外部中断（正在接收 SSE 流或执行工具）
	return state == State.READING_BODY


func is_terminal() -> bool:
	## 终态 — 可被回收
	return state == State.COMPLETED or state == State.FAILED


func get_state_name() -> String:
	if state >= 0 and state < STATE_NAMES.size():
		return STATE_NAMES[state]
	return "UNKNOWN"


## 检查并标记通知 — 返回 true 仅第一次调用（用于防止信号重复发射）
func mark_notified() -> bool:
	if _notified:
		return false
	_notified = true
	return true


## 公共超时接口 — 由 HTTPClientPool watchdog 调用
func timeout(msg: String) -> void:
	_fail(msg)


# ============ 生命周期 ============

## 声明此槽 — 分配给指定 Worker
func claim(wid: String) -> void:
	assert(state == State.IDLE, "Cannot claim slot in state: %s" % get_state_name())
	worker_id = wid
	_reset_results()


## 发起 HTTP 连接并发送请求
func send(host: String, port: int, path: String, body: String, headers: PackedStringArray, use_tls: bool = true) -> void:
	assert(state == State.IDLE, "Cannot send in state: %s" % get_state_name())

	_host = host
	_port = port
	_request_path = path
	_request_body = body
	_headers = headers

	client = HTTPClient.new()
	parser = StreamParser.new()

	var err: Error
	if use_tls:
		err = client.connect_to_host(host, port, TLSOptions.client())
	else:
		err = client.connect_to_host(host, port)

	if err != OK:
		_fail("connect_to_host() returned error %d" % err)
		return

	state = State.CONNECTING
	_touch_activity()
	request_start_time = Time.get_ticks_msec() / 1000.0


## 由 HTTPClientPool._process() 每帧调用 — 驱动状态机
func poll() -> void:
	if state == State.IDLE or state == State.COMPLETED or state == State.FAILED:
		return
	if client == null:
		_fail("Client lost during poll")
		return

	client.poll()
	var status: int = client.get_status()

	match state:
		State.CONNECTING:
			_poll_connecting(status)
		State.SENDING:
			pass  # send 在 connecting 完成后立即触发，不需要 poll
		State.WAITING_RESPONSE:
			_poll_waiting(status)
		State.READING_BODY:
			_poll_reading(status)


## 释放槽 — 关闭连接，重置状态
func release() -> void:
	if client:
		client.close()
		client = null
	parser = null
	state = State.IDLE
	worker_id = ""
	_host = ""
	_request_body = ""
	_headers = PackedStringArray()
	_reset_results()
	_notified = false
	error_message = ""


# ============ 内部状态机 ============

func _poll_connecting(status: int) -> void:
	if status == HTTPClient.STATUS_CONNECTING or status == HTTPClient.STATUS_RESOLVING:
		return  # 还在连接中
	if status != HTTPClient.STATUS_CONNECTED:
		_fail("Connection failed: status=%d" % status)
		return

	# 连接成功 → 发送请求
	state = State.SENDING
	var err: Error = client.request(
		HTTPClient.METHOD_POST,
		_request_path,
		_headers,
		_request_body,
	)
	if err != OK:
		_fail("Request send failed: %d" % err)
		return
	state = State.WAITING_RESPONSE
	_touch_activity()


func _poll_waiting(status: int) -> void:
	if status == HTTPClient.STATUS_REQUESTING or status == HTTPClient.STATUS_CONNECTED:
		return  # 等待响应头
	if status == HTTPClient.STATUS_DISCONNECTED:
		_fail("Server disconnected before response")
		return
	if status != HTTPClient.STATUS_BODY:
		return  # 重试下一帧

	# 检查 HTTP 状态码
	if client.get_response_code() >= 400:
		var err_body: PackedByteArray = PackedByteArray()
		while client.get_status() == HTTPClient.STATUS_BODY:
			err_body.append_array(client.read_response_body_chunk())
		var body_str: String = err_body.get_string_from_utf8().substr(0, 500)
		_fail("HTTP %d: %s" % [client.get_response_code(), body_str])
		return

	state = State.READING_BODY
	_touch_activity()
	_read_chunks()


func _poll_reading(status: int) -> void:
	if state != State.READING_BODY:
		return  # 已被 _process_parser_chunks 中的 [DONE] 完成
	if status == HTTPClient.STATUS_DISCONNECTED or status == HTTPClient.STATUS_BODY:
		_read_chunks()
		# 检查是否还有数据
		if client.get_status() == HTTPClient.STATUS_DISCONNECTED:
			# 连接关闭 = 流结束
			_finish_stream()
	elif status != HTTPClient.STATUS_BODY:
		# 意外状态
		_finish_stream()


func _read_chunks() -> void:
	var count: int = 0
	while client != null and client.get_status() == HTTPClient.STATUS_BODY:
		var chunk: PackedByteArray = client.read_response_body_chunk()
		if chunk.size() > 0:
			var text: String = chunk.get_string_from_utf8()
			parser.feed(text)
			_process_parser_chunks()
			_touch_activity()
		count += 1
		if count > 64:
			return  # 让出 CPU，下一帧继续


func _process_parser_chunks() -> void:
	var chunks: Array = parser.drain()
	for chunk in chunks:
		var chunk_type: String = chunk.get("type", "")
		match chunk_type:
			"content":
				var content: String = chunk.get("content", "")
				if not content.is_empty():
					accumulated_content += content
				var reasoning: String = chunk.get("reasoning", "")
				if not reasoning.is_empty():
					accumulated_reasoning += reasoning
			"tool_call":
				pass  # tool_call 由 parser 内部累积，结束后一次性获取
			"done":
				_finish_stream()
				return

		# 检查 finish_reason（某些 API 不发 [DONE]，靠 finish_reason 判断结束）
		var fr: String = str(chunk.get("finish_reason", ""))
		if not fr.is_empty() and accumulated_finish_reason.is_empty():
			accumulated_finish_reason = fr


func _finish_stream() -> void:
	# 最后一次 drain — 处理可能的未消费事件
	if parser:
		var remaining: Array = parser.drain()
		for chunk in remaining:
			var content: String = chunk.get("content", "")
			if not content.is_empty():
				accumulated_content += content
			var reasoning: String = chunk.get("reasoning", "")
			if not reasoning.is_empty():
				accumulated_reasoning += reasoning
	accumulated_tool_calls = parser.get_accumulated_tool_calls() if parser else []
	# 如果 finish_reason 为空，从最后一个 chunk 推断
	if accumulated_finish_reason.is_empty():
		if not accumulated_tool_calls.is_empty():
			accumulated_finish_reason = "tool_calls"
		else:
			accumulated_finish_reason = "stop"
	state = State.COMPLETED
	_touch_activity()


func _fail(msg: String) -> void:
	error_message = msg
	state = State.FAILED
	_touch_activity()


func _touch_activity() -> void:
	last_activity = Time.get_ticks_msec() / 1000.0


func _reset_results() -> void:
	accumulated_content = ""
	accumulated_reasoning = ""
	accumulated_tool_calls = []
	accumulated_finish_reason = ""
	error_message = ""
	request_start_time = 0.0
