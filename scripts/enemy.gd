extends Area2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

signal killed(score_value, position)
signal damaged(hp)

enum EnemyType { SCOUT, FIGHTER, TANK }

@export var enemy_type: EnemyType = EnemyType.SCOUT

var hp = 1
var max_hp = 1
var score_value = 10
var speed = 200.0
var fire_rate = 0.0
var fire_timer = 0.0
var color = Color(1.0, 0.4, 0.4)
var shoot_offset = Vector2(0, 28)
var screen_size: Vector2
var t = 0.0
var horizontal_amp = 0.0
var horizontal_freq = 0.0
var start_x = 0.0
var aim_at_player = false

func _ready():
	screen_size = get_viewport_rect().size
	start_x = position.x
	setup_by_type()
	add_to_group("enemies")
	if fire_rate > 0:
		fire_timer = randf_range(0.3, fire_rate)

func setup_by_type():
	if enemy_type == EnemyType.SCOUT:
		hp = 1
		max_hp = 1
		score_value = 10
		speed = randf_range(180, 280)
		fire_rate = 0.0
		color = Color(1.0, 0.5, 0.4)
		horizontal_amp = randf_range(60, 130)
		horizontal_freq = randf_range(1.5, 3.0)
	elif enemy_type == EnemyType.FIGHTER:
		hp = 2
		max_hp = 2
		score_value = 25
		speed = randf_range(120, 180)
		fire_rate = 1.6
		color = Color(1.0, 0.3, 0.5)
		horizontal_amp = randf_range(40, 80)
		horizontal_freq = randf_range(1.0, 2.0)
		aim_at_player = true
	elif enemy_type == EnemyType.TANK:
		hp = 5
		max_hp = 5
		score_value = 75
		speed = randf_range(60, 100)
		fire_rate = 2.2
		color = Color(0.8, 0.3, 1.0)
		horizontal_amp = 0
		aim_at_player = false

func _process(delta):
	t += delta
	position.y += speed * delta
	if horizontal_amp > 0:
		position.x = start_x + sin(t * horizontal_freq) * horizontal_amp
	if fire_rate > 0:
		fire_timer -= delta
		if fire_timer <= 0:
			fire()
			fire_timer = fire_rate
	queue_redraw()
	if position.y > screen_size.y + 60:
		queue_free()

func fire():
	_am().play_sfx("shoot")
	var dir = Vector2.DOWN
	if aim_at_player:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			dir = (player.position - position).normalized()
	var b = preload("res://scenes/enemy_bullet.tscn").instantiate()
	b.position = position + shoot_offset
	b.set("velocity", dir * 380.0)
	get_tree().current_scene.get_node("Enemies").add_child(b)

func take_damage(dmg = 1):
	hp -= dmg
	damaged.emit(hp)
	if hp <= 0:
		die()
		return true
	return false

func die():
	_am().play_sfx("explode")
	killed.emit(score_value, position)
	queue_free()

func _draw():
	var body: PackedVector2Array
	if enemy_type == EnemyType.SCOUT:
		body = PackedVector2Array([
			Vector2(0, 24), Vector2(16, -10),
			Vector2(8, -16), Vector2(-8, -16), Vector2(-16, -10)
		])
	elif enemy_type == EnemyType.FIGHTER:
		body = PackedVector2Array([
			Vector2(0, 22), Vector2(22, 4), Vector2(28, -8),
			Vector2(14, -16), Vector2(-14, -16), Vector2(-28, -8), Vector2(-22, 4)
		])
	else:
		body = PackedVector2Array([
			Vector2(0, 32), Vector2(24, 14), Vector2(30, -8),
			Vector2(20, -22), Vector2(-20, -22), Vector2(-30, -8), Vector2(-24, 14)
		])
	draw_colored_polygon(body, color)
	var outline = color.darkened(0.5)
	for i in body.size():
		var a = body[i]
		var b_pt = body[(i + 1) % body.size()]
		draw_line(a, b_pt, outline, 2)
	draw_circle(Vector2(0, 0), 4, Color(1, 1, 0.4, 0.9))
	if enemy_type != EnemyType.SCOUT:
		var bar_w = 32.0
		var bar_h = 4.0
		var ratio = float(hp) / max_hp
		draw_rect(Rect2(-bar_w / 2, -38, bar_w, bar_h), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(-bar_w / 2, -38, bar_w * ratio, bar_h), Color(0.2, 1.0, 0.4))
