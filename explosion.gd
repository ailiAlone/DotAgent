extends Node2D

# 爆炸特效 — CPU 粒子 + 闪光

@onready var particles: CPUParticles2D = $Particles
@onready var flash: Polygon2D = $Flash

func _ready() -> void:
	# 标记：DotAgent 测试标记 2026 — 此行由 replace_in_file 插入
	particles.emitting = true
	# 闪光淡出
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.4)
	# 销毁
	var t := Timer.new()
	t.wait_time = particles.lifetime + 0.2
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()
