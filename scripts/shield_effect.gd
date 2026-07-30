extends Node2D

var pulse: float = 0.0

func _ready():
	top_level = true
	queue_redraw()

func _process(delta):
	pulse = fmod(pulse + delta * 4.0, TAU)
	var parent = get_parent()
	if parent:
		global_position = parent.global_position
	queue_redraw()

func _draw():
	var alpha = 0.3 + 0.2 * sin(pulse)
	draw_circle(Vector2.ZERO, 38.0, Color(0.3, 0.9, 1.0, alpha * 0.4))
	draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 64, Color(0.4, 0.95, 1.0, alpha), 2.5)
