extends Node

## Autoload singleton managing game state: score, high score, lives, and current wave.

const Singleton: String = "GameManager"

signal score_changed(score: int)
signal high_score_changed(high_score: int)
signal lives_changed(lives: int)
signal wave_changed(wave: int)
signal game_paused(paused: bool)

@export var starting_lives: int = 3
@export var max_lives: int = 99

var score: int = 0
var high_score: int = 0
var lives: int = 3
var wave: int = 1
var paused: bool = false


func _ready() -> void:
	load_high_score()


func reset() -> void:
	score = 0
	wave = 1
	lives = starting_lives
	score_changed.emit(score)
	high_score_changed.emit(high_score)
	lives_changed.emit(lives)
	wave_changed.emit(wave)
	paused = false
	get_tree().paused = false
	game_paused.emit(paused)


func add_score(amount: int) -> void:
	score += amount
	if score > high_score:
		high_score = score
		save_high_score()
	score_changed.emit(score)
	high_score_changed.emit(high_score)


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


func _game_over() -> void:
	print("Game Over! Final score: ", score)
	set_pause(true)
