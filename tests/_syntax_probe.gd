extends SceneTree
func _init() -> void:
	var paths := [
		"res://addons/dotagent/banyan_agent/tree/agent_node.gd",
		"res://addons/dotagent/banyan_agent/tree/agent_tree.gd",
		"res://addons/dotagent/tools/exec_tools.gd",
		"res://tests/run_banyan_headless.gd",
	]
	var bad := 0
	for p in paths:
		var r = load(p)
		if r == null:
			bad += 1
			print("[FAIL] ", p)
		else:
			print("[OK] ", p)
	quit(1 if bad > 0 else 0)
