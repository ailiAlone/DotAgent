extends Area2D

var velocity := Vector2(0, 80)
var rotation_speed: float = 0.0
var size: float = 1.0
var hp: int = 3
var color: Color = Color(0.45, 0.4, 0.35)
var points: Array[Vector2] = []
var screen_size: Vector2

func _ready():
	screen_size = get_viewport_rect().size
	rotation_speed = randf_range(-2.0, 2.0)
	velocity = Vector2(randf_range(-30, 30), randf_range(50, 120))
	size = randf_range(0.7, 1.5)
	hp = randi_range(2, 5)
	var r = 22 * size
	for i in range(randi_range(7, 12)):
		var angle = float(i) / 8.0 * TAU
		var dist = r * randf_range(0.7, 1.3)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist))
	add_to_group("asteroids")
	area_entered.connect(_on_area)

func _process(delta):
	position += velocity * delta
	rotation += rotation_speed * delta
	queue_redraw()
	if position.y > screen_size.y + 60:
		queue_free()

func _on_area(area: Area2D):
	if area.is_in_group("bullets"):
		hp -= 1
		area.queue_free()
		if hp <= 0:
			_spawn_fragments()
			queue_free()
	elif area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(1)
		_spawn_fragments()
		queue_free()

func _spawn_fragments():
	var parent = get_parent()
	if not parent:
		return
	for i in range(3):
		var frag = load("res://scenes/asteroid.tscn").instantiate()
		frag.size = size * 0.4
		frag.hp = 1
		frag.position = position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
		frag.velocity = Vector2(randf_range(-80, 80), randf_range(-80, 80))
		frag.rotation_speed = randf_range(-6, 6)
		parent.add_child(frag)

func _draw():
	var r = 22 * size
	if points.is_empty():
		draw_circle(Vector2.ZERO, r, color)
		draw_arc(Vector2.ZERO, r, 0, TAU, 16, color.darkened(0.3), 2)
		return
	draw_colored_polygon(PackedVector2Array(points), color)
	for i in points.size():
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		draw_line(a, b, color.darkened(0.35), 2)
	# 高光点
	draw_circle(Vector2(-5, -8), 4 * size, Color(0.55, 0.5, 0.45, 0.5))