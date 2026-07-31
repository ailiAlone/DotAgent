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
signal combo_changed(combo_count: int, is_milestone: bool)
signal kills_changed(kills: int)
signal best_kills_changed(best_kills: int)
signal victory_requested(final_kills: int)

@export var starting_lives: int = 3
@export var max_lives: int = 99

var score: int = 0
var high_score: int = 0
var lives: int = 3
var wave: int = 1
var paused: bool = false
var _current_rank: int = -1
var _achievement_manager: Node = null

# Kill tracking
var kills: int = 0
var best_kills: int = 0

# Combo system
const COMBO_TIMEOUT: float = 5.0
var _combo_count: int = 0
var _combo_timer: float = 0.0

func _ready() -> void:
	load_high_score()
	load_best_kills()
	_setup_achievement_manager()


func _setup_achievement_manager() -> void:
	_achievement_manager = Engine.get_main_loop().root.get_node_or_null("AchievementManager")
	if _achievement_manager != null:
		_achievement_manager.achievement_unlocked.connect(_on_achievement_unlocked)


func _process(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0
			combo_changed.emit(0, false)


func reset() -> void:
	score = 0
	wave = 1
	lives = starting_lives
	paused = false
	_current_rank = -1
	_combo_count = 0
	_combo_timer = 0.0
	reset_kills()
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


func trigger_victory() -> void:
	victory_requested.emit(kills)


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


# Combo system methods
func increment_combo() -> void:
	_combo_count += 1
	_combo_timer = COMBO_TIMEOUT
	
	# Check if this is a milestone (5, 10, 15, 20, ...)
	var is_milestone: bool = (_combo_count > 0) and (_combo_count % 5 == 0)
	combo_changed.emit(_combo_count, is_milestone)


func get_combo_count() -> int:
	return _combo_count


func reset_combo() -> void:
	_combo_count = 0
	_combo_timer = 0.0
	combo_changed.emit(0, false)


static func _lb() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Leaderboard")


# Kill tracking methods
func record_kill() -> void:
	kills += 1
	kills_changed.emit(kills)
	if kills > best_kills:
		best_kills = kills
		save_best_kills()
		best_kills_changed.emit(best_kills)


func get_kills() -> int:
	return kills


func save_best_kills() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("game", "best_kills", best_kills)
	var err: int = config.save("user://save.cfg")
	if err != OK:
		push_error("Failed to save best kills: " + str(err))


func load_best_kills() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load("user://save.cfg")
	if err == OK and config.has_section_key("game", "best_kills"):
		best_kills = config.get_value("game", "best_kills") as int
	else:
		best_kills = 0
	best_kills_changed.emit(best_kills)


func reset_kills() -> void:
	kills = 0
	kills_changed.emit(kills)
