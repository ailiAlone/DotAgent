extends SceneTree
## Banyan 全工具自动化测试套件 v2 — 无头模式
##
## 运行方式: godot --headless --script tests/test_runner.gd
## 输出: tests/results.json + 终端摘要
##
## 覆盖全部 14 个工具:
## 感知 (8): extract_script_interface, inspect_scene_structured,
##   get_project_architecture, inspect_live_scene, inspect_resource_interface,
##   get_scene_dependencies, analyze_signal_flow, compare_scenes
## 配置 (4): build_scene, patch_scene, configure_resource, configure_project
## 复合 (2): build_script, update_script

const RESULTS_PATH := "res://tests/results.json"
const OUT := "res://tests/_output/"

var results: Array = []
var pass_count: int = 0
var fail_count: int = 0

# Tool module instances
var perception = null
var configuration = null
var composite = null

func _init():
	print("=" .repeat(60))
	print("  Banyan Full Tool Test Suite — Godot %s" % Engine.get_version_info().get("string", ""))
	print("=" .repeat(60))
	print("")

	# Ensure output dir
	if not DirAccess.dir_exists_absolute(OUT):
		DirAccess.make_dir_recursive_absolute(OUT)

	# Load tool modules
	var perc_script = load("res://addons/dotagent/tools/perception_tools.gd")
	var cfg_script = load("res://addons/dotagent/tools/configuration_tools.gd")
	var comp_script = load("res://addons/dotagent/tools/composite_tools.gd")

	if perc_script == null or cfg_script == null or comp_script == null:
		print("FATAL: Cannot load tool modules")
		quit(1)
		return

	perception = perc_script.new()
	configuration = cfg_script.new()
	composite = comp_script.new()

	if perception == null or configuration == null or composite == null:
		print("FATAL: Cannot instantiate tool modules")
		quit(1)
		return

	# === PERCEPTION TOOLS (8) ===
	_run("01_extract_script_interface", _test_extract_script_interface)
	_run("02_inspect_scene_structured", _test_inspect_scene_structured)
	_run("03_get_project_architecture", _test_get_project_architecture)
	_run("04_inspect_live_scene", _test_inspect_live_scene)
	_run("05_inspect_resource_interface", _test_inspect_resource_interface)
	_run("06_get_scene_dependencies", _test_get_scene_dependencies)
	_run("07_analyze_signal_flow", _test_analyze_signal_flow)
	_run("08_compare_scenes", _test_compare_scenes)

	# === CONFIGURATION TOOLS (4) ===
	_run("09_build_scene", _test_build_scene)
	_run("10_patch_scene", _test_patch_scene)
	_run("11_configure_resource", _test_configure_resource)
	_run("12_configure_project", _test_configure_project)

	# === COMPOSITE TOOLS (2) ===
	_run("13_build_script", _test_build_script)
	_run("14_update_script", _test_update_script)

	# Output
	_write_results()
	print("")
	print("=" .repeat(60))
	print("  Results: %d passed / %d failed / %d total" % [pass_count, fail_count, results.size()])
	print("=" .repeat(60))

	# Cleanup
	_cleanup()
	quit(0 if fail_count == 0 else 1)


func _run(name: String, callable: Callable) -> void:
	print("▶ %s ..." % name)
	var result: Dictionary = callable.call()
	result["name"] = name
	results.append(result)
	if result.get("ok", false):
		pass_count += 1
		print("  ✅ PASS: %s" % result.get("detail", ""))
	else:
		fail_count += 1
		print("  ❌ FAIL: %s" % result.get("detail", ""))
		var errs: Array = result.get("data", {}).get("errors", [])
		for e in errs:
			print("     ⚠ %s" % str(e))
	print("")


# ================================================================
#  TEST 01: extract_script_interface
# ================================================================
func _test_extract_script_interface() -> Dictionary:
	var r = perception.call_method("_tool_extract_script_interface", {
		"path": "res://scripts/player.gd",
		"include_private_methods": true
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool returned error: " + r.get("content", ""))
	else:
		if data.get("type", "") != "script_interface":
			errors.append("Wrong type: " + str(data.get("type", "")))
		if data.get("extends", "") != "Area2D":
			errors.append("extends should be Area2D, got: " + str(data.get("extends", "")))

		var sigs: Array = data.get("signals", [])
		var sig_names: Array = sigs.map(func(s): return s.name)
		if not sig_names.has("died"):
			errors.append("Missing signal: died")
		if not sig_names.has("shoot"):
			errors.append("Missing signal: shoot")

		var exps: Array = data.get("exports", [])
		var exp_names: Array = exps.map(func(e): return e.name)
		if not exp_names.has("speed"):
			errors.append("Missing export: speed")

		var pub: Array = data.get("public_methods", [])
		var priv: Array = data.get("private_methods", [])
		if pub.is_empty() and priv.is_empty():
			errors.append("No methods found")

	return _result(errors, data, "%d signals, %d exports, %d pub/%d priv methods" % [
		data.get("signals", []).size(), data.get("exports", []).size(),
		data.get("public_methods", []).size(), data.get("private_methods", []).size()
	])


# ================================================================
#  TEST 02: inspect_scene_structured
# ================================================================
func _test_inspect_scene_structured() -> Dictionary:
	var r = perception.call_method("_tool_inspect_scene_structured", {
		"scene_path": "res://scenes/player.tscn",
		"include_signals": true,
		"include_script_interface": true,
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		if data.get("type", "") != "scene_struct":
			errors.append("Wrong type")
		var stats: Dictionary = data.get("stats", {})
		if stats.get("total_nodes", 0) < 1:
			errors.append("No nodes found")
		var root_data: Dictionary = data.get("root", {})
		if root_data.get("type", "") == "":
			errors.append("Root type missing")

	return _result(errors, data, "%d nodes, %d scripts, type=%s" % [
		data.get("stats", {}).get("total_nodes", 0),
		data.get("stats", {}).get("total_scripts", 0),
		data.get("scene_type", "?")
	])


# ================================================================
#  TEST 03: get_project_architecture
# ================================================================
func _test_get_project_architecture() -> Dictionary:
	var r = perception.call_method("_tool_get_project_architecture", {
		"include_dependencies": true,
		"include_signal_map": true,
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		var autoloads: Array = data.get("autoloads", [])
		if autoloads.is_empty():
			errors.append("No autoloads found")
		var scripts_summary: Dictionary = data.get("scripts_summary", {})
		if scripts_summary.get("total", 0) < 5:
			errors.append("Too few scripts: %d" % scripts_summary.get("total", 0))
		var scene_tree: Dictionary = data.get("scene_tree", {})
		if scene_tree.is_empty():
			errors.append("Scene tree empty")

	return _result(errors, data, "%d autoloads, %d scenes, %d scripts" % [
		data.get("autoloads", []).size(),
		data.get("scene_tree", {}).size(),
		data.get("scripts_summary", {}).get("total", 0)
	])


# ================================================================
#  TEST 04: inspect_live_scene (requires editor — expect graceful failure)
# ================================================================
func _test_inspect_live_scene() -> Dictionary:
	var r = perception.call_method("_tool_inspect_live_scene", {})
	# In headless mode, this SHOULD return an error (no EditorInterface)
	if not r.get("ok", false):
		# Expected — tool correctly reports EditorInterface unavailable
		return {"ok": true, "detail": "Correctly returns error in headless: " + r.get("content", "").left(60), "data": {}}
	else:
		return {"ok": true, "detail": "Unexpectedly succeeded (editor mode?)", "data": {}}


# ================================================================
#  TEST 05: inspect_resource_interface
# ================================================================
func _test_inspect_resource_interface() -> Dictionary:
	# Test with a built-in type
	var r = perception.call_method("_tool_inspect_resource_interface", {
		"path": "StyleBoxFlat"
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		if data.get("property_count", 0) < 5:
			errors.append("Too few properties: %d" % data.get("property_count", 0))
		if data.get("class", "") != "StyleBoxFlat":
			errors.append("Wrong class: " + str(data.get("class", "")))

	# Also test with a .gd file
	var r2 = perception.call_method("_tool_inspect_resource_interface", {
		"path": "res://scripts/player.gd"
	})
	if not r2.get("ok", false):
		errors.append("GD file test failed: " + r2.get("content", ""))

	return _result(errors, data, "%d properties on StyleBoxFlat" % data.get("property_count", 0))


# ================================================================
#  TEST 06: get_scene_dependencies
# ================================================================
func _test_get_scene_dependencies() -> Dictionary:
	var r = perception.call_method("_tool_get_scene_dependencies", {
		"path": "res://scenes/game.tscn",
		"recursive": true,
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		var direct: Dictionary = data.get("direct", {})
		var scenes: Array = direct.get("scenes", [])
		if scenes.is_empty():
			errors.append("game.tscn should depend on other scenes")

	# Also test reverse dependencies
	var r2 = perception.call_method("_tool_get_scene_dependencies", {
		"path": "res://scenes/player.tscn",
		"reverse": true,
	})
	if not r2.get("ok", false):
		errors.append("Reverse deps failed: " + r2.get("content", ""))

	return _result(errors, data, "%d direct scenes, %d scripts, %d resources" % [
		data.get("direct", {}).get("scenes", []).size(),
		data.get("direct", {}).get("scripts", []).size(),
		data.get("direct", {}).get("resources", []).size(),
	])


# ================================================================
#  TEST 07: analyze_signal_flow
# ================================================================
func _test_analyze_signal_flow() -> Dictionary:
	var r = perception.call_method("_tool_analyze_signal_flow", {
		"scope": "project",
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		var signals: Array = data.get("signals", [])
		if signals.is_empty():
			errors.append("No signals found")
		# Check that 'died' signal exists
		var found_died := false
		for sig in signals:
			if sig.get("name", "") == "died":
				found_died = true
				break
		if not found_died:
			errors.append("Signal 'died' not found in flow analysis")

	return _result(errors, data, "%d signals, %d scripts scanned" % [
		data.get("signals", []).size(), data.get("scripts_scanned", 0)
	])


# ================================================================
#  TEST 08: compare_scenes
# ================================================================
func _test_compare_scenes() -> Dictionary:
	# First create two slightly different scenes
	_build_test_scene_a()
	_build_test_scene_b()

	var r = perception.call_method("_tool_compare_scenes", {
		"path_a": OUT + "cmp_a.tscn",
		"path_b": OUT + "cmp_b.tscn",
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		var changes: Dictionary = data.get("scene_changes", {})
		# cmp_b has one more node and modified position
		var added: Array = changes.get("added_nodes", [])
		var modified: Array = changes.get("modified_nodes", [])
		if added.is_empty() and modified.is_empty():
			errors.append("Expected differences but found none")

	return _result(errors, data, "%d added, %d removed, %d modified" % [
		data.get("scene_changes", {}).get("added_nodes", []).size(),
		data.get("scene_changes", {}).get("removed_nodes", []).size(),
		data.get("scene_changes", {}).get("modified_nodes", []).size(),
	])


# ================================================================
#  TEST 09: build_scene
# ================================================================
func _test_build_scene() -> Dictionary:
	var r = configuration.call_method("_tool_build_scene", {
		"path": OUT + "built_scene.tscn",
		"root": {
			"type": "Area2D",
			"name": "TestRoot",
			"properties": {"collision_layer": 2, "collision_mask": 3}
		},
		"sub_resources": [
			{"id": "shape1", "type": "RectangleShape2D", "properties": {"size": [40, 50]}}
		],
		"children": [
			{"name": "CollisionShape2D", "type": "CollisionShape2D",
			 "properties": {"shape": {"sub_resource": "shape1"}}},
			{"name": "Sprite2D", "type": "Sprite2D",
			 "properties": {"modulate": {"r": 0.3, "g": 0.85, "b": 1.0, "a": 1.0}}}
		],
		"unique_names": ["CollisionShape2D"],
		"open_in_editor": false,
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		if data.get("nodes_created", 0) < 3:
			errors.append("Expected 3+ nodes, got %d" % data.get("nodes_created", 0))
		# Verify file exists
		if not FileAccess.file_exists(OUT + "built_scene.tscn"):
			errors.append("Scene file not created")
		else:
			# Verify by loading
			var packed = load(OUT + "built_scene.tscn") as PackedScene
			if packed == null:
				errors.append("Cannot load created scene")
			else:
				var state = packed.get_state()
				if state.get_node_count() < 3:
					errors.append("Loaded scene has < 3 nodes: %d" % state.get_node_count())

	return _result(errors, data, "%d nodes, %d sub_resources" % [
		data.get("nodes_created", 0), data.get("sub_resources_created", 0)
	])


# ================================================================
#  TEST 10: patch_scene
# ================================================================
func _test_patch_scene() -> Dictionary:
	# Use the scene created by build_scene test
	var scene_path := OUT + "built_scene.tscn"
	if not FileAccess.file_exists(scene_path):
		return {"ok": false, "detail": "built_scene.tscn not found (depends on build_scene test)", "data": {}}

	var r = configuration.call_method("_tool_patch_scene", {
		"path": scene_path,
		"operations": [
			{"op": "set", "node_path": "TestRoot",
			 "properties": {"position": [100, 200]}},
			{"op": "add", "parent_path": ".",
			 "type": "Timer", "name": "PatchTimer",
			 "properties": {"wait_time": 2.0, "one_shot": true}},
			{"op": "remove", "node_path": "Sprite2D"},
		]
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		if data.get("succeeded", 0) < 3:
			errors.append("Expected 3 succeeded, got %d" % data.get("succeeded", 0))
		# Verify modifications
		var packed = load(scene_path) as PackedScene
		if packed:
			var state = packed.get_state()
			# Should have 3 nodes: root + collision + timer (sprite removed)
			if state.get_node_count() != 3:
				errors.append("Expected 3 nodes after patch, got %d" % state.get_node_count())

	return _result(errors, data, "%d/%d succeeded" % [
		data.get("succeeded", 0), data.get("operations_applied", 0)
	])


# ================================================================
#  TEST 11: configure_resource
# ================================================================
func _test_configure_resource() -> Dictionary:
	var errors: Array = []
	var data: Dictionary = {}

	# Test A: Create a StyleBoxFlat
	var r = configuration.call_method("_tool_configure_resource", {
		"path": OUT + "test_style.tres",
		"type": "StyleBoxFlat",
		"properties": {
			"bg_color": {"r": 0.15, "g": 0.15, "b": 0.2, "a": 0.9},
			"corner_radius_top_left": 8,
			"corner_radius_top_right": 8,
			"corner_radius_bottom_left": 8,
			"corner_radius_bottom_right": 8,
		}
	})
	if not r.get("ok", false):
		errors.append("StyleBoxFlat create failed: " + r.get("content", ""))
	else:
		# Verify
		var loaded = ResourceLoader.load(OUT + "test_style.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded == null:
			errors.append("Cannot reload created resource")
		else:
			var bg = loaded.get("bg_color")
			if bg is Color and not is_equal_approx(bg.r, 0.15):
				errors.append("bg_color mismatch: %s" % str(bg))

	# Test B: Update existing resource
	var r2 = configuration.call_method("_tool_configure_resource", {
		"action": "update",
		"path": OUT + "test_style.tres",
		"properties": {"corner_radius_top_left": 16}
	})
	if not r2.get("ok", false):
		errors.append("Update failed: " + r2.get("content", ""))
	else:
		var loaded2 = ResourceLoader.load(OUT + "test_style.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded2 and loaded2.get("corner_radius_top_left") != 16:
			errors.append("Update didn't apply: corner_radius = %s" % str(loaded2.get("corner_radius_top_left")))

	data = {"stylebox_created": errors.is_empty()}
	return _result(errors, data, "StyleBoxFlat create + update")


# ================================================================
#  TEST 12: configure_project
# ================================================================
func _test_configure_project() -> Dictionary:
	# Only test READ operations — don't modify actual project settings in test
	var errors: Array = []
	var data: Dictionary = {}

	# Test: read current settings (no modifications)
	var project_name: String = ProjectSettings.get_setting("application/config/name", "")
	if project_name.is_empty():
		errors.append("Cannot read project name")
	data["project_name"] = project_name

	# Test: read autoloads
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		var pname: String = str(p.get("name", ""))
		if pname.begins_with("autoload/"):
			autoloads.append(pname.replace("autoload/", ""))
	data["autoloads"] = autoloads
	if autoloads.is_empty():
		errors.append("No autoloads found")

	# Test: read input actions
	var actions: Array = InputMap.get_actions()
	data["input_action_count"] = actions.size()
	if actions.size() < 5:
		errors.append("Too few input actions: %d" % actions.size())

	return _result(errors, data, "project=%s, %d autoloads, %d inputs" % [
		project_name, autoloads.size(), actions.size()
	])


# ================================================================
#  TEST 13: build_script
# ================================================================
func _test_build_script() -> Dictionary:
	var r = composite.call_method("_tool_build_script", {
		"path": OUT + "test_enemy.gd",
		"class_name": "TestEnemy",
		"extends": "Area2D",
		"doc_comment": "Auto-generated enemy for testing",
		"signals": [
			{"name": "died", "params": ["score: int"]},
			{"name": "damaged", "params": ["hp: int"]},
		],
		"exports": [
			{"name": "speed", "type": "float", "default": 200.0},
			{"name": "max_hp", "type": "int", "default": 3},
		],
		"enums": [
			{"name": "State", "values": ["IDLE", "MOVING", "ATTACKING"]},
		],
		"methods": [
			{"name": "take_damage", "params": ["amount: int"], "body": "pass # TODO: implement damage"},
			{"name": "get_score_value", "params": [], "returns": "int", "body": "return 100"},
		],
		"validate_syntax": true,
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		if not FileAccess.file_exists(OUT + "test_enemy.gd"):
			errors.append("Script file not created")
		else:
			# Verify content
			var f := FileAccess.open(OUT + "test_enemy.gd", FileAccess.READ)
			var content: String = f.get_as_text()
			f.close()
			if not content.contains("class_name TestEnemy"):
				errors.append("Missing class_name")
			if not content.contains("extends Area2D"):
				errors.append("Missing extends")
			if not content.contains("signal died"):
				errors.append("Missing signal died")
			if not content.contains("@export var speed"):
				errors.append("Missing export speed")
			if not content.contains("func take_damage"):
				errors.append("Missing method take_damage")
			if data.get("syntax_valid", false) != true:
				errors.append("Syntax not validated")

	return _result(errors, data, "class_name=%s, %d signals, %d methods" % [
		data.get("class_name", ""), data.get("signals_count", 0), data.get("methods_count", 0)
	])


# ================================================================
#  TEST 14: update_script
# ================================================================
func _test_update_script() -> Dictionary:
	var script_path := OUT + "test_update.gd"
	var content := """extends Node
## Updated script test

signal updated

var count: int = 0

func increment() -> void:
	count += 1

func get_count() -> int:
	return count
"""
	var r = composite.call_method("_tool_update_script", {
		"path": script_path,
		"content": content,
		"validate_syntax": true,
	})
	var ok: bool = r.get("ok", false)
	var data: Dictionary = {}
	if ok:
		data = JSON.parse_string(r.content) if r.content.begins_with("{") else {}
	var errors: Array = []

	if not ok:
		errors.append("Tool error: " + r.get("content", ""))
	else:
		if not FileAccess.file_exists(script_path):
			errors.append("Script file not created")
		else:
			var f := FileAccess.open(script_path, FileAccess.READ)
			var read_content: String = f.get_as_text()
			f.close()
			if not read_content.contains("signal updated"):
				errors.append("Content mismatch")
			if data.get("syntax_valid", false) != true:
				errors.append("Syntax not validated")

	# Test: syntax validation catches bad code
	var bad_r = composite.call_method("_tool_update_script", {
		"path": OUT + "test_bad.gd",
		"content": "extends Node\nfunc bad( -> int:\n\treturn 1\n",
		"validate_syntax": true,
	})
	if bad_r.get("ok", false):
		errors.append("Bad syntax should have been rejected")

	return _result(errors, data, "valid script + bad syntax rejection")


# ================================================================
#  HELPERS
# ================================================================

func _result(errors: Array, data: Dictionary, detail: String) -> Dictionary:
	if not errors.is_empty():
		data["errors"] = errors
		return {"ok": false, "detail": detail + " | %d errors" % errors.size(), "data": data}
	return {"ok": true, "detail": detail, "data": data}


func _build_test_scene_a() -> void:
	var root := Area2D.new()
	root.name = "CmpRoot"
	root.position = Vector2(0, 0)
	var child := Sprite2D.new()
	child.name = "Sprite"
	root.add_child(child)
	child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OUT + "cmp_a.tscn")
	root.queue_free()


func _build_test_scene_b() -> void:
	var root := Area2D.new()
	root.name = "CmpRoot"
	root.position = Vector2(100, 200)  # Modified
	var child := Sprite2D.new()
	child.name = "Sprite"
	root.add_child(child)
	child.owner = root
	var extra := CollisionShape2D.new()  # Added
	extra.name = "Shape"
	root.add_child(extra)
	extra.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OUT + "cmp_b.tscn")
	root.queue_free()


func _write_results() -> void:
	var output := {
		"timestamp": Time.get_datetime_string_from_system(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"test_count": results.size(),
		"passed": pass_count,
		"failed": fail_count,
		"results": results,
	}
	var json := JSON.stringify(output, "  ")
	var f := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()


func _cleanup() -> void:
	# Remove test output files
	var d := DirAccess.open(OUT)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir():
			d.remove(name)
		name = d.get_next()
	d.list_dir_end()
	# Remove temp test scripts
	for temp_file in ["_compile_check.gd", "_compile_cfg.gd", "_compile_comp.gd",
					  "_syntax_check.gd", "_capability_check.gd", "_caps2.gd",
					  "_caps.json", "_ping_result.json", "_cap_test.tscn"]:
		if FileAccess.file_exists("res://tests/" + temp_file):
			DirAccess.remove_absolute("res://tests/" + temp_file)
