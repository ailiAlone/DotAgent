@tool
extends EditorScript
## Banyan 工具测试运行器
##
## 用法：在 Godot 编辑器的脚本编辑器中打开此文件，按 Ctrl+Shift+X 运行。
## 结果写入 res://tests/results.json，QoderWork 会读取并分析。
##
## 每个 test_* 方法代表一个测试用例。返回 Dictionary：
##   {"name": "测试名", "ok": bool, "detail": "说明", "data": {...}}

func _run():
	var results: Array = []
	var ei := get_editor_interface()

	print("=== Banyan Tool Tests ===")
	print("Godot: %s" % Engine.get_version_info().get("string", ""))
	print("Scene: %s" % str(ei.get_edited_scene_root()))
	print("")

	# ---- 测试 1: EditorInterface 可用性 ----
	results.append(_test_editor_interface(ei))

	# ---- 测试 2: 脚本接口提取（核心逻辑验证）----
	results.append(_test_extract_script_interface(ei))

	# ---- 测试 3: 场景树结构化读取 ----
	results.append(_test_inspect_scene_structured(ei))

	# ---- 测试 4: ClassDB 工具验证 ----
	results.append(_test_classdb(ei))

	# ---- 测试 5: 资源接口提取 ----
	results.append(_test_inspect_resource_interface(ei))

	# ---- 写入结果文件 ----
	_write_results(results)


# ============ 测试用例 ============

func _test_editor_interface(ei: EditorInterface) -> Dictionary:
	var test := {"name": "EditorInterface 可用性", "ok": false, "detail": "", "data": {}}
	if ei == null:
		test.detail = "EditorInterface 为 null"
		return test
	var root = ei.get_edited_scene_root()
	if root == null:
		test.detail = "当前无打开的场景。请打开一个 Star Hunter 场景后重新运行。"
		return test
	test.ok = true
	test.detail = "场景根节点: %s (%s), 路径: %s" % [root.name, root.get_class(), root.scene_file_path]
	test.data = {
		"root_name": root.name,
		"root_type": root.get_class(),
		"scene_path": root.scene_file_path,
		"child_count": root.get_child_count(),
		"godot_version": Engine.get_version_info().get("string", ""),
	}
	print("✅ %s: %s" % [test.name, test.detail])
	return test


func _test_extract_script_interface(ei: EditorInterface) -> Dictionary:
	var test := {"name": "脚本接口提取", "ok": false, "detail": "", "data": {}}

	# 测试目标：player.gd（已知其接口）
	var path := "res://scripts/player.gd"
	if not FileAccess.file_exists(path):
		test.detail = "文件不存在: %s" % path
		return test

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		test.detail = "无法打开文件"
		return test
	var text := f.get_as_text()
	f.close()

	# 正则模式（这就是 extract_script_interface 的核心逻辑）
	var re_signal := RegEx.new()
	re_signal.compile("^signal\\s+(\\w+)(?:\\(([^)]*)\\))?")

	var re_func := RegEx.new()
	re_func.compile("^(static\\s+)?func\\s+(\\w+)\\s*\\(([^)]*)\\)(?:\\s*->\\s*(\\S+))?")

	var re_export := RegEx.new()
	re_export.compile("^@export\\s+(?:var\\s+)?(\\w+)\\s*(?::\\s*(\\w+))?\\s*(?:=\\s*(.+))?")

	var re_class_name := RegEx.new()
	re_class_name.compile("^class_name\\s+(\\w+)")

	var re_extends := RegEx.new()
	re_extends.compile("^extends\\s+(\\w+)")

	var re_enum := RegEx.new()
	re_enum.compile("^enum\\s+(\\w+)\\s*\\{")

	var signals_found: Array = []
	var public_methods: Array = []
	var private_methods: Array = []
	var exports_found: Array = []
	var class_name_found: String = ""
	var extends_found: String = ""
	var enums_found: Array = []
	var line_num: int = 0

	for line in text.split("\n"):
		line_num += 1
		var s := line.strip_edges()

		# class_name
		var m_cn := re_class_name.search(s)
		if m_cn:
			class_name_found = m_cn.get_string(1)

		# extends
		var m_ext := re_extends.search(s)
		if m_ext:
			extends_found = m_ext.get_string(1)

		# signal
		var m_sig := re_signal.search(s)
		if m_sig:
			var params_str := m_sig.get_string(2)
			var params: Array = []
			if not params_str.is_empty():
				for p in params_str.split(","):
					params.append(p.strip_edges())
			signals_found.append({"name": m_sig.get_string(1), "params": params, "line": line_num})

		# func
		var m_func := re_func.search(s)
		if m_func:
			var is_static := not m_func.get_string(1).is_empty()
			var fname := m_func.get_string(2)
			var params_str := m_func.get_string(3)
			var returns := m_func.get_string(4)
			var params: Array = []
			if not params_str.is_empty():
				for p in params_str.split(","):
					params.append(p.strip_edges())
			if fname.begins_with("_"):
				private_methods.append({"name": fname, "line": line_num})
			else:
				public_methods.append({
					"name": fname, "params": params,
					"returns": returns if not returns.is_empty() else "Variant",
					"is_static": is_static, "line": line_num
				})

		# @export
		var m_exp := re_export.search(s)
		if m_exp:
			exports_found.append({
				"name": m_exp.get_string(1),
				"type": m_exp.get_string(2) if not m_exp.get_string(2).is_empty() else "auto",
				"default": m_exp.get_string(3).strip_edges() if not m_exp.get_string(3).is_empty() else "",
				"line": line_num
			})

		# enum
		var m_enum := re_enum.search(s)
		if m_enum:
			enums_found.append({"name": m_enum.get_string(1), "line": line_num})

	# 验证已知接口（基于我们对 player.gd 的了解）
	var errors: Array = []

	# 应该找到 signal died
	var has_died := false
	for sig in signals_found:
		if sig.name == "died":
			has_died = true
	if not has_died:
		errors.append("未找到 signal died")

	# 应该找到 signal shoot
	var has_shoot := false
	for sig in signals_found:
		if sig.name == "shoot":
			has_shoot = true
	if not has_shoot:
		errors.append("未找到 signal shoot")

	# extends 应该是 Area2D
	if extends_found != "Area2D":
		errors.append("extends 应为 Area2D，实际: %s" % extends_found)

	# public_methods 应该包含 take_damage（如果有的话）
	# 注意：player.gd 的 public 方法可能不多，很多以 _ 开头

	test.ok = errors.is_empty()
	test.detail = "%d 个信号, %d 个公开方法, %d 个私有方法, %d 个 export, %d 个 enum" % [
		signals_found.size(), public_methods.size(), private_methods.size(),
		exports_found.size(), enums_found.size()
	]
	if not errors.is_empty():
		test.detail += "\n错误: " + "; ".join(errors)

	test.data = {
		"class_name": class_name_found,
		"extends": extends_found,
		"signals": signals_found,
		"public_methods": public_methods,
		"private_methods_count": private_methods.size(),
		"exports": exports_found,
		"enums": enums_found,
		"errors": errors,
	}

	if test.ok:
		print("✅ %s: %s" % [test.name, test.detail])
	else:
		print("❌ %s: %s" % [test.name, test.detail])
	return test


func _test_inspect_scene_structured(ei: EditorInterface) -> Dictionary:
	var test := {"name": "场景树结构化读取", "ok": false, "detail": "", "data": {}}

	var root = ei.get_edited_scene_root()
	if root == null:
		test.detail = "无打开场景"
		return test

	# 遍历场景树，收集结构化信息（这就是 inspect_scene_structured 的核心逻辑）
	var nodes: Array = []
	_collect_nodes(root, root, nodes, 0)

	# 统计
	var total_nodes := nodes.size()
	var nodes_with_scripts := 0
	var signal_connections := 0
	var groups_found: Array = []

	for nd in nodes:
		if not nd.get("script", "").is_empty():
			nodes_with_scripts += 1
		signal_connections += nd.get("signal_count", 0)
		for g in nd.get("groups", []):
			if not groups_found.has(g):
				groups_found.append(g)

	test.ok = total_nodes > 0
	test.detail = "%d 个节点, %d 个有脚本, %d 个信号连接, 组: %s" % [
		total_nodes, nodes_with_scripts, signal_connections,
		str(groups_found) if not groups_found.is_empty() else "(无)"
	]
	test.data = {
		"scene_path": root.scene_file_path,
		"total_nodes": total_nodes,
		"nodes_with_scripts": nodes_with_scripts,
		"signal_connections": signal_connections,
		"groups": groups_found,
		"nodes": nodes,  # 完整的结构化节点列表
	}

	if test.ok:
		print("✅ %s: %s" % [test.name, test.detail])
	else:
		print("❌ %s: %s" % [test.name, test.detail])
	return test


func _test_classdb(_ei: EditorInterface) -> Dictionary:
	var test := {"name": "ClassDB 工具验证", "ok": false, "detail": "", "data": {}}

	# 验证 ClassDB 能实例化常见的节点和资源类型
	var test_types := [
		"Area2D", "Node2D", "Control", "Sprite2D", "CollisionShape2D",
		"Label", "Button", "Timer", "Camera2D", "CanvasLayer",
		"RectangleShape2D", "CircleShape2D", "StyleBoxFlat",
	]

	var results: Array = []
	var failures: Array = []

	for type_name in test_types:
		if not ClassDB.class_exists(type_name):
			failures.append("%s: 不存在" % type_name)
			continue
		var obj = ClassDB.instantiate(type_name)
		if obj == null:
			failures.append("%s: 实例化失败" % type_name)
			continue
		var is_node := obj is Node
		var is_res := obj is Resource
		results.append({
			"type": type_name,
			"ok": true,
			"is_node": is_node,
			"is_resource": is_res,
		})
		if is_node:
			(obj as Node).queue_free()

	test.ok = failures.is_empty()
	test.detail = "%d/%d 类型可用" % [results.size(), test_types.size()]
	if not failures.is_empty():
		test.detail += "\n失败: " + "; ".join(failures)
	test.data = {"results": results, "failures": failures}

	if test.ok:
		print("✅ %s: %s" % [test.name, test.detail])
	else:
		print("❌ %s: %s" % [test.name, test.detail])
	return test


func _test_inspect_resource_interface(ei: EditorInterface) -> Dictionary:
	var test := {"name": "资源接口提取", "ok": false, "detail": "", "data": {}}

	# 测试 get_property_list() 反射能力
	# 用 StyleBoxFlat 作为测试对象（内置 Resource 类型）
	var res = ClassDB.instantiate("StyleBoxFlat")
	if res == null:
		test.detail = "无法实例化 StyleBoxFlat"
		return test

	var props: Array = []
	for p in res.get_property_list():
		var pname: String = p.get("name", "")
		var ptype: int = p.get("type", 0)
		var pusage: int = p.get("usage", 0)
		# 只收集有意义的属性（过滤内部属性和方法）
		if pname.begins_with("_"):
			continue
		if pusage & PROPERTY_USAGE_EDITOR == 0 and pusage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if ptype == TYPE_NIL and pusage & PROPERTY_USAGE_GROUP:
			continue
		props.append({
			"name": pname,
			"type": type_string(ptype),
			"type_id": ptype,
			"value": str(res.get(pname)) if ptype != TYPE_NIL else "",
		})

	test.ok = props.size() > 10  # StyleBoxFlat 应该有很多属性
	test.detail = "StyleBoxFlat 有 %d 个可编辑属性" % props.size()
	test.data = {
		"class": "StyleBoxFlat",
		"property_count": props.size(),
		"sample_properties": props.slice(0, min(20, props.size())),
	}

	if test.ok:
		print("✅ %s: %s" % [test.name, test.detail])
	else:
		print("❌ %s: %s" % [test.name, test.detail])

	res = null
	return test


# ============ 辅助函数 ============

func _collect_nodes(root: Node, node: Node, out: Array, depth: int) -> void:
	var info: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(root.get_path_to(node)) if node != root else ".",
		"depth": depth,
		"child_count": node.get_child_count(),
		"script": "",
		"signal_count": 0,
		"groups": node.get_groups(),
		"properties": {},
	}

	# 脚本
	var script = node.get_script()
	if script != null:
		var script_res = script as Resource
		if script_res != null:
			info.script = script_res.resource_path

	# 信号连接（编辑器绑定）
	var sig_count := 0
	for sig_info in node.get_signal_list():
		var sig_name: String = str(sig_info.get("name", ""))
		sig_count += node.get_signal_connection_list(sig_name).size()
	info.signal_count = sig_count

	# 关键属性（只收集有意义的，过滤默认值和内部属性）
	if node is Node2D:
		var n2d := node as Node2D
		if n2d.position != Vector2.ZERO:
			info.properties["position"] = [n2d.position.x, n2d.position.y]
		if n2d.rotation != 0:
			info.properties["rotation"] = n2d.rotation
		if n2d.scale != Vector2.ONE:
			info.properties["scale"] = [n2d.scale.x, n2d.scale.y]
		if n2d.z_index != 0:
			info.properties["z_index"] = n2d.z_index
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		info.properties["collision_layer"] = co.collision_layer
		info.properties["collision_mask"] = co.collision_mask
	if node is Control:
		var ctrl := node as Control
		if ctrl.layout_mode != 0:
			info.properties["layout_mode"] = ctrl.layout_mode
		if ctrl.anchors_preset != -1:
			info.properties["anchors_preset"] = ctrl.anchors_preset
	if node is Timer:
		var timer := node as Timer
		info.properties["wait_time"] = timer.wait_time
		info.properties["autostart"] = timer.autostart
	if node is Label:
		var label := node as Label
		if not label.text.is_empty():
			info.properties["text"] = label.text

	out.append(info)

	for child in node.get_children():
		_collect_nodes(root, child, out, depth + 1)


func _write_results(results: Array) -> void:
	var output := {
		"timestamp": Time.get_datetime_string_from_system(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"test_count": results.size(),
		"passed": 0,
		"failed": 0,
		"results": results,
	}

	for r in results:
		if r.get("ok", false):
			output.passed += 1
		else:
			output.failed += 1

	var json := JSON.stringify(output, "  ")
	var f := FileAccess.open("res://tests/results.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
		print("\n📁 结果已写入: res://tests/results.json")
		print("✅ %d 通过 / ❌ %d 失败 / 共 %d 测试" % [output.passed, output.failed, output.test_count])
	else:
		print("⚠️ 无法写入结果文件")

	# 同时写一份人类可读的摘要
	var summary := FileAccess.open("res://tests/results_summary.txt", FileAccess.WRITE)
	if summary:
		summary.store_string("Banyan Tool Test Results\n")
		summary.store_string("========================\n")
		summary.store_string("Time: %s\n" % output.timestamp)
		summary.store_string("Godot: %s\n" % output.godot_version)
		summary.store_string("Pass: %d / Fail: %d / Total: %d\n\n" % [output.passed, output.failed, output.test_count])
		for r in results:
			var icon := "✅" if r.ok else "❌"
			summary.store_string("%s %s\n" % [icon, r.name])
			summary.store_string("   %s\n" % r.detail)
			if not r.get("data", {}).get("errors", []).is_empty():
				for e in r.data.errors:
					summary.store_string("   ⚠️ %s\n" % e)
			summary.store_string("\n")
		summary.close()
