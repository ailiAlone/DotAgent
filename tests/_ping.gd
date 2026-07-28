extends SceneTree
## 最小化连通性测试 — 验证 Godot 无头模式可用

func _init():
	var result := {
		"ok": true,
		"godot_version": Engine.get_version_info().get("string", ""),
		"headless": DisplayServer.get_name() == "headless",
		"project_name": ProjectSettings.get_setting("application/config/name", "unknown"),
		"classdb_area2d": ClassDB.class_exists("Area2D"),
		"classdb_styleboxflat": ClassDB.class_exists("StyleBoxFlat"),
	}

	# 测试 ClassDB 实例化
	var test_types := ["Area2D", "Node2D", "Sprite2D", "RectangleShape2D", "StyleBoxFlat"]
	var instances := {}
	for t in test_types:
		var obj = ClassDB.instantiate(t)
		if obj != null:
			instances[t] = true
			if obj is Node:
				(obj as Node).queue_free()
		else:
			instances[t] = false
	result["instances"] = instances

	# 测试 FileAccess
	result["player_gd_exists"] = FileAccess.file_exists("res://scripts/player.gd")
	result["game_tscn_exists"] = FileAccess.file_exists("res://scenes/game.tscn")

	# 写入结果
	var f := FileAccess.open("res://tests/_ping_result.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(result, "  "))
		f.close()

	print("PING OK: Godot %s | Project: %s | Headless: %s" % [
		result.godot_version, result.project_name, str(result.headless)
	])
	quit(0)
