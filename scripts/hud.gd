## Heads-up display showing score, lives, high score and current wave.

extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var high_score_label: Label = $HighScoreLabel
@onready var lives_label: Label = $LivesLabel
@onready var wave_label: Label = $WaveLabel
@onready var game_manager: Node = $"/root/GameManager"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_manager.score_changed.connect(_on_score_changed)
	game_manager.high_score_changed.connect(_on_high_score_changed)
	game_manager.lives_changed.connect(_on_lives_changed)
	game_manager.wave_changed.connect(_on_wave_changed)
	_on_score_changed(game_manager.score)
	_on_high_score_changed(game_manager.high_score)
	_on_lives_changed(game_manager.lives)
	_on_wave_changed(game_manager.wave)

func _on_score_changed(new_score: int) -> void:
	score_label.text = "Score: %d" % new_score

func _on_high_score_changed(new_high_score: int) -> void:
	high_score_label.text = "High Score: %d" % new_high_score

func _on_lives_changed(new_lives: int) -> void:
	lives_label.text = "Lives: %d" % new_lives

func _on_wave_changed(new_wave: int) -> void:
	wave_label.text = "Wave: %d" % new_wave
