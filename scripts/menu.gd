extends Control

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var title: Label = $Center/Title
@onready var subtitle: Label = $Center/Subtitle
@onready var best_label: Label = $Center/Best
@onready var start_btn: Button = $Center/StartBtn
@onready var quit_btn: Button = $Center/QuitBtn
@onready var controls: Label = $Center/Controls
@onready var credits: Label = $Center/Credits

var t = 0.0
var star_field: Node2D

func _ready():
	title.text = "STAR HUNTER"
	subtitle.text = "星 海 猎 手"
	best_label.text = "BEST  %06d" % _gm().high_score
	start_btn.text = "START    开始"
	quit_btn.text = "QUIT     退出"
	controls.text = "[WASD / 方向键] 移动     [SPACE] 射击     [ESC] 暂停"
	credits.text = "v1.0 · Made with Godot 4"
	start_btn.pressed.connect(_on_start)
	quit_btn.pressed.connect(_on_quit)
	start_btn.grab_focus()
	star_field = preload("res://scenes/star_field.tscn").instantiate()
	add_child(star_field)
	star_field.position = Vector2(size.x / 2, size.y / 2)
	star_field.z_index = -10
	_am().play_music("menu")

func _process(delta):
	t += delta
	title.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(t * 1.5))
	if Input.is_action_just_pressed("ui_accept"):
		_on_start()

func _on_start():
	_am().play_sfx("click")
	_am().stop_music()
	var game = preload("res://scenes/game.tscn").instantiate()
	get_parent().add_child(game)
	queue_free()

func _on_quit():
	_am().play_sfx("click")
	get_tree().quit()