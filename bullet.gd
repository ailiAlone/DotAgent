extends Area2D

# 子弹 — 玩家和敌人共用
# 通过 is_eney 区分阵营，碰撞层自动切换

var direction: Vector2 = Vector2.UP
var speed: float = 800.0
var damage: int = 10
var is_enemy: bool = false

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 3.0
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()

	if is_enemy:
		collision_layer = 4   # enemy_bullet
		collision_mask = 1    # player
	else:
		collision_layer = 8   # player_bullet
		collision_mask = 2    # enemy

	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	if global_position.y < -50.0 or global_position.y > 800.0 \
		or global_position.x < -50.0 or global_position.x > 1330.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body == self or not is_instance_valid(body):
		return
	if is_enemy and body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
	elif not is_enemy and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
