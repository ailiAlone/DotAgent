extends SceneTree
## 一次性自验：直接调用 exec_tools 的 run_game_check，验证冒烟闭环端到端可用。

func _init() -> void:
	var res = load("res://addons/dotagent/tools/exec_tools.gd")
	if res == null:
		print("[TEST-FAIL] cannot load exec_tools.gd")
		quit(1)
		return
	var obj = res.new()
	print("[TEST] calling run_game_check on scenes/game.tscn ...")
	var result: Dictionary = await obj.call_method("_tool_run_game_check", {
		"scene": "res://scenes/game.tscn",
		"frames": 120,
		"expect": "Player",
		"timeout_ms": 60000,
	})
	print("[TEST] ok=%s" % str(result.get("ok")))
	print(str(result.get("content", "")))
	quit(0)
