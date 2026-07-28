@tool
extends Node
## HTTP 连接池 — 管理多个 RequestSlot，驱动其状态机。

const ReqSlot = preload("res://addons/dotagent/banyan_agent/http/request_slot.gd")
##
## 用法:
##   var pool := HTTPClientPool.new(1)  # 串行模式
##   host_node.add_child(pool)
##   var slot := pool.acquire_slot("Worker:Player:001")
##   slot.send(host, port, path, body, headers)
##   # ... _process() 自动驱动 slot 状态机 ...
##   # 检查 slot.state == COMPLETED 后:
##   pool.release_slot(slot)
##
## 设计原则:
##   - 串行模式 pool_size=1，并行模式 pool_size=N
##   - _process() 统一驱动所有活跃 slot 的 poll()
##   - 每 slot 独立 watchdog — 超时无数据则标记 FAILED
##   - 原子状态（READING_BODY）的 slot 不可被强制释放

signal slot_completed(slot: ReqSlot)
signal slot_failed(slot: ReqSlot, error: String)

const DEFAULT_POOL_SIZE := 1
const SLOT_WATCHDOG_TIMEOUT := 90.0   # 单 slot 总超时
const STREAM_WATCHDOG_TIMEOUT := 60.0  # 流式响应无数据超时
const POLL_INTERVAL := 0.05  # 50ms 轮询间隔

var slots: Array = []
var max_slots: int = DEFAULT_POOL_SIZE
var _poll_timer: float = 0.0
var _active_count: int = 0


func _init(pool_size: int = DEFAULT_POOL_SIZE) -> void:
	max_slots = max(1, pool_size)
	for i in range(max_slots):
		slots.append(ReqSlot.new(i))


func _ready() -> void:
	set_process(false)  # 无活跃 slot 时不消耗性能


func _process(delta: float) -> void:
	process_frame(delta)


## 手动驱动一帧 — 供无头测试或 MVP 客户端调用。
## 不依赖 Node 生命周期，可在 SceneTree 脚本中逐帧轮询。
func process_frame(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer < POLL_INTERVAL:
		return
	_poll_timer = 0.0

	var any_active: bool = false
	for slot in slots:
		if slot.state == ReqSlot.State.IDLE:
			continue
		any_active = true

		# 驱动 slot 状态机
		slot.poll()

		# watchdog 检查（使用公共接口）
		if not slot.is_terminal():
			var elapsed: float = Time.get_ticks_msec() / 1000.0 - slot.last_activity
			if elapsed > SLOT_WATCHDOG_TIMEOUT:
				slot.timeout("Watchdog timeout: %.0fs without completion" % elapsed)

		# 终态处理 — 只通知一次
		if slot.is_terminal() and slot.mark_notified():
			if slot.state == ReqSlot.State.COMPLETED:
				slot_completed.emit(slot)
			elif slot.state == ReqSlot.State.FAILED:
				slot_failed.emit(slot, slot.error_message)

	if not any_active:
		if is_inside_tree():
			set_process(false)


# ============ 公共接口 ============

## 获取一个空闲 slot，分配给指定 Worker。无空闲时返回 null。
func acquire_slot(worker_id: String) -> ReqSlot:
	for slot in slots:
		if slot.is_idle() and slot.worker_id.is_empty():
			slot.claim(worker_id)
			_active_count += 1
			if is_inside_tree():
				set_process(true)
			return slot
	return null


## 等待获取空闲 slot — 实现背压：繁忙时排队而非立即失败
## poll_interval: 轮询间隔（秒），timeout: 最大等待时间（秒）
func wait_for_slot(worker_id: String, timeout: float = 30.0, poll_interval: float = 0.5) -> ReqSlot:
	var slot: ReqSlot = acquire_slot(worker_id)
	if slot != null:
		return slot
	var elapsed: float = 0.0
	while elapsed < timeout:
		if is_inside_tree():
			await get_tree().create_timer(poll_interval).timeout
		elapsed += poll_interval
		slot = acquire_slot(worker_id)
		if slot != null:
			return slot
	return null


## 释放 slot — 关闭连接，重置状态，回到空闲
func release_slot(slot: ReqSlot) -> void:
	slot.release()
	_active_count = max(0, _active_count - 1)
	if _active_count == 0 and is_inside_tree():
		set_process(false)


## 获取当前活跃 slot 数量
func get_active_count() -> int:
	var count: int = 0
	for slot in slots:
		if not slot.is_idle() or not slot.worker_id.is_empty():
			count += 1
	return count


## 获取空闲 slot 数量
func get_idle_count() -> int:
	var count: int = 0
	for slot in slots:
		if slot.is_idle() and slot.worker_id.is_empty():
			count += 1
	return count


## 强制释放所有 slot（紧急关闭用）
func release_all() -> void:
	for slot in slots:
		if not slot.worker_id.is_empty() or not slot.is_idle():
			slot.release()
	_active_count = 0
	if is_inside_tree():
		set_process(false)


## 检查指定 Worker 是否持有 slot
func has_slot_for(worker_id: String) -> bool:
	for slot in slots:
		if slot.worker_id == worker_id and not slot.worker_id.is_empty():
			return true
	return false


## 获取指定 Worker 持有的 slot
func get_slot_for(worker_id: String) -> ReqSlot:
	for slot in slots:
		if slot.worker_id == worker_id and not slot.worker_id.is_empty():
			return slot
	return null


# ============ 请求构建辅助 ============

## 解析 URL 为 host + port + path
static func parse_url(url: String) -> Dictionary:
	var u: String = url.strip_edges()
	var use_tls: bool = true
	if u.begins_with("https://"):
		u = u.substr(8)
	elif u.begins_with("http://"):
		u = u.substr(7)
		use_tls = false

	var slash: int = u.find("/")
	var host: String
	var path: String
	var port: int = 443 if use_tls else 80

	if slash > 0:
		var host_part: String = u.substr(0, slash)
		path = u.substr(slash)
		# 检查 host:port
		var colon: int = host_part.rfind(":")
		if colon > 0:
			host = host_part.substr(0, colon)
			port = int(host_part.substr(colon + 1))
		else:
			host = host_part
	else:
		host = u
		path = "/"

	return {"host": host, "port": port, "path": path, "use_tls": use_tls}


## 构建 OpenAI 兼容的 LLM 请求 body（不含 temperature，由 API 使用默认值）
static func build_request_body(model: String, messages: Array, tools: Array, stream: bool, max_tokens: int = 4096) -> String:
	var body: Dictionary = {
		"model": model,
		"messages": messages,
		"max_tokens": max_tokens,
		"stream": stream,
	}
	if not tools.is_empty():
		body["tools"] = tools
		body["tool_choice"] = "auto"
	return JSON.stringify(body)


## 构建 OpenAI 兼容的认证 headers
static func build_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
		"Accept: text/event-stream",
	])
