extends Area2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

signal died
signal shoot(bullet_path, position, direction)
signal shoot_spread(bullet_path, position, direction)  # 副武器散射
signal hit
signal powerup_collected(type)

@export var speed = 420.0
@export var fire_rate = 0.18
@export var max_hp = 5
@export var alt_fire_rate = 0.35  # 副武器射速
@export var alt_ammo = 0  # 副武器弹药（0 表示无限，>0 限定数）

var hp = 3
var fire_timer = 0.0
var alt_fire_timer = 0.0
var rapid_fire_timer = 0.0
var shield = false
var shield_timer = 0.0
var invuln_timer = 0.0
var screen_size: Vector2
var body_color = Color(0.3, 0.85, 1.0)
var engine_pulse = 0.0
var trail_scene: PackedScene = null
var trail_instance: Node2D = null
var trail_timer: float = 0.0
# —— 武器等级 0-4，改变子弹数量/模式 ——
var weapon_level: int = 0
var weapon_xp: int = 0
var weapon_xp_next: int = 500
# —— Dash 闪避 ——
var dash_cooldown: float = 0.0
var dash_duration: float = 0.0
var dash_dir: Vector2 = Vector2.ZERO
var dash_speed: float = 1600.0
var dash_trail: Array = []

func _ready():
	# 兜底注册 alt_shoot（player 单独跑时也能工作）
	if not InputMap.has_action("alt_shoot"):
		InputMap.add_action("alt_shoot")
		var ev = InputEventKey.new()
		ev.keycode = KEY_SHIFT
		InputMap.action_add_event("alt_shoot", ev)
	screen_size = get_viewport_rect().size
	add_to_group("player")

func _process(delta):
	# —— Dash 闪避逻辑 ——
	if dash_duration > 0:
		dash_duration -= delta
		position += dash_dir * dash_speed * delta
		position.x = clamp(position.x, 30, screen_size.x - 30)
		position.y = clamp(position.y, 30, screen_size.y - 30)
		invuln_timer = 0.15
		_spawn_trail()
		if dash_duration <= 0:
			dash_cooldown = 0.8
		engine_pulse = fmod(engine_pulse + delta * 14.0, TAU)
		queue_redraw()
		return
	if dash_cooldown > 0:
		dash_cooldown -= delta
	
	var input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 0:
		input = input.normalized()
		# 双方向输入触发 Dash
		if Input.is_action_just_pressed("dash") and dash_cooldown <= 0 and dash_duration <= 0:
			dash_dir = input
			dash_duration = 0.15
			_am().play_sfx("powerup")
			_spawn_trail()
			_spawn_trail()
			return
	position += input * speed * delta
	position.x = clamp(position.x, 30, screen_size.x - 30)
	position.y = clamp(position.y, 30, screen_size.y - 30)
	# 拖尾
	trail_timer -= delta
	if input.length() > 0 and trail_timer <= 0:
		_spawn_trail()
		trail_timer = 0.04

	if invuln_timer > 0:
		invuln_timer -= delta
	if rapid_fire_timer > 0:
		rapid_fire_timer -= delta
	if shield and shield_timer > 0:
		shield_timer -= delta
		if shield_timer <= 0:
			shield = false

	fire_timer -= delta
	engine_pulse = fmod(engine_pulse + delta * 8.0, TAU)

	if Input.is_action_pressed("shoot") and fire_timer <= 0:
		fire()
		fire_timer = 0.07 if rapid_fire_timer > 0 else fire_rate

	# 副武器：按住 Shift 散射
	if alt_fire_timer > 0:
		alt_fire_timer -= delta
	if Input.is_action_pressed("alt_shoot") and alt_fire_timer <= 0:
		fire_spread()
		alt_fire_timer = 0.4
	queue_redraw()

func fire():
	_am().play_sfx("shoot")
	var up = Vector2.UP
	var b = "res://scenes/bullet.tscn"
	var p = position
	match weapon_level:
		0:
			shoot.emit(b, p + Vector2(-12, -28), up)
			shoot.emit(b, p + Vector2(12, -28), up)
		1:
			shoot.emit(b, p + Vector2(0, -30), up)
			shoot.emit(b, p + Vector2(-18, -26), Vector2(-0.3, -1).normalized())
			shoot.emit(b, p + Vector2(18, -26), Vector2(0.3, -1).normalized())
		2:
			shoot.emit(b, p + Vector2(0, -32), up)
			shoot.emit(b, p + Vector2(-22, -26), Vector2(-0.4, -1).normalized())
			shoot.emit(b, p + Vector2(22, -26), Vector2(0.4, -1).normalized())
			shoot.emit(b, p + Vector2(-8, -30), Vector2(-0.15, -1).normalized())
			shoot.emit(b, p + Vector2(8, -30), Vector2(0.15, -1).normalized())
		3:
			shoot.emit(b, p + Vector2(0, -32), up)
			shoot.emit(b, p + Vector2(-26, -24), Vector2(-0.5, -1).normalized())
			shoot.emit(b, p + Vector2(26, -24), Vector2(0.5, -1).normalized())
			shoot.emit(b, p + Vector2(-14, -30), Vector2(-0.25, -1).normalized())
			shoot.emit(b, p + Vector2(14, -30), Vector2(0.25, -1).normalized())
			shoot.emit(b, p + Vector2(0, 26), Vector2.DOWN)
			shoot.emit(b, p + Vector2(-20, 20), Vector2(-0.7, 1).normalized() * 600)
			shoot.emit(b, p + Vector2(20, 20), Vector2(0.7, 1).normalized() * 600)
		4:
			for i in range(9):
				var angle = -PI/2 + (i - 4) * 0.15
				var dir = Vector2(cos(angle), sin(angle))
				shoot.emit(b, p + Vector2(i * 6 - 24, -28), dir)
			# 穿透激光（中间大伤害子弹）
			shoot.emit("res://scenes/bullet.tscn", p + Vector2(0, -36), up)
	if rapid_fire_timer > 0:
		var diag_left = Vector2(-0.25, -1).normalized()
		var diag_right = Vector2(0.25, -1).normalized()
		shoot.emit(b, p + Vector2(-20, -22), diag_left)
		shoot.emit(b, p + Vector2(20, -22), diag_right)

func take_damage(amount = 1):
	if invuln_timer > 0:
		return
	if shield:
		shield = false
		shield_timer = 0
		invuln_timer = 1.0
		_am().play_sfx("hit")
		hit.emit()
		return
	hp -= amount
	invuln_timer = 1.0
	_am().play_sfx("damage")
	hit.emit()
	if hp <= 0:
		die()

func heal(amount = 1):
	hp = min(hp + amount, max_hp)

# 击杀敌人获得武器经验，满经验升级
func add_weapon_xp(points: int):
	if weapon_level >= 4:
		return
	weapon_xp += points
	if weapon_xp >= weapon_xp_next:
		weapon_xp -= weapon_xp_next
		weapon_level += 1
		weapon_xp_next = int(weapon_xp_next * 1.6)
		_am().play_sfx("powerup")
		var t = create_tween()
		t.tween_property(self, "scale", Vector2(1.6, 1.6), 0.15)
		t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK)
		powerup_collected.emit(5)

func apply_powerup(type):
	if type == 0:  # HEAL
		heal(2)
	elif type == 1:  # RAPID_FIRE
		rapid_fire_timer = 8.0
	elif type == 2:  # SHIELD
		shield = true
		shield_timer = 6.0
	elif type == 3:  # BOMB — 清屏
		_explode_all_enemies()
	elif type == 4:  # SCORE_X2
		_gm().score_multiplier = max(_gm().score_multiplier, 2.0)
		_gm().score_multiplier_timer = 10.0
	_am().play_sfx("powerup")
	powerup_collected.emit(type)

func _explode_all_enemies():
	var game = get_tree().current_scene
	if game == null:
		return
	for enemy in game.get_node("Enemies").get_children():
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("die"):
			enemy.die()

func die():
	_am().play_sfx("explode")
	died.emit()
	set_process(false)
	set_physics_process(false)
	visible = false
	$CollisionShape2D.set_deferred("disabled", true)

func reset():
	hp = 3
	fire_timer = 0
	rapid_fire_timer = 0
	shield = false
	shield_timer = 0
	invuln_timer = 1.0
	weapon_level = 0
	weapon_xp = 0
	weapon_xp_next = 500
	dash_cooldown = 0
	dash_duration = 0
	visible = true
	$CollisionShape2D.disabled = false
	set_process(true)
	set_physics_process(true)

func _draw():
	var body = PackedVector2Array([
		Vector2(0, -32), Vector2(20, 16), Vector2(10, 8),
		Vector2(-10, 8), Vector2(-20, 16)
	])
	var blink_visible = invuln_timer <= 0 or fmod(invuln_timer, 0.12) > 0.06
	if blink_visible:
		draw_colored_polygon(body, body_color)
		draw_circle(Vector2(0, -8), 4, Color(0.1, 0.6, 0.9))
		draw_line(Vector2(-15, 5), Vector2(0, -8), Color(0.6, 0.95, 1.0), 2)
		draw_line(Vector2(15, 5), Vector2(0, -8), Color(0.6, 0.95, 1.0), 2)
		var glow = 0.5 + 0.5 * sin(engine_pulse)
		draw_circle(Vector2(-7, 12), 5 * glow, Color(1.0, 0.6, 0.2, 0.9))
		draw_circle(Vector2(7, 12), 5 * glow, Color(1.0, 0.6, 0.2, 0.9))
	if shield:
		var pulse = 0.5 + 0.5 * sin(engine_pulse * 2.0)
		draw_arc(Vector2.ZERO, 38, 0, TAU, 32, Color(0.3, 0.9, 1.0, 0.3 + 0.4 * pulse), 2.5)
	# 武器等级指示器：轨道上彩色光点
	if weapon_level > 0:
		var lv_colors = [Color(1,1,0.4), Color(0.4,1,1), Color(1,0.5,1), Color(0.5,1,0.5)]
		var orbit_r = 44.0
		for i in range(weapon_level):
			var angle = fmod(engine_pulse * 0.7 + i * TAU / max(weapon_level, 1), TAU)
			var cx = cos(angle) * orbit_r
			var cy = sin(angle) * orbit_r
			draw_circle(Vector2(cx, cy), 3.5, lv_colors[min(i, 3)])
	# Dash 冷却指示器
	if dash_cooldown > 0:
		var cd_pct = dash_cooldown / 0.8
		draw_arc(Vector2.ZERO, 50, -PI/2, -PI/2 + TAU * (1 - cd_pct), 16, Color(1, 1, 1, 0.5), 2)

func fire_spread():
	_am().play_sfx("shoot")
	# 5 发散射：左二 + 中 + 右二
	var center = position + Vector2(0, -30)
	var up = Vector2.UP
	var up_left = Vector2(-0.4, -1).normalized()
	var up_right = Vector2(0.4, -1).normalized()
	var far_left = Vector2(-0.7, -1).normalized()
	var far_right = Vector2(0.7, -1).normalized()
	shoot_spread.emit("res://scenes/bullet.tscn", center + Vector2(-4, 0), far_left)
	shoot_spread.emit("res://scenes/bullet.tscn", center + Vector2(-2, 0), up_left)
	shoot_spread.emit("res://scenes/bullet.tscn", center, up)
	shoot_spread.emit("res://scenes/bullet.tscn", center + Vector2(2, 0), up_right)
	shoot_spread.emit("res://scenes/bullet.tscn", center + Vector2(4, 0), far_right)

func _spawn_trail():
	if trail_scene == null:
		trail_scene = preload("res://scenes/player_trail.tscn")
	var t = trail_scene.instantiate()
	t.position = position + Vector2(0, 16)
	get_parent().add_child(t)
