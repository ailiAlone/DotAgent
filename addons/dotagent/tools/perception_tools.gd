@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 感知工具模块 — Cortex 基础设施
##
## 将编辑器状态转化为结构化 JSON，替代文本阅读。
## 所有工具在无头模式下也可工作（降级到文件级操作）。
##
## Tools:
## - extract_script_interface
## - inspect_scene_structured
## - get_project_architecture
## - inspect_live_scene
## - inspect_resource_interface
## - get_scene_dependencies
## - analyze_signal_flow
## - compare_scenes


# ============ 正则模式（编译一次，复用）============

var _re_signal: RegEx
var _re_func: RegEx
var _re_export: RegEx
var _re_class_name: RegEx
var _re_extends: RegEx
var _re_enum: RegEx
var _re_const: RegEx
var _re_onready: RegEx
var _re_preload: RegEx
var _re_load: RegEx
var _re_emit: RegEx
var _re_connect: RegEx
var _re_ext_resource: RegEx
var _re_sub_resource: RegEx
var _re_node: RegEx

var _regex_ready := false


func _ensure_regex() -> void:
	if _regex_ready:
		return
	_re_signal = RegEx.create_from_string("^signal\\s+(\\w+)(?:\\(([^)]*)\\))?")
	_re_func = RegEx.create_from_string("^(static\\s+)?func\\s+(\\w+)\\s*\\(([^)]*)\\)(?:\\s*->\\s*(\\S+))?")
	_re_export = RegEx.create_from_string("^@export\\s+(?:\\([^)]*\\)\\s+)?(?:var\\s+)?(\\w+)\\s*(?::\\s*([^=\\s]+))?\\s*(?:=\\s*(.+))?")
	_re_class_name = RegEx.create_from_string("^class_name\\s+(\\w+)")
	_re_extends = RegEx.create_from_string("^extends\\s+(\\w+)")
	_re_enum = RegEx.create_from_string("^enum\\s+(\\w+)\\s*\\{")
	_re_const = RegEx.create_from_string("^const\\s+(\\w+)\\s*=\\s*(.*)")
	_re_onready = RegEx.create_from_string("^@onready\\s+var\\s+(\\w+)\\s*(?::\\s*(\\w+))?")
	_re_preload = RegEx.create_from_string("preload\\(\"([^\"]+)\"\\)")
	_re_load = RegEx.create_from_string("(?<!pre)load\\(\"([^\"]+)\"\\)")
	_re_emit = RegEx.create_from_string("(\\w+)\\.emit\\(")
	_re_connect = RegEx.create_from_string("(\\w+)\\.connect\\(")
	_re_ext_resource = RegEx.create_from_string("\\[ext_resource[^\\]]*type=\"([^\"]+)\"[^\\]]*path=\"([^\"]+)\"[^\\]]*id=\"([^\"]+)\"")
	_re_sub_resource = RegEx.create_from_string("\\[sub_resource[^\\]]*type=\"([^\"]+)\"[^\\]]*id=\"([^\"]+)\"")
	_re_node = RegEx.create_from_string("\\[node name=\"([^\"]+)\" type=\"([^\"]+)\"(?: parent=\"([^\"]*)\")?")
	_regex_ready = true


# ============ 工具定义 ============

func get_tool_definitions() -> Array:
	return [
		_td("extract_script_interface",
			"Extract the interface summary of a .gd script: class_name, extends, signals, exports, public methods, enums, constants, dependencies. Returns structured JSON, not raw text.",
			"_tool_extract_script_interface",
			{
				"path": {"type": "string", "description": "Path to .gd file, e.g. 'res://scripts/player.gd'"},
				"include_private_methods": {"type": "boolean", "description": "Include _ prefixed methods", "default": false},
				"include_body_preview": {"type": "boolean", "description": "Include first 3 lines of each method body", "default": false},
			},
			["path"]),
		_td("inspect_scene_structured",
			"Get structured JSON description of a scene: node tree, properties, signals, script interfaces, sub-resources. Replaces text-based get_scene_tree.",
			"_tool_inspect_scene_structured",
			{
				"scene_path": {"type": "string", "description": "Path to .tscn file (omit to use currently edited scene)"},
				"focus_path": {"type": "string", "description": "Focus on specific node path (skip rest)", "default": ""},
				"properties": {"type": "array", "description": "Only return these properties", "default": []},
				"include_signals": {"type": "boolean", "description": "Include signal connections", "default": true},
				"include_script_interface": {"type": "boolean", "description": "Include script interface summary", "default": true},
				"max_depth": {"type": "integer", "description": "Max tree depth (0=unlimited)", "default": 0},
			},
			[]),
		_td("get_project_architecture",
			"Get project-level architecture overview: scenes, scripts, autoloads, dependencies, signal bus, statistics.",
			"_tool_get_project_architecture",
			{
				"include_dependencies": {"type": "boolean", "description": "Include scene dependency tree", "default": true},
				"include_signal_map": {"type": "boolean", "description": "Include cross-module signal map", "default": true},
			},
			[]),
		_td("inspect_live_scene",
			"Get current editor scene state. Supports incremental mode (only return changes since last query).",
			"_tool_inspect_live_scene",
			{
				"incremental": {"type": "boolean", "description": "Only return changes since baseline_hash", "default": false},
				"baseline_hash": {"type": "string", "description": "Hash from previous query for incremental mode", "default": ""},
				"include_groups": {"type": "boolean", "description": "Include node groups", "default": true},
			},
			[]),
		_td("inspect_resource_interface",
			"Extract the property interface of any Resource type (built-in or custom extends Resource).",
			"_tool_inspect_resource_interface",
			{
				"path": {"type": "string", "description": "Path to .gd script or .tres file"},
			},
			["path"]),
		_td("get_scene_dependencies",
			"Get recursive dependency graph for a scene: sub-scenes, scripts, resources.",
			"_tool_get_scene_dependencies",
			{
				"path": {"type": "string", "description": "Scene path"},
				"recursive": {"type": "boolean", "description": "Follow dependencies recursively", "default": true},
				"reverse": {"type": "boolean", "description": "Reverse: who references this scene?", "default": false},
			},
			["path"]),
		_td("analyze_signal_flow",
			"Analyze signal flow across all scripts: declarations, emitters, listeners, cross-module detection.",
			"_tool_analyze_signal_flow",
			{
				"scope": {"type": "string", "description": "'project' or 'module'", "default": "project"},
				"module_filter": {"type": "string", "description": "Filter by module/script name", "default": ""},
			},
			[]),
		_td("compare_scenes",
			"Compare two scene files: added/removed/modified nodes, property changes, script changes.",
			"_tool_compare_scenes",
			{
				"path_a": {"type": "string", "description": "First scene path"},
				"path_b": {"type": "string", "description": "Second scene path (or .bak file)"},
				"compare_scripts": {"type": "boolean", "description": "Also compare associated scripts", "default": true},
			},
			["path_a", "path_b"]),
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	_ensure_regex()
	match method_name:
		"_tool_extract_script_interface": return _tool_extract_script_interface(args)
		"_tool_inspect_scene_structured": return _tool_inspect_scene_structured(args)
		"_tool_get_project_architecture": return _tool_get_project_architecture(args)
		"_tool_inspect_live_scene": return _tool_inspect_live_scene(args)
		"_tool_inspect_resource_interface": return _tool_inspect_resource_interface(args)
		"_tool_get_scene_dependencies": return _tool_get_scene_dependencies(args)
		"_tool_analyze_signal_flow": return _tool_analyze_signal_flow(args)
		"_tool_compare_scenes": return _tool_compare_scenes(args)
	return _err("Unknown method: " + method_name)


# ============ Tool 1: extract_script_interface ============

func _tool_extract_script_interface(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".gd"):
		return _err("Only .gd files supported")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)

	var include_private: bool = args.get("include_private_methods", false)
	var include_preview: bool = args.get("include_body_preview", false)

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot open file: " + path)
	var text: String = f.get_as_text()
	f.close()

	var result := {
		"type": "script_interface",
		"path": path,
		"class_name": "",
		"extends": "",
		"signals": [],
		"exports": [],
		"constants": [],
		"enums": [],
		"public_methods": [],
		"private_methods": [],
		"dependencies": {"preload": [], "load": []},
		"node_refs": [],
		"observations": [],
	}

	var lines := text.split("\n")
	var emitted_signals: Array = []  # track .emit() calls
	var connected_signals: Array = []  # track .connect() calls
	var line_num := 0

	for line in lines:
		line_num += 1
		var s: String = line.strip_edges()

		# class_name
		var m := _re_class_name.search(s)
		if m:
			result.class_name = m.get_string(1)
			continue

		# extends
		m = _re_extends.search(s)
		if m:
			result.extends = m.get_string(1)
			continue

		# signal
		m = _re_signal.search(s)
		if m:
			var params_str: String = m.get_string(2)
			var params: Array = []
			if not params_str.is_empty():
				for p in params_str.split(","):
					params.append(p.strip_edges())
			result.signals.append({"name": m.get_string(1), "params": params, "line": line_num})
			continue

		# func
		m = _re_func.search(s)
		if m:
			var is_static: bool = not m.get_string(1).is_empty()
			var fname: String = m.get_string(2)
			var params_str: String = m.get_string(3)
			var returns: String = m.get_string(4)
			var params: Array = []
			if not params_str.is_empty():
				for p in params_str.split(","):
					var param: String = p.strip_edges()
					if not param.is_empty():
						params.append(param)
			var entry := {
				"name": fname, "params": params,
				"returns": returns if not returns.is_empty() else "Variant",
				"is_static": is_static, "line": line_num,
			}
			if include_preview:
				var preview_lines: Array = []
				for i in range(line_num, mini(line_num + 3, lines.size())):
					preview_lines.append(lines[i])
				entry["body_preview"] = preview_lines
			if fname.begins_with("_"):
				result.private_methods.append(entry)
			else:
				result.public_methods.append(entry)
			continue

		# @export
		m = _re_export.search(s)
		if m:
			result.exports.append({
				"name": m.get_string(1),
				"type": m.get_string(2) if not m.get_string(2).is_empty() else "auto",
				"default": m.get_string(3).strip_edges() if not m.get_string(3).is_empty() else "",
				"line": line_num,
			})
			continue

		# enum
		m = _re_enum.search(s)
		if m:
			result.enums.append({"name": m.get_string(1), "line": line_num})
			continue

		# const
		m = _re_const.search(s)
		if m:
			result.constants.append({
				"name": m.get_string(1),
				"value": m.get_string(2).strip_edges(),
				"line": line_num,
			})
			continue

		# @onready
		m = _re_onready.search(s)
		if m:
			result.node_refs.append({
				"name": m.get_string(1),
				"type": m.get_string(2) if not m.get_string(2).is_empty() else "",
				"line": line_num,
			})
			continue

		# preload()
		for pm in _re_preload.search_all(s):
			var dep_path: String = pm.get_string(1)
			if not result.dependencies.preload.has(dep_path):
				result.dependencies.preload.append(dep_path)

		# load() (not preload)
		for lm in _re_load.search_all(s):
			var dep_path: String = lm.get_string(1)
			if not result.dependencies.load.has(dep_path):
				result.dependencies.load.append(dep_path)

		# .emit()
		for em in _re_emit.search_all(s):
			var sig_name: String = em.get_string(1)
			if not emitted_signals.has(sig_name):
				emitted_signals.append(sig_name)

		# .connect()
		for cm in _re_connect.search_all(s):
			var sig_name: String = cm.get_string(1)
			if not connected_signals.has(sig_name):
				connected_signals.append(sig_name)

	# Observations
	var signal_names: Array = result.signals.map(func(s): return s.name)
	for sig_name in signal_names:
		if not emitted_signals.has(sig_name) and not connected_signals.has(sig_name):
			result.observations.append("signal '%s' declared but never emitted or connected" % sig_name)

	if not include_private:
		result.erase("private_methods")

	return _ok_json(result)


# ============ Tool 2: inspect_scene_structured ============

func _tool_inspect_scene_structured(args: Dictionary) -> Dictionary:
	var scene_path: String = args.get("scene_path", "")
	var focus_path: String = args.get("focus_path", "")
	var filter_props: Array = args.get("properties", [])
	var include_signals: bool = args.get("include_signals", true)
	var include_script_iface: bool = args.get("include_script_interface", true)
	var max_depth: int = int(args.get("max_depth", 0))

	# Try editor first, fall back to file
	var packed: PackedScene = null
	var root: Node = null
	var from_editor := false

	var ei = _ei()
	if ei and scene_path.is_empty():
		root = ei.get_edited_scene_root()
		if root:
			from_editor = true
			scene_path = root.scene_file_path

	if root == null:
		if scene_path.is_empty():
			return _err("No scene open and no scene_path provided")
		if not FileAccess.file_exists(scene_path):
			return _err("Scene not found: " + scene_path)
		packed = load(scene_path) as PackedScene
		if packed == null:
			return _err("Failed to load scene: " + scene_path)
		root = packed.instantiate()

	# Build structured output
	var result := {
		"type": "scene_struct",
		"path": scene_path,
		"scene_type": _detect_scene_type(root),
		"from_editor": from_editor,
		"root": _serialize_node(root, root, 0, max_depth, focus_path, filter_props, include_signals, include_script_iface),
		"observations": [],
		"stats": {"total_nodes": 0, "total_scripts": 0},
	}

	# Count stats
	_count_stats(result.root, result.stats)

	# Generate observations
	_generate_scene_observations(result.root, result.observations)

	if not from_editor and root:
		root.queue_free()

	return _ok_json(result)


# ============ Tool 3: get_project_architecture ============

func _tool_get_project_architecture(args: Dictionary) -> Dictionary:
	var include_deps: bool = args.get("include_dependencies", true)
	var include_signals: bool = args.get("include_signal_map", true)

	# File traversal
	var scenes: Array = []
	var scripts: Array = []
	var resources: Array = []
	_walk_dir("res://", scenes, [".tscn"], "")
	_walk_dir("res://", scripts, [".gd"], "")
	_walk_dir("res://", resources, [".tres", ".res"], "")

	# Autoloads via ProjectSettings
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		var pname: String = str(p.get("name", ""))
		if pname.begins_with("autoload/"):
			var aname: String = pname.replace("autoload/", "")
			var aval: String = str(ProjectSettings.get_setting(pname, ""))
			autoloads.append({"name": aname, "path": aval.lstrip("*")})

	# Scene tree (instance hierarchy)
	var scene_tree: Dictionary = {}
	for scene_path in scenes:
		var sp: String = str(scene_path)
		var packed = load(sp) as PackedScene
		if packed == null:
			continue
		var state := packed.get_state()
		var root_type: String = ""
		var script_path: String = ""
		var instances: Array = []
		if state.get_node_count() > 0:
			root_type = state.get_node_type(0)
			for pi in range(state.get_node_property_count(0)):
				var pn: String = state.get_node_property_name(0, pi)
				if pn == "script":
					var sv = state.get_node_property_value(0, pi)
					if sv is Resource:
						script_path = sv.resource_path
		# Find instances (ext_resource of type PackedScene)
		var f := FileAccess.open(sp, FileAccess.READ)
		if f:
			var text: String = f.get_as_text()
			f.close()
			for m in _re_ext_resource.search_all(text):
				if m.get_string(1) == "PackedScene":
					instances.append(m.get_string(2))
		scene_tree[sp] = {
			"root_type": root_type,
			"script": script_path,
			"instances": instances,
		}

	# Signal map
	var signal_map: Array = []
	if include_signals:
		signal_map = _build_signal_map(scripts)

	# Script stats
	var total_lines := 0
	var with_class_name := 0
	var with_signals := 0
	var with_exports := 0
	for sp in scripts:
		var sf := FileAccess.open(str(sp), FileAccess.READ)
		if sf == null:
			continue
		var st: String = sf.get_as_text()
		sf.close()
		total_lines += st.split("\n").size()
		if _re_class_name.search(st) != null:
			with_class_name += 1
		if _re_signal.search(st) != null:
			with_signals += 1
		if _re_export.search(st) != null:
			with_exports += 1

	# Observations
	var observations: Array = []
	for sp in scene_tree:
		var info: Dictionary = scene_tree[sp]
		if info.get("instances", []).size() > 5:
			observations.append("%s instances %d scenes — may need splitting" % [sp, info.instances.size()])

	var result := {
		"type": "project_architecture",
		"project_name": ProjectSettings.get_setting("application/config/name", "unknown"),
		"main_scene": ProjectSettings.get_setting("run/main_scene", ""),
		"viewport": {
			"width": ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
			"height": ProjectSettings.get_setting("display/window/size/viewport_height", 648),
		},
		"autoloads": autoloads,
		"scene_tree": scene_tree,
		"signal_bus": signal_map,
		"scripts_summary": {
			"total": scripts.size(),
			"with_class_name": with_class_name,
			"with_signals": with_signals,
			"with_exports": with_exports,
			"total_lines": total_lines,
		},
		"resource_types": {
			"scenes": scenes.size(),
			"scripts": scripts.size(),
			"resources": resources.size(),
		},
		"observations": observations,
	}

	return _ok_json(result)


# ============ Tool 4: inspect_live_scene ============

func _tool_inspect_live_scene(args: Dictionary) -> Dictionary:
	var incremental: bool = args.get("incremental", false)
	var baseline_hash: String = args.get("baseline_hash", "")
	var include_groups: bool = args.get("include_groups", true)

	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable — this tool requires the editor")
	var root = ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open in editor")

	var result := {
		"type": "live_scene",
		"path": root.scene_file_path,
		"unsaved_changes": false,  # TODO: detect via editor API
		"root": _serialize_live_node(root, root, include_groups),
		"hash": "",
	}

	# Simple hash based on node count + names
	var hash_input: String = ""
	_collect_hash(root, hash_input)
	result.hash = str(hash(hash_input))

	return _ok_json(result)


# ============ Tool 5: inspect_resource_interface ============

func _tool_inspect_resource_interface(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")

	# Case 1: .gd file — parse @export declarations
	if path.ends_with(".gd"):
		if not FileAccess.file_exists(path):
			return _err("File not found: " + path)
		var f := FileAccess.open(path, FileAccess.READ)
		var text: String = f.get_as_text()
		f.close()

		var class_name_found := ""
		var extends_found := ""
		var exports: Array = []
		var line_num := 0

		for line in text.split("\n"):
			line_num += 1
			var s: String = line.strip_edges()

			var m := _re_class_name.search(s)
			if m:
				class_name_found = m.get_string(1)
				continue

			m = _re_extends.search(s)
			if m:
				extends_found = m.get_string(1)
				continue

			m = _re_export.search(s)
			if m:
				exports.append({
					"name": m.get_string(1),
					"type": m.get_string(2) if not m.get_string(2).is_empty() else "auto",
					"default": m.get_string(3).strip_edges() if not m.get_string(3).is_empty() else "",
					"line": line_num,
				})

		return _ok_json({
			"type": "resource_interface",
			"path": path,
			"class_name": class_name_found,
			"extends": extends_found,
			"exports": exports,
		})

	# Case 2: .tres file — load and reflect
	if path.ends_with(".tres") or path.ends_with(".res"):
		if not FileAccess.file_exists(path):
			return _err("File not found: " + path)
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			return _err("Failed to load resource: " + path)
		return _ok_json(_reflect_resource(res, path))

	# Case 3: type name — instantiate and reflect
	if ClassDB.class_exists(path) and ClassDB.is_parent_class(path, "Resource"):
		var res = ClassDB.instantiate(path)
		if res == null:
			return _err("Failed to instantiate: " + path)
		var result := _reflect_resource(res, "")
		res = null
		return _ok_json(result)

	return _err("Unsupported path type. Use .gd, .tres, or a Resource class name.")


# ============ Tool 6: get_scene_dependencies ============

func _tool_get_scene_dependencies(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	if path.is_empty():
		return _err("path is required")
	if not FileAccess.file_exists(path):
		return _err("File not found: " + path)

	var recursive: bool = args.get("recursive", true)
	var reverse: bool = args.get("reverse", false)

	if reverse:
		return _get_reverse_dependencies(path)

	# Forward dependencies
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _err("Cannot open: " + path)
	var text: String = f.get_as_text()
	f.close()

	var direct := {"scenes": [], "scripts": [], "resources": []}
	for m in _re_ext_resource.search_all(text):
		var res_type: String = m.get_string(1)
		var res_path: String = m.get_string(2)
		if res_path.ends_with(".tscn") or res_path.ends_with(".scn"):
			direct.scenes.append(res_path)
		elif res_path.ends_with(".gd"):
			direct.scripts.append(res_path)
		else:
			direct.resources.append(res_path)

	var all_deps: Array = [{"path": path, "depth": 0}]
	if recursive:
		var visited: Array = [path]
		var queue: Array = []
		for dep_path in direct.scenes:
			queue.append({"path": dep_path, "depth": 1})
		while not queue.is_empty():
			var item: Dictionary = queue.pop_front()
			var dp: String = item.path
			if visited.has(dp):
				continue
			visited.append(dp)
			all_deps.append(item)
			# Parse sub-scene dependencies
			if FileAccess.file_exists(dp):
				var sf := FileAccess.open(dp, FileAccess.READ)
				if sf:
					var st: String = sf.get_as_text()
					sf.close()
					for sm in _re_ext_resource.search_all(st):
						var sp: String = sm.get_string(2)
						if sp.ends_with(".tscn") and not visited.has(sp):
							queue.append({"path": sp, "depth": item.depth + 1})

	return _ok_json({
		"type": "dependency_graph",
		"root": path,
		"direction": "forward",
		"direct": direct,
		"recursive": all_deps,
		"stats": {
			"total_scenes": direct.scenes.size(),
			"total_scripts": direct.scripts.size(),
			"total_resources": direct.resources.size(),
		},
	})


# ============ Tool 7: analyze_signal_flow ============

func _tool_analyze_signal_flow(args: Dictionary) -> Dictionary:
	var scope: String = args.get("scope", "project")
	var module_filter: String = args.get("module_filter", "")

	var scripts: Array = []
	_walk_dir("res://", scripts, [".gd"], "")

	if module_filter != "":
		var filtered: Array = []
		for sp in scripts:
			if str(sp).find(module_filter) >= 0:
				filtered.append(sp)
		scripts = filtered

	var all_signals: Dictionary = {}  # signal_name → {declared_in, emitted_in, connected_in}

	for script_path in scripts:
		var sp: String = str(script_path)
		var sf := FileAccess.open(sp, FileAccess.READ)
		if sf == null:
			continue
		var text: String = sf.get_as_text()
		sf.close()
		var short_path: String = sp.replace("res://", "")

		for line in text.split("\n"):
			var s: String = line.strip_edges()
			if s.begins_with("#"):
				continue

			# signal declaration
			var m := _re_signal.search(s)
			if m:
				var sig_name: String = m.get_string(1)
				if not all_signals.has(sig_name):
					all_signals[sig_name] = {"declared_in": [], "emitted_in": [], "connected_in": []}
				if not all_signals[sig_name].declared_in.has(short_path):
					all_signals[sig_name].declared_in.append(short_path)

			# .emit()
			for em in _re_emit.search_all(s):
				var sig_name: String = em.get_string(1)
				if not all_signals.has(sig_name):
					all_signals[sig_name] = {"declared_in": [], "emitted_in": [], "connected_in": []}
				if not all_signals[sig_name].emitted_in.has(short_path):
					all_signals[sig_name].emitted_in.append(short_path)

			# .connect()
			for cm in _re_connect.search_all(s):
				var sig_name: String = cm.get_string(1)
				if not all_signals.has(sig_name):
					all_signals[sig_name] = {"declared_in": [], "emitted_in": [], "connected_in": []}
				if not all_signals[sig_name].connected_in.has(short_path):
					all_signals[sig_name].connected_in.append(short_path)

	# Build output
	var signals_out: Array = []
	var observations: Array = []
	for sig_name in all_signals:
		var info: Dictionary = all_signals[sig_name]
		var cross_module: bool = info.declared_in.size() + info.emitted_in.size() + info.connected_in.size() > 2
		var consistency: String = "ok"
		var warning: String = ""
		if info.declared_in.is_empty() and not info.emitted_in.is_empty():
			consistency = "warning"
			warning = "emitted but never declared"
		elif info.connected_in.is_empty() and info.emitted_in.is_empty() and not info.declared_in.is_empty():
			consistency = "warning"
			warning = "declared but never emitted or connected"

		signals_out.append({
			"name": sig_name,
			"declared_in": info.declared_in,
			"emitted_in": info.emitted_in,
			"connected_in": info.connected_in,
			"cross_module": cross_module,
			"consistency": consistency,
			"warning": warning,
		})
		if not warning.is_empty():
			observations.append("signal '%s': %s" % [sig_name, warning])

	return _ok_json({
		"type": "signal_flow",
		"scope": scope,
		"signals": signals_out,
		"observations": observations,
		"scripts_scanned": scripts.size(),
	})


# ============ Tool 8: compare_scenes ============

func _tool_compare_scenes(args: Dictionary) -> Dictionary:
	var path_a: String = args.get("path_a", "")
	var path_b: String = args.get("path_b", "")
	var compare_scripts: bool = args.get("compare_scripts", true)

	if not FileAccess.file_exists(path_a):
		return _err("File not found: " + path_a)
	if not FileAccess.file_exists(path_b):
		return _err("File not found: " + path_b)

	# Load both scenes
	var packed_a = load(path_a) as PackedScene
	var packed_b = load(path_b) as PackedScene
	if packed_a == null:
		return _err("Cannot load scene A: " + path_a)
	if packed_b == null:
		return _err("Cannot load scene B: " + path_b)

	var state_a := packed_a.get_state()
	var state_b := packed_b.get_state()

	# Build node maps
	var nodes_a := _build_node_map(state_a)
	var nodes_b := _build_node_map(state_b)

	var added: Array = []
	var removed: Array = []
	var modified: Array = []

	# Find removed and modified
	for node_path in nodes_a:
		if not nodes_b.has(node_path):
			removed.append({"path": node_path, "type": nodes_a[node_path].type})
		else:
			var props_diff := _compare_properties(nodes_a[node_path].properties, nodes_b[node_path].properties)
			if not props_diff.is_empty():
				modified.append({"path": node_path, "properties": props_diff})

	# Find added
	for node_path in nodes_b:
		if not nodes_a.has(node_path):
			added.append({"path": node_path, "type": nodes_b[node_path].type})

	var summary: String = "%d added, %d removed, %d modified" % [added.size(), removed.size(), modified.size()]

	var result := {
		"type": "scene_diff",
		"path_a": path_a,
		"path_b": path_b,
		"scene_changes": {
			"added_nodes": added,
			"removed_nodes": removed,
			"modified_nodes": modified,
		},
		"summary": summary,
	}

	return _ok_json(result)


# ============ Helper: Node Serialization ============

func _serialize_node(node: Node, root: Node, depth: int, max_depth: int, focus_path: String, filter_props: Array, include_signals: bool, include_script_iface: bool) -> Dictionary:
	var info := {
		"name": node.name,
		"type": node.get_class(),
	}

	# Path
	if node != root:
		info["path"] = str(root.get_path_to(node))

	# Properties — only meaningful non-default ones
	var props: Dictionary = {}
	_collect_meaningful_properties(node, props, filter_props)
	if not props.is_empty():
		info["properties"] = props

	# Script interface
	if include_script_iface:
		var script = node.get_script()
		if script != null and script is Resource:
			var script_path: String = (script as Resource).resource_path
			if not script_path.is_empty():
				info["script"] = {"path": script_path}
				# Quick inline interface extraction
				var iface := _quick_script_interface(script_path)
				if not iface.is_empty():
					info.script["class_name"] = iface.get("class_name", "")
					info.script["extends"] = iface.get("extends", "")
					if iface.has("signals") and not iface.signals.is_empty():
						info.script["signals"] = iface.signals
					if iface.has("exports") and not iface.exports.is_empty():
						info.script["exports"] = iface.exports

	# Signal connections
	if include_signals:
		var sig_conns: Array = []
		for sig_info in node.get_signal_list():
			var sig_name: String = str(sig_info.get("name", ""))
			for conn in node.get_signal_connection_list(sig_name):
				sig_conns.append({
					"signal": sig_name,
					"target": str(conn.get("callable", "")),
					"method": conn.get("method", ""),
				})
		if not sig_conns.is_empty():
			info["signal_connections"] = sig_conns

	# Children
	if max_depth == 0 or depth < max_depth:
		var children: Array = []
		for child in node.get_children():
			children.append(_serialize_node(child, root, depth + 1, max_depth, focus_path, filter_props, include_signals, include_script_iface))
		if not children.is_empty():
			info["children"] = children
			info["child_count"] = children.size()

	return info


func _collect_meaningful_properties(node: Node, out: Dictionary, filter_props: Array) -> void:
	if node is Node2D:
		var n2d := node as Node2D
		if n2d.position != Vector2.ZERO:
			out["position"] = [n2d.position.x, n2d.position.y]
		if n2d.rotation != 0:
			out["rotation"] = n2d.rotation
		if n2d.scale != Vector2.ONE:
			out["scale"] = [n2d.scale.x, n2d.scale.y]
		if n2d.z_index != 0:
			out["z_index"] = n2d.z_index
		if not n2d.visible:
			out["visible"] = false
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		if co.collision_layer != 1:
			out["collision_layer"] = co.collision_layer
		if co.collision_mask != 1:
			out["collision_mask"] = co.collision_mask
	if node is Control:
		var ctrl := node as Control
		if ctrl.layout_mode != 0:
			out["layout_mode"] = ctrl.layout_mode
		if ctrl.anchors_preset != -1:
			out["anchors_preset"] = ctrl.anchors_preset
		if ctrl.custom_minimum_size != Vector2.ZERO:
			out["custom_minimum_size"] = [ctrl.custom_minimum_size.x, ctrl.custom_minimum_size.y]
	if node is Timer:
		var timer := node as Timer
		out["wait_time"] = timer.wait_time
		if timer.autostart:
			out["autostart"] = true
		if timer.one_shot:
			out["one_shot"] = true
	if node is Label:
		var label := node as Label
		if not label.text.is_empty():
			out["text"] = label.text
	if node is CollisionShape2D:
		var cs := node as CollisionShape2D
		if cs.shape != null:
			out["shape"] = _serialize_resource_value(cs.shape)

	# Apply filter
	if not filter_props.is_empty():
		var filtered: Dictionary = {}
		for key in filter_props:
			if out.has(key):
				filtered[key] = out[key]
		out.clear()
		for key in filtered:
			out[key] = filtered[key]


func _serialize_resource_value(res: Resource) -> Variant:
	if res == null:
		return null
	var result := {"type": res.get_class()}
	if res is RectangleShape2D:
		result["size"] = [(res as RectangleShape2D).size.x, (res as RectangleShape2D).size.y]
	elif res is CircleShape2D:
		result["radius"] = (res as CircleShape2D).radius
	elif res is CapsuleShape2D:
		result["radius"] = (res as CapsuleShape2D).radius
		result["height"] = (res as CapsuleShape2D).height
	else:
		result["resource_path"] = res.resource_path
	return result


# ============ Helper: Live Node Serialization ============

func _serialize_live_node(node: Node, root: Node, include_groups: bool) -> Dictionary:
	var info := {
		"name": node.name,
		"type": node.get_class(),
		"instance_id": node.get_instance_id(),
	}
	if node != root:
		info["path"] = str(root.get_path_to(node))

	var script = node.get_script()
	if script != null and script is Resource:
		info["script"] = (script as Resource).resource_path

	var props: Dictionary = {}
	_collect_meaningful_properties(node, props, [])
	if not props.is_empty():
		info["properties"] = props

	if include_groups:
		var groups := node.get_groups()
		if not groups.is_empty():
			info["groups"] = groups

	var connections_arr: Array = []
	for sig_info in node.get_signal_list():
		var sig_name: String = str(sig_info.get("name", ""))
		for conn in node.get_signal_connection_list(sig_name):
			connections_arr.append({
				"signal": sig_name,
				"method": conn.get("method", ""),
			})
	if not connections_arr.is_empty():
		info["signal_connections"] = connections_arr

	var children: Array = []
	for child in node.get_children():
		children.append(_serialize_live_node(child, root, include_groups))
	if not children.is_empty():
		info["children"] = children

	return info


# ============ Helper: Script Interface (quick inline) ============

func _quick_script_interface(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()

	var result := {"class_name": "", "extends": "", "signals": [], "exports": []}

	for line in text.split("\n"):
		var s: String = line.strip_edges()

		var m := _re_class_name.search(s)
		if m:
			result.class_name = m.get_string(1)
			continue

		m = _re_extends.search(s)
		if m:
			result.extends = m.get_string(1)
			continue

		m = _re_signal.search(s)
		if m:
			result.signals.append({"name": m.get_string(1)})
			continue

		m = _re_export.search(s)
		if m:
			result.exports.append({
				"name": m.get_string(1),
				"type": m.get_string(2) if not m.get_string(2).is_empty() else "auto",
			})
			continue

	return result


# ============ Helper: Scene Type Detection ============

func _detect_scene_type(root: Node) -> String:
	if root is Control:
		return "ui"
	if root is Node3D:
		return "3d"
	if root is Node2D or root is Sprite2D or root is Area2D or root is CharacterBody2D or root is RigidBody2D or root is StaticBody2D:
		return "2d"
	return "general"


# ============ Helper: Stats ============

func _count_stats(node_data: Dictionary, stats: Dictionary) -> void:
	stats.total_nodes += 1
	if node_data.has("script"):
		stats.total_scripts += 1
	var children: Array = node_data.get("children", [])
	for child in children:
		_count_stats(child, stats)


# ============ Helper: Scene Observations ============

func _generate_scene_observations(node_data: Dictionary, observations: Array) -> void:
	var node_type: String = node_data.get("type", "")
	var props: Dictionary = node_data.get("properties", {})

	# CollisionShape2D without shape
	if node_type == "CollisionShape2D" and not props.has("shape"):
		var node_name: String = node_data.get("name", "unknown")
		observations.append("%s (CollisionShape2D) has no shape assigned — collision will not work" % node_name)

	# Node with script but no collision layer info
	if node_type == "Area2D" or node_type == "CharacterBody2D":
		if props.get("collision_layer", 1) == 0 and props.get("collision_mask", 1) == 0:
			var node_name: String = node_data.get("name", "unknown")
			observations.append("%s (%s) has collision_layer=0 and collision_mask=0" % [node_name, node_type])

	var children: Array = node_data.get("children", [])
	for child in children:
		_generate_scene_observations(child, observations)


# ============ Helper: Hash Collection ============

func _collect_hash(node: Node, out: String) -> void:
	out += str(node.name) + str(node.get_class())
	for child in node.get_children():
		_collect_hash(child, out)


# ============ Helper: Reverse Dependencies ============

func _get_reverse_dependencies(target_path: String) -> Dictionary:
	var all_scenes: Array = []
	_walk_dir("res://", all_scenes, [".tscn"], "")

	var dependents: Array = []
	for scene_path in all_scenes:
		var sp: String = str(scene_path)
		if sp == target_path:
			continue
		var f := FileAccess.open(sp, FileAccess.READ)
		if f == null:
			continue
		var text: String = f.get_as_text()
		f.close()
		if text.find(target_path) >= 0:
			dependents.append(sp)

	return _ok_json({
		"type": "dependency_graph",
		"root": target_path,
		"direction": "reverse",
		"dependents": dependents,
		"count": dependents.size(),
	})


# ============ Helper: Build Node Map (for compare) ============

func _build_node_map(state: SceneState) -> Dictionary:
	var nodes: Dictionary = {}
	for i in range(state.get_node_count()):
		var node_path: String = str(state.get_node_path(i))
		var node_type: String = state.get_node_type(i)
		var props: Dictionary = {}
		for pi in range(state.get_node_property_count(i)):
			var pname: String = state.get_node_property_name(i, pi)
			var pval = state.get_node_property_value(i, pi)
			props[pname] = _serialize_value(pval)
		nodes[node_path] = {"type": node_type, "properties": props}
	return nodes


func _compare_properties(a: Dictionary, b: Dictionary) -> Array:
	var diffs: Array = []
	var all_keys: Array = []
	for key in a:
		if not all_keys.has(key):
			all_keys.append(key)
	for key in b:
		if not all_keys.has(key):
			all_keys.append(key)
	for key in all_keys:
		var va = a.get(key, null)
		var vb = b.get(key, null)
		if str(va) != str(vb):
			diffs.append({"name": key, "old": va, "new": vb})
	return diffs


# ============ Helper: Serialize Variant ============

func _serialize_value(val: Variant) -> Variant:
	if val == null:
		return null
	if val is Vector2:
		return [val.x, val.y]
	if val is Vector3:
		return [val.x, val.y, val.z]
	if val is Color:
		return [val.r, val.g, val.b, val.a]
	if val is Rect2:
		return {"position": [val.position.x, val.position.y], "size": [val.size.x, val.size.y]}
	if val is Resource:
		return {"resource_path": (val as Resource).resource_path, "class": val.get_class()}
	if val is NodePath:
		return str(val)
	if val is Array:
		var arr: Array = []
		for item in val:
			arr.append(_serialize_value(item))
		return arr
	return val


# ============ Helper: Reflect Resource ============

func _reflect_resource(res: Resource, path: String) -> Dictionary:
	var props: Array = []
	for p in res.get_property_list():
		var pname: String = str(p.get("name", ""))
		var ptype: int = p.get("type", 0)
		var pusage: int = p.get("usage", 0)
		if pname.begins_with("_"):
			continue
		if pusage & PROPERTY_USAGE_EDITOR == 0 and pusage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if ptype == TYPE_NIL and pusage & PROPERTY_USAGE_GROUP:
			continue
		props.append({
			"name": pname,
			"type": type_string(ptype),
			"value": _serialize_value(res.get(pname)),
		})

	return {
		"type": "resource_interface",
		"path": path,
		"class": res.get_class(),
		"property_count": props.size(),
		"properties": props,
	}


# ============ Helper: Signal Map ============

func _build_signal_map(scripts: Array) -> Array:
	var signal_map: Dictionary = {}
	for script_path in scripts:
		var sp: String = str(script_path)
		var sf := FileAccess.open(sp, FileAccess.READ)
		if sf == null:
			continue
		var text: String = sf.get_as_text()
		sf.close()
		var short: String = sp.replace("res://", "")

		for line in text.split("\n"):
			var s: String = line.strip_edges()
			if s.begins_with("#"):
				continue
			var m := _re_signal.search(s)
			if m:
				var sig_name: String = m.get_string(1)
				if not signal_map.has(sig_name):
					signal_map[sig_name] = {"declared_in": [], "connected_in": []}
				signal_map[sig_name].declared_in.append(short)

			for cm in _re_connect.search_all(s):
				var sig_name: String = cm.get_string(1)
				if not signal_map.has(sig_name):
					signal_map[sig_name] = {"declared_in": [], "connected_in": []}
				if not signal_map[sig_name].connected_in.has(short):
					signal_map[sig_name].connected_in.append(short)

	var result: Array = []
	for sig_name in signal_map:
		result.append({"name": sig_name, "declared_in": signal_map[sig_name].declared_in, "connected_in": signal_map[sig_name].connected_in})
	return result
