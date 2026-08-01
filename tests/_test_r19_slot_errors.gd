extends SceneTree
## R19: request_slot 传输层错误处理回归
## 1. TLS 对端说垃圾话（mbedtls 失败）→ slot 必须快速 FAILED，不得挂起
## 2. WAITING_RESPONSE 遇到 DISCONNECTED/错误态 → FAILED（此前"重试下一帧"死循环）

const ReqSlot = preload("res://addons/dotagent/banyan_agent/http/request_slot.gd")

var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _sent_garbage := false
var _pass := 0
var _fail := 0


func _init() -> void:
	call_deferred("_main")


func _main() -> void:
	await _test_tls_garbage()
	_test_disconnected_waiting()
	print("=== Results: %d/%d passed ===" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


## 本地 TCP 服务器对 TLS 握手回垃圾数据 — 复现 mbedtls -0x6c00 类错误
func _test_tls_garbage() -> void:
	_server = TCPServer.new()
	if _server.listen(18999, "127.0.0.1") != OK:
		print("  [SKIP] 无法监听 18999")
		return
	var slot := ReqSlot.new(1)
	slot.claim("test")
	slot.send("127.0.0.1", 18999, "/", "{}", PackedStringArray(), true)
	var deadline: int = Time.get_ticks_msec() + 15000
	while not slot.is_terminal() and Time.get_ticks_msec() < deadline:
		if _server.is_connection_available():
			_peer = _server.take_connection()
		if _peer:
			_peer.poll()
			if not _sent_garbage and _peer.get_available_bytes() > 0:
				_sent_garbage = true
				_peer.put_data("GARBAGE-NOT-TLS\r\n".to_utf8_buffer())
		slot.poll()
		await process_frame
	_check(slot.is_terminal(), "TLS 对端垃圾：slot 到达终态（不挂起）")
	_check(slot.state == ReqSlot.State.FAILED, "TLS 对端垃圾：终态为 FAILED")
	_check(slot.error_message.length() > 0, "TLS 对端垃圾：带错误信息 (%s)" % slot.error_message.substr(0, 60))
	_server.stop()
	_peer = null


## 合成场景：请求已发出，等待响应时连接已断（A1 挂死的同款分支）
func _test_disconnected_waiting() -> void:
	var slot := ReqSlot.new(2)
	slot.claim("test")
	slot.client = HTTPClient.new()  # 未连接 → get_status() == DISCONNECTED
	slot.state = ReqSlot.State.WAITING_RESPONSE
	var frames := 0
	while not slot.is_terminal() and frames < 100:
		slot.poll()
		frames += 1
	_check(slot.is_terminal(), "WAITING+DISCONNECTED：slot 到达终态（不挂起）")
	_check(slot.state == ReqSlot.State.FAILED, "WAITING+DISCONNECTED：终态为 FAILED")
	_check(frames < 10, "WAITING+DISCONNECTED：快速失败（%d 帧）" % frames)
