extends SceneTree
## DotAgent Banyan Regression Suite
##
## Unified entry point for all regression tests. Runs in headless mode.
## Usage: godot --headless --path E:\Projects\DotAgent --script res://tests/_regression_suite.gd
##
## Runs critical checks from all test modules and outputs a JSON report.
## Exit code 0 = all passed, 1 = failures detected.

const OUT_PATH := "res://tests/regression_results.json"

var results: Array = []
var pass_count: int = 0
var fail_count: int = 0


func _init():
	print("=" .repeat(60))
	print("  DotAgent Banyan Regression Suite")
	print("  Godot %s" % Engine.get_version_info().get("string", ""))
	print("=" .repeat(60))
	print("")

	# ── Group 1: Core Compilation ──
	print("── Core Compilation ──")
	_run("agent_node.gd compiles", _test_agent_node_compiles)
	_run("plugin.gd compiles", _test_plugin_compiles)
	_run("tool_executor.gd compiles", _test_tool_executor_compiles)
	_run("agent_tree.gd compiles", _test_agent_tree_compiles)

	# ── Group 2: Tool Definitions ──
	print("\n── Tool Definitions ──")
	_run("node_tools.json valid", _test_node_tools_json)
	_run("tool count >= 32", _test_tool_count)

	# ── Group 3: Prompt Files ──
	print("\n── Prompt Files ──")
	_run("node_prompt.md exists", _test_node_prompt_exists)
	_run("project_structure.md exists", _test_project_structure_exists)
	_run("node_prompt has Write tasks rule", _test_write_tasks_rule)
	_run("node_prompt has File Organization", _test_file_organization_rule)

	# ── Group 4: Key Functions Exist ──
	print("\n── Key Functions ──")
	_run("_inject_error_recovery exists", _test_error_recovery_exists)
	_run("_build_incremental_context exists", _test_incremental_context_exists)
	_run("_build_this_run_output exists", _test_this_run_output_exists)
	_run("_score_child_relevance exists", _test_score_child_relevance_exists)
	_run("_check_flat_directory exists", _test_check_flat_directory_exists)
	_run("_truncate_child_report exists", _test_truncate_child_report_exists)

	# ── Group 5: Scene Loading ──
	print("\n── Scene Loading ──")
	_run("dotagent_dock.tscn loads", _test_dock_scene_loads)
	_run("banyan_bottom_panel.tscn loads", _test_bottom_panel_loads)

	# ── Summary ──
	print("\n" + "=" .repeat(60))
	print("  Results: %d passed / %d failed / %d total" % [pass_count, fail_count, results.size()])
	print("=" .repeat(60))

	# Write JSON report
	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"godot_version": Engine.get_version_info().get("string", ""),
		"total": results.size(),
		"passed": pass_count,
		"failed": fail_count,
		"tests": results,
	}
	var f: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		print("\nReport written to: %s" % OUT_PATH)

	quit(0 if fail_count == 0 else 1)


func _run(name: String, test_func: Callable) -> void:
	var result: Dictionary = test_func.call()
	result["name"] = name
	results.append(result)
	if result.get("ok", false):
		pass_count += 1
		print("  [PASS] %s" % name)
	else:
		fail_count += 1
		print("  [FAIL] %s — %s" % [name, result.get("detail", "")])


# ============ Group 1: Core Compilation ============

func _test_agent_node_compiles() -> Dictionary:
	var script = load("res://addons/dotagent/banyan_agent/tree/agent_node.gd") as GDScript
	if script == null:
		return {"ok": false, "detail": "Failed to load script"}
	var node = script.new()
	if node == null:
		return {"ok": false, "detail": "Failed to instantiate"}
	return {"ok": true, "detail": "AgentNode loaded and instantiated"}


func _test_plugin_compiles() -> Dictionary:
	var script = load("res://addons/dotagent/plugin.gd") as GDScript
	if script == null:
		return {"ok": false, "detail": "Failed to load script"}
	return {"ok": true, "detail": "plugin.gd loaded"}


func _test_tool_executor_compiles() -> Dictionary:
	var script = load("res://addons/dotagent/banyan_agent/tools/tool_executor.gd") as GDScript
	if script == null:
		return {"ok": false, "detail": "Failed to load script"}
	var executor = script.new()
	if executor == null:
		return {"ok": false, "detail": "Failed to instantiate"}
	return {"ok": true, "detail": "BanyanToolExecutor loaded and instantiated"}


func _test_agent_tree_compiles() -> Dictionary:
	var script = load("res://addons/dotagent/banyan_agent/tree/agent_tree.gd") as GDScript
	if script == null:
		return {"ok": false, "detail": "Failed to load script"}
	return {"ok": true, "detail": "agent_tree.gd loaded"}


# ============ Group 2: Tool Definitions ============

func _test_node_tools_json() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://addons/dotagent/banyan_agent/tools/definitions/node_tools.json", FileAccess.READ)
	if f == null:
		return {"ok": false, "detail": "File not found"}
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "detail": "Invalid JSON"}
	if parsed is Dictionary and parsed.has("tools"):
		var tools: Array = parsed["tools"]
		return {"ok": true, "detail": "%d tools defined" % tools.size()}
	if parsed is Array:
		return {"ok": true, "detail": "%d tools defined" % parsed.size()}
	return {"ok": false, "detail": "Unexpected structure: %s" % typeof(parsed)}


func _test_tool_count() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://addons/dotagent/banyan_agent/tools/definitions/node_tools.json", FileAccess.READ)
	if f == null:
		return {"ok": false, "detail": "File not found"}
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "detail": "Invalid JSON"}
	var count: int = 0
	if parsed is Dictionary and parsed.has("tools"):
		count = parsed["tools"].size()
	elif parsed is Array:
		count = parsed.size()
	else:
		return {"ok": false, "detail": "Unexpected structure"}
	if count >= 32:
		return {"ok": true, "detail": "%d tools (>= 32)" % count}
	return {"ok": false, "detail": "Only %d tools (expected >= 32)" % count}


# ============ Group 3: Prompt Files ============

func _test_node_prompt_exists() -> Dictionary:
	if FileAccess.file_exists("res://addons/dotagent/banyan_agent/prompts/node_prompt.md"):
		return {"ok": true, "detail": "File exists"}
	return {"ok": false, "detail": "File not found"}


func _test_project_structure_exists() -> Dictionary:
	if FileAccess.file_exists("res://addons/dotagent/banyan_agent/prompts/project_structure.md"):
		return {"ok": true, "detail": "File exists"}
	return {"ok": false, "detail": "File not found"}


func _test_write_tasks_rule() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://addons/dotagent/banyan_agent/prompts/node_prompt.md", FileAccess.READ)
	if f == null:
		return {"ok": false, "detail": "Cannot open file"}
	var text: String = f.get_as_text()
	f.close()
	if "Write tasks MUST produce writes" in text:
		return {"ok": true, "detail": "Rule found"}
	return {"ok": false, "detail": "Write tasks rule not found in node_prompt.md"}


func _test_file_organization_rule() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://addons/dotagent/banyan_agent/prompts/node_prompt.md", FileAccess.READ)
	if f == null:
		return {"ok": false, "detail": "Cannot open file"}
	var text: String = f.get_as_text()
	f.close()
	if "File Organization" in text and "domain-based" in text:
		return {"ok": true, "detail": "File Organization section found"}
	return {"ok": false, "detail": "File Organization section not found"}


# ============ Group 4: Key Functions ============

func _test_error_recovery_exists() -> Dictionary:
	return _check_function_exists("res://addons/dotagent/banyan_agent/tree/agent_node.gd", "_inject_error_recovery")


func _test_incremental_context_exists() -> Dictionary:
	return _check_function_exists("res://addons/dotagent/banyan_agent/tree/agent_node.gd", "_build_incremental_context")


func _test_this_run_output_exists() -> Dictionary:
	return _check_function_exists("res://addons/dotagent/banyan_agent/tree/agent_node.gd", "_build_this_run_output")


func _test_score_child_relevance_exists() -> Dictionary:
	return _check_function_exists("res://addons/dotagent/banyan_agent/tree/agent_node.gd", "_score_child_relevance")


func _test_check_flat_directory_exists() -> Dictionary:
	return _check_function_exists("res://addons/dotagent/banyan_agent/tools/tool_executor.gd", "_check_flat_directory")


func _test_truncate_child_report_exists() -> Dictionary:
	return _check_function_exists("res://addons/dotagent/banyan_agent/tree/agent_node.gd", "_truncate_child_report")


func _check_function_exists(path: String, func_name: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "detail": "Cannot open %s" % path}
	var text: String = f.get_as_text()
	f.close()
	if ("func %s(" % func_name) in text:
		return {"ok": true, "detail": "%s found" % func_name}
	return {"ok": false, "detail": "%s not found in %s" % [func_name, path.get_file()]}


# ============ Group 5: Scene Loading ============

func _test_dock_scene_loads() -> Dictionary:
	return _check_scene_loads("res://addons/dotagent/ui/dotagent_dock.tscn")


func _test_bottom_panel_loads() -> Dictionary:
	return _check_scene_loads("res://addons/dotagent/banyan_agent/ui/banyan_bottom_panel.tscn")


func _check_scene_loads(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"ok": false, "detail": "Scene not found: %s" % path}
	var scene = load(path) as PackedScene
	if scene == null:
		return {"ok": false, "detail": "Failed to load: %s" % path}
	return {"ok": true, "detail": "%s loaded" % path.get_file()}
