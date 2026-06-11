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

func _ready():
	add_to_group("bullets")

func _process(delta):
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0 or not _in_bounds():
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
	draw_line(tip, tail, Color(color.r, color.g, color.b, 0.4), 8)
	draw_line(tip, tail, color, 3)
	draw_circle(Vector2(0, 0), 4, color)
