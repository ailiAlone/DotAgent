extends CharacterBody2D

@export var speed: float = 300.0


func _ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input = input.normalized()
	velocity = input * speed
	move_and_slide()


func _draw() -> void:
	const size := 20.0
	# Triangle pointing upward
	var points := PackedVector2Array([
		Vector2(0, -size),
		Vector2(-size * 0.7, size),
		Vector2(size * 0.7, size),
	])
	draw_colored_polygon(points, Color.WHITE)
