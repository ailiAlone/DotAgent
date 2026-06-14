extends Node2D
func _ready():
	pass

func _draw():
	var c = Color(1, 0, 0) 
	draw_circle(Vector2.ZERO, 5.0, c)
