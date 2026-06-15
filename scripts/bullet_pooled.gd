extends Area2D

# 子弹的池化版本：用 reset() 重置参数，配合 game.gd 的 pool 复用

class_name BulletPooled

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

var velocity: Vector2 = Vector2.UP * 900
var damage: int = 1
var lifetime: float = 3.0
var is_enemy: bool = false
var color: Color = Color(1.0, 0.95, 0.4)
var active: bool = false

func _ready():
	add_to_group("bullets")
	# 池化的子弹默认是 inactive
	set_process(false)
	set_physics_process(false)
	visible = false
	monitoring = false
	monitorable = false

func reset(pos: Vector2, vel: Vector2, dmg: int, is_e: bool, col: Color):
	position = pos
	velocity = vel
	damage = dmg
	is_enemy = is_e
	color = col
	lifetime = 3.0
	active = true
	visible = true
	monitoring = true
	monitorable = true
	set_process(true)
	set_physics_process(true)
	queue_redraw()

func _process(delta):
	if not active:
		return
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0 or not _in_bounds():
		_deactivate()

func _in_bounds() -> bool:
	var vp = get_viewport_rect()
	return position.x > -50 and position.x < vp.size.x + 50 and position.y > -50 and position.y < vp.size.y + 50

func deactivate():
	_deactivate()

func _deactivate():
	active = false
	visible = false
	set_process(false)
	set_physics_process(false)
	monitoring = false
	monitorable = false
	# 通知 game 池
	if has_node("/root/GamePool") or true:
		# 走路径回退，game 自身监听
		var game = get_tree().current_scene
		if game and game.has_method("return_bullet"):
			game.return_bullet(self)

func _draw():
	var tip = Vector2(0, -16)
	var tail = Vector2(0, 16)
	if is_enemy:
		tip = Vector2(0, 16)
		tail = Vector2(0, -16)
	draw_line(tip, tail, Color(color.r, color.g, color.b, 0.4), 8)
	draw_line(tip, tail, color, 3)
	draw_circle(Vector2(0, 0), 4, color)
