extends Node2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

@onready var screen_flash: CanvasLayer = $ScreenFlash
@onready var player: Area2D = $Player
@onready var bullets: Node2D = $Bullets
@onready var enemies: Node2D = $Enemies
@onready var effects: Node2D = $Effects
@onready var powerups: Node2D = $Powerups
@onready var hud: Control = $UI_Layer/HUD
@onready var spawn_timer: Timer = $SpawnTimer
@onready var powerup_timer: Timer = $PowerupTimer
@onready var wave_timer: Timer = $WaveTimer
@onready var wave_label: Label = $WaveAnnounce
# 统一 UI_Layer CanvasLayer 承载全部 UI（HUD / PauseMenu）
@onready var pause_menu: Control = $UI_Layer/PauseMenu
@onready var asteroid_timer: Timer = $AsteroidTimer
@onready var asteroids: Node2D = $Asteroids

var screen_size: Vector2
var difficulty = 1.0
var spawn_interval = 1.4
var enemy_weights = {"scout": 1.0, "fighter": 0.0, "tank": 0.0, "bomber": 0.0, "sweeper": 0.0, "carrier": 0.0}
var wave = 1
var wave_type: int = 0  # 0=Normal 1=ScoutRush 2=FighterWing 3=TankColumn 4=BomberRaid 5=SweeperSwarm
var paused = false
var game_over = false
var hitstop_timer = 0.0
var wave_kills: int = 0
var wave_hits: int = 0
var total_kills: int = 0
var milestone_timer: float = 0.0  # 命中顿帧倒计时

func _hit_spark(pos: Vector2, color: Color, intensity: float = 1.0):
	var s = preload("res://scenes/hit_spark.tscn").instantiate()
	s.position = pos
	effects.add_child(s)
	s.spark(color, intensity)

func _hitstop(duration: float = 0.05):
	hitstop_timer = max(hitstop_timer, duration)

func _ready():
	# 运行时兜底：alt_shoot
	if not InputMap.has_action("alt_shoot"):
		InputMap.add_action("alt_shoot")
		var ev = InputEventKey.new()
		ev.keycode = KEY_SHIFT
		InputMap.action_add_event("alt_shoot", ev)
	# 兜底注册 dash（L 键）
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var ev2 = InputEventKey.new()
		ev2.keycode = KEY_L
		InputMap.action_add_event("dash", ev2)
	screen_size = get_viewport_rect().size
	_gm().reset_run()
	_gm().lives = 3
	player.position = Vector2(screen_size.x / 2, screen_size.y - 100)
	player.reset()
	player.shoot.connect(_on_player_shoot)
	player.shoot_spread.connect(_on_player_shoot_spread)
	player.died.connect(_on_player_died)
	player.hit.connect(_on_player_hit)
	hud.attach_player(player)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	powerup_timer.timeout.connect(_on_powerup_timer_timeout)
	wave_timer.timeout.connect(_on_wave_timer_timeout)
	asteroid_timer.timeout.connect(_on_asteroid_timer_timeout)
	spawn_timer.start()
	powerup_timer.start()
	wave_timer.start()
	_am().play_music("game")
	_announce_wave(1)
	_start_wave(1)

func _process(_delta):
	if hitstop_timer > 0:
		hitstop_timer -= _delta
		if Input.is_action_just_pressed("pause"):
			_toggle_pause()
		return
	if not game_over and Input.is_action_just_pressed("pause"):
		_toggle_pause()
	_collisions_check()
	_process_milestones(_delta)

func _toggle_pause():
	paused = not paused
	get_tree().paused = paused
	pause_menu.visible = paused
	if pause_menu.visible:
		var resume_btn = pause_menu.get_node_or_null("Center/Resume")
		if resume_btn:
			resume_btn.grab_focus()

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
				_hit_spark(b.position, Color(1.0, 1.0, 0.6), 0.5)
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
	# 检查上一波是否无伤通过
	if n > 1 and wave_hits == 0 and wave_kills >= 5:
		_show_milestone("✨ FLAWLESS WAVE!", Color(0.3, 1.0, 0.7), 2.5)
	var stage = ((n - 1) / 5) + 1
	var wave_in_stage = ((n - 1) % 5) + 1
	var type_names = ["", "SCOUT RUSH!", "FIGHTER WING!", "TANK COLUMN!", "BOMBER RAID!", "SWEEPER SWARM!"]
	if n % 5 == 0:
		wave_label.text = "⚠ BOSS  STAGE %d ⚠" % stage
	else:
		var type_str = type_names[wave_type] if wave_type >= 1 and wave_type <= 5 else ""
		wave_label.text = "STAGE %d  ·  WAVE %d   %s" % [stage, wave_in_stage, type_str]
	wave_label.modulate.a = 1.0
	wave_label.scale = Vector2(1.5, 1.5)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave_label, "modulate:a", 0.0, 2.5)
	tween.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK)
	_am().play_sfx("wave")

func _announce_stage_clear(stage: int):
	# 持续 3 秒的 STAGE CLEAR 提示（金色 + 大字号 + 缩放动画）
	wave_label.text = "★  STAGE %d CLEARED  ★" % stage
	wave_label.modulate = Color(1.0, 0.95, 0.3, 1.0)
	wave_label.scale = Vector2(2.0, 2.0)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(wave_label, "modulate:a", 0.0, 2.5).set_delay(1.0)
	t.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_BACK)
	_am().play_sfx("powerup")

func _start_wave(n):
	wave = n
	wave_kills = 0
	wave_hits = 0
	difficulty = 1.0 + (n - 1) * 0.15
	spawn_interval = max(0.4, 1.4 - n * 0.08)
	spawn_timer.wait_time = spawn_interval
	# 波次类型选择（每 5 波 Boss，其余按权重）
	if n % 5 == 0:
		wave_type = -1  # Boss
	else:
		wave_type = _pick_wave_type(n)
	# 基础权重（渐进解锁）
	enemy_weights["scout"] = clamp(1.0 - n * 0.04, 0.1, 1.0)
	enemy_weights["fighter"] = clamp((n - 1) * 0.07, 0.0, 0.5)
	enemy_weights["tank"] = clamp((n - 2) * 0.05, 0.0, 0.3)
	enemy_weights["bomber"] = clamp((n - 3) * 0.06, 0.0, 0.35)
	enemy_weights["sweeper"] = clamp((n - 4) * 0.05, 0.0, 0.25)
	enemy_weights["carrier"] = clamp((n - 6) * 0.04, 0.0, 0.2)
	# 波次主题覆盖权重
	_apply_wave_theme()
	hud.set_wave(n)
	# 星空颜色随阶段变化
	var stage = ((n - 1) / 5) + 1
	if n % 5 == 0 or n == 1:
		$StarField.set_palette(stage)
	if n % 5 == 0:
		_spawn_boss(n)

func _pick_wave_type(n: int) -> int:
	var roll = randf()
	if n <= 2:
		return 0  # Normal
	if n <= 4:
		return 0 if roll < 0.6 else (1 if roll < 0.85 else 2)
	if n <= 7:
		return 0 if roll < 0.35 else (1 if roll < 0.55 else (2 if roll < 0.75 else (3 if roll < 0.9 else 4)))
	# Wave 8+
	return 0 if roll < 0.2 else (3 if roll < 0.4 else (4 if roll < 0.6 else (5 if roll < 0.8 else 2)))

func _apply_wave_theme():
	match wave_type:
		1:  # Scout Rush — 大量 Scout、双倍刷新速度
			enemy_weights["scout"] = 3.0
			enemy_weights["fighter"] = 0.2
			spawn_timer.wait_time = max(0.25, spawn_interval * 0.5)
		2:  # Fighter Wing — 编队攻击
			enemy_weights["fighter"] = 2.0
			enemy_weights["scout"] = 0.5
		3:  # Tank Column — 重型波次
			enemy_weights["tank"] = 2.0
			enemy_weights["scout"] = 0.4
			spawn_timer.wait_time = spawn_interval * 1.3
		4:  # Bomber Raid — 精准火力
			enemy_weights["bomber"] = 2.0
			enemy_weights["fighter"] = 0.6
		5:  # Sweeper Swarm — 侧翼扫荡
			enemy_weights["sweeper"] = 2.0
			enemy_weights["scout"] = 0.5
		_:  # Normal — 默认权重
			pass

func _on_spawn_timer_timeout():
	_spawn_enemy()

func _spawn_boss(n: int):
	# Boss 波次：暂停小兵刷新，专注 Boss
	spawn_timer.stop()
	powerup_timer.stop()
	wave_timer.stop()
	var b = preload("res://scenes/boss.tscn").instantiate()
	b.position = Vector2(screen_size.x / 2, -120)
	b.killed.connect(_on_boss_killed)
	b.damaged.connect(_on_boss_damaged)
	enemies.add_child(b)
	# 全屏警告
	wave_label.text = "⚠ BOSS  WAVE %d ⚠" % n
	wave_label.modulate.a = 1.0
	wave_label.scale = Vector2(1.8, 1.8)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(wave_label, "modulate:a", 0.0, 3.0)
	t.tween_property(wave_label, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_BACK)
	_am().play_sfx("warning")

func _on_boss_killed(value, pos):
	_gm().add_score(value)
	_spawn_explosion(pos, 3.0, Color(1.0, 0.4, 0.8))
	_shake(0.8, 30)
	_hit_spark(pos, Color(1.0, 0.6, 0.9), 2.0)
	_hitstop(0.15)
	_show_milestone("💀 BOSS DOWN!", Color(1.0, 0.5, 0.8), 3.0)
	# 恢复小兵刷新
	spawn_timer.start()
	powerup_timer.start()
	wave_timer.start()
	# 手动推进下一波
	wave += 1
	_start_wave(wave)

func _on_boss_damaged(_hp):
	_shake(0.04, 2)
	_hitstop(0.02)

func am():
	# 环境增援：高波次时偶尔额外生成敌人
	if wave >= 3 and randf() < 0.3:
		_spawn_enemy()

func _spawn_enemy():
	# 30% 概率生成编队
	if wave >= 2 and randf() < 0.3:
		_spawn_formation()
		return
	_single_spawn()

func _single_spawn():
	var keys = ["scout", "fighter", "tank", "bomber", "sweeper", "carrier"]
	var total = 0.0
	for k in keys:
		total += enemy_weights[k]
	var r = randf() * total
	var type_name = "scout"
	var acc = 0.0
	for k in keys:
		acc += enemy_weights[k]
		if r < acc:
			type_name = k
			break
	var type_map = {"scout": 0, "fighter": 1, "tank": 2, "bomber": 3, "sweeper": 4, "carrier": 5}
	var type: int = type_map[type_name]
	var e = _make_enemy(type)
	if type == 4:
		var from_left = randf() < 0.5
		e.position = Vector2(-40 if from_left else screen_size.x + 40, randf_range(60, 200))
	else:
		e.position = Vector2(randf_range(60, screen_size.x - 60), -40)
	enemies.add_child(e)

func _make_enemy(type: int) -> Node:
	var e = preload("res://scenes/enemy.tscn").instantiate()
	e.enemy_type = type
	e.speed *= (1.0 + (wave - 1) * 0.1)
	e.killed.connect(_on_enemy_killed)
	return e

func _spawn_formation():
	var formations = ["v", "line", "diamond"]
	var form = formations[randi() % 3]
	var etype = [0, 1, 1, 2][randi() % 4]  # 编队以 Scout/Fighter 为主
	var cx = screen_size.x / 2 + randf_range(-200, 200)
	var cy = -60.0
	match form:
		"v":
			for i in range(randi_range(3, 5)):
				var e = _make_enemy(etype)
				e.position = Vector2(cx + (i - 2) * 70, cy - abs(i - 2) * 30)
				enemies.add_child(e)
		"line":
			for i in range(randi_range(3, 6)):
				var e = _make_enemy(etype)
				e.position = Vector2(cx + (i - 2.5) * 50, cy)
				enemies.add_child(e)
		"diamond":
			var offs = [Vector2(0, -50), Vector2(-50, 0), Vector2(50, 0), Vector2(0, 50), Vector2(0, 0)]
			for off in offs:
				var e = _make_enemy(etype)
				e.position = Vector2(cx + off.x, cy + off.y)
				enemies.add_child(e)

func _on_powerup_timer_timeout():
	_spawn_powerup()

func _spawn_powerup():
	var r = randf()
	var type: int
	if r < 0.4:
		type = 0  # HEAL
	elif r < 0.7:
		type = 2  # SHIELD
	elif r < 0.85:
		type = 1  # RAPID_FIRE
	elif r < 0.95:
		type = 3  # BOMB
	else:
		type = 4  # SCORE_X2
	var p = preload("res://scenes/powerup.tscn").instantiate()
	p.powerup_type = type
	p.position = Vector2(randf_range(100, screen_size.x - 100), -30)
	powerups.add_child(p)

func _on_asteroid_timer_timeout():
	_spawn_asteroid()
	# 高波次加速
	asteroid_timer.wait_time = max(3.0, 8.0 - wave * 0.3)

func _spawn_asteroid():
	var count = randi_range(1, min(wave, 4))
	for i in range(count):
		var a = preload("res://scenes/asteroid.tscn").instantiate()
		a.position = Vector2(randf_range(60, screen_size.x - 60), randf_range(-60, -20))
		asteroids.add_child(a)

func _on_wave_timer_timeout():
	var next_wave = wave + 1
	_start_wave(next_wave)
	_announce_wave(next_wave)

func _on_player_shoot(bullet_path, pos, dir):
	var b = load(bullet_path).instantiate()
	b.position = pos
	b.velocity = dir * 900.0
	b.is_enemy = false
	b.color = Color(1.0, 0.95, 0.4)
	bullets.add_child(b)

func _on_player_shoot_spread(bullet_path, pos, dir):
	var b = load(bullet_path).instantiate()
	b.position = pos
	b.velocity = dir * 700.0
	b.is_enemy = false
	b.color = Color(0.4, 0.95, 1.0)  # 散射用蓝色
	b.damage = 1
	bullets.add_child(b)

func _on_player_hit():
	wave_hits += 1
	_spawn_explosion(player.position, 0.4, Color(1.0, 0.3, 0.3))
	_shake(0.08, 5)
	_hit_spark(player.position, Color(1.0, 0.4, 0.4), 1.2)
	if screen_flash:
		screen_flash.flash(0.45)
	_hitstop(0.06)

func _on_player_died():
	_spawn_explosion(player.position, 1.8, Color(1.0, 0.6, 0.2))
	_shake(0.5, 22)
	_gm().lives -= 1
	if _gm().lives <= 0:
		_game_over()
	else:
		_respawn()

func _respawn():
	# 延长无敌时间从 1s 到 1.8s，让玩家有反应时间
	await get_tree().create_timer(0.5).timeout
	# 复活光环（视觉强调）
	_spawn_respawn_ring(player.position)
	# 屏幕震动
	_shake(0.15, 8)
	player.position = Vector2(screen_size.x / 2, screen_size.y - 100)
	player.reset()
	player.invuln_timer = 1.8  # 1.8s 无敌期

func _spawn_respawn_ring(pos: Vector2):
	# 用 8 个小 hit_spark 模拟扩张光环
	for i in 8:
		var angle = TAU / 8 * i
		var s = preload("res://scenes/hit_spark.tscn").instantiate()
		s.position = pos
		effects.add_child(s)
		# 用 -angle 计算方向，让火花从中心向外飞
		s.spark(Color(0.3, 0.85, 1.0), 0.8)
		# 重置粒子方向（hack：hit_spark 默认朝多个方向，我们这里手动覆盖）
		# 简单方案：传一个 angle 让 spark 沿固定方向
		# 改用更简单方法：直接修改 spark 内部 particles
		for p in s.particles:
			var dir = Vector2(cos(angle), sin(angle))
			p.vel = dir * p.vel.length()

func _on_enemy_killed(value, pos):
	_gm().add_score(value)
	_spawn_explosion(pos, 1.0, Color(1.0, 0.7, 0.2))
	_shake(0.05, 3)
	_hit_spark(pos, Color(1.0, 0.9, 0.3), 0.8)
	_hitstop(0.04)
	wave_kills += 1
	total_kills += 1
	_check_milestones()
	# 传递武器经验给玩家
	if player and player.has_method("add_weapon_xp"):
		player.add_weapon_xp(value)

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

# ——— 里程碑系统 ———
var _milestone_queue: Array = []  # [{text, color, timer}]

func _show_milestone(txt: String, col: Color = Color(1.0, 0.9, 0.3), dur: float = 2.0):
	_milestone_queue.append({"text": txt, "color": col, "timer": dur})

func _check_milestones():
	if total_kills > 0 and total_kills % 50 == 0:
		_show_milestone("☠ %d KILLS!" % total_kills, Color(1.0, 0.6, 0.2), 2.5)
	if _gm().combo >= 20 and _gm().combo % 10 == 0:
		_show_milestone("⚡ COMBO x%d!" % _gm().combo, Color(0.4, 1.0, 0.6), 2.0)
	if total_kills == 1 and wave == 1:
		_show_milestone("FIRST BLOOD!", Color(1.0, 0.9, 0.3), 1.8)

func _process_milestones(delta: float):
	if _milestone_queue.is_empty():
		return
	var m: Dictionary = _milestone_queue[0]
	m["timer"] = m["timer"] - delta
	if m["timer"] > 0:
		wave_label.text = m["text"]
		wave_label.modulate = m["color"]
		wave_label.modulate.a = min(m["timer"] / 0.5, 1.0)
		wave_label.scale = Vector2(1.3, 1.3)
	else:
		_milestone_queue.pop_front()
		if _milestone_queue.is_empty():
			wave_label.modulate.a = 0.0

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
