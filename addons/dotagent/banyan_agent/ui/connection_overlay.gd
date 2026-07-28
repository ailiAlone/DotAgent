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
	# 清空所有节点的所有 slot
	for child in graph.get_children():
		if child is GraphElement and child.has_method("_clear_slots"):
			child._clear_slots()

	for conn in connections:
		var from_node = graph.get_node_or_null(NodePath(str(conn["from"])))
		var to_node = graph.get_node_or_null(NodePath(str(conn["to"])))
		if from_node == null or to_node == null:
			continue
		if not from_node.has_method("add_slot") or not to_node.has_method("add_slot"):
			continue

		var from_center: Vector2 = from_node.global_position + from_node.size * 0.5
		var to_center: Vector2 = to_node.global_position + to_node.size * 0.5
		var dir: Vector2 = to_center - from_center
		if dir.length() < 1.0:
			continue

		var from_dir: String = from_node.best_slot_for(dir)
		var to_dir: String = to_node.best_slot_for(-dir)

		var from_slot = from_node.add_slot(from_dir)
		var to_slot = to_node.add_slot(to_dir)
		if from_slot:
			from_slot.set_status("connected")
		if to_slot:
			to_slot.set_status("connected")

		# 记住这条连线用的方向和索引
		conn["_from_dir"] = from_dir
		conn["_to_dir"] = to_dir
		conn["_from_idx"] = from_node.slot_count(from_dir) - 1
		conn["_to_idx"] = to_node.slot_count(to_dir) - 1


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

		var from_slot = from_node.get_slot(from_dir, from_idx)
		var to_slot = to_node.get_slot(to_dir, to_idx)
		if from_slot == null or to_slot == null:
			continue

		var s_start: Vector2 = from_slot.get_center() - overlay_origin
		var s_end: Vector2 = to_slot.get_center() - overlay_origin

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
