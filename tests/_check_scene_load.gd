@tool
extends SceneTree
## 全场景 script 挂接回归：任何 .tscn 节点的 script 属性必须解析为 GDScript，
## 不允许 String/Dictionary（LLM 手写场景曾全部挂空 — 游戏从未真正运行过脚本）
## 运行: godot --headless --path <project> --script res://tests/_check_scene_load.gd
func _init() -> void:
	var bad: int = 0
	var total: int = 0
	var dir := DirAccess.open("res://scenes")
	if dir == null:
		print("[FAIL] scenes 目录不存在")
		quit(1)
		return
	for fname in dir.get_files():
		if not fname.ends_with(".tscn"):
			continue
		total += 1
		var p: String = "res://scenes/" + fname
		var res = load(p)
		if res == null:
			print("[FAIL] %s 加载失败" % fname)
			bad += 1
			continue
		var inst = res.instantiate()
		bad += _check_node_scripts(inst, fname)
	if bad == 0:
		print("[PASS] 全部 %d 个场景 script 挂接正确" % total)
	else:
		print("[FAIL] %d 处 script 异常" % bad)
	quit(1 if bad > 0 else 0)


func _check_node_scripts(node: Node, fname: String) -> int:
	var bad: int = 0
	var sc = node.get_script()
	if sc != null and not (sc is GDScript or sc is Script):
		print("[FAIL] %s/%s script 是 %s 而非 Script" % [fname, str(node.get_path()), type_string(typeof(sc))])
		bad += 1
	for c in node.get_children():
		bad += _check_node_scripts(c, fname)
	return bad
