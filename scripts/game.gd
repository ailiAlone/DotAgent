extends Node2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var player: Area2D = $Player
@onready var bullets: Node2D = $Bullets
@onready var enemies: Node2D = $Enemies
@onready var effects: Node2D = $Effects
@onready var powerups: Node2D = $Powerups
@onready var hud: CanvasLayer = $HUD
@onready var spawn_timer: Timer = $SpawnTimer
@onready var powerup_timer: Timer = $PowerupTimer
@onready var wave_timer: Timer = $WaveTimer
@onready var wave_label: Label = $WaveAnnounce
@onready var pause_menu: Control = $PauseMenu

var screen_size: Vector2
var difficulty = 1.0
var spawn_interval = 1.4
var enemy_weights = {"scout": 1.0, "fighter": 0.0, "tank": 0.0}
var wave = 1
var paused = false
var game_over = false

func _ready():
	screen_size = get_viewport_rect().size
	_gm().reset_run()
	_gm().lives = 3
	player.position = Vector2(screen_size.x / 2, screen_size.y - 100)
	player.reset()
	player.shoot.connect(_on_player_shoot)
	player.died.connect(_on_player_died)
	player.hit.connect(_on_player_hit)
	hud.attach_player(player)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	powerup_timer.timeout.connect(_on_powerup_timer_timeout)
	wave_timer.timeout.connect(_on_wave_timer_timeout)
	spawn_timer.start()
	powerup_timer.start()
	wave_timer.start()
	_am().play_music("game")
	_announce_wave(1)
	_start_wave(1)

func _process(_delta):
	if not game_over and Input.is_action_just_pressed("pause"):
		_toggle_pause()
	_collisions_check()

func _toggle_pause():
	paused = not paused
	get_tree().paused = paused
	pause_menu.visible = paused
	if pause_menu.visible:
		pause_menu.get_node("Center/Resume").grab_focus()

func _collisions_check():
	for enemy in enemies.get_children():
		if not is_instance_valid(enemy):
			continue
		if player.overlaps_area(enemy):
			player.take_damage(2)
			if enemy.has_method("take_damage"):
				enemy.take_damage(99)
			break
	for b in bullets.get_children():
		if not is_instance_valid(b):
			continue
		if b.is_enemy:
			if player.overlaps_area(b):
				player.take_damage(1)
				b.queue_free()
			continue
		for enemy in enemies.get_children():
			if not is_instance_valid(enemy):
				continue
			if b.overlaps_area(enemy):
				if enemy.has_method("take_damage"):
					enemy.take_damage(b.damage)
				b.queue_free()
				break
	for p in powerups.get_children():
		if not is_instance_valid(p):
			continue
		if player.overlaps_area(p):
			player.apply_powerup(p.powerup_type)
			_am().play_sfx("powerup")
			_spawn_explosion(p.position, 0.5, Color(0.3, 1.0, 0.4))
			p.queue_free()

func _announce_wave(n):
	wave = n
	wave_label.text = "WAVE %d" % n
	wave_label.modulate.a = 1.0
	wave_label.scale = Vector2(1.5, 1.5)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave_label, "modulate:a", 0.0, 2.5)
	tween.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK)
	_am().play_sfx("wave")

func _start_wave(n):
	difficulty = 1.0 + (n - 1) * 0.15
	spawn_interval = max(0.4, 1.4 - n * 0.08)
	spawn_timer.wait_time = spawn_interval
	enemy_weights["scout"] = clamp(1.0 - n * 0.05, 0.25, 1.0)
	enemy_weights["fighter"] = clamp((n - 1) * 0.08, 0.0, 0.65)
	enemy_weights["tank"] = clamp((n - 2) * 0.06, 0.0, 0.35)
	hud.set_wave(n)

func _on_spawn_timer_timeout():
	_spawn_enemy()
	if wave >= 3 and randf() < 0.3:
		_spawn_enemy()

func _spawn_enemy():
	var total_weight = enemy_weights["scout"] + enemy_weights["fighter"] + enemy_weights["tank"]
	var r = randf() * total_weight
	var type: int
	if r < enemy_weights["scout"]:
		type = 0
	elif r < enemy_weights["scout"] + enemy_weights["fighter"]:
		type = 1
	else:
		type = 2
	var e = preload("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(randf_range(60, screen_size.x - 60), -40)
	e.enemy_type = type
	e.speed *= (1.0 + (wave - 1) * 0.1)
	e.killed.connect(_on_enemy_killed)
	enemies.add_child(e)

func _on_powerup_timer_timeout():
	_spawn_powerup()

func _spawn_powerup():
	var r = randf()
	var type: int
	if r < 0.5:
		type = 0
	elif r < 0.85:
		type = 2
	else:
		type = 1
	var p = preload("res://scenes/powerup.tscn").instantiate()
	p.powerup_type = type
	p.position = Vector2(randf_range(100, screen_size.x - 100), -30)
	powerups.add_child(p)

func _on_wave_timer_timeout():
	_start_wave(wave + 1)
	_announce_wave(wave)

func _on_player_shoot(bullet_path, pos, dir):
	var b = load(bullet_path).instantiate()
	b.position = pos
	b.velocity = dir * 900.0
	b.is_enemy = false
	b.color = Color(1.0, 0.95, 0.4)
	bullets.add_child(b)

func _on_player_hit():
	_spawn_explosion(player.position, 0.4, Color(1.0, 0.3, 0.3))
	_shake(0.08, 5)

func _on_player_died():
	_spawn_explosion(player.position, 1.8, Color(1.0, 0.6, 0.2))
	_shake(0.5, 22)
	_gm().lives -= 1
	if _gm().lives <= 0:
		_game_over()
	else:
		_respawn()

func _respawn():
	await get_tree().create_timer(0.8).timeout
	player.position = Vector2(screen_size.x / 2, screen_size.y - 100)
	player.reset()

func _on_enemy_killed(value, pos):
	_gm().add_score(value)
	_spawn_explosion(pos, 1.0, Color(1.0, 0.7, 0.2))
	_shake(0.05, 3)

func _shake(duration, amplitude):
	var cam = $Camera
	if cam == null:
		return
	var tween = create_tween()
	var steps = 6
	for i in steps:
		var ox = randf_range(-amplitude, amplitude)
		var oy = randf_range(-amplitude, amplitude)
		tween.tween_property(cam, "offset", Vector2(ox, oy), duration / steps)
	tween.tween_property(cam, "offset", Vector2.ZERO, duration / steps)

func _spawn_explosion(pos, size, color):
	var e = preload("res://scenes/explosion.tscn").instantiate()
	e.position = pos
	e.size = size
	e.color = color
	effects.add_child(e)

func _game_over():
	if game_over:
		return
	game_over = true
	_am().stop_music()
	_am().play_sfx("gameover")
	spawn_timer.stop()
	powerup_timer.stop()
	wave_timer.stop()
	await get_tree().create_timer(1.4).timeout
	var go = preload("res://scenes/game_over.tscn").instantiate()
	go.final_score = _gm().score
	go.wave_reached = wave
	get_tree().root.add_child(go)
	go.process_mode = Node.PROCESS_MODE_ALWAYS

func retry():
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	var new_game = preload("res://scenes/game.tscn").instantiate()
	get_parent().add_child(new_game)
	queue_free()

func to_menu():
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	var menu = preload("res://scenes/menu.tscn").instantiate()
	get_parent().add_child(menu)
	queue_free()
