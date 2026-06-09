extends CharacterBody3D

@export var speed := 10.0
var score := 0

@onready var score_label := $"../UILayer/ScoreLabel"


func _ready() -> void:
	# Connect to all coin Area3D nodes
	for child in $"..".get_children():
		if child is Area3D:
			child.body_entered.connect(_on_coin_collected.bind(child))


func _physics_process(delta: float) -> void:
	# 3D movement - direct key detection (most reliable)
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x = -1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x = 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y = -1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y = 1.0
	
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	move_and_slide()


func _on_coin_collected(body: Node, coin: Node3D) -> void:
	if body != self:
		return
	
	score += 1
	score_label.text = "Score: " + str(score)
	
	# Respawn coin at random position
	coin.position = Vector3(
		randf_range(-15, 15),
		1.0,
		randf_range(-15, 15)
	)
