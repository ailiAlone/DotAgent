extends Node2D

## Visual explosion effect: an expanding ring that fades out and self-destructs.

@export var max_radius: float = 60.0
@export var duration: float = 0.5
@export var color: Color = Color.ORANGE
@export var line_width: float = 4.0

var _elapsed: float = 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	var radius := lerpf(0.0, max_radius, t)
	var alpha := 1.0 - t
	var draw_color := color
	draw_color.a = alpha
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, draw_color, line_width, true)
