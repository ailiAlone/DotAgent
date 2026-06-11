extends Control

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

var final_score = 0
var wave_reached = 1

@onready var title: Label = $Center/Title
@onready var score_label: Label = $Center/ScoreLabel
@onready var best_label: Label = $Center/BestLabel
@onready var wave_label: Label = $Center/WaveLabel
@onready var new_record: Label = $Center/NewRecord
@onready var retry: Button = $Center/Retry
@onready var menu: Button = $Center/Menu

func _ready():
	top_level = true
	# Subscribe to viewport resize for adaptation
	if get_viewport():
		get_viewport().size_changed.connect(_on_viewport_resized)
	_resize_self()
	title.text = "GAME OVER"
	score_label.text = "SCORE  %06d" % final_score
	best_label.text = "BEST   %06d" % _gm().high_score
	wave_label.text = "REACHED WAVE %d" % wave_reached
	var is_record = final_score > 0 and final_score >= _gm().high_score
	new_record.visible = is_record
	retry.text = "RETRY    再来一次"
	menu.text = "MENU     主菜单"
	retry.pressed.connect(_on_retry)
	menu.pressed.connect(_on_menu)
	retry.grab_focus()
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)

func _process(_delta):
	# Continuously ensure size matches viewport (in case viewport wasn't ready at _ready)
	if size.x <= 100 or size.y <= 100:
		_resize_self()

func _on_viewport_resized():
	_resize_self()

func _resize_self():
	# Try to get viewport size; fall back to project setting
	var vp = Vector2(1280, 720)
	if get_viewport():
		var vr = get_viewport().get_visible_rect().size
		if vr.x > 100 and vr.y > 100:
			vp = vr
		else:
			var pr = get_viewport().get_visible_rect().size
			# In headless, get_visible_rect may be tiny; use project setting
			vp = Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
				ProjectSettings.get_setting("display/window/size/viewport_height", 720)
			)
	position = Vector2.ZERO
	size = vp

func _find_main():
	var n = get_parent()
	while n != null and n.name != "Main":
		n = n.get_parent()
	return n

func _on_retry():
	_am().play_sfx("click")
	var main = _find_main()
	if main == null:
		main = get_tree().root
	var game = preload("res://scenes/game.tscn").instantiate()
	main.add_child(game)
	queue_free()

func _on_menu():
	_am().play_sfx("click")
	var main = _find_main()
	if main == null:
		main = get_tree().root
	var m = preload("res://scenes/menu.tscn").instantiate()
	main.add_child(m)
	queue_free()