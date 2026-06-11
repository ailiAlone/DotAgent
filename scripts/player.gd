extends Area2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

signal died
signal shoot(bullet_path, position, direction)
signal hit
signal powerup_collected(type)

@export var speed = 420.0
@export var fire_rate = 0.18
@export var max_hp = 5

var hp = 3
var fire_timer = 0.0
var rapid_fire_timer = 0.0
var shield = false
var shield_timer = 0.0
var invuln_timer = 0.0
var screen_size: Vector2
var body_color = Color(0.3, 0.85, 1.0)
var engine_pulse = 0.0

func _ready():
	screen_size = get_viewport_rect().size
	add_to_group("player")

func _process(delta):
	var input = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 0:
		input = input.normalized()
	position += input * speed * delta
	position.x = clamp(position.x, 30, screen_size.x - 30)
	position.y = clamp(position.y, 30, screen_size.y - 30)

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
	queue_redraw()

func fire():
	_am().play_sfx("shoot")
	var up = Vector2.UP
	shoot.emit("res://scenes/bullet.tscn", position + Vector2(-12, -28), up)
	shoot.emit("res://scenes/bullet.tscn", position + Vector2(12, -28), up)
	if rapid_fire_timer > 0:
		var diag_left = Vector2(-0.25, -1).normalized()
		var diag_right = Vector2(0.25, -1).normalized()
		shoot.emit("res://scenes/bullet.tscn", position + Vector2(-20, -22), diag_left)
		shoot.emit("res://scenes/bullet.tscn", position + Vector2(20, -22), diag_right)

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

func apply_powerup(type):
	if type == 0:
		heal(2)
	elif type == 1:
		rapid_fire_timer = 8.0
	elif type == 2:
		shield = true
		shield_timer = 6.0
	_am().play_sfx("powerup")
	powerup_collected.emit(type)

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
