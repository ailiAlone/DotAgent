extends Node2D

# Tool Test Script - updated
# Now verifies: update_script

var counter: int = 0
var label_text: String = "ready"
var last_update: String = "2026-tool-test-updated-by-replace"

func _ready() -> void:
	print("[tool_test] _ready called, counter=", counter)
	counter = 1
	label_text = "initialized"
	last_update = "after_replace_in_scripts"

func increment() -> int:
	counter += 1
	return counter

func get_label_text() -> String:
	return label_text

func get_last_update() -> String:
	return last_update

func reset() -> void:
	counter = 0
	label_text = "ready"
