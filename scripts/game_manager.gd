extends Node

signal score_changed(new_score)
signal high_score_changed(new_high_score)
signal lives_changed(new_lives)

const SAVE_PATH = "user://leaderboard.save"
const MAX_ENTRIES = 10

var score: int = 0:
	set(value):
		score = max(0, value)
		score_changed.emit(score)

var high_score: int = 0:
	set(value):
		if value == high_score:
			return
		high_score = value
		high_score_changed.emit(high_score)

var lives: int = 3:
	set(value):
		lives = clamp(value, 0, 5)
		lives_changed.emit(lives)

var combo: int = 0
var combo_timer: float = 0.0
var score_multiplier: float = 1.0
var score_multiplier_timer: float = 0.0

# Leaderboard entries: [{"score": int, "date": String, "wave": int}]
var leaderboard: Array = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_leaderboard()
	_update_high_score_from_leaderboard()

func reset_run():
	score = 0
	lives = 3
	combo = 0
	combo_timer = 0.0
	score_multiplier = 1.0
	score_multiplier_timer = 0.0
	var cs = Engine.get_main_loop().root.get_node_or_null("CraftingSystem")
	if cs != null and cs.has_method("reset_inventory"):
		cs.reset_inventory()

func add_score(amount: int):
	var multiplier = (1 + combo / 10) * score_multiplier
	score += int(amount * multiplier)
	combo += 1
	combo_timer = 2.0

func tick_combo(delta: float):
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0
	if score_multiplier > 1.0:
		score_multiplier_timer -= delta
		if score_multiplier_timer <= 0:
			score_multiplier = 1.0

# --- Leaderboard API ---

func record_score(value: int, wave: int = 1) -> bool:
	if value <= 0:
		return false
	var entry = {
		"score": value,
		"date": _format_date(),
		"wave": wave
	}
	leaderboard.append(entry)
	leaderboard.sort_custom(func(a, b): return a["score"] > b["score"])
	if leaderboard.size() > MAX_ENTRIES:
		leaderboard.resize(MAX_ENTRIES)
	_update_high_score_from_leaderboard()
	save_leaderboard()
	return entry in leaderboard

func get_leaderboard() -> Array:
	return leaderboard.duplicate()

func get_top_score() -> int:
	return high_score

func is_top_score(value: int) -> bool:
	if value <= 0:
		return false
	if leaderboard.is_empty():
		return true
	return value > leaderboard[0]["score"]

func is_on_leaderboard(value: int) -> bool:
	if value <= 0:
		return false
	if leaderboard.size() < MAX_ENTRIES:
		return true
	return value > leaderboard[-1]["score"]

func _update_high_score_from_leaderboard():
	if leaderboard.is_empty():
		return
	high_score = leaderboard[0]["score"]

func _format_date() -> String:
	var dt = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

# --- Persistence ---

func load_leaderboard():
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("GameManager: failed to open leaderboard save for reading: ", FileAccess.get_open_error())
		return
	var json := f.get_as_text()
	f.close()
	if json.is_empty():
		return
	var parsed = JSON.parse_string(json)
	if parsed is Array:
		leaderboard = parsed
		# Ensure valid entries
		leaderboard = leaderboard.filter(func(e): return e is Dictionary and e.has("score") and e["score"] is int)
		leaderboard.sort_custom(func(a, b): return a["score"] > b["score"])
		if leaderboard.size() > MAX_ENTRIES:
			leaderboard.resize(MAX_ENTRIES)
	else:
		push_warning("GameManager: leaderboard save format invalid")

func save_leaderboard():
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("GameManager: failed to open leaderboard save for writing: ", FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(leaderboard))
	f.close()
