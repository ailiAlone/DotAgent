extends Control

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var score_label: Label = $Margin/HBox/Score/Value
@onready var high_label: Label = $Margin/HBox/HighScore/Value
@onready var lives_label: Label = $Margin/HBox/Lives/Value
@onready var combo_label: Label = $Margin/HBox/Combo/Value
@onready var powerup_label: Label = $Margin/HBox/Powerup/Value
@onready var wave_label: Label = $Margin/HBox/Wave/Value

var player_ref: Node = null
var last_lives = 0
var last_hp = 0
var last_max_hp = 0
var _wave_num: int = 1

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
	if _gm().score_multiplier > 1.0:
		combo_label.visible = true
		combo_label.text = "x%.1f BONUS" % _gm().score_multiplier
		combo_label.modulate = Color(1.0, 0.5, 1.0, 0.9)
	else:
		combo_label.modulate = Color(1, 1, 1, 0.8)
	if player_ref and is_instance_valid(player_ref):
		if player_ref.hp != last_hp or player_ref.max_hp != last_max_hp:
			_update_ship_hp()
		if player_ref.rapid_fire_timer > 0:
			powerup_label.text = "RAPID %.1f" % player_ref.rapid_fire_timer
			powerup_label.modulate = Color(1.0, 0.85, 0.2, 0.9)
		elif player_ref.shield:
			powerup_label.text = "SHIELD %.1f" % player_ref.shield_timer
			powerup_label.modulate = Color(0.3, 0.9, 1.0, 0.9)
		else:
			powerup_label.modulate.a = max(0, powerup_label.modulate.a - _delta * 0.5)
		# 武器等级
		if player_ref.has_method("add_weapon_xp"):
			wave_label.text = "W%d Lv.%d" % [_wave_num, player_ref.weapon_level]

func attach_player(p):
	player_ref = p
	p.powerup_collected.connect(_flash_powerup)
	last_max_hp = p.max_hp
	last_hp = p.hp

func _flash_powerup(_type):
	var names = ["♥ HEAL!", "⚡ RAPID!", "🛡 SHIELD!", "💣 BOMB!", "x2 SCORE!", "⬆ WEAPON!"]
	powerup_label.text = names[min(_type, 5)]
	powerup_label.modulate = Color(1, 1, 0.3)
	var t = create_tween()
	t.tween_property(powerup_label, "modulate:a", 0.0, 1.5)

func get_wave_num() -> int:
	return _wave_num

func set_wave(v):
	_wave_num = v
	wave_label.text = "W%d" % v
	wave_label.modulate = Color(1, 1, 0.4)
	var t = create_tween()
	t.tween_property(wave_label, "modulate", Color(1, 1, 1), 0.5)

func _update_ship_hp():
	if not player_ref or not is_instance_valid(player_ref):
		lives_label.text = "LIVES %d" % _gm().lives
		return
	last_hp = player_ref.hp
	last_max_hp = player_ref.max_hp
	var s = ""
	for i in range(player_ref.max_hp):
		if i < player_ref.hp:
			s += "♥ "
		else:
			s += "♡ "
	lives_label.text = "%s  LIVES %d" % [s, _gm().lives]

func _on_score_changed(v):
	score_label.text = "%06d" % v

func _on_high_changed(v):
	high_label.text = "HI %06d" % v

func _on_lives_changed(v):
	if player_ref and is_instance_valid(player_ref):
		_update_ship_hp()
	else:
		lives_label.text = "LIVES %d" % v
