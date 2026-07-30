extends CanvasLayer

## Head-up display showing score, lives, high score, current wave, weapon level, boss health, kill feedback and combos.

const Singleton: String = "GameManager"

signal pause_requested
signal resume_requested

@onready var score_label: Label = %ScoreLabel
@onready var high_score_label: Label = %HighScoreLabel
@onready var lives_label: Label = %LivesLabel
@onready var wave_label: Label = %WaveLabel
@onready var weapon_level_label: Label = %WeaponLevelLabel
@onready var pause_overlay: Control = %PauseOverlay
@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var quit_button: Button = %QuitButton
@onready var boss_health_container: VBoxContainer = %BossHealthContainer
@onready var boss_health_label: Label = %BossHealthLabel
@onready var boss_health_bar: ProgressBar = %BossHealthBar
@onready var weather_icon_label: Label = %WeatherIconLabel

@onready var achievement_popup_scene: PackedScene = preload("res://scenes/achievement_popup.tscn")

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
	gm.achievement_unlocked.connect(_on_achievement_unlocked)
	gm.weather_changed.connect(_on_weather_changed)
	_update_pause_overlay(gm.paused)
	_update_boss_health_bar(0, 1)
	_update_boss_health_visibility(false)
	
	if resume_button != null:
		resume_button.pressed.connect(_on_resume_pressed)
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)


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


func _on_resume_pressed() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.set_pause(false)


func _on_restart_pressed() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.set_pause(false)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_quit_pressed() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.set_pause(false)
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_score_changed(value: int) -> void:
	_update_labels_score(value)


func _on_high_score_changed(value: int) -> void:
	_update_labels_highscore(value)


func _on_lives_changed(value: int) -> void:
	_update_labels_lives(value)


func _on_wave_changed(value: int) -> void:
	_update_labels_wave(value)


func _on_game_paused(paused: bool) -> void:
	_update_pause_overlay(paused)


func _on_achievement_unlocked(achievement_id: String) -> void:
	_show_achievement_popup(achievement_id)


func _show_achievement_popup(achievement_id: String) -> void:
	var gm: Node = _gm()
	if gm == null:
		return
	
	var info: Dictionary = gm.get_achievement_info(achievement_id)
	if info.is_empty():
		return
	
	var popup: Node = achievement_popup_scene.instantiate()
	add_child(popup)
	popup.show_achievement(info.get("name", ""), info.get("description", ""))


func _update_labels(score: int, high_score: int, lives: int, wave: int) -> void:
	if score_label != null:
		score_label.text = str(score)
	if high_score_label != null:
		high_score_label.text = "HI: " + str(high_score)
	if lives_label != null:
		lives_label.text = str(lives)
	if wave_label != null:
		wave_label.text = "WAVE " + str(wave)


func _update_labels_score(score: int) -> void:
	if score_label != null:
		score_label.text = str(score)


func _update_labels_highscore(high_score: int) -> void:
	if high_score_label != null:
		high_score_label.text = "HI: " + str(high_score)


func _update_labels_lives(lives: int) -> void:
	if lives_label != null:
		lives_label.text = str(lives)


func _update_labels_wave(wave: int) -> void:
	if wave_label != null:
		wave_label.text = "WAVE " + str(wave)


func _update_pause_overlay(paused: bool) -> void:
	if pause_overlay != null:
		pause_overlay.visible = paused


func _update_boss_health_visibility(visible: bool) -> void:
	if boss_health_container != null:
		boss_health_container.visible = visible


func _update_boss_health_bar(current: int, max_val: int) -> void:
	if boss_health_label != null:
		boss_health_label.text = str(current) + " / " + str(max_val)
	if boss_health_bar != null:
		boss_health_bar.max_value = max_val
		boss_health_bar.value = current


func show_boss_health(current: int, max_val: int) -> void:
	_update_boss_health_bar(current, max_val)
	_update_boss_health_visibility(true)


func hide_boss_health() -> void:
	_update_boss_health_visibility(false)


func update_boss_health(current: int, max_val: int) -> void:
	_update_boss_health_bar(current, max_val)


func set_weather_icon(weather_type: int) -> void:
	if weather_icon_label == null:
		return
	var icons: Array[String] = ["☀️", "🌧️", "❄️", "⛈️", "🌫️", "💨"]
	if weather_type >= 0 and weather_type < icons.size():
		weather_icon_label.text = icons[weather_type]
	else:
		weather_icon_label.text = "☀️"


func _on_weather_changed(weather_type: int) -> void:
	set_weather_icon(weather_type)


func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
