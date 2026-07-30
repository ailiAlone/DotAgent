## Leaderboard system managing top 10 scores with persistence.
## Stores player names and scores, persists to user://leaderboard.cfg,
## and provides ranking queries.

const MAX_ENTRIES: int = 10
const SAVE_PATH: String = "user://leaderboard.cfg"

signal leaderboard_updated

var _entries: Array = []

func _ready() -> void:
	_load_entries()

func _load_entries() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SAVE_PATH)
	_entries.clear()
	if err == OK:
		var index: int = 0
		while config.has_section_key("leaderboard", str(index)):
			var entry: Dictionary = config.get_value("leaderboard", str(index))
			_entries.append(entry)
			index += 1
	else:
		_entries.clear()

func _save_entries() -> void:
	var config: ConfigFile = ConfigFile.new()
	for i: int in range(_entries.size()):
		config.set_value("leaderboard", str(i), _entries[i])
	var err: int = config.save(SAVE_PATH)
	if err == OK:
		leaderboard_updated.emit()
	else:
		push_error("Failed to save leaderboard: " + str(err))

func add_entry(player_name: String, score: int) -> int:
	var rank: int = get_rank_for_score(score)
	if rank > MAX_ENTRIES:
		return -1
	
	var new_entry: Dictionary = {
		"name": player_name,
		"score": score
	}
	_entries.insert(rank - 1, new_entry)
	
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)
	
	_save_entries()
	return rank

func get_entries() -> Array:
	return _entries.duplicate()

func get_rank_for_score(score: int) -> int:
	var rank: int = 1
	for entry: Dictionary in _entries:
		if score < entry.get("score", 0):
			rank += 1
	return rank

func is_high_score(score: int) -> bool:
	return get_rank_for_score(score) <= MAX_ENTRIES

func get_top_score() -> int:
	if _entries.is_empty():
		return 0
	return _entries[0].get("score", 0)

func clear_entries() -> void:
	_entries.clear()
	_save_entries()
