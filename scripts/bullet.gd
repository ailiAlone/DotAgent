extends Area2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

var velocity: Vector2 = Vector2.UP * 900
var damage: int = 1
var lifetime: float = 3.0
var is_enemy: bool = false
var color: Color = Color(1.0, 0.95, 0.4)

@onready var trail: Line2D = $Trail

var _trail_length: int = 8
var _trail_timer: float = 0.0
var _trail_step: float = 0.016

func _ready():
	add_to_group("bullets")
	if trail:
		trail.default_color = Color(color.r, color.g, color.b, 0.7)
		trail.gradient = _create_trail_gradient()
		trail.width_curve = _create_trail_width_curve()
		trail.width = 12

func _process(delta):
	position += velocity * delta
	lifetime -= delta
	_update_trail(delta)
	if lifetime <= 0 or not _in_bounds():
		queue_free()

func _update_trail(delta: float) -> void:
	if not trail:
		return
	_trail_timer += delta
	while _trail_timer >= _trail_step:
		_trail_timer -= _trail_step
		trail.add_point(Vector2.ZERO)
		while trail.get_point_count() > _trail_length:
			trail.remove_point(0)
	# Keep the newest point anchored to the bullet center.
	if trail.get_point_count() > 0:
		trail.set_point_position(trail.get_point_count() - 1, Vector2.ZERO)

func _create_trail_gradient() -> Gradient:
	var g = Gradient.new()
	g.colors = [Color(color.r, color.g, color.b, 0.85), Color(color.r, color.g, color.b, 0.0)]
	g.offsets = [0.0, 1.0]
	return g

func _create_trail_width_curve() -> Curve:
	var c = Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	c.min_value = 0.0
	c.max_value = 1.0
	return c

func _in_bounds() -> bool:
	var vp = get_viewport_rect()
	return position.x > -50 and position.x < vp.size.x + 50 and position.y > -50 and position.y < vp.size.y + 50

func _draw():
	var tip = Vector2(0, -16)
	var tail = Vector2(0, 16)
	if is_enemy:
		tip = Vector2(0, 16)
		tail = Vector2(0, -16)
	draw_line(tip, tail, Color(color.r, color.g, color.b, 0.4), 8)
	draw_line(tip, tail, color, 3)
	draw_circle(Vector2(0, 0), 4, color)
