extends Node2D

# 玩家飞船 — WASD/方向键移动，鼠标/空格射击，Shift 放炸弹

@export var max_speed: float = 380.0
@export var acceleration: float = 1500.0
@export var friction: float = 900.0
@export var fire_rate: float = 0.14

@onready var body: Polygon2D = %Body
@onready var muzzle_l: Marker2D = $MuzzleL
@onready var muzzle_r: Marker2D = $MuzzleR
@onready var hitbox: CollisionShape2D = $CollisionShape2D
@onready var thruster: CPUParticles2D = $Body/ThrusterParticles

var fire_cooldown: float = 0.0
var is_dead: bool = false
var screen_rect: Rect2
var invuln_time: float = 0.0

const BULLET_SCENE = preload("res://bullet.tscn")

func _ready() -> void:
	screen_rect = Rect2(Vector2.ZERO, get_viewport_rect().size)
	add_to_group("player")
	invuln_time = 1.5  # 出生无敌

func _physics_process(delta: float) -> void:
	if is_dead or GameState.is_game_over:
		velocity = Vector2.ZERO
		return

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right"): input_dir.x += 1.0
	if Input.is_action_pressed("ui_left"):  input_dir.x -= 1.0
	if Input.is_action_pressed("ui_down"):  input_dir.y += 1.0
	if Input.is_action_pressed("ui_up"):    input_dir.y -= 1.0

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
		thruster.emitting = true
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		thruster.emitting = false

	move_and_slide()

	# 屏幕边界
	var margin := 30.0
	var pos := global_position
	pos.x = clamp(pos.x, screen_rect.position.x + margin, screen_rect.end.x - margin)
	pos.y = clamp(pos.y, screen_rect.position.y + margin, screen_rect.end.y - margin)
	global_position = pos

	# 倾斜（基于 X 速度）
	body.rotation = clamp(velocity.x / max_speed * 0.25, -0.3, 0.3)

	# 射击
	if Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if fire_cooldown <= 0.0:
			fire()
			fire_cooldown = fire_rate / (1.0 + float(GameState.weapon_level - 1) * 0.3)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)

	# 炸弹
	if Input.is_action_just_pressed("ui_select"):
		try_bomb()

	# 无敌闪烁
	if invuln_time > 0.0:
		invuln_time -= delta
		body.modulate.a = 0.4 + 0.6 * (sin(invuln_time * 30.0) * 0.5 + 0.5)
	else:
		body.modulate.a = 1.0

func fire() -> void:
	var lv := GameState.weapon_level
	var dirs: Array[Vector2] = []
	match lv:
		1:
			dirs = [Vector2(0, -1), Vector2(0, -1)]
		2:
			dirs = [
				Vector2(-0.08, -1).normalized(), Vector2(0, -1),
				Vector2(0, -1), Vector2(0.08, -1).normalized()
			]
		3:
			dirs = [
				Vector2(-0.12, -1).normalized(), Vector2(-0.05, -1).normalized(),
				Vector2(0, -1),
				Vector2(0.05, -1).normalized(), Vector2(0.12, -1).normalized()
			]
		_:
			for i in range(7):
				var angle := -PI / 2.0 + float(i - 3) * 0.12
				dirs.append(Vector2(cos(angle), sin(angle)))

	for i in range(dirs.size()):
		var spawn_pos: Vector2
		if i == 2 and lv >= 3:
			spawn_pos = global_position + Vector2(0, -22)
		elif i % 2 == 0:
			spawn_pos = muzzle_l.global_position
		else:
			spawn_pos = muzzle_r.global_position
		spawn_bullet(spawn_pos, dirs[i])

func spawn_bullet(pos: Vector2, dir: Vector2) -> void:
	var b := BULLET_SCENE.instantiate()
	b.global_position = pos
	b.direction = dir
	b.is_enemy = false
	b.damage = 12 + (GameState.weapon_level - 1) * 4
	%Bullets.add_child(b)

func try_bomb() -> void:
	if GameState.use_bomb():
		screen_shake(20.0, 0.3)
		for enemy in %Enemies.get_children():
			if is_instance_valid(enemy) and enemy.has_method("take_damage"):
				enemy.take_damage(60)
		# 中心爆炸特效
		spawn_explosion(global_position, 2.5)

func take_damage(amount: int) -> void:
	if is_dead or invuln_time > 0.0:
		return
	GameState.damage(amount)
	screen_shake(8.0, 0.15)
	invuln_time = 0.4
	if GameState.health <= 0:
		die()

func die() -> void:
	is_dead = true
	for i in range(5):
		var offset := Vector2(randf_range(-25.0, 25.0), randf_range(-25.0, 25.0))
		spawn_explosion(global_position + offset, randf_range(1.2, 2.0))
	GameState.game_over()
	visible = false
	set_physics_process(false)
	hitbox.set_deferred("disabled", true)

func spawn_explosion(pos: Vector2, scale: float = 1.0) -> void:
	var scene := preload("res://explosion.tscn")
	var e := scene.instantiate()
	e.global_position = pos
	e.set_scale(Vector2.ONE * scale)
	%Effects.add_child(e)

func screen_shake(intensity: float, duration: float) -> void:
	get_tree().call_group("camera_shake", "shake", intensity, duration)
