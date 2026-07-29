extends Area2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

static func _ws():
	return Engine.get_main_loop().root.get_node_or_null("WeaponSystem")

signal died
signal shoot(bullet_path, position, direction, extra)
signal shoot_spread(bullet_path, position, direction, extra)
signal hit
signal powerup_collected(type)
signal weapon_level_changed(level)
signal weapon_type_changed(weapon_type)

@export var speed = 420.0
@export var fire_rate = 0.18
@export var max_hp = 5
@export var alt_fire_rate = 0.35
@export var alt_ammo = 0

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

var weapon_level: int = 0:
	set(v):
		v = clamp(v, 0, 3)
		if v != weapon_level:
			weapon_level = v
			weapon_level_changed.emit(weapon_level)

var weapon_type: int = 0:
	set(v):
		if v != weapon_type:
			weapon_type = v
			weapon_type_changed.emit(weapon_type)

var weapon_xp: int = 0
var weapon_xp_next: int = 500

var dash_cooldown: float = 0.0
var dash_duration: float = 0.0
var dash_dir: Vector2 = Vector2.ZERO
var dash_speed: float = 1600.0
var dash_trail: Array = []

var _bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")

func _ready():
	screen_size = get_viewport_rect().size
	add_to_group("player")

func _process(delta):
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

	if alt_fire_timer > 0:
		alt_fire_timer -= delta
	if Input.is_action_pressed("alt_shoot") and alt_fire_timer <= 0:
		fire_spread()
		alt_fire_timer = 0.4
	queue_redraw()

func _weapon_data() -> Dictionary:
	var ws = _ws()
	if ws:
		return ws.get_weapon_data(weapon_type, weapon_level)
	return {"damage": 1, "fire_rate": 0.18, "bullet_count": 2, "bullet_speed": 900.0, "spread": 0.12, "color": Color(1.0, 0.95, 0.4)}

func _emit_shot(offset: Vector2, dir: Vector2, data: Dictionary, is_spread: bool = false):
	var extra = {
		"damage": data.get("damage", 1),
		"speed": data.get("bullet_speed", 900.0),
		"color": data.get("color", Color(1.0, 0.95, 0.4))
	}
	if is_spread:
		shoot_spread.emit(_bullet_scene.resource_path, position + offset, dir, extra)
	else:
		shoot.emit(_bullet_scene.resource_path, position + offset, dir, extra)

func fire():
	_am().play_sfx("shoot")
	var data = _weapon_data()
	var count = data.get("bullet_count", 2)
	var spread = data.get("spread", 0.15)
	var forward = Vector2.UP

	if count == 1:
		_emit_shot(Vector2(0, -30), forward, data)
		return

	var angle_step = 0.0
	var start_angle = 0.0
	if count > 1:
		var total_spread = spread * (count - 1)
		start_angle = -total_spread * 0.5
		angle_step = spread

	for i in range(count):
		var angle = start_angle + i * angle_step
		var dir = forward.rotated(angle)
		var side_offset = (i - (count - 1) * 0.5) * 12.0
		var offset = Vector2(side_offset, -30 + abs(angle) * -10.0)
		_emit_shot(offset, dir, data)

func fire_spread():
	_am().play_sfx("shoot")
	var ws = _ws()
	var data = {"damage": 1, "bullet_speed": 700.0, "color": Color(0.4, 0.95, 1.0)}
	if ws:
		data = ws.get_weapon_data(1, 1)
	var forward = Vector2.UP
	var directions = [
		forward.rotated(-0.7),
		forward.rotated(-0.4),
		forward,
		forward.rotated(0.4),
		forward.rotated(0.7)
	]
	for i in range(directions.size()):
		var offset = Vector2((i - 2) * 4.0, -30)
		_emit_shot(offset, directions[i], data, true)

func take_damage(dmg = 1):
	if invuln_timer > 0:
		return false
	if shield:
		shield = false
		shield_timer = 0.0
		hit.emit()
		return true
	hp -= dmg
	hit.emit()
	if hp <= 0:
		die()
		return true
	return true

func heal(amount):
	hp = min(hp + amount, max_hp)

func reset():
	hp = 3
	fire_timer = 0
	rapid_fire_timer = 0
	shield = false
	shield_timer = 0
	invuln_timer = 1.0
	weapon_type = 0
	weapon_level = 0
	weapon_xp = 0
	weapon_xp_next = 500
	dash_cooldown = 0
	dash_duration = 0
	visible = true
	$CollisionShape2D.disabled = false
	set_process(true)
	set_physics_process(true)

func add_weapon_xp(points: int):
	if weapon_level >= 3:
		weapon_xp += points
		if weapon_xp >= weapon_xp_next:
			weapon_xp = weapon_xp_next
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

func upgrade_weapon():
	var ws = _ws()
	var count = 5
	if ws and ws.has("WEAPON_COUNT"):
		count = ws.WEAPON_COUNT
	if weapon_level < 3:
		weapon_level += 1
	else:
		weapon_type = (weapon_type + 1) % count
		weapon_level = 0
		weapon_xp = 0
		weapon_xp_next = 500

func set_weapon_type(new_type: int):
	if new_type != weapon_type:
		weapon_type = new_type

func apply_powerup(type):
	if type == 0:
		heal(2)
	elif type == 1:
		rapid_fire_timer = 8.0
	elif type == 2:
		shield = true
		shield_timer = 6.0
	elif type == 3:
		_explode_all_enemies()
	elif type == 4:
		_gm().score_multiplier = max(_gm().score_multiplier, 2.0)
		_gm().score_multiplier_timer = 10.0
	_am().play_sfx("powerup")
	powerup_collected.emit(type)

func _explode_all_enemies():
	var game = get_tree().current_scene
	if game == null:
		return
	var enemies = game.get_node_or_null("Enemies")
	if enemies == null:
		return
	for enemy in enemies.get_children():
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
	if weapon_level > 0:
		var lv_colors = [Color(1,1,0.4), Color(0.4,1,1), Color(1,0.5,1), Color(0.5,1,0.5)]
		var orbit_r = 44.0
		for i in range(weapon_level):
			var angle = fmod(engine_pulse * 0.7 + i * TAU / max(weapon_level, 1), TAU)
			var cx = cos(angle) * orbit_r
			var cy = sin(angle) * orbit_r
			draw_circle(Vector2(cx, cy), 3.5, lv_colors[min(i, 3)])
	if dash_cooldown > 0:
		var cd_pct = dash_cooldown / 0.8
		draw_arc(Vector2.ZERO, 50, -PI/2, -PI/2 + TAU * (1 - cd_pct), 16, Color(1, 1, 1, 0.5), 2)

func _spawn_trail():
	if trail_scene == null:
		trail_scene = preload("res://scenes/player_trail.tscn")
	var t = trail_scene.instantiate()
	t.position = position + Vector2(0, 16)
	get_parent().add_child(t)
