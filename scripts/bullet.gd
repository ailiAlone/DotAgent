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

var _trail_length: int = 10
var _trail_timer: float = 0.0
var _trail_step: float = 0.012

func _ready():
	add_to_group("bullets")
	if trail:
		_setup_trail_visuals()

func _setup_trail_visuals() -> void:
	trail.default_color = Color(color.r, color.g, color.b, 0.8)
	trail.gradient = _create_trail_gradient()
	trail.width_curve = _create_trail_width_curve()
	trail.width = 10
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.cap_mode = Line2D.LINE_CAP_ROUND
	trail.antialiased = true
	trail.material = _create_glow_material()

func _create_glow_material() -> CanvasItemMaterial:
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat

func _create_trail_gradient() -> Gradient:
	var g = Gradient.new()
	var core = Color(color.r, color.g, color.b, 1.0)
	core.r = min(core.r * 1.4, 1.0)
	core.g = min(core.g * 1.4, 1.0)
	core.b = min(core.b * 1.4, 1.0)
	g.colors = [core, Color(color.r, color.g, color.b, 0.0)]
	g.offsets = [0.0, 1.0]
	return g

func _create_trail_width_curve() -> Curve:
	var c = Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.6, 0.5))
	c.add_point(Vector2(1.0, 0.0))
	c.min_value = 0.0
	c.max_value = 1.0
	return c

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
	if trail.get_point_count() > 0:
		trail.set_point_position(trail.get_point_count() - 1, Vector2.ZERO)

func _in_bounds() -> bool:
	var vp = get_viewport_rect()
	return position.x > -50 and position.x < vp.size.x + 50 and position.y > -50 and position.y < vp.size.y + 50

func _draw():
	var tip = Vector2(0, -16)
	var tail = Vector2(0, 16)
	if is_enemy:
		tip = Vector2(0, 16)
		tail = Vector2(0, -16)
	var glow = Color(color.r, color.g, color.b, 0.35)
	glow.r = min(glow.r * 1.6, 1.0)
	glow.g = min(glow.g * 1.6, 1.0)
	glow.b = min(glow.b * 1.6, 1.0)
	draw_line(tip, tail, glow, 14)
	draw_line(tip, tail, color, 3)
	draw_circle(Vector2(0, 0), 5, color)
