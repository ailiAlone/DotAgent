@tool
extends SceneTree
func _init() -> void:
	var bad := 0
	for p in ["res://scripts/hud.gd", "res://scripts/magnet_powerup.gd"]:
		var res = load(p)
		if res == null:
			print("[FAIL] %s 解析失败" % p)
			bad += 1
		else:
			print("[OK] %s" % p)
	quit(1 if bad else 0)
