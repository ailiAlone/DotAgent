@tool
extends VBoxContainer
## Banyan 底部面板 — Agent Graph 可视化 + Node Inspector + Activity Log

const ConnectionOverlay = preload("res://addons/dotagent/banyan_agent/ui/connection_overlay.gd")
const BanyanNodeScene = preload("res://addons/dotagent/banyan_agent/ui/CustomNode/custom_node.tscn")

signal prune_requested(node_id: String)
signal node_selected(node_id: String)

# ============ UI 引用 ============

@onready var _graph: GraphEdit = $Split/Left/GraphEdit
@onready var _tree_count: Label = $Split/Left/TreeBar/TreeCount
@onready var _id_label: Label = $Split/Right/Inspector/InspectorScroll/InspectorContent/IDLabel
@onready var _state_label: Label = $Split/Right/Inspector/InspectorScroll/InspectorContent/StateLabel
@onready var _rounds_label: Label = $Split/Right/Inspector/InspectorScroll/InspectorContent/RoundsLabel
@onready var _files_label: Label = $Split/Right/Inspector/InspectorScroll/InspectorContent/FilesLabel
@onready var _children_label: Label = $Split/Right/Inspector/InspectorScroll/InspectorContent/ChildrenLabel
@onready var _history_label: Label = $Split/Right/Inspector/InspectorScroll/InspectorContent/HistoryLabel
@onready var _knowledge_label: RichTextLabel = $Split/Right/Inspector/InspectorScroll/InspectorContent/KnowledgeLabel
@onready var _prune_button: Button = $Split/Right/Inspector/InspectorBar/PruneBtn
@onready var _log_scroll: ScrollContainer = $Split/Right/LogPane/LogScroll
@onready var _log_list: VBoxContainer = $Split/Right/LogPane/LogScroll/LogList
@onready var _log_badge: Label = $Split/Right/LogPane/LogBar/LogBadge

const MAX_LOG_ENTRIES := 200
const GRAY := Color(0.5, 0.5, 0.5)

# 布局常量
const NODE_PADDING: float = 50.0

# 当前展示的树数据: { node_id → {state, rounds, files, children_count, domain_knowledge, history, children: [id], parent_id} }
var _tree_data: Dictionary = {}
var _selected_node_id: String = ""
var _log_entries: Array = []

# Prune 建议缓存
var _prune_suggestions: Array = []
var _overlay: Control = null
var _connections: Array = []


func _ready() -> void:
	get_node("Split/Right/LogPane/LogBar/ClearBtn").pressed.connect(_on_log_clear)
	_prune_button.pressed.connect(_on_prune_pressed)
	_clear_inspector()

	# 创建连线覆盖层 — 自己画方向感知连线
	_overlay = ConnectionOverlay.new()
	_overlay._panel = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_graph.add_child(_overlay)


# ============ Agent Graph 可视化 ============

## 更新整张图 — 从 AgentTree 对象或 Dictionary
func update_tree(data) -> void:
	if not _graph:
		return
	_clear_graph()

	if data == null:
		_tree_count.text = "0 nodes"
		return

	# 支持 AgentTree 对象
	if data is RefCounted and data.has_method("get_all_nodes"):
		_build_from_agent_tree(data)
		return

	# 兼容 Dictionary 格式（实时运行更新）
	_build_from_dict(data)


func _build_from_agent_tree(agent_tree) -> void:
	var all_nodes: Dictionary = agent_tree.get_all_nodes()
	var root_id: String = agent_tree.get_root_id()

	_tree_data.clear()

	for nid in all_nodes:
		var n = all_nodes[nid]
		_tree_data[nid] = {
			"state": n.state,
			"rounds": n.get_round_count(),
			"files": n.managed_files.duplicate(),
			"children_count": agent_tree.get_children(nid).size(),
			"domain_knowledge": n.domain_knowledge,
			"history": n.history.duplicate(),
			"children": [],
			"parent_id": n.parent_id,
		}
	for nid in all_nodes:
		var n = all_nodes[nid]
		if not n.parent_id.is_empty() and _tree_data.has(n.parent_id):
			_tree_data[n.parent_id]["children"].append(nid)

	if not root_id.is_empty():
		_layout_and_render(root_id)

	_tree_count.text = "%d nodes" % all_nodes.size()
	_refresh_inspector()


func _build_from_dict(data: Dictionary) -> void:
	_tree_data.clear()

	var root_id: String = str(data.get("root_id", "Root"))
	var root_state: String = str(data.get("root_state", "IDLE"))

	_tree_data[root_id] = {
		"state": root_state,
		"rounds": int(data.get("rounds", 0)),
		"files": data.get("files", []),
		"children_count": 0,
		"domain_knowledge": str(data.get("domain_knowledge", "")),
		"history": data.get("history", []),
		"children": [],
		"parent_id": "",
	}

	# 递归展平嵌套 dict
	_flatten_children(root_id, data.get("children", {}))

	_layout_and_render(root_id)
	_tree_count.text = "%d nodes" % _tree_data.size()
	_refresh_inspector()


func _flatten_children(parent_id: String, children_dict: Dictionary) -> void:
	for cid in children_dict:
		var cdata: Dictionary = children_dict[cid]
		_tree_data[cid] = {
			"state": str(cdata.get("state", "")),
			"rounds": int(cdata.get("rounds", 0)),
			"files": cdata.get("files", []),
			"children_count": 0,
			"domain_knowledge": str(cdata.get("domain_knowledge", "")),
			"history": cdata.get("history", []),
			"children": [],
			"parent_id": parent_id,
		}
		_tree_data[parent_id]["children"].append(cid)
		# 递归
		var grandchildren: Dictionary = cdata.get("children", {})
		if not grandchildren.is_empty():
			_tree_data[cid]["children_count"] = grandchildren.size()
			_flatten_children(cid, grandchildren)


# ============ 布局 & 渲染 ============

## 径向布局：Root 居中，子节点向四周散开
func _layout_and_render(root_id: String) -> void:
	var positions: Dictionary = {}
	var center := Vector2(400, 300)

	# 计算子树叶节点数（用于角度分配）
	var leaf_counts: Dictionary = {}
	_count_leaves(root_id, leaf_counts)

	# 先用估算尺寸定位（创建节点后才能拿到真实尺寸）
	_position_radial(root_id, center, -PI, PI, 0, leaf_counts, positions)

	# 创建 GraphNode
	for nid in positions:
		_create_graph_node(nid, positions[nid])

	# 拿到真实节点尺寸后，重新计算布局
	var max_size := Vector2.ZERO
	for child in _graph.get_children():
		if child is GraphElement:
			max_size.x = maxf(max_size.x, child.size.x)
			max_size.y = maxf(max_size.y, child.size.y)
	if max_size.x < 10:
		max_size = Vector2(100, 60)

	# 用真实尺寸重新定位
	positions.clear()
	_position_radial(root_id, center, -PI, PI, 0, leaf_counts, positions, max_size)

	# 更新节点位置
	for nid in positions:
		var node = _graph.get_node_or_null(NodePath(nid))
		if node:
			node.position_offset = positions[nid]

	# 存储连线数据给覆盖层绘制
	_connections.clear()
	for nid in _tree_data:
		var ndata: Dictionary = _tree_data[nid]
		var pid: String = str(ndata.get("parent_id", ""))
		if not pid.is_empty() and positions.has(pid) and positions.has(nid):
			_connections.append({"from": pid, "to": nid})

	if _overlay:
		_overlay.refresh()

	# 将视图居中到 Root
	if positions.has(root_id):
		var root_pos: Vector2 = positions[root_id]
		var root_node = _graph.get_node_or_null(NodePath(root_id))
		var root_size: Vector2 = root_node.size if root_node else Vector2(100, 60)
		_graph.scroll_offset = root_pos - Vector2(400, 300) + root_size * 0.5


func _count_leaves(nid: String, out: Dictionary) -> int:
	var ndata: Dictionary = _tree_data.get(nid, {})
	var children: Array = ndata.get("children", [])
	if children.is_empty():
		out[nid] = 1
		return 1
	var total: int = 0
	for cid in children:
		total += _count_leaves(str(cid), out)
	out[nid] = total
	return total


func _position_radial(nid: String, pos: Vector2, angle_start: float, angle_end: float, depth: int, leaf_counts: Dictionary, out: Dictionary, node_size: Vector2 = Vector2(100, 60)) -> void:
	out[nid] = pos

	var ndata: Dictionary = _tree_data.get(nid, {})
	var children: Array = ndata.get("children", [])
	if children.is_empty():
		return

	# 动态半径：保证子节点不重叠
	var n: int = children.size()
	var total_angle: float = angle_end - angle_start
	var gap: float = 0.12 if n > 1 else 0.0
	var available: float = total_angle - gap * (n - 1)
	var angle_per_child: float = available / maxf(n, 1)

	var node_diagonal: float = node_size.length()
	var min_radius: float = node_diagonal + NODE_PADDING
	var arc_radius: float = 0.0
	if angle_per_child > 0.01:
		arc_radius = (node_size.x + 15.0) / (2.0 * sin(angle_per_child * 0.5))
	var radius: float = maxf(min_radius, arc_radius)

	# 按叶节点数分配角度
	var total_leaves: int = 0
	for cid in children:
		total_leaves += leaf_counts.get(str(cid), 1)
	if total_leaves == 0:
		total_leaves = 1

	var current_angle: float = angle_start
	for cid in children:
		var cid_str: String = str(cid)
		var leaves: int = leaf_counts.get(cid_str, 1)
		var child_angle: float = available * (float(leaves) / float(total_leaves))
		var mid_angle: float = current_angle + child_angle * 0.5

		var child_pos := Vector2(
			pos.x + cos(mid_angle) * radius,
			pos.y + sin(mid_angle) * radius,
		)

		# 子节点的扇区范围（越深越窄）
		var sub_spread: float = child_angle * 0.8
		_position_radial(
			cid_str, child_pos,
			mid_angle - sub_spread * 0.5,
			mid_angle + sub_spread * 0.5,
			depth + 1, leaf_counts, out, node_size,
		)

		current_angle += child_angle + gap


func _create_graph_node(nid: String, pos: Vector2) -> void:
	var ndata: Dictionary = _tree_data.get(nid, {})
	var state: String = str(ndata.get("state", "IDLE"))
	var rounds: int = int(ndata.get("rounds", 0))
	var color: Color = _state_color(state)
	var files = ndata.get("files", [])
	var fc: int = files.size() if files is Array else 0
	var cc: int = int(ndata.get("children_count", 0))
	var knowledge: String = str(ndata.get("domain_knowledge", ""))

	var gn = BanyanNodeScene.instantiate()
	gn.position_offset = pos
	gn.configure(nid, state, rounds, color, fc, cc, knowledge)
	gn.node_clicked.connect(func(id):
		_show_inspector(id)
		node_selected.emit(id)
	)
	_graph.add_child(gn)


func _clear_graph() -> void:
	_connections.clear()
	_graph.clear_connections()
	for child in _graph.get_children():
		if child is GraphElement or child is GraphNode:
			child.queue_free()
	if _overlay:
		_overlay.queue_redraw()


# ============ Node Inspector ============

func _refresh_inspector() -> void:
	if not _selected_node_id.is_empty() and _tree_data.has(_selected_node_id):
		_show_inspector(_selected_node_id)
	else:
		_clear_inspector()


func _show_inspector(nid: String) -> void:
	var ndata: Dictionary = _tree_data.get(nid, {})
	if ndata.is_empty():
		_clear_inspector()
		return

	_selected_node_id = nid
	_id_label.text = "ID: %s" % nid
	_state_label.text = "State: %s" % str(ndata.get("state", "UNKNOWN"))
	_state_label.add_theme_color_override("font_color", _state_color(str(ndata.get("state", ""))))

	var rounds: int = int(ndata.get("rounds", 0))
	_rounds_label.text = "Rounds: %d" % rounds

	var files = ndata.get("files", [])
	var fc: int = files.size() if files is Array else 0
	_files_label.text = "Files: %d" % fc
	if fc > 0 and files is Array:
		var file_list: String = ""
		for f in files:
			file_list += "  %s\n" % str(f)
		_files_label.tooltip_text = file_list.strip_edges()

	var children_count: int = int(ndata.get("children_count", 0))
	_children_label.text = "Children: %d" % children_count

	var history: Array = ndata.get("history", [])
	if not history.is_empty():
		var recent: Array = history
		if recent.size() > 5:
			recent = recent.slice(-5)
		_history_label.text = "Recent:\n  " + "\n  ".join(recent)
	else:
		_history_label.text = ""

	var knowledge: String = str(ndata.get("domain_knowledge", ""))
	if not knowledge.is_empty():
		_knowledge_label.text = knowledge.substr(0, 500)
	else:
		_knowledge_label.text = "[i]No knowledge recorded[/i]"


func _clear_inspector() -> void:
	_selected_node_id = ""
	_id_label.text = ""
	_state_label.text = ""
	_rounds_label.text = ""
	_files_label.text = ""
	_children_label.text = ""
	_history_label.text = ""
	_knowledge_label.text = "[i]Select a node to inspect[/i]"


# ============ Prune ============

func set_prune_suggestions(suggestions: Array) -> void:
	_prune_suggestions = suggestions
	if suggestions.is_empty():
		_prune_button.text = "Prune"
		_prune_button.tooltip_text = ""
		_prune_button.disabled = true
	else:
		_prune_button.text = "Prune (%d)" % suggestions.size()
		var reasons: Array = []
		for s in suggestions:
			reasons.append(str(s.get("reason", "")))
		_prune_button.tooltip_text = "\n".join(reasons)
		_prune_button.disabled = false


func _on_prune_pressed() -> void:
	if _prune_suggestions.is_empty():
		return
	prune_requested.emit(_selected_node_id)
	_prune_suggestions.clear()
	_prune_button.text = "Prune"
	_prune_button.disabled = true


# ============ Activity Log ============

func add_log(message: String, level: String = "info") -> void:
	if not _log_list:
		return
	_log_entries.append({"message": message, "level": level})

	while _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()
		if _log_list.get_child_count() > 0:
			_log_list.get_child(0).queue_free()

	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(0, 16)
	label.text = _format_log(message, level)
	_log_list.add_child(label)

	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func clear_log() -> void:
	_log_entries.clear()
	if _log_list:
		for child in _log_list.get_children():
			child.queue_free()
	_log_badge.text = ""


# ============ 内部 ============

func _state_color(state: String) -> Color:
	match str(state):
		"COMPLETED": return Color.GREEN
		"FAILED": return Color.RED
		"RUNNING", "LLM_REQUEST", "TOOL_EXEC": return Color(1, 0.8, 0)
		"BLOCKED": return Color.ORANGE
		_: return GRAY


func _format_log(message: String, level: String) -> String:
	var t: String = Time.get_time_string_from_system()
	var c: String
	match level:
		"error": c = "[color=red]"
		"warning": c = "[color=orange]"
		"success": c = "[color=green]"
		"tool": c = "[color=cyan]"
		_: c = "[color=gray]"
	return "[color=#555555]%s[/color] %s%s[/color]" % [t, c, message]


func _on_log_clear() -> void:
	clear_log()

