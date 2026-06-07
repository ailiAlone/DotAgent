extends Control

## 躲避掉落方块的小游戏
## 鼠标/触屏控制玩家，WASD/方向键也可移动
## 每躲过一个敌人 +1 分，碰到敌人游戏结束

const PLAYER_SIZE := Vector2(48, 48)
const ENEMY_SIZE := Vector2(40, 40)
const ENEMY_SPAWN_INTERVAL := 0.8
const ENEMY_SPEED_MIN := 200.0
const ENEMY_SPEED_MAX := 500.0
const PLAYER_SPEED := 500.0

var score := 0
var game_running := false
var spawn_timer: float = 0.0
var enemies: Array[ColorRect] = []
var player_velocity := Vector2.ZERO


@onready var player: ColorRect = %Player
@onready var score_label: Label = %ScoreLabel
@onready var game_over_panel: Panel = %GameOverPanel
@onready var final_score_label: Label = %FinalScoreLabel
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	restart_button.pressed.connect(_restart_game)
	start_game()


func _process(delta: float) -> void:
	if not game_running:
		return

	# 玩家移动
	_handle_player_input(delta)
	# 敌人生成
	_spawn_enemies(delta)
	# 敌人移动 + 碰撞检测
	_move_enemies(delta)


func _handle_player_input(delta: float) -> void:
	var input_dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)

	# 鼠标跟随（鼠标在窗口内时覆盖键盘）
	var mouse_pos := get_local_mouse_position()
	var viewport_size := get_viewport_rect().size
	if mouse_pos.x >= 0 and mouse_pos.x <= viewport_size.x and mouse_pos.y >= 0 and mouse_pos.y <= viewport_size.y:
		player.position = player.position.move_toward(mouse_pos - PLAYER_SIZE / 2, PLAYER_SPEED * delta)
	else:
		player.position += input_dir * PLAYER_SPEED * delta

	# 限制玩家在屏幕内
	player.position.x = clamp(player.position.x, 0, viewport_size.x - PLAYER_SIZE.x)
	player.position.y = clamp(player.position.y, 0, viewport_size.y - PLAYER_SIZE.y)


func _spawn_enemies(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer > 0:
		return

	var viewport_size := get_viewport_rect().size
	var enemy := ColorRect.new()
	enemy.size = ENEMY_SIZE
	enemy.color = Color(randf(), randf(), randf(), 1.0)
	enemy.position = Vector2(randf() * (viewport_size.x - ENEMY_SIZE.x), -ENEMY_SIZE.y)
	add_child(enemy)
	enemies.append(enemy)

	# 随时间加速
	spawn_timer = max(ENEMY_SPAWN_INTERVAL - score * 0.02, 0.2)


func _move_enemies(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var player_rect := Rect2(player.position, PLAYER_SIZE)

	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		if not is_instance_valid(enemy):
			enemies.remove_at(i)
			continue

		var speed := randf() * (ENEMY_SPEED_MAX - ENEMY_SPEED_MIN) + ENEMY_SPEED_MIN
		enemy.position.y += speed * delta

		# 敌人离开屏幕底部 → 得分
		if enemy.position.y > viewport_size.y:
			score += 1
			score_label.text = "Score: %d" % score
			enemy.queue_free()
			enemies.remove_at(i)
			continue

		# 碰撞检测
		var enemy_rect := Rect2(enemy.position, ENEMY_SIZE)
		if player_rect.intersects(enemy_rect):
			_game_over()
			return


func start_game() -> void:
	score = 0
	game_running = true
	spawn_timer = 1.0
	score_label.text = "Score: 0"
	score_label.visible = true
	player.visible = true
	game_over_panel.visible = false

	# 清除旧敌人
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()

	# 玩家居中
	player.position = get_viewport_rect().size / 2 - PLAYER_SIZE / 2


func _game_over() -> void:
	game_running = false
	player.visible = false
	score_label.visible = false
	game_over_panel.visible = true
	final_score_label.text = "Score: %d" % score

	# 清除所有敌人
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()


func _restart_game() -> void:
	start_game()
