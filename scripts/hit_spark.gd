extends Node2D

# 程序化命中粒子 — 喷出 N 个小火花，渐隐消失
# 用法：在击中点 instantiate 这个场景，调用 spark(color, intensity)

var particles: Array = []
var lifetime: float = 0.0
var max_lifetime: float = 0.5
var active: bool = false

func _ready():
	queue_redraw()

func spark(color: Color, intensity: float = 1.0):
	max_lifetime = 0.4 + randf_range(0, 0.2)
	lifetime = 0.0
	active = true
	var count = int(8 * intensity)
	for i in count:
		var angle = randf_range(0, TAU)
		var speed = randf_range(80, 220) * intensity
		particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": color,
			"size": randf_range(2.0, 4.0),
		})
	queue_redraw()

func _process(delta):
	if not active:
		return
	lifetime += delta
	if lifetime >= max_lifetime:
		active = false
		particles.clear()
		queue_free()
		return
	# 物理更新
	for p in particles:
		p.pos += p.vel * delta
		p.vel *= 0.92  # 减速
	queue_redraw()

func _draw():
	if not active:
		return
	var alpha = 1.0 - (lifetime / max_lifetime)
	for p in particles:
		var c = p.color
		c.a *= alpha
		draw_circle(p.pos, p.size, c)
