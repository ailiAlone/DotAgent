extends Node

## Core game management singleton handling score, high score, lives, and wave state.

signal score_changed(new_score: int)
signal high_score_changed(new_high_score: int)
signal lives_changed(new_lives: int)
signal wave_changed(new_wave: int)
signal game_over

@export var starting_lives: int = 3

var score: int = 0
var high_score: int = 0
var lives: int = 3
var wave: int = 1

const DEFAULT_LIVES: int = 3

func _ready() -> void:
	load_high_score()

func reset_game() -> void:
	score = 0
	lives = starting_lives
	wave = 1
	emit_signal("score_changed", score)
	emit_signal("lives_changed", lives)
	emit_signal("wave_changed", wave)

func add_score(points: int) -> void:
	score += points
	emit_signal("score_changed", score)
	if score > high_score:
		high_score = score
		save_high_score()
		emit_signal("high_score_changed", high_score)

func take_life() -> void:
	lives -= 1
	emit_signal("lives_changed", lives)
	if lives <= 0:
		emit_signal("game_over")

func next_wave() -> void:
	wave += 1
	emit_signal("wave_changed", wave)

func save_high_score() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "high_score", high_score)
	config.save("user://high_score.cfg")

func load_high_score() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://high_score.cfg")
	if err == OK:
		high_score = config.get_value("game", "high_score", 0)
	emit_signal("high_score_changed", high_score)
