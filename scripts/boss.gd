extends Node2D

## Boss enemy with 3 phases, homing bullets, and a health pool. Designed to be spawned every 5th wave.

signal died(position: Vector2)
signal health_changed(health: int, max_health: int)

const ENTRY_SPEED: float = 80.0
const MOVE_SPEED: float = 60.0
const DAMAGE: int = 3

@export var max_health: int = 300
@export var score_value: int = 1000
@export var size: float = 50.0

var _health: int = max_health
var _phase: int = 3
var _dead: bool = false
var _entry_complete: bool = false
var _entry_timer: float = 0.0
var _attack_timer: float = 0.0
var _move_direction: float = 1.0
var _phase_changed_flash: float = 0.0


func _ready() -> void:
	add_to_group("boss")
	add_to_group("enemy")
	var viewport_size: Vector2 = get_viewport_rect().size
	position = Vector2(viewport_size.x * 0.5, -size * 2.0)
	_health = max_health
	_phase = 3
	health_changed.emit(_health, max_health)


func _process(delta: float) -> void:
	if _dead:
		return
	if _phase_changed_flash > 0.0:
		_phase_changed_flash -= delta
	_update_phase()
	if not _entry_complete:
		position.y += ENTRY_SPEED * delta
		var viewport_size: Vector2 = get_viewport_rect().size
		var target_y: float = viewport_size.y * 0.15
		if position.y >= target_y:
			position.y = target_y
			_entry_complete = true
			_attack_timer = 0.5
	else:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = _get_attack_interval()
			_perform_attack()
		_move_sideways(delta)

	if _health <= 0 and not _dead:
		_die()


func _update_phase() -> void:
	var new_phase: int = 3
	var health_ratio: float = float(_health) / float(max_health)
	if health_ratio <= 0.33:
		new_phase = 1
	elif health_ratio <= 0.66:
		new_phase = 2
	if new_phase != _phase:
		_phase = new_phase
		_phase_changed_flash = 0.3


func _get_attack_interval() -> float:
	match _phase:
		3:
			return 1.2
		2:
			return 0.9
		1:
			return 0.6
	return 1.0


func _perform_attack() -> void:
	match _phase:
		3:
			_fire_single_homing()
		2:
			_fire_spread_homing(3)
		1:
			_fire_spread_homing(5)


func _fire_single_homing() -> void:
	_fire_homing_bullet(position, 0.0)


func _fire_spread_homing(count: int) -> void:
	var spread_angle: float = PI * 0.25
	var start_angle: float = -spread_angle * 0.5
	var step: float = spread_angle / maxf(1.0, float(count - 1))
	for i: int in range(count):
		var angle_offset: float = start_angle + step * float(i)
		_fire_homing_bullet(position, angle_offset)


func _fire_homing_bullet(from_position: Vector2, angle_offset: float) -> void:
	var player: Node2D = _get_player()
	var direction: Vector2 = Vector2.DOWN
	if player != null:
		direction = (player.position - from_position).normalized()
	var spread_rotation: float = angle_offset
	direction = direction.rotated(spread_rotation)
	var gm: Node = get_parent()
	if gm != null and gm.has_method("spawn_boss_bullet"):
		gm.spawn_boss_bullet(from_position, direction)


func _move_sideways(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var bounds_x: float = clampf(size, 0.0, viewport_size.x - size)
	position.x += _move_direction * MOVE_SPEED * delta * (1.0 + float(4 - _phase) * 0.3)
	if position.x <= bounds_x:
		position.x = bounds_x
		_move_direction = 1.0
	elif position.x >= viewport_size.x - bounds_x:
		position.x = viewport_size.x - bounds_x
		_move_direction = -1.0


func _get_player() -> Node2D:
	var parent: Node = get_parent()
	if parent == null:
		return null
	var player: Node2D = parent.get_node_or_null("Player") as Node2D
	return player


func take_damage(damage: int) -> void:
	if _dead:
		return
	_health -= damage
	if _health < 0:
		_health = 0
	health_changed.emit(_health, max_health)
	queue_redraw()
	if _health <= 0:
		_die()


func _die() -> void:
	_dead = true
	var gm: Node = get_parent()
	if gm != null and gm.has_method("on_boss_died"):
		gm.on_boss_died(self, position)
	queue_free()


func _draw() -> void:
	var draw_color: Color = Color(0.7, 0.0, 0.8, 1.0)
	if _phase == 2:
		draw_color = Color(0.9, 0.0, 0.5, 1.0)
	elif _phase == 1:
		draw_color = Color(1.0, 0.0, 0.0, 1.0)
	if _phase_changed_flash > 0.0:
		draw_color = Color(1.0, 1.0, 1.0, 1.0)
		draw_circle(Vector2.ZERO, size * 0.3, Color.YELLOW)
	draw_circle(Vector2.ZERO, size, draw_color)
	draw_circle(Vector2.ZERO, size * 0.7, Color(0.3, 0.0, 0.4, 1.0))
	var eye_size: float = 8.0
	draw_circle(Vector2(-size * 0.25, -size * 0.2), eye_size, Color.WHITE)
	draw_circle(Vector2(size * 0.25, -size * 0.2), eye_size, Color.WHITE)
	draw_circle(Vector2(-size * 0.25, -size * 0.2), eye_size * 0.5, Color.BLACK)
	draw_circle(Vector2(size * 0.25, -size * 0.2), eye_size * 0.5, Color.BLACK)


func is_dead() -> bool:
	return _dead
