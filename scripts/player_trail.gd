extends Node2D

# 玩家拖尾：每 N 帧在玩家位置生成一个小光点，自动渐隐

class_name PlayerTrail

var positions: Array = []  # 历史位置队列
var max_trail: int = 14
var spawn_interval: float = 0.025
var last_spawn: float = 0.0
var life: float = 0.0
var max_life: float = 0.6
var dot_color: Color = Color(0.3, 0.85, 1.0, 0.8)

func reset(pos: Vector2):
	positions.clear()
	positions.append(pos)
	last_spawn = 0.0
	life = max_life

func tick(delta: float, pos: Vector2):
	last_spawn += delta
	if last_spawn >= spawn_interval:
		last_spawn = 0.0
		positions.append(pos)
		if positions.size() > max_trail:
			positions.pop_front()
	life -= delta
	queue_redraw()
	if positions.is_empty() and life <= 0:
		queue_free()

func _draw():
	var n = positions.size()
	if n < 1:
		return
	for i in n:
		var t = float(i + 1) / n  # 0..1
		var p = positions[i]
		var alpha = t * 0.5
		var size = 2.0 + t * 4.0
		var c = dot_color
		c.a *= alpha
		draw_circle(p, size, c)
