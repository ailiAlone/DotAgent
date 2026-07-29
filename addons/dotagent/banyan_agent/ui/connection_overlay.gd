@tool
extends Control
## Connection overlay — 贝塞尔曲线 + 开口箭头。
##
## 仅在树结构变化时由 update_tree() 显式调用 refresh()，
## 不做每帧轮询。

const BEZIER_STEPS: int = 20

var _panel = null


## 由 banyan_bottom_panel.update_tree() 调用，一次性完成 slot 创建 + 绘制
func refresh() -> void:
	if _panel == null:
		return
	var connections: Array = _panel._connections
	var graph: GraphEdit = _panel._graph
	if connections.is_empty():
		queue_redraw()
		return
	_setup_slots(connections, graph)
	queue_redraw()


func _setup_slots(connections: Array, graph: GraphEdit) -> void:
	# 第一遍：计算每条连线的方向和序号，统计每个节点每个方向需要的 slot 数
	var need: Dictionary = {}  # GraphElement → { direction: count }
	for conn in connections:
		var from_node = graph.get_node_or_null(NodePath(str(conn["from"])))
		var to_node = graph.get_node_or_null(NodePath(str(conn["to"])))
		if from_node == null or to_node == null:
			continue
		if not from_node.has_method("add_slot") or not to_node.has_method("add_slot"):
			continue

		# 用 position_offset（图空间坐标，布局时同步赋值）计算方向，
		# 避免初次加载时 global_position 尚未被 GraphEdit 应用导致方向为 0。
		var from_center: Vector2 = from_node.position_offset + from_node.size * 0.5
		var to_center: Vector2 = to_node.position_offset + to_node.size * 0.5
		var dir: Vector2 = to_center - from_center
		if dir.length() < 1.0:
			continue

		var from_dir: String = from_node.best_slot_for(dir)
		var to_dir: String = to_node.best_slot_for(-dir)

		if not need.has(from_node):
			need[from_node] = {}
		if not need.has(to_node):
			need[to_node] = {}
		need[from_node][from_dir] = int(need[from_node].get(from_dir, 0)) + 1
		need[to_node][to_dir] = int(need[to_node].get(to_dir, 0)) + 1

		# 记住这条连线用的方向和序号（同边第几条）
		conn["_from_dir"] = from_dir
		conn["_to_dir"] = to_dir
		conn["_from_idx"] = need[from_node][from_dir] - 1
		conn["_to_idx"] = need[to_node][to_dir] - 1

	# 第二遍：按需求差额调整 slot（持久 slot — 不整体重建，
	# 否则新建 slot 要等容器排版才有正确坐标，连线端点采样会拿到旧值）
	for child in graph.get_children():
		if not (child is GraphElement) or not child.has_method("ensure_slot_count"):
			continue
		var node_need: Dictionary = need.get(child, {})
		for d in ["left", "right", "top", "bottom"]:
			child.ensure_slot_count(d, int(node_need.get(d, 0)))
			for i in child.slot_count(d):
				var s = child.get_slot(d, i)
				if s:
					s.set_status("connected")


func _draw() -> void:
	if _panel == null:
		return
	var connections: Array = _panel._connections
	var graph: GraphEdit = _panel._graph
	if connections.is_empty():
		return

	var overlay_origin: Vector2 = global_position
	var zoom: float = graph.zoom

	for conn in connections:
		var from_node = graph.get_node_or_null(NodePath(str(conn["from"])))
		var to_node = graph.get_node_or_null(NodePath(str(conn["to"])))
		if from_node == null or to_node == null:
			continue

		# 用 _setup_slots 阶段存储的方向和索引
		var from_dir: String = conn.get("_from_dir", "")
		var to_dir: String = conn.get("_to_dir", "")
		var from_idx: int = conn.get("_from_idx", 0)
		var to_idx: int = conn.get("_to_idx", 0)
		if from_dir.is_empty() or to_dir.is_empty():
			continue

		# 端点采样持久 slot 的真实中心（精确落在槽点上）；
		# slot 不存在时（异常路径）退化解析计算，保证线不断
		var from_slot = from_node.get_slot(from_dir, from_idx)
		var to_slot = to_node.get_slot(to_dir, to_idx)
		var s_start: Vector2 = (from_slot.get_center() if from_slot else _side_point(from_node, from_dir, from_idx)) - overlay_origin
		var s_end: Vector2 = (to_slot.get_center() if to_slot else _side_point(to_node, to_dir, to_idx)) - overlay_origin

		# 贝塞尔控制点
		var exit_dir: Vector2 = _dir_vector(from_dir)
		var entry_dir: Vector2 = _dir_vector(to_dir)
		var dist: float = s_start.distance_to(s_end)
		var handle: float = clampf(dist * 0.4, 30.0, 200.0)

		var cp1: Vector2 = s_start + exit_dir * handle
		var cp2: Vector2 = s_end + entry_dir * handle

		# 采样贝塞尔
		var points := PackedVector2Array()
		points.resize(BEZIER_STEPS + 1)
		for i in range(BEZIER_STEPS + 1):
			var t: float = float(i) / float(BEZIER_STEPS)
			points[i] = _cubic_bezier(s_start, cp1, cp2, s_end, t)

		# 画曲线
		var line_color := Color(0.55, 0.6, 0.65, 0.75)
		if points.size() >= 2:
			draw_polyline(points, line_color, 1.5 * zoom, true)

		# 箭头 — 更大更明显
		var arrow_len: float = 12.0 * zoom
		var arrow_angle: float = 0.5
		var arrow_color := Color(0.7, 0.75, 0.8, 0.9)
		var tangent: Vector2 = (s_end - points[maxi(points.size() - 3, 0)]).normalized()
		var left: Vector2 = s_end - tangent.rotated(arrow_angle) * arrow_len
		var right: Vector2 = s_end - tangent.rotated(-arrow_angle) * arrow_len
		draw_line(left, s_end, arrow_color, 2.5 * zoom, true)
		draw_line(s_end, right, arrow_color, 2.5 * zoom, true)


## 兜底：slot 缺失时按边均布估算连接点（仅异常路径使用）
## slot 10px、容器默认 separation=4 → 间距 14px、整体居中
func _side_point(node, direction: String, idx: int) -> Vector2:
	const SLOT_PITCH: float = 14.0  # 10px slot + 默认 separation 4
	var count: int = maxi(node.slot_count(direction), 1)
	var shift: float = (float(idx) - float(count - 1) * 0.5) * SLOT_PITCH
	var zoom: float = _panel._graph.zoom
	var sz: Vector2 = node.size * zoom
	var p: Vector2 = node.global_position
	match direction:
		"left": return p + Vector2(0, sz.y * 0.5 + shift * zoom)
		"right": return p + Vector2(sz.x, sz.y * 0.5 + shift * zoom)
		"top": return p + Vector2(sz.x * 0.5 + shift * zoom, 0)
		"bottom": return p + Vector2(sz.x * 0.5 + shift * zoom, sz.y)
	return p + sz * 0.5


static func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3


static func _dir_vector(direction: String) -> Vector2:
	match direction:
		"left": return Vector2(-1, 0)
		"right": return Vector2(1, 0)
		"top": return Vector2(0, -1)
		"bottom": return Vector2(0, 1)
	return Vector2(1, 0)
