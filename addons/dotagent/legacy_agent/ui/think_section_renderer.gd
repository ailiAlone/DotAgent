@tool
class_name ThinkSectionRenderer
extends RefCounted
## Think 折叠块渲染器（拆自 dock.gd）
##
## 参考版样式:
##   💭 思考过程 ▾  ← Label（灰色小字，鼠标点击切换）
##   ─────────────
##   think 内容...   ← RichTextLabel（灰色小字，流式时展开，完成后折叠）
##
## 使用:
##   var r := ThinkSectionRenderer.new()
##   r.create(parent_vbox, anchor_node)   # content 默认展开(visible=true)
##   r.content.text = "thinking..."
##   r.finalize()  # 折叠 content + 切换箭头

var section: VBoxContainer = null
var header: Label = null
var content: RichTextLabel = null
var _parent: Node = null
var _anchor: Node = null
var _finalized: bool = false


## 创建 think section，插入到 anchor 节点之前（思考 → 回复）
## 默认 content 展开 — 流式时用户可见思考过程
func create(parent: VBoxContainer, anchor: Node) -> void:
	_parent = parent
	_anchor = anchor
	section = VBoxContainer.new()
	section.name = "ThinkSection"

	# Label 做折叠按钮 — 灰色小字，鼠标悬停变色提示可点击
	header = Label.new()
	header.text = "💭 思考过程 ▾"
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.custom_minimum_size = Vector2(100, 20)
	header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	header.add_theme_font_size_override("font_size", 12)
	header.mouse_entered.connect(func():
		header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	)
	header.mouse_exited.connect(func():
		header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	)
	section.add_child(header)

	# ThinkContent 容器包裹 RichTextLabel
	var content_box := VBoxContainer.new()
	content_box.name = "ThinkContent"
	content_box.visible = true  # 流式时展开

	content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.fit_content = true
	content.selection_enabled = true
	content.add_theme_color_override("default_color", Color(0.5, 0.5, 0.5))
	content.add_theme_font_size_override("normal_font_size", 12)
	content_box.add_child(content)
	section.add_child(content_box)

	# 插入到 anchor 之前（思考 → 回复）
	var anchor_idx := -1
	if anchor and anchor.get_parent() == parent:
		anchor_idx = anchor.get_index()
	if anchor_idx >= 0:
		parent.add_child(section)
		parent.move_child(section, anchor_idx)
	else:
		parent.add_child(section)

	# 点击事件绑定
	var sec := section
	header.gui_input.connect(func(ev): _toggle(sec, ev))
	section.gui_input.connect(func(ev): _toggle(sec, ev))


## 标记 think 块完成 — 折叠内容 + 切换箭头
func finalize() -> void:
	_finalized = true
	var content_box: VBoxContainer = null
	if section and is_instance_valid(section):
		content_box = section.get_node_or_null("ThinkContent") as VBoxContainer
	if content_box:
		content_box.visible = false
	if header and is_instance_valid(header):
		header.text = "💭 思考过程 ▸"


## 释放内部引用（节点保留在场景中）
func reset() -> void:
	section = null
	header = null
	content = null
	_parent = null
	_anchor = null
	_finalized = false


func _toggle(sec: VBoxContainer, event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if sec == null or not is_instance_valid(sec):
		return
	var content_box := sec.get_node_or_null("ThinkContent") as VBoxContainer
	if content_box == null:
		return
	content_box.visible = not content_box.visible
	var lbl := sec.get_child(0) as Label
	if lbl:
		lbl.text = "💭 思考过程 ▾" if content_box.visible else "💭 思考过程 ▸"
