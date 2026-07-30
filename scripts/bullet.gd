## Player bullet that travels upward and damages enemies.

extends Area2D

@export var speed: float = 600.0

func _ready():
		add_to_group("bullets")
		area_entered.connect(_on_area_entered)
	

func _physics_process(delta: float):
		position += Vector2.UP * speed * delta
	
		var viewport_size := get_viewport_rect().size
		if position.y < -50.0:
			queue_free()
	

func _on_area_entered(area: Area2D):
		if area.is_in_group("enemies"):
			area.take_damage()
			queue_free()
	
