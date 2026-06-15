extends Area2D

# Boss：多阶段敌人，每 5 波出现一个
# 3 阶段：phase 0 = 满血入场，phase 1 = 66% 血量进入弹幕模式，phase 2 = 33% 血量暴走

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

signal killed(score_value, position)
signal damaged(hp)

var hp = 120
var max_hp = 120
var score_value = 2000
var screen_size: Vector2
var t = 0.0
var phase = 0
var shoot_timer = 0.0
var aim_timer = 0.0
var move_target_x = 0.0
var body_color = Color(0.6, 0.2, 0.7)
var accent_color = Color(1.0, 0.4, 0.4)
var core_pulse = 0.0
var hit_flash = 0.0
var entry_y = -120.0
var landed = false
var shake_on_hit = 0.3

func _ready():
	screen_size = get_viewport_rect().size
	add_to_group("enemies")
	position = Vector2(screen_size.x / 2, entry_y)
	move_target_x = screen_size.x / 2

func take_damage(dmg = 1):
	hp -= dmg
	hit_flash = 0.15
	damaged.emit(hp)
	var pct = float(hp) / max_hp
	if pct <= 0.33 and phase < 2:
		phase = 2
		shoot_timer = 0
		_am().play_sfx("warning")
	elif pct <= 0.66 and phase < 1:
		phase = 1
		shoot_timer = 0
		_am().play_sfx("warning")
	if hp <= 0:
		die()
		return true
	return false

func die():
	_am().play_sfx("explode")
	killed.emit(score_value, position)
	# 多次爆炸形成大爆裂
	var parent = get_parent()
	if parent:
		var exp = preload("res://scenes/explosion.tscn").instantiate()
		exp.position = position
		exp.size = 3.0
		exp.color = Color(1.0, 0.4, 0.8)
		parent.add_child(exp)
	queue_free()

func _process(delta):
	t += delta
	core_pulse = fmod(core_pulse + delta * 4.0, TAU)
	hit_flash = max(0, hit_flash - delta)
	# 入场动画
	if not landed:
		position.y += (140 - position.y) * 2.0 * delta
		if position.y >= 138:
			position.y = 140
			landed = true
	else:
		# 左右摆动
		move_target_x = screen_size.x / 2 + sin(t * 0.8) * 280
		position.x += (move_target_x - position.x) * 1.5 * delta
		position.y = 140 + sin(t * 2.0) * 8
	# 弹幕发射
	shoot_timer -= delta
	if landed and shoot_timer <= 0:
		fire_pattern()
		shoot_timer = _shoot_interval()
	queue_redraw()

func _shoot_interval() -> float:
	match phase:
		0: return 1.2
		1: return 0.55
		2: return 0.28
	return 1.0

func fire_pattern():
	_am().play_sfx("shoot")
	var player = get_tree().get_first_node_in_group("player")
	# 用 get_parent() 不用 current_scene：boss 既可能作为 current_scene 单独跑，也可能被加到 Enemies 节点下
	var enemies_node = get_parent()
	if enemies_node == null:
		return
	match phase:
		0:
			# 单发朝向玩家
			_spawn_bullet_to(enemies_node, position + Vector2(0, 50), player)
		1:
			# 三连发扇形
			for ang in [-0.3, 0, 0.3]:
				var dir = Vector2(sin(ang), cos(ang))
				if player:
					dir = (player.position - position).normalized().rotated(ang)
				_spawn_bullet_dir(enemies_node, position + Vector2(0, 50), dir)
		2:
			# 环形弹幕
			for i in 16:
				var a = (TAU / 16) * i + t * 2
				var dir = Vector2(cos(a), sin(a))
				_spawn_bullet_dir(enemies_node, position + Vector2(0, 50), dir)

func _spawn_bullet_to(parent, pos, target):
	if target == null:
		_spawn_bullet_dir(parent, pos, Vector2.DOWN)
		return
	var dir = (target.position - position).normalized()
	_spawn_bullet_dir(parent, pos, dir)

func _spawn_bullet_dir(parent, pos, dir):
	var b = preload("res://scenes/enemy_bullet.tscn").instantiate()
	b.position = pos
	b.velocity = dir * 340.0
	b.color = Color(1.0, 0.3, 0.7) if phase >= 1 else Color(1.0, 0.6, 0.3)
	parent.add_child(b)

func _draw():
	var w = 90
	var h = 60
	var body = PackedVector2Array([
		Vector2(0, h), Vector2(w, h*0.3), Vector2(w*0.7, -h*0.4),
		Vector2(w*0.4, -h), Vector2(-w*0.4, -h), Vector2(-w*0.7, -h*0.4),
		Vector2(-w, h*0.3)
	])
	var draw_color = body_color
	if hit_flash > 0:
		draw_color = draw_color.lerp(Color.WHITE, hit_flash * 3.0)
	# 外壳
	draw_colored_polygon(body, draw_color)
	# 描边
	draw_polyline(body + PackedVector2Array([body[0]]), Color(0, 0, 0, 0.4), 2.0)
	# 左右翼炮
	draw_rect(Rect2(Vector2(-w-20, -5), Vector2(20, 18)), accent_color)
	draw_rect(Rect2(Vector2(w, -5), Vector2(20, 18)), accent_color)
	# 核心
	var pulse = 0.6 + 0.4 * sin(core_pulse)
	var core_col = Color(1.0, 0.8 - 0.5 * phase/2.0, 0.2)
	draw_circle(Vector2(0, 0), 18 * pulse, core_col)
	# 阶段指示
	match phase:
		0:
			draw_arc(Vector2(0, 0), 36, 0, TAU, 32, Color(0.3, 0.9, 1.0, 0.3), 2)
		1:
			draw_arc(Vector2(0, 0), 36, 0, TAU, 32, Color(1.0, 0.9, 0.3, 0.5), 2)
			# 多画两圈
			draw_arc(Vector2(0, 0), 44, 0, TAU, 32, Color(1.0, 0.5, 0.2, 0.3), 1.5)
		2:
			draw_arc(Vector2(0, 0), 36, 0, TAU, 32, Color(1.0, 0.2, 0.2, 0.6), 2)
			draw_arc(Vector2(0, 0), 44, 0, TAU, 32, Color(1.0, 0.5, 0.0, 0.5), 1.5)
			draw_arc(Vector2(0, 0), 52, 0, TAU, 32, Color(1.0, 0.8, 0.0, 0.4), 1.0)
