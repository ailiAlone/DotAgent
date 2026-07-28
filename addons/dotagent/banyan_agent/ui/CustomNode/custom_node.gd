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
	_update_content()


func configure(id: String, state: String, rounds: int, color: Color, files: int = 0, children: int = 0, knowledge: String = "") -> void:
	node_id = id
	agent_state = state
	round_count = rounds
	files_count = files
	children_count = children
	domain_knowledge = knowledge
	name = id

	# 状态色 → 边框颜色
	if panel_container:
		var style = panel_container.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = _state_color(state)

	# 仅在 @onready 已就绪时更新（否则由 _ready() 处理）
	if is_node_ready():
		_update_content()
		_clear_slots()


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


## 获取指定方向第 index 个 slot 的中心坐标
func get_slot_center(direction: String, index: int = 0) -> Vector2:
	var slot: NodeSlot = get_slot(direction, index)
	if slot:
		return slot.get_center()
	return global_position + size * 0.5


## 指定方向当前的 slot 数量
func slot_count(direction: String) -> int:
	return _slots.get(direction, []).size()


func _update_content() -> void:
	# 直接更新静态 Label 的文本
	if name_label:
		name_label.text = node_id

	if ctx_value_label:
		ctx_value_label.text = "%d" % domain_knowledge.length()

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
		"RUNNING", "LLM_REQUEST", "TOOL_EXEC": return Color(1, 0.8, 0)
		"BLOCKED": return Color.ORANGE
		_: return Color(0.5, 0.5, 0.5)
