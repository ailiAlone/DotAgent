extends Control

signal back_pressed

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var title: Label = $Center/Title
@onready var list_container: VBoxContainer = $Center/Scroll/List
@onready var empty_label: Label = $Center/EmptyLabel
@onready var back_btn: Button = $Center/BackBtn

func _ready():
	top_level = true
	if get_viewport():
		get_viewport().size_changed.connect(_on_viewport_resized)
	_resize_self()
	title.text = "LEADERBOARD"
	back_btn.text = "BACK    返回"
	back_btn.pressed.connect(_on_back)
	back_btn.grab_focus()
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	_refresh_list()

func _process(_delta):
	if size.x <= 100 or size.y <= 100:
		_resize_self()

func _on_viewport_resized():
	_resize_self()

func _resize_self():
	var vp = Vector2(1280, 720)
	if get_viewport():
		var vr = get_viewport().get_visible_rect().size
		if vr.x > 100 and vr.y > 100:
			vp = vr
	position = Vector2.ZERO
	size = vp

func _get_scene_holder() -> Node:
	var n = get_parent()
	while n != null and n.name != "Main":
		n = n.get_parent()
	return n if n != null else get_tree().root

func _refresh_list():
	for c in list_container.get_children():
		c.queue_free()
	var entries = _gm().get_leaderboard()
	if entries.is_empty():
		empty_label.visible = true
		list_container.visible = false
		return
	empty_label.visible = false
	list_container.visible = true
	for i in range(entries.size()):
		var e = entries[i]
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 24)
		var rank_label = _make_label("#%d" % (i + 1), 80)
		var score_label = _make_label("%06d" % e.get("score", 0), 140)
		var wave_label = _make_label("WAVE %d" % e.get("wave", 1), 100)
		var date_label = _make_label(str(e.get("date", "")), 120)
		if i == 0:
			rank_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		row.add_child(rank_label)
		row.add_child(score_label)
		row.add_child(wave_label)
		row.add_child(date_label)
		list_container.add_child(row)

func _make_label(text: String, min_width: int) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = min_width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _on_back():
	_am().play_sfx("click")
	back_pressed.emit()
	var holder = _get_scene_holder()
	var menu = preload("res://scenes/menu.tscn").instantiate()
	holder.add_child(menu)
	queue_free()
