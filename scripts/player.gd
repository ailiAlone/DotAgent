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
@export var max_hp = 5

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

var dodge_cooldown: float = 0.0
var dodge_duration: float = 0.0
var dodge_dir: Vector2 = Vector2.ZERO
var dodge_speed: float = 900.0
var dodge_trail: Array = []

const DODGE_DURATION: float = 0.4
const DODGE_COOLDOWN: float = 1.5

var _bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
var _damage_popup_scene: PackedScene = preload("res://scenes/damage_popup.tscn")
var _shield_effect_scene: PackedScene = preload("res://scenes/shield_effect.tscn")
var _dodge_spark_scene: PackedScene = preload("res://scenes/hit_spark.tscn")

var _shield_system: Node = null
var _shield_effect: Node2D = null

func _ready():
	screen_size = get_viewport_rect().size
	add_to_group("player")
	var shield_script = load("res://scripts/shield_system.gd")
	_shield_system = shield_script.new()
	_shield_system.name = "ShieldSystem"
	_shield_system.shield_depleted.connect(_on_shield_depleted)
	add_child(_shield_system)

	# Ensure dodge roll input is registered (spacebar).
	if not InputMap.has_action("dodge"):
		InputMap.add_action("dodge")
	var dodge_ev = InputEventKey.new()
	dodge_ev.keycode = KEY_SPACE
	InputMap.action_add_event("dodge", dodge_ev)
	# Remove spacebar from shoot so it does not conflict with dodge roll.
	for ev in InputMap.action_get_events("shoot"):
		if ev is InputEventKey and ev.keycode == KEY_SPACE:
			InputMap.action_erase_event("shoot", ev)

func _process(delta):
	_update_shield_input()
	_update_shield_visuals()

	# Dodge roll active: move quickly and remain invulnerable.
	if dodge_duration > 0:
		dodge_duration -= delta
		if invuln_timer > 0:
			invuln_timer -= delta
		position += dodge_dir * dodge_speed * delta
		position.x = clamp(position.x, 30, screen_size.x - 30)
		position.y = clamp(position.y, 30, screen_size.y - 30)
		if dodge_duration <= 0:
			dodge_cooldown = DODGE_COOLDOWN
		engine_pulse = fmod(engine_pulse + delta * 14.0, TAU)
		queue_redraw()
		return
	if dodge_cooldown > 0:
		dodge_cooldown -= delta

	var input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 0:
		input = input.normalized()

	# Trigger dodge roll on spacebar.
	if Input.is_action_just_pressed("dodge") and dodge_cooldown <= 0 and dodge_duration <= 0:
		dodge_dir = input if input.length() > 0 else Vector2.UP
		dodge_duration = DODGE_DURATION
		invuln_timer = DODGE_DURATION
		_am().play_sfx("powerup")
		_spawn_dodge_spark()
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

	var data = _weapon_data()
	var weapon_fire_rate: float = data.get("fire_rate", 0.18)

	if Input.is_action_pressed("shoot") and fire_timer <= 0:
		fire()
		fire_timer = 0.07 if rapid_fire_timer > 0 else weapon_fire_rate

	if alt_fire_timer > 0:
		alt_fire_timer -= delta
	if Input.is_action_pressed("alt_shoot") and alt_fire_timer <= 0:
		fire_spread()
		var spread_data = _spread_weapon_data()
		alt_fire_timer = spread_data.get("fire_rate", 0.28)
	queue_redraw()

func _weapon_data() -> Dictionary:
	var ws = _ws()
	if ws:
		return ws.get_weapon_data(weapon_type, weapon_level)
	return {"damage": 1, "fire_rate": 0.18, "bullet_count": 2, "bullet_speed": 900.0, "spread": 0.12, "color": Color(1.0, 0.95, 0.4)}

func _spread_weapon_data() -> Dictionary:
	var ws = _ws()
	if ws:
		return ws.get_weapon_data(1, 1)  # Always use SPREAD data for secondary fire
	return {"damage": 1, "fire_rate": 0.28, "bullet_count": 5, "bullet_speed": 700.0, "spread": 0.22, "color": Color(1.0, 0.5, 0.3)}

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
	var data = _spread_weapon_data()
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
	_spawn_damage_popup(dmg, false)
	hit.emit()
	if hp <= 0:
		die()
		return true
	return true

func heal(amount):
	hp = min(hp + amount, max_hp)
	_spawn_damage_popup(amount, true)

func _spawn_damage_popup(value: int, is_heal: bool):
	if _damage_popup_scene == null:
		return
	var popup = _damage_popup_scene.instantiate()
	popup.position = position
	popup.value = value
	popup.is_heal = is_heal
	get_parent().add_child(popup)

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
	dodge_cooldown = 0
	dodge_duration = 0
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
	elif type == 5:
		upgrade_weapon()
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
	if dodge_cooldown > 0:
		var cd_pct = dodge_cooldown / DODGE_COOLDOWN
		draw_arc(Vector2.ZERO, 50, -PI/2, -PI/2 + TAU * (1 - cd_pct), 16, Color(1, 1, 1, 0.5), 2)

func _spawn_trail():
	if trail_scene == null:
		trail_scene = preload("res://scenes/player_trail.tscn")
	var t = trail_scene.instantiate()
	t.position = position + Vector2(0, 16)
	get_parent().add_child(t)

func _spawn_dodge_spark():
	if _dodge_spark_scene == null:
		return
	var spark = _dodge_spark_scene.instantiate()
	spark.position = position
	get_parent().add_child(spark)
	if spark.has_method("spark"):
		spark.spark(Color(0.3, 0.85, 1.0), 1.5)

func _update_shield_input():
	if Input.is_action_just_pressed("shield"):
		_shield_system.activate()
	elif Input.is_action_just_released("shield"):
		_shield_system.deactivate()

func _update_shield_visuals():
	if _shield_system.is_active():
		if _shield_effect == null:
			_shield_effect = _shield_effect_scene.instantiate()
			_shield_effect.position = position
			get_parent().add_child(_shield_effect)
	else:
		if _shield_effect != null:
			_shield_effect.queue_free()
			_shield_effect = null

func _on_shield_depleted():
	_update_shield_visuals()
