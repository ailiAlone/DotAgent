extends Node

## Autoload singleton managing game state: score, high score, lives, current wave, and achievements.

const Singleton: String = "GameManager"
const LEADERBOARD_NAME: String = "Player"

signal score_changed(score: int)
signal high_score_changed(high_score: int)
signal lives_changed(lives: int)
signal wave_changed(wave: int)
signal game_paused(paused: bool)
signal rank_calculated(rank: int)
signal achievement_unlocked(achievement_id: String)
signal weather_changed(weather_type: int)

@export var starting_lives: int = 3
@export var max_lives: int = 99

var score: int = 0
var high_score: int = 0
var lives: int = 3
var wave: int = 1
var paused: bool = false
var _current_rank: int = -1
var _achievement_manager: Node = null

func _ready() -> void:
	load_high_score()
	_setup_achievement_manager()

func _setup_achievement_manager() -> void:
	_achievement_manager = Engine.get_main_loop().root.get_node_or_null("AchievementManager")
	if _achievement_manager != null:
		_achievement_manager.achievement_unlocked.connect(_on_achievement_unlocked)

func reset() -> void:
	score = 0
	wave = 1
	lives = starting_lives
	paused = false
	_current_rank = -1
	get_tree().paused = false
	score_changed.emit(score)
	high_score_changed.emit(high_score)
	lives_changed.emit(lives)
	wave_changed.emit(wave)
	game_paused.emit(paused)

func add_score(amount: int) -> void:
	score += amount
	if score > high_score:
		high_score = score
		save_high_score()
	score_changed.emit(score)
	high_score_changed.emit(high_score)
	_record_score_achievements()

func add_life(amount: int) -> void:
	lives += amount
	if lives > max_lives:
		lives = max_lives
	lives_changed.emit(lives)

func take_life() -> void:
	lives -= 1
	if lives < 0:
		lives = 0
	lives_changed.emit(lives)
	if lives <= 0:
		_game_over()

func next_wave() -> void:
	wave += 1
	wave_changed.emit(wave)
	_record_wave_achievements()

func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	game_paused.emit(paused)

func set_pause(value: bool) -> void:
	paused = value
	get_tree().paused = paused
	game_paused.emit(paused)

func save_high_score() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("game", "high_score", high_score)
	var err: int = config.save("user://high_score.cfg")
	if err != OK:
		push_error("Failed to save high score: " + str(err))

func load_high_score() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load("user://high_score.cfg")
	if err == OK and config.has_section_key("game", "high_score"):
		high_score = config.get_value("game", "high_score") as int
	else:
		high_score = 0
	high_score_changed.emit(high_score)

func get_score() -> int:
	return score

func submit_to_leaderboard(player_name: String) -> int:
	var lb: Node = _lb()
	if lb != null and lb.has_method("add_entry"):
		var rank: int = lb.add_entry(player_name, score)
		_current_rank = rank
		rank_calculated.emit(rank)
		return rank
	return -1

func get_current_rank() -> int:
	return _current_rank

func calculate_rank() -> int:
	var lb: Node = _lb()
	if lb != null and lb.has_method("get_rank_for_score"):
		return lb.get_rank_for_score(score)
	return -1

func is_high_score_for_leaderboard() -> bool:
	var lb: Node = _lb()
	if lb != null and lb.has_method("is_high_score"):
		return lb.is_high_score(score)
	return false

func _game_over() -> void:
	_record_game_over_achievements()
	var lb: Node = _lb()
	if lb != null and lb.has_method("is_high_score"):
		if not lb.is_high_score(score):
			get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func _record_score_achievements() -> void:
	if _achievement_manager != null and _achievement_manager.has_method("record_score"):
		_achievement_manager.record_score(score)
	if _achievement_manager != null and _achievement_manager.has_method("record_high_score"):
		_achievement_manager.record_high_score(high_score)

func _record_wave_achievements() -> void:
	if _achievement_manager != null and _achievement_manager.has_method("record_wave"):
		_achievement_manager.record_wave(wave)

func _record_game_over_achievements() -> void:
	if _achievement_manager != null and _achievement_manager.has_method("record_lives_remaining"):
		_achievement_manager.record_lives_remaining(lives)

func record_enemy_killed(is_boss: bool = false) -> void:
	if _achievement_manager != null and _achievement_manager.has_method("record_kill"):
		_achievement_manager.record_kill(is_boss)

func record_powerup_collected() -> void:
	if _achievement_manager != null and _achievement_manager.has_method("record_powerup"):
		_achievement_manager.record_powerup()

func record_weapon_level(level: int) -> void:
	if _achievement_manager != null and _achievement_manager.has_method("record_weapon_level"):
		_achievement_manager.record_weapon_level(level)

func _on_achievement_unlocked(achievement_id: String) -> void:
	achievement_unlocked.emit(achievement_id)

func get_achievement_info(achievement_id: String) -> Dictionary:
	if _achievement_manager != null and _achievement_manager.has_method("get_achievement"):
		var achievement = _achievement_manager.get_achievement(achievement_id)
		if achievement != null:
			return {
				"name": achievement.name,
				"description": achievement.description,
				"unlocked": achievement.unlocked
			}
	return {}

static func _lb() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Leaderboard")
