extends Node

## Singleton that persists game settings to user://settings.cfg.
## Provides defaults for audio (master, sfx, music), difficulty, and input settings.

signal settings_loaded
signal settings_saved
signal master_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal music_volume_changed(value: float)
signal difficulty_changed(value: int)

const _SETTINGS_PATH = "user://settings.cfg"

@export var master_volume: float = 0.8
@export var sfx_volume: float = 0.8
@export var music_volume: float = 0.7
@export var difficulty: int = 1

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_audio_buses()

func load_settings():
	var cfg = ConfigFile.new()
	var err = cfg.load(_SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SettingsManager: failed to load settings, error code %d" % err)

	master_volume = cfg.get_value("audio", "master_volume", 0.8)
	sfx_volume = cfg.get_value("audio", "sfx_volume", 0.8)
	music_volume = cfg.get_value("audio", "music_volume", 0.7)
	difficulty = cfg.get_value("game", "difficulty", 1)

	settings_loaded.emit()

func save_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("game", "difficulty", difficulty)

	var err = cfg.save(_SETTINGS_PATH)
	if err != OK:
		push_warning("SettingsManager: failed to save settings, error code %d" % err)
		return
	settings_saved.emit()

func apply_audio_buses():
	_set_bus_volume_percent("Master", master_volume)
	_set_bus_volume_percent("SFX", sfx_volume)
	_set_bus_volume_percent("Music", music_volume)

func _set_bus_volume_percent(bus_name: String, percent: float):
	var idx = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(percent))

func set_master_volume(value: float):
	master_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume_percent("Master", master_volume)
	master_volume_changed.emit(master_volume)
	save_settings()

func set_sfx_volume(value: float):
	sfx_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume_percent("SFX", sfx_volume)
	sfx_volume_changed.emit(sfx_volume)
	save_settings()

func set_music_volume(value: float):
	music_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume_percent("Music", music_volume)
	music_volume_changed.emit(music_volume)
	save_settings()

func set_difficulty(value: int):
	difficulty = clampi(value, 0, 2)
	difficulty_changed.emit(difficulty)
	save_settings()

func get_difficulty_name(idx: int) -> String:
	match idx:
		0: return "EASY"
		1: return "NORMAL"
		2: return "HARD"
	return "NORMAL"

func get_difficulty_multiplier(idx: int = difficulty) -> float:
	match idx:
		0: return 0.75
		1: return 1.0
		2: return 1.35
	return 1.0
