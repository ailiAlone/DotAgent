extends Node

## SaveManager autoload singleton.
##
## Handles saving and loading game data to user://save.json.

const SAVE_PATH = "user://save.json"
const SAVE_VERSION = 1
const REQUIRED_KEYS = ["score", "high_score", "wave", "lives", "version", "timestamp"]

func save_game(data: Dictionary) -> bool:
	var save_data := {
		"score": data.get("score", 0),
		"high_score": data.get("high_score", 0),
		"wave": data.get("wave", 0),
		"lives": data.get("lives", 0),
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(save_data))
	file.close()
	return true

func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}

	var text := file.get_as_text()
	file.close()

	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return {}

	var dict = result as Dictionary
	if not _validate_save(dict):
		return {}

	return dict

func _validate_save(dict: Dictionary) -> bool:
	for key in REQUIRED_KEYS:
		if not dict.has(key):
			return false

	if dict["version"] != SAVE_VERSION:
		return false

	for key in ["score", "high_score", "wave", "lives"]:
		var value = dict[key]
		if not (value is int or value is float):
			return false

	return true

static func get_save_summary() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return "No save"

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return "No save"

	var text := file.get_as_text()
	file.close()

	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return "No save"

	var dict = result as Dictionary
	if dict.get("version", -1) != SAVE_VERSION:
		return "No save"

	var required_keys := ["score", "high_score", "wave", "lives", "timestamp"]
	for key in required_keys:
		if not dict.has(key):
			return "No save"

	var wave = dict["wave"]
	var score = dict["score"]
	return "Wave %s - Score %s" % [wave, score]
