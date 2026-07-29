@tool
class_name BanyanGraphElement
extends GraphElement
## 自定义 Agent 节点 — 在 GraphEdit 中显示。
##
## 四方向 NodeSlot 端口（上下左右），连线由 connection_overlay.gd 绘制。
## NodeSlot.modulate 表示端口状态：gray=空闲, green=已连接, yellow=传输中, red=错误。

signal node_clicked(node_id: String)

var node_id: String = ""
var agent_state: String = "IDLE"
var round_count: int = 0
var files_count: int = 0
var children_count: int = 0
var domain_knowledge: String = ""
var _ctx_size: int = 0
var _stream_chars: int = 0  # 正在流入的字符数（LLM_REQUEST 中实时增长）
var _state_style: StyleBoxFlat = null  # 每实例独立的样式副本（场景子资源默认共享，必须复制）

const NodeSlotScene = preload("res://addons/dotagent/banyan_agent/ui/CustomNode/node_slot.tscn")

@onready var left_slot_container: VBoxContainer = %LeftContainer
@onready var right_slot_container: VBoxContainer = %RightContainer
@onready var top_slot_container: HBoxContainer = %TopContainer
@onready var bottom_slot_container: HBoxContainer = %BottomContainer
@onready var panel_container: PanelContainer = $GridContainer/PanelContainer
@onready var name_label: Label = $GridContainer/PanelContainer/ContentContainer/NameLabel
@onready var ctx_value_label: Label = $GridContainer/PanelContainer/ContentContainer/HBoxContainer/CTXValueLabel
@onready var files_count_value_label: Label = $GridContainer/PanelContainer/ContentContainer/HBoxContainer2/FilesCountValueLabel

var _slots: Dictionary = {"left": [], "right": [], "top": [], "bottom": []}


func _ready() -> void:
	_clear_slots()
	_ensure_state_style()
	_apply_state_color()
	_update_content()


## 获取每实例独立的 StyleBoxFlat — 场景子资源在所有实例间共享，
## 直接修改会让全图节点变成同一个颜色，必须 duplicate 后 override
func _ensure_state_style() -> void:
	if _state_style != null or panel_container == null:
		return
	var base = panel_container.get_theme_stylebox("panel")
	if base is StyleBoxFlat:
		_state_style = base.duplicate()
		panel_container.add_theme_stylebox_override("panel", _state_style)


## 按当前状态着色：边框用状态色，底色用状态色的低透明度版本
func _apply_state_color() -> void:
	if _state_style == null:
		return
	var c: Color = _state_color(agent_state)
	_state_style.border_color = c
	_state_style.bg_color = Color(c.r, c.g, c.b, 0.12)


func configure(id: String, state: String, rounds: int, color: Color, files: int = 0, children: int = 0, knowledge: String = "", ctx_size: int = 0, stream_chars: int = 0) -> void:
	node_id = id
	agent_state = state
	round_count = rounds
	files_count = files
	children_count = children
	domain_knowledge = knowledge
	_ctx_size = ctx_size
	_stream_chars = stream_chars
	name = id

	# 状态色 → 每实例独立样式（配置可能发生在 _ready 之前，颜色在 _ready 应用）
	_ensure_state_style()
	_apply_state_color()

	# 仅在 @onready 已就绪时更新（否则由 _ready() 处理）
	# 注意：slot 生命周期由 connection_overlay 管理，这里不要清理 slot
	if is_node_ready():
		_update_content()


func _clear_slots() -> void:
	for dir in _slots:
		_slots[dir].clear()
	for container in [left_slot_container, top_slot_container, bottom_slot_container, right_slot_container]:
		if container:
			for child in container.get_children():
				child.queue_free()


## 在指定方向创建一个新 slot 并返回
func add_slot(direction: String) -> NodeSlot:
	var container = null
	var dir_enum: NodeSlot.Direction
	match direction:
		"left": container = left_slot_container; dir_enum = NodeSlot.Direction.LEFT
		"right": container = right_slot_container; dir_enum = NodeSlot.Direction.RIGHT
		"top": container = top_slot_container; dir_enum = NodeSlot.Direction.TOP
		"bottom": container = bottom_slot_container; dir_enum = NodeSlot.Direction.BOTTOM
	if container == null:
		return null
	var slot: NodeSlot = NodeSlotScene.instantiate()
	slot.direction = dir_enum
	container.add_child(slot)
	_slots[direction].append(slot)
	return slot


## 获取指定方向的第 index 个 slot（默认第一个）
func get_slot(direction: String, index: int = 0) -> NodeSlot:
	var arr: Array = _slots.get(direction, [])
	if index >= 0 and index < arr.size():
		return arr[index]
	return null


## 调整指定方向的 slot 数量到 count — 只增减排尾差额，已存在的 slot 保持不动。
## slot 持久化是连线端点采样（get_center）可靠的前提：
## 新建的 slot 要等容器排版才有正确坐标，频繁销毁重建会让采样拿到旧值
func ensure_slot_count(direction: String, count: int) -> void:
	var arr: Array = _slots.get(direction, [])
	while arr.size() < count:
		add_slot(direction)
	while arr.size() > count:
		var slot = arr.pop_back()
		if slot:
			slot.queue_free()


## 指定方向当前的 slot 数量
func slot_count(direction: String) -> int:
	return _slots.get(direction, []).size()


func _update_content() -> void:
	# 直接更新静态 Label 的文本
	if name_label:
		name_label.text = node_id

	if ctx_value_label:
		# LLM 请求中显示实时流入量：ctx + 正在流入（流式心跳驱动，约 0.5s 一跳）
		if agent_state == "LLM_REQUEST" and _stream_chars > 0:
			ctx_value_label.text = "%d+%d" % [_ctx_size, _stream_chars]
		else:
			ctx_value_label.text = "%d" % _ctx_size

	if files_count_value_label:
		files_count_value_label.text = "%d" % files_count


## 根据目标方向返回最佳端口方向名
func best_slot_for(target_dir: Vector2) -> String:
	if absf(target_dir.x) > absf(target_dir.y):
		return "right" if target_dir.x > 0 else "left"
	return "bottom" if target_dir.y > 0 else "top"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			node_clicked.emit(node_id)


static func _state_color(state: String) -> Color:
	match str(state):
		"COMPLETED": return Color.GREEN
		"FAILED": return Color.RED
		"RETRYING", "BLOCKED": return Color.ORANGE
		"RUNNING", "LLM_REQUEST", "TOOL_EXEC": return Color(1, 0.8, 0)
		_: return Color(0.5, 0.5, 0.5)
