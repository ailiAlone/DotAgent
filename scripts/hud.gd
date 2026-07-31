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
@onready var combo_label: Label = %ComboLabel
@onready var kills_label: Label = %KillsLabel
@onready var best_kills_label: Label = %BestKillsLabel

@onready var achievement_popup_scene: PackedScene = preload("res://scenes/achievement_popup.tscn")
@onready var victory_panel_scene: PackedScene = preload("res://scenes/victory_panel.tscn")

var _kill_count: int = 0
var _combo_timer: float = 0.0
var _combo_count: int = 0
var _victory_panel: Control = null

# Combo milestone popup
var _combo_popup_label: Label = null
var _combo_popup_tween: Tween = null


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
	gm.combo_changed.connect(_on_combo_changed)
	gm.kills_changed.connect(_on_kills_changed)
	gm.best_kills_changed.connect(_on_best_kills_changed)
	gm.victory_requested.connect(_on_victory_requested)
	_update_kills_label(gm.kills)
	_update_best_kills_label(gm.best_kills)
	_update_pause_overlay(gm.paused)
	_update_boss_health_bar(0, 1)
	_update_boss_health_visibility(false)
	_update_combo_label(0)
	
	if resume_button != null:
		resume_button.pressed.connect(_on_resume_pressed)
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)
	
	# Create combo popup label (hidden initially)
	_create_combo_popup()


func _process(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0
			_update_combo_label(0)


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


func _on_combo_changed(combo_count: int, is_milestone: bool) -> void:
	_combo_count = combo_count
	_update_combo_label(combo_count)
	
	# Flash gold when combo reaches a multiple of 10
	if combo_count > 0 and combo_count % 10 == 0:
		_flash_combo_gold()
	
	if is_milestone and combo_count > 0:
		_show_combo_milestone_popup(combo_count)


func _on_kills_changed(kills: int) -> void:
	_update_kills_label(kills)


func _on_best_kills_changed(best_kills: int) -> void:
	_update_best_kills_label(best_kills)


func _on_victory_requested(final_kills: int) -> void:
	_show_victory_panel(final_kills)


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


# Kills tracking methods
func _update_kills_label(kills: int) -> void:
	if kills_label != null:
		kills_label.text = "KILLS: " + str(kills)


func _update_best_kills_label(best_kills: int) -> void:
	if best_kills_label != null:
		best_kills_label.text = "BEST: " + str(best_kills)


func _check_new_best_kills(kills: int, best_kills: int) -> void:
	if kills >= best_kills and best_kills > 0:
		_show_new_best_kills_popup(kills)


func _show_new_best_kills_popup(kills: int) -> void:
	_show_achievement_popup("new_best_kills_" + str(kills))


# Combo system methods
func _update_combo_label(combo_count: int) -> void:
	if combo_label != null:
		if combo_count > 0:
			combo_label.text = "x" + str(combo_count)
			combo_label.visible = true
			# Scale effect based on combo
			var scale: float = 1.0 + (combo_count * 0.02)
			scale = minf(scale, 1.5)  # Cap at 1.5x
			combo_label.scale = Vector2(scale, scale)
		else:
			combo_label.text = ""
			combo_label.visible = false


func _flash_combo_gold() -> void:
	if combo_label == null:
		return
	
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	
	# Flash gold color (from white to gold and back)
	var gold_color: Color = Color(1.0, 0.84, 0.0, 1.0)
	var normal_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	
	# First flash: white to gold
	tween.tween_property(combo_label, "modulate", gold_color, 0.1)
	# Then gold to white
	tween.tween_property(combo_label, "modulate", normal_color, 0.2)
	# Scale bounce effect
	tween.tween_property(combo_label, "scale", combo_label.scale * 1.3, 0.1).set_trans(Tween.TRANS_BACK)
	tween.tween_property(combo_label, "scale", combo_label.scale, 0.2).set_trans(Tween.TRANS_ELASTIC)


func _create_combo_popup() -> void:
	_combo_popup_label = Label.new()
	_combo_popup_label.name = "ComboPopupLabel"
	_combo_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_popup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_popup_label.z_index = 100
	_combo_popup_label.modulate = Color(1.0, 0.8, 0.0, 1.0)  # Gold color
	
	# Position at screen center
	_combo_popup_label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_combo_popup_label)


func _show_combo_milestone_popup(combo_count: int) -> void:
	if _combo_popup_label == null:
		return
	
	# Stop any existing tween
	if _combo_popup_tween != null and _combo_popup_tween.is_valid():
		_combo_popup_tween.kill()
	
	# Set text and reset transform
	_combo_popup_label.text = "COMBO x" + str(combo_count) + "!"
	_combo_popup_label.scale = Vector2(0.5, 0.5)
	_combo_popup_label.modulate = Color(1.0, 0.8, 0.0, 1.0)
	
	# Play combo milestone sound
	_play_combo_sound()
	
	# Create tween for scale up and fade out
	_combo_popup_tween = create_tween()
	_combo_popup_tween.set_parallel(true)
	
	# Scale up animation
	_combo_popup_tween.tween_property(_combo_popup_label, "scale", Vector2(2.0, 2.0), 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Fade out animation (delayed)
	_combo_popup_tween.tween_property(_combo_popup_label, "modulate:a", 0.0, 0.5)\
		.set_delay(0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)


func _play_combo_sound() -> void:
	var audio_manager: Node = Engine.get_main_loop().root.get_node_or_null("AudioManager")
	if audio_manager != null and audio_manager.has_method("play_combo"):
		audio_manager.play_combo()


# Victory panel methods
func _show_victory_panel(final_kills: int) -> void:
	if _victory_panel != null:
		_victory_panel.queue_free()
	
	if victory_panel_scene == null:
		return
	
	_victory_panel = victory_panel_scene.instantiate()
	add_child(_victory_panel)
	
	if _victory_panel.has_method("show_victory_screen"):
		_victory_panel.show_victory_screen(final_kills)


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


func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
