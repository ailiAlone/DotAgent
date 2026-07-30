## Heads-up display showing score, lives, high score, current wave, kills, and combo.

extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var high_score_label: Label = $HighScoreLabel
@onready var lives_label: Label = $LivesLabel
@onready var wave_label: Label = $WaveLabel
@onready var kill_label: Label = $KillLabel
@onready var combo_label: Label = $ComboLabel
@onready var game_manager: Node = $"/root/GameManager"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_manager.score_changed.connect(_on_score_changed)
	game_manager.high_score_changed.connect(_on_high_score_changed)
	game_manager.lives_changed.connect(_on_lives_changed)
	game_manager.wave_changed.connect(_on_wave_changed)
	game_manager.kill_count_changed.connect(_on_kill_count_changed)
	game_manager.combo_changed.connect(_on_combo_changed)
	_on_score_changed(game_manager.score)
	_on_high_score_changed(game_manager.high_score)
	_on_lives_changed(game_manager.lives)
	_on_wave_changed(game_manager.wave)
	_on_kill_count_changed(game_manager.kill_count)
	_on_combo_changed(game_manager.combo)

func _on_score_changed(new_score: int) -> void:
	score_label.text = "Score: %d" % new_score

func _on_high_score_changed(new_high_score: int) -> void:
	high_score_label.text = "High Score: %d" % new_high_score

func _on_lives_changed(new_lives: int) -> void:
	lives_label.text = "Lives: %d" % new_lives

func _on_wave_changed(new_wave: int) -> void:
	wave_label.text = "Wave: %d" % new_wave

func _on_kill_count_changed(new_count: int) -> void:
	kill_label.text = "Kills: %d" % new_count

func _on_combo_changed(new_combo: int) -> void:
	combo_label.text = "Combo: %d" % new_combo
	combo_label.visible = new_combo > 0
