class_name SaveManager
extends Node

## SaveManager autoload singleton.
##
## Handles saving and loading player progress to user://save.json.
## Public API:
## - save_game(save_data: Dictionary) -> bool
## - load_game() -> Dictionary

signal game_saved(success: bool)
signal game_loaded(data: Dictionary)

const SAVE_PATH = "user://save.json"
const DEFAULT_DATA = {
	"score": 0,
	"high_score": 0,
	"wave": 1,
	"lives": 3,
}
const REQUIRED_KEYS = ["score", "high_score", "wave", "lives"]

func save_game(save_data: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("SaveManager: Failed to open save file for writing. Error: " + str(FileAccess.get_open_error()))
		game_saved.emit(false)
		return false

	var data := save_data.duplicate(true)
	for key in REQUIRED_KEYS:
		if not data.has(key):
			data[key] = DEFAULT_DATA[key]

	var json_text := JSON.stringify(data, "\t", false, true)
	file.store_string(json_text)
	file = null

	game_saved.emit(true)
	return true


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("SaveManager: No save file found at " + SAVE_PATH + ". Returning default data.")
		return DEFAULT_DATA.duplicate(true)

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_warning("SaveManager: Failed to open save file for reading. Error: " + str(FileAccess.get_open_error()))
		return DEFAULT_DATA.duplicate(true)

	var json_text := file.get_as_text()
	file = null

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_warning("SaveManager: Failed to parse save JSON. Error: " + json.get_error_message() + " at line " + str(json.get_error_line()))
		return DEFAULT_DATA.duplicate(true)

	var parsed_data: Dictionary = json.data
	if typeof(parsed_data) != TYPE_DICTIONARY:
		push_warning("SaveManager: Save file does not contain a valid Dictionary. Returning default data.")
		return DEFAULT_DATA.duplicate(true)

	var result := DEFAULT_DATA.duplicate(true)
	for key in REQUIRED_KEYS:
		if parsed_data.has(key):
			result[key] = parsed_data[key]

	game_loaded.emit(result)
	return result


func _ready():
	pass
