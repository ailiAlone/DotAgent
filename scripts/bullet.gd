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

@onready var trail: Line2D = get_node_or_null("Trail") as Line2D
@onready var glow: PointLight2D = get_node_or_null("Glow") as PointLight2D

var _trail_length: int = 10
var _trail_timer: float = 0.0
var _trail_step: float = 0.012

var _dying: bool = false
var _death_fade: float = 0.15
var _death_timer: float = 0.0

# Glow + trail visuals are set up at runtime in _ready().
func _ready():
	add_to_group("bullets")
	if trail:
		trail.top_level = true
		_setup_trail_visuals()
	if glow:
		_setup_glow_visuals()

func _setup_trail_visuals() -> void:
	trail.default_color = Color(color.r, color.g, color.b, 0.8)
	trail.gradient = _create_trail_gradient()
	trail.width_curve = _create_trail_width_curve()
	trail.width = 10
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.cap_mode = Line2D.LINE_CAP_ROUND
	trail.antialiased = true
	trail.material = _create_glow_material()

func _setup_glow_visuals() -> void:
	glow.color = color
	glow.energy = 2.0
	glow.range = 48.0
	glow.texture = _create_glow_texture()
	glow.z_index = 1
	glow.enabled = true

func _create_glow_material() -> CanvasItemMaterial:
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat

func _create_glow_texture() -> GradientTexture2D:
	var gt = GradientTexture2D.new()
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var grad = Gradient.new()
	grad.colors = [color, Color(color.r, color.g, color.b, 0.0)]
	grad.offsets = [0.0, 1.0]
	gt.gradient = grad
	return gt

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
	if _dying:
		_fade_out(delta)
		return

	position += velocity * delta
	lifetime -= delta
	_update_trail(delta)

	if lifetime <= 0 or not _in_bounds():
		_start_death()

func _update_trail(delta: float) -> void:
	if not trail:
		return
	_trail_timer += delta
	var head := to_global(Vector2.ZERO)
	while _trail_timer >= _trail_step:
		_trail_timer -= _trail_step
		trail.add_point(head)
		while trail.get_point_count() > _trail_length:
			trail.remove_point(0)
	if trail.get_point_count() > 0:
		trail.set_point_position(trail.get_point_count() - 1, head)

func _start_death() -> void:
	set_process(false)
	_dying = true
	_death_timer = 0.0
	if glow:
		glow.enabled = false
	_fade_out(0.0)

func _fade_out(delta: float) -> void:
	_death_timer += delta
	var t := clampf(_death_timer / _death_fade, 0.0, 1.0)
	modulate.a = 1.0 - t
	if trail:
		trail.modulate.a = 1.0 - t
	if _death_timer >= _death_fade:
		queue_free()

func _in_bounds() -> bool:
	var vp = get_viewport_rect()
	return position.x > -50 and position.x < vp.size.x + 50 and position.y > -50 and position.y < vp.size.y + 50

func _draw():
	var tip = Vector2(0, -16)
	var tail = Vector2(0, 16)
	if is_enemy:
		tip = Vector2(0, 16)
		tail = Vector2(0, -16)
	var glow_color = Color(color.r, color.g, color.b, 0.35)
	glow_color.r = min(glow_color.r * 1.6, 1.0)
	glow_color.g = min(glow_color.g * 1.6, 1.0)
	glow_color.b = min(glow_color.b * 1.6, 1.0)
	draw_line(tip, tail, glow_color, 14)
	draw_line(tip, tail, color, 3)
	draw_circle(Vector2(0, 0), 5, color)
