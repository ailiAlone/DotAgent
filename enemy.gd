extends CharacterBody2D

# 敌人基类 — 通过 enemy_type 切换行为（basic/tracker/shooter/dasher/tank）

signal died(points: int, pos: Vector2)

@export var max_health: int = 20
@export var speed: float = 150.0
@export var damage: int = 15
@export var points: int = 100
@export var shoot_interval: float = 1.5

@onready var sprite: Polygon2D = $Body

var health: int
var shoot_cooldown: float = 0.0
var enemy_type: String = "basic"
var time_alive: float = 0.0

const BULLET_SCENE = preload("res://bullet.tscn")

func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	collision_layer = 2   # enemy
	collision_mask = 1 | 8  # player + player_bullet

	# 自动销毁
	var t := Timer.new()
	t.wait_time = 30.0
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()

	setup_appearance()
	shoot_cooldown = randf_range(0.0, shoot_interval)

func setup_appearance() -> void:
	match enemy_type:
		"basic":
			sprite.polygon = PackedVector2Array([
				Vector2(0, 24), Vector2(-20, -16), Vector2(0, -8), Vector2(20, -16)
			])
			sprite.color = Color(0.95, 0.3, 0.3)
		"tracker":
			sprite.polygon = PackedVector2Array([
				Vector2(-22, 16), Vector2(0, -22), Vector2(22, 16)
			])
			sprite.color = Color(0.95, 0.6, 0.2)
		"shooter":
			sprite.polygon = PackedVector2Array([
				Vector2(-24, 0), Vector2(-12, -18), Vector2(12, -18),
				Vector2(24, 0), Vector2(12, 18), Vector2(-12, 18)
			])
			sprite.color = Color(0.6, 0.3, 0.95)
		"dasher":
			sprite.polygon = PackedVector2Array([
				Vector2(0, 22), Vector2(-18, 0), Vector2(-8, -20),
				Vector2(8, -20), Vector2(18, 0)
			])
			sprite.color = Color(0.95, 0.9, 0.3)
		"tank":
			sprite.polygon = PackedVector2Array([
				Vector2(-26, -20), Vector2(26, -20), Vector2(26, 20), Vector2(-26, 20)
			])
			sprite.color = Color(0.5, 0.5, 0.65)

func _physics_process(delta: float) -> void:
	if GameState.is_game_over:
		velocity = Vector2.ZERO
		return

	time_alive += delta
	var target_pos := _get_player_pos()

	match enemy_type:
		"basic":
			velocity = Vector2(0, 1) * speed
		"tracker":
			var dir := (target_pos - global_position).normalized()
			velocity = dir * speed * 0.8
		"shooter":
			velocity.x = sin(time_alive * 1.5 + global_position.y * 0.005) * speed * 0.6
			velocity.y = speed * 0.25
			shoot_cooldown -= delta
			if shoot_cooldown <= 0.0:
				shoot(target_pos)
				shoot_cooldown = shoot_interval
		"dasher":
			if time_alive < 0.8:
				velocity = Vector2(0, 1) * speed * 0.3
			else:
				var dir := (target_pos - global_position).normalized()
				velocity = dir * speed * 1.5
		"tank":
			velocity = Vector2(0, 1) * speed

	move_and_slide()

func _get_player_pos() -> Vector2:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		return p.global_position
	return Vector2.ZERO

func shoot(target: Vector2) -> void:
	var b := BULLET_SCENE.instantiate()
	b.global_position = global_position
	b.direction = (target - global_position).normalized()
	b.is_enemy = true
	b.damage = maxi(5, damage / 2)
	b.speed = 450.0
	b.modulate = Color(1, 0.5, 0.5)
	%EnemyBullets.add_child(b)

func take_damage(amount: int) -> void:
	health -= amount
	sprite.modulate = Color(2, 2, 2)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 1, 1), 0.15)
	if health <= 0:
		die()

func die() -> void:
	GameState.add_score(points)
	GameState.combo += 1
	GameState.combo_changed.emit(GameState.combo)
	died.emit(points, global_position)

	var scene := preload("res://explosion.tscn")
	var e := scene.instantiate()
	e.global_position = global_position
	e.set_scale(Vector2.ONE * randf_range(0.8, 1.4))
	%Effects.add_child(e)

	get_tree().call_group("camera_shake", "shake", 3.0, 0.08)

	if randf() < 0.18:
		drop_powerup()

	queue_free()

func drop_powerup() -> void:
	var PowerUpScene := preload("res://powerup.tscn")
	var p := PowerUpScene.instantiate()
	p.global_position = global_position
	var types := ["heal", "bomb", "weapon"]
	p.powerup_type = types[randi() % types.size()]
	%PowerUps.add_child(p)
