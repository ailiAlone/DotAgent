extends CanvasLayer

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var score_label: Label = $UI/Margin/HBox/Score/Value
@onready var high_label: Label = $UI/Margin/HBox/HighScore/Value
@onready var lives_label: Label = $UI/Margin/HBox/Lives/Value
@onready var combo_label: Label = $UI/Margin/HBox/Combo/Value
@onready var powerup_label: Label = $UI/Margin/HBox/Powerup/Value
@onready var wave_label: Label = $UI/Margin/HBox/Wave/Value

var player_ref: Node = null
var last_lives = 0
var last_hp = 0
var last_max_hp = 0

func _ready():
	_gm().score_changed.connect(_on_score_changed)
	_gm().high_score_changed.connect(_on_high_changed)
	_gm().lives_changed.connect(_on_lives_changed)
	_on_score_changed(_gm().score)
	_on_high_changed(_gm().high_score)
	_on_lives_changed(_gm().lives)

func _process(_delta):
	_gm().tick_combo(_delta)
	if _gm().combo > 1:
		combo_label.visible = true
		var mult = 1 + _gm().combo / 10
		combo_label.text = "x%d" % mult
	else:
		combo_label.visible = false
	if player_ref and is_instance_valid(player_ref):
		if player_ref.hp != last_hp or player_ref.max_hp != last_max_hp:
			_update_ship_hp()
		if player_ref.rapid_fire_timer > 0:
			powerup_label.text = "RAPID %.1fs" % player_ref.rapid_fire_timer
			powerup_label.visible = true
		elif player_ref.shield:
			powerup_label.text = "SHIELD %.1fs" % player_ref.shield_timer
			powerup_label.visible = true
		else:
			powerup_label.visible = false

func attach_player(p):
	player_ref = p
	p.powerup_collected.connect(_flash_powerup)
	last_max_hp = p.max_hp
	last_hp = p.hp
	_update_ship_hp()

func _update_ship_hp():
	if not player_ref or not is_instance_valid(player_ref):
		return
	last_hp = player_ref.hp
	last_max_hp = player_ref.max_hp
	var hearts = ""
	for i in last_hp:
		hearts += "♥"
	for i in last_max_hp - last_hp:
		hearts += "♡"
	lives_label.text = "%s  LIVES %d" % [hearts, _gm().lives]

func _flash_powerup(_type):
	pass

func _on_score_changed(v):
	score_label.text = "%06d" % v

func _on_high_changed(v):
	high_label.text = "HI %06d" % v

func _on_lives_changed(v):
	if player_ref and is_instance_valid(player_ref):
		_update_ship_hp()
	else:
		lives_label.text = "LIVES %d" % v

func set_wave(v):
	wave_label.text = "WAVE %d" % v
	wave_label.modulate = Color(1, 1, 0.4)
	var t = create_tween()
	t.tween_property(wave_label, "modulate", Color(1, 1, 1, 0.7), 1.5)
