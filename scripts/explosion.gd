extends Node2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

var particles = []
var life = 1.2
var elapsed = 0.0
var color = Color(1.0, 0.6, 0.2)
var size = 1.0

func _ready():
	var n = int(24 * size)
	for i in n:
		var angle = randf() * TAU
		var speed = randf_range(60, 320) * size
		particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": _pick_color(),
			"size": randf_range(2.0, 6.0) * size,
			"life": randf_range(0.5, 1.0) * life
		})

func _pick_color():
	var r = randf()
	if r < 0.4:
		return Color(1.0, 0.9, 0.4)
	elif r < 0.7:
		return Color(1.0, 0.5, 0.1)
	elif r < 0.9:
		return Color(1.0, 0.2, 0.1)
	else:
		return Color(0.85, 0.85, 1.0)

func _process(delta):
	elapsed += delta
	for p in particles:
		p.pos += p.vel * delta
		p.vel *= 1.0 - delta * 1.5
	queue_redraw()
	if elapsed >= life:
		queue_free()

func _draw():
	var t = clamp(elapsed / life, 0.0, 1.0)
	for p in particles:
		var a = 1.0 - t
		var c = Color(p.color.r, p.color.g, p.color.b, a)
		draw_circle(p.pos, p.size * (1.0 - t * 0.5), c)
	if elapsed < 0.1:
		var fa = 1.0 - elapsed / 0.1
		draw_circle(Vector2.ZERO, 24 * size, Color(1, 1, 0.8, fa * 0.7))
