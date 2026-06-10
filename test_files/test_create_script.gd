extends Node
# Tool test script — verifies create_script AND update_script

var created_at: String = "2026-tool-test-updated-by-replace"
var value: int = 42
var last_update: String = "after_replace_in_file"
var extra_field: int = 99

func _ready() -> void:
	print("[test_create_script] ready v2, value=", value, " last=", last_update)

func get_value() -> int:
	return value

func get_last_update() -> String:
	return last_update

func double_value() -> int:
	return value * 2
