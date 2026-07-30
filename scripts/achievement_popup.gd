## Achievement Popup - Shows achievement unlock notifications with animation.

extends Control

const POPUP_DURATION: float = 3.0
const ANIMATION_DURATION: float = 0.5

@onready var background: ColorRect = $Background
@onready var icon_label: Label = $IconLabel
@onready var title_label: Label = $TitleLabel
@onready var description_label: Label = $DescriptionLabel

var _timer: float = 0.0
var _animating: bool = false
var _animation_progress: float = 0.0
var _target_x: float = 0.0
var _start_x: float = 0.0

func _ready() -> void:
	visible = false
	modulate.a = 0.0

func show_achievement(achievement_name: String, achievement_description: String) -> void:
	title_label.text = achievement_name
	description_label.text = achievement_description
	
	# Play a sound if audio manager is available
	var am: Node = _am()
	if am != null and am.has_method("play_achievement"):
		am.play_achievement()
	
	visible = true
	modulate.a = 1.0
	
	_animating = true
	_animation_progress = 0.0
	_start_x = -300.0
	_target_x = 20.0
	position.x = _start_x
	
	_timer = POPUP_DURATION

func _process(delta: float) -> void:
	if not visible:
		return
	
	if _animating:
		_animation_progress += delta / ANIMATION_DURATION
		if _animation_progress >= 1.0:
			_animation_progress = 1.0
			_animating = false
		var t: float = ease(_animation_progress, 0.3)
		position.x = lerpf(_start_x, _target_x, t)
	
	_timer -= delta
	if _timer <= 0.0:
		queue_free()

static func _am() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")
