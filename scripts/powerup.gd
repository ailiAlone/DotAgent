extends Area2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

enum PowerupType { HEAL, RAPID_FIRE, SHIELD, BOMB, SCORE_X2 }

var powerup_type: PowerupType = PowerupType.HEAL
var velocity := Vector2(0, 120)
var t: float = 0.0
var base_x: float = 0.0
var color: Color = Color(0.3, 1.0, 0.4)

func _ready():
	base_x = position.x
	match powerup_type:
		PowerupType.HEAL: color = Color(0.3, 1.0, 0.4)
		PowerupType.RAPID_FIRE: color = Color(1.0, 0.85, 0.2)
		PowerupType.SHIELD: color = Color(0.3, 0.8, 1.0)
		PowerupType.BOMB: color = Color(1.0, 0.3, 0.2)
		PowerupType.SCORE_X2: color = Color(0.9, 0.3, 1.0)
	add_to_group("powerups")

func _process(delta):
	t += delta
	position += velocity * delta
	position.x = base_x + sin(t * 3.0) * 30
	queue_redraw()
	if position.y > get_viewport_rect().size.y + 40:
		queue_free()

func _draw():
	var gem = PackedVector2Array([
		Vector2(0, -16), Vector2(14, 0), Vector2(0, 16), Vector2(-14, 0)
	])
	draw_colored_polygon(gem, color)
	draw_circle(Vector2(0, 0), 4, Color(1, 1, 1, 0.85))
	match powerup_type:
		PowerupType.HEAL:
			draw_line(Vector2(-6, 0), Vector2(6, 0), Color.WHITE, 2)
			draw_line(Vector2(0, -6), Vector2(0, 6), Color.WHITE, 2)
		PowerupType.RAPID_FIRE:
			draw_line(Vector2(-7, -4), Vector2(0, -10), Color.WHITE, 2)
			draw_line(Vector2(0, -10), Vector2(7, -4), Color.WHITE, 2)
			draw_line(Vector2(-7, 4), Vector2(0, -2), Color.WHITE, 2)
			draw_line(Vector2(0, -2), Vector2(7, 4), Color.WHITE, 2)
		PowerupType.SHIELD:
			draw_arc(Vector2.ZERO, 7, 0, TAU, 16, Color(1, 1, 1, 0.7), 2)
		PowerupType.BOMB:
			# 炸弹图标：星爆
			for i in 8:
				var a = TAU / 8.0 * i + t * 0.5
				var p1 = Vector2(cos(a) * 4, sin(a) * 4)
				var p2 = Vector2(cos(a) * 9, sin(a) * 9)
				draw_line(p1, p2, Color.WHITE, 2)
			draw_circle(Vector2(0, 0), 3, Color.WHITE)
		PowerupType.SCORE_X2:
			# X2 文字
			draw_line(Vector2(-7, -7), Vector2(7, 7), Color.WHITE, 2)
			draw_line(Vector2(-7, 7), Vector2(7, -7), Color.WHITE, 2)
			# 上下两条小横
			draw_line(Vector2(-3, -10), Vector2(3, -10), Color.WHITE, 2)
			draw_line(Vector2(-3, 10), Vector2(3, 10), Color.WHITE, 2)
