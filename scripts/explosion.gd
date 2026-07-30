extends Node2D

## Explosion effect: draws an expanding ring and fades out.

const DURATION: float = 0.5
const MAX_RADIUS: float = 40.0
const WIDTH: float = 4.0

@export var color: Color = Color(1.0, 0.5, 0.0, 1.0)

var _lifetime: float = 0.0


func _ready() -> void:
	z_index = 10


func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= DURATION:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var t: float = _lifetime / DURATION
	var radius: float = t * MAX_RADIUS
	var alpha: float = 1.0 - t
	var draw_color: Color = color
	draw_color.a = alpha
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, draw_color, WIDTH, true)
