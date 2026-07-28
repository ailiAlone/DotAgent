extends Node2D

static func _gm():
	return Engine.get_main_loop().root.get_node_or_null("GameManager")

static func _am():
	return Engine.get_main_loop().root.get_node_or_null("AudioManager")

const TRANSITION_DURATION := 1.5

var stars: Array = []
var screen_size: Vector2
var _target_palette: Array[Color] = []
var _transition_timer: float = 0.0
var _transitioning: bool = false

var layers := [
	{"count": 70, "speed": 50.0, "size_range": [1.0, 1.8], "color": Color(0.7, 0.8, 1.0, 0.65)},
	{"count": 45, "speed": 130.0, "size_range": [1.4, 2.2], "color": Color(0.9, 0.9, 1.0, 0.85)},
	{"count": 18, "speed": 250.0, "size_range": [2.4, 3.6], "color": Color(1.0, 1.0, 1.0, 1.0)},
]

func _ready():
	screen_size = get_viewport_rect().size
	get_tree().root.size_changed.connect(_on_size_changed)
	_randomize()

func _on_size_changed():
	screen_size = get_viewport_rect().size

func _randomize():
	stars.clear()
	for layer in layers:
		for i in layer.count:
			stars.append({
				"pos": Vector2(randf() * screen_size.x, randf() * screen_size.y),
				"speed": layer.speed * randf_range(0.7, 1.3),
				"size": randf_range(layer.size_range[0], layer.size_range[1]),
				"color": layer.color,
				"twinkle": randf() * TAU,
				"twinkle_speed": randf_range(2.0, 5.0)
			})

func _process(delta):
	for s in stars:
		s.pos.y += s.speed * delta
		s.twinkle += s.twinkle_speed * delta
		if s.pos.y > screen_size.y + 10:
			s.pos.y = -10
			s.pos.x = randf() * screen_size.x

	if _transitioning:
		_transition_timer = clamp(_transition_timer + delta, 0.0, TRANSITION_DURATION)
		var t := _transition_timer / TRANSITION_DURATION
		var idx := 0
		for s in stars:
			var layer_idx := _layer_index_for_star(idx)
			if layer_idx >= 0 and layer_idx < _target_palette.size():
				s.color = s.color.lerp(_target_palette[layer_idx], t)
			idx += 1
		if _transition_timer >= TRANSITION_DURATION:
			_transitioning = false
			for i in range(3):
				layers[i]["color"] = _target_palette[i]

	queue_redraw()

func _layer_index_for_star(star_index: int) -> int:
	var cumulative := 0
	for i in range(layers.size()):
		cumulative += layers[i].count
		if star_index < cumulative:
			return i
	return -1

func _draw():
	for s in stars:
		var tw := 0.7 + 0.3 * sin(s.twinkle)
		var c := Color(s.color.r, s.color.g, s.color.b, s.color.a * tw)
		draw_circle(s.pos, s.size, c)
		if s.size > 2.0:
			draw_circle(s.pos, s.size * 2.8, Color(c.r, c.g, c.b, c.a * 0.12))


# 阶段调色板：每过一个 Stage（5波）平滑改变星空色相
func set_palette(stage: int):
	var hue_shift := float((stage - 1) % 6) * 0.16
	_target_palette = [
		Color.from_hsv(fmod(0.58 + hue_shift, 1.0), 0.2, 1.0, 0.65),
		Color.from_hsv(fmod(0.60 + hue_shift, 1.0), 0.1, 1.0, 0.85),
		Color.from_hsv(fmod(0.62 + hue_shift, 1.0), 0.05, 1.0, 1.0),
	]
	_transition_timer = 0.0
	_transitioning = true
	for i in range(3):
		layers[i]["color"] = _target_palette[i]
