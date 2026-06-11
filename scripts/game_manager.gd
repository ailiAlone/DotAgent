extends Node

signal score_changed(new_score)
signal high_score_changed(new_high_score)
signal lives_changed(new_lives)

const SAVE_PATH = "user://high_score.save"

var score: int = 0:
	set(value):
		score = max(0, value)
		score_changed.emit(score)
		if score > high_score:
			high_score = score

var high_score: int = 0:
	set(value):
		if value == high_score:
			return
		high_score = value
		high_score_changed.emit(high_score)
		save_high_score()

var lives: int = 3:
	set(value):
		lives = clamp(value, 0, 5)
		lives_changed.emit(lives)

var combo: int = 0
var combo_timer: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_high_score()

func reset_run():
	score = 0
	lives = 3
	combo = 0
	combo_timer = 0.0

func add_score(amount: int):
	var multiplier = 1 + combo / 10
	score += amount * multiplier
	combo += 1
	combo_timer = 2.0

func tick_combo(delta: float):
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0

func load_high_score():
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		high_score = f.get_32()

func save_high_score():
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_32(high_score)
