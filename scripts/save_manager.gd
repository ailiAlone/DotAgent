extends Node

## SaveManager autoload singleton.
##
## Handles saving and loading player run progress to user://save.json.
## Public API:
## - save_game(save_data: Dictionary = {}) -> bool
## - load_save() -> Dictionary
## - has_save() -> bool

const SAVE_PATH = "user://save.json"
const SAVE_VERSION = "1.0.0"
const REQUIRED_KEYS = ["score", "high_score", "wave", "lives"]

const DEFAULT_DATA = {
	"version": SAVE_VERSION,
	"score": 0,
	"high_score": 0,
	"wave": 1,
	"lives": 3,
}

func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

func _game():
	var root = Engine.get_main_loop().root
	var tree = get_tree()
	var current = tree.current_scene if tree != null else null
	if current != null and (current.name == "Game" or current.has_method("apply_save_data")):
		return current
	for child in root.get_children():
		if child.name == "Game" or child.has_method("apply_save_data"):
			return child
	return null

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(save_data: Dictionary = {}) -> bool:
	var data = DEFAULT_DATA.duplicate(true)

	# If caller passes values, use them directly.
	for key in REQUIRED_KEYS:
		if save_data.has(key):
			data[key] = save_data[key]

	# Otherwise fall back to live game state.
	var gm = _gm()
	if gm != null and save_data.is_empty():
		var s = gm.get("score")
		var h = gm.get("high_score")
		var l = gm.get("lives")
		if s != null:
			data["score"] = int(s)
		if h != null:
			data["high_score"] = int(h)
		if l != null:
			data["lives"] = int(l)

	var game = _game()
	if game != null and save_data.is_empty():
		var w = game.get("wave")
		if w != null:
			data["wave"] = int(w)
	elif gm != null and save_data.is_empty():
		var gw = gm.get("wave")
		if gw != null:
			data["wave"] = int(gw)

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: Failed to open save file for writing. Error: %s" % str(FileAccess.get_open_error()))
		return false

	file.store_string(JSON.stringify(data, "\t", false, true))
	file.close()
	return true

func load_save() -> Dictionary:
	if not has_save():
		return DEFAULT_DATA.duplicate(true)

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: Failed to open save file for reading. Error: %s" % str(FileAccess.get_open_error()))
		return DEFAULT_DATA.duplicate(true)

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_warning("SaveManager: Failed to parse save JSON. Error: %s at line %d" % [json.get_error_message(), json.get_error_line()])
		return DEFAULT_DATA.duplicate(true)

	var parsed_data = json.data
	if typeof(parsed_data) != TYPE_DICTIONARY:
		push_warning("SaveManager: Save file does not contain a valid Dictionary.")
		return DEFAULT_DATA.duplicate(true)

	var parsed_dict = parsed_data
	if parsed_dict.get("version", "") != SAVE_VERSION:
		push_warning("SaveManager: Save version mismatch (expected %s, got %s). Returning default data." % [SAVE_VERSION, parsed_dict.get("version", "<missing>")])
		return DEFAULT_DATA.duplicate(true)

	for key in REQUIRED_KEYS:
		if not parsed_dict.has(key):
			push_warning("SaveManager: Save data missing required key '%s'. Returning default data." % key)
			return DEFAULT_DATA.duplicate(true)

	var result = DEFAULT_DATA.duplicate(true)
	for key in REQUIRED_KEYS:
		result[key] = parsed_dict[key]

	return result
