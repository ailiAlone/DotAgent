@tool
extends SceneTree
## 运行时冒烟驱动 — 由 run_game_check 工具以 --script 方式拉起。
## 用法（-- 后的用户参数）:
##   scene=res://scenes/game.tscn   必填，实例化并运行
##   frames=300                     运行帧数（默认 300）
##   press=sprint@30,slow_mo@60     第 N 帧按下动作（Input.action_press）
##   release=sprint@90              第 N 帧松开动作
##   expect=SprintLabel,SlowMoLabel 结束时必须存在的节点名（find_child 递归）
## 输出协议（供工具解析）:
##   [SMOKE] ... 信息行 / [SMOKE-PASS] / [SMOKE-FAIL] ... / [SMOKE-ERROR] ...

var _press := {}
var _release := {}
var _expect: Array = []
var _frames: int = 300
var _scene_path: String = ""
var _inst: Node = null
var _frame: int = 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="):
			_scene_path = a.substr(6)
		elif a.begins_with("frames="):
			_frames = int(a.substr(7))
		elif a.begins_with("press="):
			_parse_schedule(a.substr(6), _press)
		elif a.begins_with("release="):
			_parse_schedule(a.substr(8), _release)
		elif a.begins_with("expect="):
			for e in a.substr(7).split(",", false):
				_expect.append(e)
	if _scene_path.is_empty():
		print("[SMOKE-ERROR] missing scene= arg")
		quit(2)
		return
	var ps = load(_scene_path)
	if ps == null:
		print("[SMOKE-ERROR] failed to load: %s" % _scene_path)
		quit(2)
		return
	_inst = ps.instantiate()
	root.add_child(_inst)
	print("[SMOKE] instantiated %s, running %d frames" % [_scene_path, _frames])


func _parse_schedule(spec: String, into: Dictionary) -> void:
	for item in spec.split(",", false):
		var parts := item.split("@")
		if parts.size() == 2:
			var f := int(parts[1])
			if not into.has(f):
				into[f] = []
			into[f].append(parts[0])


func _process(_delta: float) -> bool:
	_frame += 1
	if _press.has(_frame):
		for act in _press[_frame]:
			Input.action_press(act)
			print("[SMOKE] press %s @%d" % [act, _frame])
	if _release.has(_frame):
		for act in _release[_frame]:
			Input.action_release(act)
			print("[SMOKE] release %s @%d" % [act, _frame])
	if _frame >= _frames:
		_finish()
	return false


func _finish() -> void:
	var missing: Array = []
	for e in _expect:
		if _inst == null or _inst.find_child(e, true, false) == null:
			missing.append(e)
	if missing.is_empty():
		print("[SMOKE-PASS] expectations met (%d)" % _expect.size())
	else:
		print("[SMOKE-FAIL] missing nodes: %s" % ", ".join(missing))
	print("[SMOKE] done frames=%d" % _frame)
	quit(0)
