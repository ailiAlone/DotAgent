extends Node
class_name ShieldSystem

signal shield_changed(current: float, max_energy: float)
signal shield_depleted
signal shield_ready

@export var max_energy: float = 100.0
@export var drain_per_second: float = 25.0
@export var recharge_per_second: float = 15.0
@export var recharge_delay: float = 0.5

var energy: float = 0.0
var _active: bool = false
var _recharge_timer: float = 0.0
var _was_depleted: bool = false

func _ready():
	energy = max_energy
	shield_changed.emit(energy, max_energy)

func _process(delta):
	if _active:
		energy -= drain_per_second * delta
		if energy <= 0.0:
			energy = 0.0
			_active = false
			_was_depleted = true
			_recharge_timer = recharge_delay
			shield_depleted.emit()
		shield_changed.emit(energy, max_energy)
	else:
		if energy < max_energy:
			if _recharge_timer > 0.0:
				_recharge_timer -= delta
			else:
				energy = min(energy + recharge_per_second * delta, max_energy)
				shield_changed.emit(energy, max_energy)
				if _was_depleted and energy >= max_energy:
					_was_depleted = false
					shield_ready.emit()
		elif _was_depleted:
			_was_depleted = false
			shield_ready.emit()

func activate() -> bool:
	if _was_depleted or energy <= 0.0:
		return false
	if not _active:
		_active = true
		shield_changed.emit(energy, max_energy)
	return true

func deactivate() -> void:
	if _active:
		_active = false
		_recharge_timer = recharge_delay
		shield_changed.emit(energy, max_energy)

func is_active() -> bool:
	return _active

func is_ready() -> bool:
	return not _was_depleted and energy >= max_energy

func get_energy() -> float:
	return energy

func recharge(amount: float) -> void:
	energy = min(energy + amount, max_energy)
	shield_changed.emit(energy, max_energy)
	if _was_depleted and energy >= max_energy:
		_was_depleted = false
		shield_ready.emit()

func reset() -> void:
	energy = max_energy
	_active = false
	_recharge_timer = 0.0
	_was_depleted = false
	shield_changed.emit(energy, max_energy)
