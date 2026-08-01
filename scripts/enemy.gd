extends Node2D

## Enemy: spawns at top of screen, moves downward, chases player when in range.

const SPEED: float = 150.0
const SIZE: float = 20.0
const SCORE_VALUE: int = 100
const DAMAGE: int = 1
const OFFSCREEN_MARGIN: float = 40.0
const CHASE_RANGE: float = 200.0
const CHASE_SPEED_MULTIPLIER: float = 1.5
const CHASE_HORIZONTAL_SPEED: float = 100.0

var _speed_multiplier: float = 1.0
var _is_chasing: bool = false


func _ready() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	position.y = -SIZE
	position.x = randf_range(SIZE, viewport_size.x - SIZE)


func _process(delta: float) -> void:
	var player: Node2D = _get_player()
	var is_player_in_range: bool = _is_player_in_range(player)
	
	if is_player_in_range:
		_is_chasing = true
		_speed_multiplier = CHASE_SPEED_MULTIPLIER
		_chase_player(delta, player)
	else:
		_is_chasing = false
		_speed_multiplier = 1.0
		_move_downward(delta)
	
	_check_offscreen()


func _move_downward(delta: float) -> void:
	position.y += SPEED * _speed_multiplier * delta


func _chase_player(delta: float, player: Node2D) -> void:
	# Move downward at chase speed
	position.y += SPEED * _speed_multiplier * delta
	
	# Move horizontally toward player
	if player != null:
		var direction: Vector2 = player.global_position - global_position
		if absf(direction.x) > 0.1:
			var horizontal_dir: float = signf(direction.x)
			position.x += CHASE_HORIZONTAL_SPEED * horizontal_dir * delta


func _is_player_in_range(player: Node2D) -> bool:
	if player == null:
		return false
	var distance: float = global_position.distance_to(player.global_position)
	return distance < CHASE_RANGE


func _get_player() -> Node2D:
	return get_tree().root.get_node_or_null("Main/Player")


func _check_offscreen() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if position.y > viewport_size.y + OFFSCREEN_MARGIN:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, SIZE, Color.RED)


func set_speed_multiplier(value: float) -> void:
	_speed_multiplier = maxf(0.1, value)


func take_hit() -> void:
	var gm: Node = _gm()
	if gm != null:
		gm.add_score(SCORE_VALUE)
		if gm.has_method("increment_combo"):
			gm.increment_combo()
		if gm.has_method("record_kill"):
			gm.record_kill()
	queue_free()


static func _gm() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameManager")
