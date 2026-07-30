class_name DamagePopup
extends Node2D

# Floating damage/healing popup.
# Instantiation helper: DamagePopup.spawn(parent, value, is_heal, world_position)

@export var value: int = 0
@export var is_heal: bool = false
@export var lifetime: float = 1.0
@export var float_speed: float = 40.0

@onready var label: Label = $Label

func _ready():
	if label == null:
		return
	_update_appearance()
	var tween = create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y - float_speed * lifetime, lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime)
	tween.chain().tween_callback(queue_free)

func _update_appearance():
	label.text = str(value)
	if is_heal:
		label.modulate = Color(0.2, 1.0, 0.3)
	else:
		label.modulate = Color(1.0, 0.2, 0.15)

func setup(popup_value: int, heal: bool = false):
	value = popup_value
	is_heal = heal
	if label != null:
		_update_appearance()

static func spawn(parent: Node, popup_value: int, heal: bool = false, world_position: Vector2 = Vector2.ZERO) -> DamagePopup:
	var scene = load("res://scenes/damage_popup.tscn")
	if scene == null:
		return null
	var popup = scene.instantiate() as DamagePopup
	if popup == null:
		return null
	popup.value = popup_value
	popup.is_heal = heal
	popup.position = world_position
	parent.add_child(popup)
	return popup
