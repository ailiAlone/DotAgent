extends CharacterBody2D

@export var speed := 400.0
@export var jump_velocity := -600.0
@export var gravity := 1500.0

@onready var sprite := $Sprite2D
@onready var root_node := $".."
@onready var score_label := $"../UILayer/ScoreLabel"

var score := 0


func _ready() -> void:
	# Connect to all star nodes under the root
	for child in root_node.get_children():
		if child is Area2D:
			child.body_entered.connect(_on_star_collected.bind(child))


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
	
	# Horizontal movement
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 2)
	
	# Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
	
	move_and_slide()


func _on_star_collected(body: Node, star: Node2D) -> void:
	if body != self:
		return
	
	score += 1
	score_label.text = "Score: " + str(score)
	
	# Visual feedback
	sprite.modulate = Color("#66ff66")
	await get_tree().create_timer(0.1).timeout
	sprite.modulate = Color("#00d4ff")
	
	# Respawn star at new random position
	star.position = Vector2(
		randf_range(100, 1180),
		randf_range(50, 400)
	)
