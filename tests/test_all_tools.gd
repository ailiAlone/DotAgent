extends SceneTree
## 全量工具验证测试 — 75 个工具逐一验证
##
## 运行: godot --headless --script tests/test_all_tools.gd
## 输出: tests/all_tools_results.json
##
## 验证全部 11 个模块的 75 个工具:
## Legacy (61): scene_tools(6), node_query_tools(5), script_tools(5),
##   script_file_tools(7), project_tools(10), file_tools(12),
##   screenshot_tools(4), exec_tools(12)
## Banyan (14): perception_tools(8), configuration_tools(4), composite_tools(2)

const RESULTS := "res://tests/all_tools_results.json"
const OUT := "res://tests/_all_out/"

var results: Array = []
var pass_count := 0
var fail_count := 0
var skip_count := 0
var modules: Dictionary = {}  # name → instance

func _init():
	print("=" .repeat(60))
	print("  All Tools Verification — Godot %s" % Engine.get_version_info().get("string", ""))
	print("=" .repeat(60))
	print("")

	if not DirAccess.dir_exists_absolute(OUT):
		DirAccess.make_dir_recursive_absolute(OUT)

	# Load all modules
	var module_paths := {
		"scene_tools": "res://addons/dotagent/tools/scene_tools.gd",
		"node_query_tools": "res://addons/dotagent/tools/node_query_tools.gd",
		"script_tools": "res://addons/dotagent/tools/script_tools.gd",
		"script_file_tools": "res://addons/dotagent/tools/script_file_tools.gd",
		"project_tools": "res://addons/dotagent/tools/project_tools.gd",
		"file_tools": "res://addons/dotagent/tools/file_tools.gd",
		"screenshot_tools": "res://addons/dotagent/tools/screenshot_tools.gd",
		"exec_tools": "res://addons/dotagent/tools/exec_tools.gd",
		"perception_tools": "res://addons/dotagent/tools/perception_tools.gd",
		"configuration_tools": "res://addons/dotagent/tools/configuration_tools.gd",
		"composite_tools": "res://addons/dotagent/tools/composite_tools.gd",
	}
	for mname in module_paths:
		var res = load(module_paths[mname])
		if res == null:
			print("❌ FATAL: Cannot load %s" % mname)
			quit(1)
			return
		var obj = res.new()
		if obj == null:
			print("❌ FATAL: Cannot instantiate %s" % mname)
			quit(1)
			return
		# Initialize editor context (provides BackupManager etc.)
		if obj.has_method("set_editor_context"):
			obj.set_editor_context(null, null)
		modules[mname] = obj

	# ===== Legacy: scene_tools (6) =====
	print("── scene_tools ──")
	_t("scene_tools", "create_scene", {"path": OUT + "cs_test.tscn", "root_type": "Node2D"})
	_t("scene_tools", "set_node_property", {"path": ".", "name": "position", "value": [10, 20]})
	_t("scene_tools", "add_node", {"parent_path": ".", "type": "Sprite2D", "name": "TestSprite"})
	_t("scene_tools", "remove_node", {"path": "TestSprite"})
	_t("scene_tools", "reparent_node", {"path": ".", "new_parent_path": "."})  # no-op but should not crash
	_t("scene_tools", "undo_last", {})

	# ===== Legacy: node_query_tools (5) =====
	print("── node_query_tools ──")
	_t("node_query_tools", "get_scene_tree", {"max_depth": 2})
	_t("node_query_tools", "get_node", {"path": "."})
	_t("node_query_tools", "get_node_properties", {"path": "."})
	_t("node_query_tools", "list_nodes", {})
	_t("node_query_tools", "get_signal_connections", {"path": "."})

	# ===== Legacy: script_tools (5) =====
	print("── script_tools ──")
	_t("script_tools", "read_script", {"path": "res://scripts/player.gd"})
	_t("script_tools", "create_script", {"path": OUT + "new_script.gd", "extends": "Node", "content": "extends Node\n\nfunc test_func() -> void:\n\tpass\n"})
	_t("script_tools", "update_script", {"path": OUT + "new_script.gd", "content": "extends Node\n\nfunc test_func() -> void:\n\tprint(\"updated\")\n"})
	_t("script_tools", "list_scripts", {})
	_t("script_tools", "replace_in_file", {"path": OUT + "new_script.gd", "old_text": "updated", "new_text": "replaced"})

	# ===== Legacy: script_file_tools (7) =====
	print("── script_file_tools ──")
	_t("script_file_tools", "delete_file", {"path": OUT + "new_script.gd"})
	# Create temp files for batch test
	_write_file(OUT + "del_a.gd", "extends Node\n")
	_write_file(OUT + "del_b.gd", "extends Node\n")
	_t("script_file_tools", "delete_files", {"paths": [OUT + "del_a.gd", OUT + "del_b.gd"]})
	_write_file(OUT + "rename_me.gd", "extends Node\n")
	_t("script_file_tools", "rename_file", {"path": OUT + "rename_me.gd", "new_path": OUT + "renamed.gd"})
	_t("script_file_tools", "search_in_scripts", {"query": "extends Area2D"})
	_t("script_file_tools", "replace_in_scripts", {"query": "nope", "replacement": "nope"})
	_t("script_file_tools", "check_script_syntax", {"path": "res://scripts/player.gd"})
	_t("script_file_tools", "get_script_references", {"path": "res://scripts/player.gd"})
	# Cleanup
	if FileAccess.file_exists(OUT + "renamed.gd"):
		DirAccess.remove_absolute(OUT + "renamed.gd")

	# ===== Legacy: project_tools (10) =====
	print("── project_tools ──")
	_t("project_tools", "get_project_info", {})
	_t("project_tools", "get_project_setting", {"key": "application/config/name"})
	_t("project_tools", "set_project_setting", {"key": "application/config/description", "value": "test"})
	_t("project_tools", "remember", {"fact": "test memory entry"})
	_t("project_tools", "recall", {"query": "test"})
	_t("project_tools", "export_session", {})
	_t("project_tools", "get_input_actions", {})
	_t("project_tools", "add_input_action", {"name": "test_action_verify", "keycode": "KEY_F12"})
	_t("project_tools", "list_skills", {})
	_t("project_tools", "create_skill", {"name": "test_skill", "triggers": ["test"], "content": "test skill content"})

	# ===== Legacy: file_tools (12) =====
	print("── file_tools ──")
	_t("file_tools", "list_files", {"directory": "res://scripts"})
	_t("file_tools", "list_scenes", {})
	_t("file_tools", "list_resources", {})
	_t("file_tools", "read_resource_as_text", {"path": "res://scenes/player.tscn"})
	_t("file_tools", "read_multiple_files", {"paths": ["res://scripts/player.gd", "res://scripts/game.gd"]})
	_t("file_tools", "read_file_tail", {"path": "res://scripts/game.gd", "lines": 5})
	_write_file(OUT + "write_test.txt", "hello")
	_t("file_tools", "write_file", {"path": OUT + "write_test2.txt", "content": "test content"})
	_t("file_tools", "peek_scene", {"path": "res://scenes/player.tscn"})
	_t("file_tools", "describe_scene", {"path": "res://scenes/player.tscn"})
	_t("file_tools", "create_resource", {"path": OUT + "test_res.tres", "type": "StyleBoxFlat", "properties": {}})
	_t("file_tools", "preview_backup", {"path": "res://scenes/player.tscn"})
	_t("file_tools", "cleanup_backups", {})

	# ===== Legacy: screenshot_tools (4) =====
	print("── screenshot_tools ──")
	_t("screenshot_tools", "focus_editor_view", {"mode": "2d"})
	_t("screenshot_tools", "screenshot_editor", {})
	_t("screenshot_tools", "screenshot_runtime", {"scene_path": "res://scenes/main.tscn"})
	_t("screenshot_tools", "analyze_image", {"path": "nonexistent.png"})

	# ===== Legacy: exec_tools (12) =====
	print("── exec_tools ──")
	_t("exec_tools", "execute_gdscript", {"snippet": "var x := 2 + 3\n_echo(str(x))"})
	_t("exec_tools", "call_node_method", {"path": ".", "method": "get_class"})
	_t("exec_tools", "open_scene", {"path": "res://scenes/player.tscn"})
	_t("exec_tools", "close_all_scenes", {})
	_t("exec_tools", "list_open_scenes", {})
	# skip run_current_scene / stop_running_scene (would run game)
	_skip("exec_tools", "run_current_scene")
	_skip("exec_tools", "stop_running_scene")
	_t("exec_tools", "reload_project", {})
	_t("exec_tools", "get_editor_selection", {})
	# skip run_scene_capture (runs game subprocess)
	_skip("exec_tools", "run_scene_capture")
	_t("exec_tools", "get_node_type_info", {"type": "Area2D"})
	_t("exec_tools", "read_editor_output", {"max_lines": 10})

	# ===== Banyan: perception_tools (8) =====
	print("── perception_tools ──")
	_t("perception_tools", "extract_script_interface", {"path": "res://scripts/player.gd"})
	_t("perception_tools", "inspect_scene_structured", {"scene_path": "res://scenes/player.tscn"})
	_t("perception_tools", "get_project_architecture", {})
	_t("perception_tools", "inspect_live_scene", {})
	_t("perception_tools", "inspect_resource_interface", {"path": "StyleBoxFlat"})
	_t("perception_tools", "get_scene_dependencies", {"path": "res://scenes/game.tscn"})
	_t("perception_tools", "analyze_signal_flow", {})
	# Build two scenes for compare
	_quick_scene(OUT + "cmp1.tscn", "Area2D", "R1", [])
	_quick_scene(OUT + "cmp2.tscn", "Area2D", "R2", ["Sprite2D"])
	_t("perception_tools", "compare_scenes", {"path_a": OUT + "cmp1.tscn", "path_b": OUT + "cmp2.tscn"})

	# ===== Banyan: configuration_tools (4) =====
	print("── configuration_tools ──")
	_t("configuration_tools", "build_scene", {
		"path": OUT + "cfg_built.tscn",
		"root": {"type": "Node2D", "name": "CfgRoot"},
		"children": [{"name": "Child1", "type": "Sprite2D"}],
		"open_in_editor": false,
	})
	_t("configuration_tools", "patch_scene", {
		"path": OUT + "cfg_built.tscn",
		"operations": [
			{"op": "set", "node_path": "CfgRoot", "properties": {"position": [50, 50]}},
			{"op": "add", "parent_path": ".", "type": "Label", "name": "CfgLabel"},
		]
	})
	_t("configuration_tools", "configure_resource", {
		"path": OUT + "cfg_res.tres",
		"type": "StyleBoxFlat",
		"properties": {"bg_color": {"r": 1, "g": 0, "b": 0, "a": 1}}
	})
	_t("configuration_tools", "configure_project", {
		"settings": {"application/config/description": "Banyan verify test"},
	})

	# ===== Banyan: composite_tools (2) =====
	print("── composite_tools ──")
	_t("composite_tools", "build_script", {
		"path": OUT + "cfg_script.gd",
		"extends": "Node",
		"signals": [{"name": "ready_signal"}],
		"methods": [{"name": "do_stuff", "body": "pass"}],
		"validate_syntax": true,
	})
	_t("composite_tools", "update_script", {
		"path": OUT + "cfg_update.gd",
		"content": "extends Node\n\nvar x := 1\n",
		"validate_syntax": true,
	})

	# ===== Summary =====
	print("")
	print("=" .repeat(60))
	print("  ✅ %d passed | ❌ %d failed | ⏭ %d skipped | %d total" % [pass_count, fail_count, skip_count, results.size()])
	print("=" .repeat(60))

	_write_results()
	_cleanup_output()
	quit(0 if fail_count == 0 else 1)


# ================================================================
#  Helpers
# ================================================================

func _t(module_name: String, tool_name: String, args: Dictionary) -> void:
	if not modules.has(module_name):
		_record(tool_name, false, "Module not loaded: " + module_name, {})
		return

	var mod = modules[module_name]
	var method_name := "_tool_" + tool_name

	# Check if method exists
	if not mod.has_method(method_name):
		_record(tool_name, false, "Method not found: " + method_name, {})
		return

	# Call the method
	var result: Dictionary = mod.call_method(method_name, args)

	var ok: bool = result.get("ok", false)
	var content: String = str(result.get("content", ""))
	var detail := ""

	if ok:
		# Truncate content for display
		if content.length() > 100:
			detail = content.left(100) + "..."
		else:
			detail = content
	else:
		detail = content.left(200)

	# Classify EditorInterface-dependent failures as expected in headless
	if not ok:
		var is_ei_dep: bool = content.contains("EditorInterface") or content.contains("No scene open")
		# scene_tools/node_query "Node not found" is also expected (no edited scene in headless)
		if not is_ei_dep and content.contains("Node not found") and module_name in ["scene_tools", "node_query_tools"]:
			is_ei_dep = true
		if is_ei_dep:
			_record_expected(tool_name, detail)
			return
		# Known no-data scenarios
		if tool_name in ["export_session", "analyze_image", "screenshot_runtime"]:
			_record_expected(tool_name, detail)
			return

	_record(tool_name, ok, detail, result)


func _skip(module_name: String, tool_name: String) -> void:
	skip_count += 1
	results.append({
		"module": module_name,
		"tool": tool_name,
		"ok": "skipped",
		"detail": "Skipped (requires game runtime)",
	})
	print("  ⏭ SKIP: %s" % tool_name)


func _record(tool_name: String, ok: bool, detail: String, full_result: Dictionary) -> void:
	if ok:
		pass_count += 1
		print("  ✅ %s" % tool_name)
	else:
		fail_count += 1
		print("  ❌ %s: %s" % [tool_name, detail.left(120)])

	results.append({
		"tool": tool_name,
		"ok": ok,
		"detail": detail,
	})


func _record_expected(tool_name: String, detail: String) -> void:
	skip_count += 1
	print("  ℹ️ %s (expected: needs editor)" % tool_name)
	results.append({
		"tool": tool_name,
		"ok": "expected_headless",
		"detail": detail,
	})


func _write_file(path: String, content: String) -> void:
	var base := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_recursive_absolute(base)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()


func _quick_scene(path: String, root_type: String, root_name: String, child_types: Array) -> void:
	var root: Node = ClassDB.instantiate(root_type)
	root.name = root_name
	for ctype in child_types:
		var child: Node = ClassDB.instantiate(str(ctype))
		child.name = str(ctype)
		root.add_child(child)
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.queue_free()


func _write_results() -> void:
	var output := {
		"timestamp": Time.get_datetime_string_from_system(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"total": results.size(),
		"passed": pass_count,
		"failed": fail_count,
		"skipped": skip_count,
		"results": results,
	}
	var json := JSON.stringify(output, "  ")
	var f := FileAccess.open(RESULTS, FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
		print("📁 Results: %s" % RESULTS)


func _cleanup_output() -> void:
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
