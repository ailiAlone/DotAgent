extends Area2D

# 道具 — heal（回血）/ bomb（+1 炸弹）/ weapon（武器升级）

var powerup_type: String = "heal"
var fall_speed: float = 80.0

@onready var sprite: Polygon2D = $Body

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	setup_appearance()

func setup_appearance() -> void:
	match powerup_type:
		"heal":
			sprite.color = Color(0.2, 1, 0.4)
		"bomb":
			sprite.color = Color(1, 0.6, 0.1)
		"weapon":
			sprite.color = Color(0.4, 0.7, 1)

func _physics_process(delta: float) -> void:
	global_position.y += fall_speed * delta
	sprite.rotation += delta * 2.0
	if global_position.y > 800.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		apply()
		queue_free()

func apply() -> void:
	match powerup_type:
		"heal":
			GameState.heal(30)
		"bomb":
			GameState.add_bomb()
		"weapon":
			GameState.upgrade_weapon()
