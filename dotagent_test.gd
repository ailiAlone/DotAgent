extends Node2D
# DotAgent test script — updated by tool test
@export var counter: int = 0
@export var label_text: String = "Updated by replace_in_file"

func _ready() -> void:
	print("[dotagent_test] ready v2 — counter=", counter, " text=", label_text)
	counter += 1

func increment(by: int = 1) -> void:
	counter += by
	print("[dotagent_test] counter is now ", counter)
