class_name AchievementManager
## Achievement System - Manages achievements, tracks progress, and triggers notifications.

extends Node

const SAVE_PATH: String = "user://achievements.cfg"

signal achievement_unlocked(achievement_id: String)
signal achievement_progress_updated(achievement_id: String, progress: int, target: int)

enum Category {
	GENERAL,
	COMBAT,
	WAVE,
	BOSS,
	SCORE
}

class Achievement:
	var id: String
	var name: String
	var description: String
	var category: Category
	var target: int
	var current: int = 0
	var unlocked: bool = false
	
	func _init(p_id: String, p_name: String, p_desc: String, p_category: Category, p_target: int) -> void:
		id = p_id
		name = p_name
		description = p_desc
		category = p_category
		target = p_target
	
	func unlock() -> void:
		if not unlocked:
			unlocked = true
			current = target
	
	func get_progress() -> float:
		if target <= 0:
			return 0.0
		return clampf(float(current) / float(target), 0.0, 1.0)

var _achievements: Dictionary = {}
var _stats: Dictionary = {
	"enemies_killed": 0,
	"bosses_killed": 0,
	"waves_survived": 0,
	"max_wave_reached": 0,
	"high_score_reached": 0,
	"max_weapon_level": 1,
	"powerups_collected": 0,
	"lives_remaining": 0
}

func _ready() -> void:
	_define_achievements()
	_load_progress()

func _define_achievements() -> void:
	# General Achievements
	_achievements["first_blood"] = Achievement.new("first_blood", "First Blood", "Kill your first enemy", Category.GENERAL, 1)
	_achievements["killer_10"] = Achievement.new("killer_10", "Rising Hunter", "Kill 10 enemies", Category.COMBAT, 10)
	_achievements["killer_50"] = Achievement.new("killer_50", "Seasoned Warrior", "Kill 50 enemies", Category.COMBAT, 50)
	_achievements["killer_100"] = Achievement.new("killer_100", "Elite Hunter", "Kill 100 enemies", Category.COMBAT, 100)
	_achievements["killer_500"] = Achievement.new("killer_500", "Massacre Master", "Kill 500 enemies", Category.COMBAT, 500)
	
	# Boss Achievements
	_achievements["boss_slayer"] = Achievement.new("boss_slayer", "Boss Slayer", "Defeat your first Boss", Category.BOSS, 1)
	_achievements["boss_hunter"] = Achievement.new("boss_hunter", "Boss Hunter", "Defeat 5 Bosses", Category.BOSS, 5)
	_achievements["boss_expert"] = Achievement.new("boss_expert", "Boss Expert", "Defeat 10 Bosses", Category.BOSS, 10)
	
	# Wave Achievements
	_achievements["wave_5"] = Achievement.new("wave_5", "Wave Survivor", "Survive to Wave 5", Category.WAVE, 5)
	_achievements["wave_10"] = Achievement.new("wave_10", "Veteran", "Survive to Wave 10", Category.WAVE, 10)
	_achievements["wave_15"] = Achievement.new("wave_15", "War Hero", "Survive to Wave 15", Category.WAVE, 15)
	_achievements["wave_20"] = Achievement.new("wave_20", "Unstoppable", "Survive to Wave 20", Category.WAVE, 20)
	
	# Score Achievements
	_achievements["score_1000"] = Achievement.new("score_1000", "Getting Started", "Reach 1000 points", Category.SCORE, 1000)
	_achievements["score_5000"] = Achievement.new("score_5000", "Above Average", "Reach 5000 points", Category.SCORE, 5000)
	_achievements["score_10000"] = Achievement.new("score_10000", "High Scorer", "Reach 10000 points", Category.SCORE, 10000)
	_achievements["score_50000"] = Achievement.new("score_50000", "Score Master", "Reach 50000 points", Category.SCORE, 50000)
	_achievements["high_score_10000"] = Achievement.new("high_score_10000", "Record Breaker", "Set a high score of 10000 or more", Category.SCORE, 10000)

func record_kill(is_boss: bool = false) -> void:
	_stats.enemies_killed += 1
	_check_achievement_progress("enemies_killed", _stats.enemies_killed)
	
	if is_boss:
		_stats.bosses_killed += 1
		_check_achievement_progress("bosses_killed", _stats.bosses_killed)

func record_wave(wave_number: int) -> void:
	_stats.waves_survived += 1
	if wave_number > _stats.max_wave_reached:
		_stats.max_wave_reached = wave_number
	_check_achievement_progress("max_wave_reached", _stats.max_wave_reached)

func record_score(score: int) -> void:
	_check_achievement_progress("high_score_reached", score)

func record_high_score(high_score: int) -> void:
	_check_achievement_progress("high_score_reached", high_score)

func record_weapon_level(level: int) -> void:
	if level > _stats.max_weapon_level:
		_stats.max_weapon_level = level

func record_powerup() -> void:
	_stats.powerups_collected += 1

func record_lives_remaining(lives: int) -> void:
	_stats.lives_remaining = lives

func _check_achievement_progress(stat_name: String, value: int) -> void:
	match stat_name:
		"enemies_killed":
			_update_and_check("first_blood", value)
			_update_and_check("killer_10", value)
			_update_and_check("killer_50", value)
			_update_and_check("killer_100", value)
			_update_and_check("killer_500", value)
		"bosses_killed":
			_update_and_check("boss_slayer", value)
			_update_and_check("boss_hunter", value)
			_update_and_check("boss_expert", value)
		"max_wave_reached":
			_update_and_check("wave_5", value)
			_update_and_check("wave_10", value)
			_update_and_check("wave_15", value)
			_update_and_check("wave_20", value)
		"high_score_reached":
			_update_and_check("score_1000", value)
			_update_and_check("score_5000", value)
			_update_and_check("score_10000", value)
			_update_and_check("score_50000", value)
			_update_and_check("high_score_10000", value)

func _update_and_check(achievement_id: String, value: int) -> void:
	if not _achievements.has(achievement_id):
		return
	var achievement: Achievement = _achievements[achievement_id]
	if achievement.unlocked:
		return
	achievement.current = value
	achievement_progress_updated.emit(achievement_id, value, achievement.target)
	if value >= achievement.target:
		_unlock_achievement(achievement_id)

func _unlock_achievement(achievement_id: String) -> void:
	if not _achievements.has(achievement_id):
		return
	var achievement: Achievement = _achievements[achievement_id]
	if achievement.unlocked:
		return
	achievement.unlock()
	_save_progress()
	achievement_unlocked.emit(achievement_id)
	print("Achievement Unlocked: ", achievement.name, " - ", achievement.description)

func get_achievement(achievement_id: String) -> Achievement:
	return _achievements.get(achievement_id)

func get_all_achievements() -> Array[Achievement]:
	var result: Array[Achievement] = []
	for achievement: Achievement in _achievements.values():
		result.append(achievement)
	return result

func get_achievements_by_category(category: Category) -> Array[Achievement]:
	var result: Array[Achievement] = []
	for achievement: Achievement in _achievements.values():
		if achievement.category == category:
			result.append(achievement)
	return result

func get_unlocked_count() -> int:
	var count: int = 0
	for achievement: Achievement in _achievements.values():
		if achievement.unlocked:
			count += 1
	return count

func get_total_count() -> int:
	return _achievements.size()

func get_unlocked_ids() -> Array[String]:
	var result: Array[String] = []
	for achievement: Achievement in _achievements.values():
		if achievement.unlocked:
			result.append(achievement.id)
	return result

func get_stats() -> Dictionary:
	return _stats.duplicate()

func reset_stats() -> void:
	_stats = {
		"enemies_killed": 0,
		"bosses_killed": 0,
		"waves_survived": 0,
		"max_wave_reached": 0,
		"high_score_reached": 0,
		"max_weapon_level": 1,
		"powerups_collected": 0,
		"lives_remaining": 0
	}
	_save_progress()

func _save_progress() -> void:
	var config: ConfigFile = ConfigFile.new()
	
	# Save achievement unlocked states
	for achievement: Achievement in _achievements.values():
		config.set_value("achievements", achievement.id, achievement.unlocked)
	
	# Save stats
	for key: String in _stats:
		config.set_value("stats", key, _stats[key])
	
	var err: int = config.save(SAVE_PATH)
	if err != OK:
		push_error("Failed to save achievements: " + str(err))

func _load_progress() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SAVE_PATH)
	
	if err == OK:
		# Load achievement unlocked states
		for achievement: Achievement in _achievements.values():
			if config.has_section_key("achievements", achievement.id):
				achievement.unlocked = config.get_value("achievements", achievement.id, false)
				if achievement.unlocked:
					achievement.current = achievement.target
		
		# Load stats
		for key: String in _stats:
			if config.has_section_key("stats", key):
				_stats[key] = config.get_value("stats", key, _stats[key])
