extends CanvasLayer

## Head-up display showing score, lives, high score, current wave, weapon level, kill feedback and combos.

const Singleton: String = "GameManager"

signal pause_requested
signal resume_requested

@onready var score_label: Label = %ScoreLabel
@onready var high_score_label: Label = %HighScoreLabel
@onready var lives_label: Label = %LivesLabel
@onready var wave_label: Label = %WaveLabel
@onready var weapon_level_label: Label = %WeaponLevelLabel
@onready var pause_overlay: Control = %PauseOverlay

var _kill_count: int = 0
var _combo_timer: float = 0.0
var _combo_count: int = 0


func _ready() -> void:
	var gm: Node = _gm()
	if gm == null:
		push_warning("GameManager autoload not found.")
		return
	_update_labels(gm.score, gm.high_score, gm.lives, gm.wave)
	gm.score_changed.connect(_on_score_changed)
	gm.high_score_changed.connect(_on_high_score_changed)
	gm.lives_changed.connect(_on_lives_changed)
	gm.wave_changed.connect(_on_wave_changed)
	gm.game_paused.connect(_on_game_paused)
	_update_pause_overlay(gm.paused)


func _process(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var gm: Node = _gm()
		if gm != null:
			gm.toggle_pause()
			get_viewport().set_input_as_handled()


func _on_score_changed(value: int) -> void:
	_update_labels(value, -1, -1, -1)


func _on_high_score_changed(value: int) -> void:
	_update_labels(-1, value, -1, -1)


func _on_lives_changed(value: int) -> void:
	_update_labels(-1, -1, value, -1)


func _on_wave_changed(value: int) -> void:
	_update_labels(-1, -1, -1, value)


func _on_game_paused(is_paused: bool) -> void:
	_update_pause_overlay(is_paused)


func set_weapon_level(level: int) -> void:
	if weapon_level_label != null:
		weapon_level_label.text = "LVL: " + str(level)


func _update_labels(new_score: int = -1, new_high_score: int = -1, new_lives: int = -1, new_wave: int = -1) -> void:
	if new_score >= 0 and score_label != null:
		score_label.text = "SCORE: " + str(new_score)
	if new_high_score >= 0 and high_score_label != null:
		high_score_label.text = "HI: " + str(new_high_score)
	if new_lives >= 0 and lives_label != null:
		lives_label.text = "LIVES: " + str(new_lives)
	if new_wave >= 0 and wave_label != null:
		wave_label.text = "WAVE: " + str(new_wave)


func _update_pause_overlay(is_paused: bool) -> void:
	if pause_overlay != null:
		pause_overlay.visible = is_paused


func show_kill_feedback(world_position: Vector2, current_score: int) -> void:
	_kill_count += 1
	_combo_count += 1
	_combo_timer = 2.0

	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(1.0, 1.0, 0.3, 1.0)
	label.text = _build_feedback_text(current_score)

	var canvas_position: Vector2 = world_position
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		canvas_position = world_position - camera.get_screen_center_position() + get_viewport().get_visible_rect().size * 0.5
	label.position = canvas_position
	add_child(label)

	var tween: Tween = create_tween()
	if tween != null:
		tween.set_parallel(true)
		tween.tween_property(label, "position:y", label.position.y - 40.0, 0.6)
		tween.tween_property(label, "modulate:a", 0.0, 0.6)
		tween.chain().tween_callback(label.queue_free)


func _build_feedback_text(current_score: int) -> String:
	var text: String = "KILL!\n+" + str(current_score)
	if _combo_count >= 3:
		text += "\n" + str(_combo_count) + " COMBO!"
	return text


static func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
