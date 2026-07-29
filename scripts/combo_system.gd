class_name ComboSystem
extends Node

## Combo Kill System
## Tracks consecutive enemy kills and provides a score multiplier reward.
## Call register_kill() when an enemy/asteroid/boss is destroyed.
## Call break_combo() when the player is hit or the combo should reset.
## Call tick(delta) every frame to decay the combo timer.

signal combo_changed(count: int, multiplier: float, timer: float)
signal combo_ended(final_count: int)
signal combo_milestone(count: int, message: String)

@export_range(0.5, 10.0, 0.1) var combo_duration: float = 3.0
@export_range(5, 50, 1) var milestone_interval: int = 10
@export_range(1.0, 10.0, 0.1) var max_multiplier: float = 5.0

var combo_count: int = 0
var combo_timer: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	combo_count = 0
	combo_timer = 0.0

func register_kill():
	combo_count += 1
	combo_timer = combo_duration
	_check_milestone()
	combo_changed.emit(combo_count, get_multiplier(), combo_timer)

func break_combo():
	if combo_count > 0:
		var final = combo_count
		combo_count = 0
		combo_timer = 0.0
		combo_ended.emit(final)
	combo_changed.emit(combo_count, get_multiplier(), combo_timer)

func get_multiplier() -> float:
	if combo_count <= 1:
		return 1.0
	var mult = 1.0 + (combo_count - 1) * 0.1
	return min(mult, max_multiplier)

func tick(delta: float):
	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			break_combo()
		else:
			combo_changed.emit(combo_count, get_multiplier(), combo_timer)

func reset():
	combo_count = 0
	combo_timer = 0.0
	combo_changed.emit(combo_count, get_multiplier(), combo_timer)

func _check_milestone():
	if combo_count > 0 and combo_count % milestone_interval == 0:
		combo_milestone.emit(combo_count, "COMBO x%d!" % combo_count)
