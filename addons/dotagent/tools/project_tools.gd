@tool
extends "res://addons/dotagent/tools/tool_base.gd"
## 项目工具集 - 项目设置、配置、记忆、技能
##
## Tools:
## - get_project_info
## - get_project_setting
## - set_project_setting
## - remember
## - recall
## - export_session
## - get_input_actions
## - add_input_action
## - list_skills
## - create_skill




func get_tool_definitions() -> Array:
	return [
		{
			"name": "get_project_info",
			"description": "Get project name, version, main scene, autoloads, and other top-level info.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_get_project_info",
			"dangerous": false,
		},
		{
			"name": "get_project_setting",
			"description": "Get a project setting value. Examples: 'application/config/name', 'display/window/size/viewport_width'.",
			"parameters": {
				"type": "object",
				"properties": {
					"key": {"type": "string", "description": "Setting key"},
				},
				"required": ["key"],
			},
			"method_name": "_tool_get_project_setting",
			"dangerous": false,
		},
		{
			"name": "set_project_setting",
			"description": "Set a project setting. value is parsed as JSON. Will be saved when project is saved.",
			"parameters": {
				"type": "object",
				"properties": {
					"key": {"type": "string", "description": "Setting key"},
					"value": {"description": "New value (JSON)"},
				},
				"required": ["key", "value"],
			},
			"method_name": "_tool_set_project_setting",
			"dangerous": false,
		},
		{
			"name": "remember",
			"description": "Save a fact or convention to project memory (.dotagent_memory.md). Use for things like 'this project uses snake_case' or 'don't modify main_menu.tscn'.",
			"parameters": {
				"type": "object",
				"properties": {
					"fact": {"type": "string", "description": "The fact or convention to remember"},
				},
				"required": ["fact"],
			},
			"method_name": "_tool_remember",
			"dangerous": false,
		},
		{
			"name": "recall",
			"description": "Read project memory (.dotagent_memory.md). Use at the start of a new session to recall conventions and decisions.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_recall",
			"dangerous": false,
		},
		{
			"name": "export_session",
			"description": "Export current conversation as a Markdown file. Saves to res://session_export.md.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_export_session",
			"dangerous": false,
		},
		{
			"name": "get_input_actions",
			"description": "List all input actions defined in the project's Input Map (project.godot). Returns action names and their bound events (key, mouse button, joypad).",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_get_input_actions",
			"dangerous": false,
		},
		{
			"name": "add_input_action",
			"description": "Add a new input action to the project Input Map. Events are simple objects: {\"type\": \"key\", \"code\": \"KEY_SPACE\"} or {\"type\": \"mouse\", \"button\": 1}. Persists to project.godot.",
			"parameters": {
				"type": "object",
				"properties": {
					"name": {"type": "string", "description": "Action name, e.g. 'jump', 'shoot'"},
					"events": {"type": "array", "description": "Event objects, e.g. [{\"type\":\"key\", \"code\":\"KEY_SPACE\"}]"},
				},
				"required": ["name"],
			},
			"method_name": "_tool_add_input_action",
			"dangerous": false,
		},
		{
			"name": "list_skills",
			"description": "List all available scene-type skills (2D game, UI, 3D game) with their trigger keywords. Skills are auto-matched based on your message, but you can call this to see what's available or if you need a specific skill not auto-matched.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_list_skills",
			"dangerous": false,
		},
		{
			"name": "create_skill",
			"description": "Create a new skill file in res://addons/dotagent/skills/custom/. Skills auto-load next session and are matched by trigger keywords against user messages.\n\nParameters:\n- name: kebab-case filename without .md, e.g. 'tilemap-platformer'\n- triggers: lowercase keywords, 5-15 recommended, e.g. ['tilemap', 'platformer', 'level']\n- content: markdown body. Recommended sections: Root & Structure, Key Nodes table, Mandatory Checklist, Common Mistakes (see existing skills in builtin/ for examples)\n\nAfter creating, call list_skills to verify. Overlapping triggers are OK — all matching skills get injected, they don't override each other.",
			"parameters": {
				"type": "object",
				"properties": {
					"name": {"type": "string", "description": "Skill filename (without .md), kebab-case, e.g. 'tilemap-platformer'"},
					"triggers": {"type": "array", "items": {"type": "string"}, "description": "Trigger keywords (lowercase), e.g. ['tilemap', 'tileset', 'platformer', 'level']"},
					"content": {"type": "string", "description": "Markdown body — sections: Root & Structure, Key Nodes, Mandatory Checklist, Common Mistakes"},
				},
				"required": ["name", "triggers", "content"],
			},
			"method_name": "_tool_create_skill",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_get_project_info": return _tool_get_project_info(args)
		"_tool_get_project_setting": return _tool_get_project_setting(args)
		"_tool_set_project_setting": return _tool_set_project_setting(args)
		"_tool_remember": return _tool_remember(args)
		"_tool_recall": return _tool_recall(args)
		"_tool_export_session": return _tool_export_session(args)
		"_tool_get_input_actions": return _tool_get_input_actions(args)
		"_tool_add_input_action": return _tool_add_input_action(args)
		"_tool_list_skills": return _tool_list_skills(args)
		"_tool_create_skill": return _tool_create_skill(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_get_project_info(args: Dictionary) -> Dictionary:
	var info := {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"autoloads": [],
	}
	# Autoloads 在 project.godot 的 [autoload] 段
	var project := ConfigFile.new()
	if project.load("res://project.godot") == OK:
		for section in project.get_sections():
			if section == "autoload":
				for k in project.get_section_keys("autoload"):
					info["autoloads"].append({"name": k, "path": project.get_value("autoload", k)})
	return _ok(JSON.stringify(info, "  "))


func _tool_get_project_setting(args: Dictionary) -> Dictionary:
	var key: String = args.get("key", "")
	if key.is_empty():
		return _err("key is required")
	if not ProjectSettings.has_setting(key):
		return _err("Setting does not exist: " + key)
	var value = ProjectSettings.get_setting(key)
	return _ok("%s = %s" % [key, str(value)])


func _tool_set_project_setting(args: Dictionary) -> Dictionary:
	var key: String = args.get("key", "")
	if key.is_empty():
		return _err("key is required")
	var value = _parse_setting_value(args.get("value"))
	# 自定义 key：先 set 再 save，不要求 has_setting
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, value)
		var err := ProjectSettings.save()
		if err != OK:
			return _err("Failed to save custom setting: " + key)
		return _ok("Registered and set %s = %s (saved to project.godot)" % [key, str(value)])
	ProjectSettings.set_setting(key, value)
	ProjectSettings.save()
	return _ok("Set %s = %s (saved to project.godot)" % [key, str(value)])


## 将 AI 传入的字符串值解析为正确的 Variant 类型。
## AI 在 JSON 中只能传字符串，但 ProjectSettings 需要正确类型（Color、int、float 等）。
func _parse_setting_value(raw):
	if typeof(raw) != TYPE_STRING:
		return raw
	var s: String = str(raw).strip_edges()
	# Color: "Color(0.02, 0.02, 0.06, 1)" → Color object
	if s.begins_with("Color(") and s.ends_with(")"):
		var inner := s.substr(6, s.length() - 7).strip_edges()
		var parts := inner.split(",", false)
		if parts.size() >= 3:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() >= 4 else 1.0)
	# Vector2: "(640, 360)"
	if s.begins_with("(") and s.ends_with(")"):
		var inner := s.substr(1, s.length() - 2).strip_edges()
		var parts := inner.split(",", false)
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
		if parts.size() == 3:
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	# float
	if s.is_valid_float():
		return s.to_float()
	# int
	if s.is_valid_int():
		return s.to_int()
	# bool
	if s == "true":
		return true
	if s == "false":
		return false
	return s


const MEMORY_PATH := "res://.dotagent_memory.md"


func _tool_remember(args: Dictionary) -> Dictionary:
	var fact: String = args.get("fact", "")
	if fact.is_empty():
		return _err("fact is required")
	var existing := ""
	if FileAccess.file_exists(MEMORY_PATH):
		var f := FileAccess.open(MEMORY_PATH, FileAccess.READ)
		if f:
			existing = f.get_as_text()
			f.close()
	var f := FileAccess.open(MEMORY_PATH, FileAccess.WRITE)
	if f == null:
		return _err("Cannot write memory file")
	f.store_string(existing + "- " + fact + "\n")
	f.close()
	return _ok("Remembered: " + fact)


func _tool_recall(args: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(MEMORY_PATH):
		return _ok("(no project memory yet — use remember to add facts)")
	var f := FileAccess.open(MEMORY_PATH, FileAccess.READ)
	if f == null:
		return _err("Cannot read memory")
	var content := f.get_as_text()
	f.close()
	return _ok(content)


func _tool_export_session(args: Dictionary) -> Dictionary:
	var logs_dir := "res://addons/dotagent/logs"
	var d := DirAccess.open(logs_dir)
	if d == null:
		return _err("Cannot access logs")
	var latest := ""
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and name > latest:
			latest = name
		name = d.get_next()
	d.list_dir_end()
	if latest == "":
		return _err("No sessions found")
	var src := logs_dir.path_join(latest).path_join("conversation.md")
	if not FileAccess.file_exists(src):
		return _err("No conversation found")
	var f := FileAccess.open(src, FileAccess.READ)
	var content := f.get_as_text()
	f.close()
	var dst := "res://session_export.md"
	var fw := FileAccess.open(dst, FileAccess.WRITE)
	fw.store_string(content)
	fw.close()
	return _ok("Exported to: " + dst)


## 列出所有 Input Map 动作
func _tool_get_input_actions(args: Dictionary) -> Dictionary:
	var actions: Array = InputMap.get_actions()
	var result: Array = []
	for action_name in actions:
		var events: Array = []
		for ev in InputMap.action_get_events(action_name):
			var ev_info := _describe_input_event(ev)
			if not ev_info.is_empty():
				events.append(ev_info)
		result.append({"name": action_name, "events": events})
	return _ok(JSON.stringify(result, "  "))


## 将 InputEvent 转为可读的字典
func _describe_input_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var ek := ev as InputEventKey
		return {"type": "key", "keycode": OS.get_keycode_string(ek.keycode), "physical": OS.get_keycode_string(ek.physical_keycode)}
	elif ev is InputEventMouseButton:
		var emb := ev as InputEventMouseButton
		var btn_names := ["", "left", "right", "middle", "wheel_up", "wheel_down", "wheel_left", "wheel_right", "x1", "x2"]
		var btn: String = btn_names[emb.button_index] if emb.button_index < btn_names.size() else "button_%d" % emb.button_index
		return {"type": "mouse", "button": btn, "pressed": emb.pressed}
	elif ev is InputEventJoypadButton:
		var ejb := ev as InputEventJoypadButton
		return {"type": "joypad_button", "button": ejb.button_index, "pressed": ejb.pressed}
	elif ev is InputEventJoypadMotion:
		var ejm := ev as InputEventJoypadMotion
		return {"type": "joypad_axis", "axis": ejm.axis, "value": ejm.axis_value}
	return {}


## 添加新的 Input Map 动作
func _tool_add_input_action(args: Dictionary) -> Dictionary:
	var name: String = args.get("name", "")
	var events: Array = args.get("events", [])

	if name.is_empty():
		return _err("name is required")
	if InputMap.has_action(name):
		return _err("Action already exists: " + name + ". Use a different name.")

	InputMap.add_action(name)
	InputMap.action_set_deadzone(name, 0.5)  # 确保 action 完整注册

	for ev_desc in events:
		var ev_type: String = ev_desc.get("type", "")
		if ev_type == "key":
			var code: String = ev_desc.get("code", "")
			if code.is_empty():
				continue
			var kc := OS.find_keycode_from_string(code)
			if kc == KEY_NONE and code != "None":
				push_warning("Unknown keycode: " + code)
				continue
			var ev := InputEventKey.new()
			ev.keycode = kc
			InputMap.action_add_event(name, ev)
		elif ev_type == "mouse":
			var btn: int = int(ev_desc.get("button", 1))
			var ev := InputEventMouseButton.new()
			ev.button_index = btn
			InputMap.action_add_event(name, ev)
		elif ev_type == "joypad_button":
			var btn: int = int(ev_desc.get("button", 0))
			var ev := InputEventJoypadButton.new()
			ev.button_index = btn
			InputMap.action_add_event(name, ev)
		elif ev_type == "joypad_axis":
			var axis: int = int(ev_desc.get("axis", 0))
			var ev := InputEventJoypadMotion.new()
			ev.axis = axis
			ev.axis_value = float(ev_desc.get("value", 1.0))
			InputMap.action_add_event(name, ev)

	ProjectSettings.save()
	var count := InputMap.action_get_events(name).size()
	return _ok("Added action '%s' with %d event(s). Saved to project.godot." % [name, count])


## List all available scene-type skills with their trigger keywords.
func _tool_list_skills(args: Dictionary) -> Dictionary:
	var sm := SkillManager.new()
	var skills := sm.list_skills()
	if skills.is_empty():
		return _ok("(no skills found in res://addons/dotagent/skills/)")
	var lines: Array = []
	lines.append("Available skills (%d):" % skills.size())
	for s in skills:
		var triggers := ", ".join(s.get("triggers", []))
		var source := "builtin" if "builtin" in s.get("path", "") else "custom"
		lines.append("  [%s] %s — triggers: %s" % [source, s.get("name", "?"), triggers])
	return _ok("\n".join(lines))


## Create a new skill file. Validates format, checks for trigger conflicts.
func _tool_create_skill(args: Dictionary) -> Dictionary:
	var skill_name: String = args.get("name", "")
	var triggers: Array = args.get("triggers", [])
	var content: String = args.get("content", "")

	if skill_name.is_empty():
		return _err("name is required (kebab-case, without .md)")
	if triggers.is_empty():
		return _err("triggers is required (array of lowercase keywords)")
	if content.is_empty():
		return _err("content is required")

	if " " in skill_name or "/" in skill_name:
		return _err("name must be kebab-case, no spaces or slashes: " + skill_name)

	var triggers_line := "# triggers: " + ", ".join(triggers)
	var file_content := triggers_line + "\n\n" + content

	var dir := "res://addons/dotagent/skills/custom"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var path := dir.path_join(skill_name + ".md")
	if FileAccess.file_exists(path):
		return _err("Skill already exists: " + path + ". Use replace_in_file to update it.")

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _err("Cannot write: " + path)
	f.store_string(file_content)
	f.close()

	# Check for trigger overlaps with existing skills
	var sm := SkillManager.new()
	var overlap_warning := ""
	for s in sm.list_skills():
		if s.get("name") == skill_name:
			continue
		var existing: Array = s.get("triggers", [])
		var shared: Array = []
		for t in triggers:
			if t in existing:
				shared.append(t)
		if not shared.is_empty():
			if overlap_warning.is_empty():
				overlap_warning = "\n\n⚠️ Trigger overlaps detected:"
			overlap_warning += "\n  '%s' shares: %s" % [s.get("name", "?"), ", ".join(shared)]

	var lines: Array = []
	lines.append("✅ Skill '%s' created at %s" % [skill_name, path])
	lines.append("Triggers: %s" % ", ".join(triggers))
	lines.append("Content: %d chars" % content.length())
	if not overlap_warning.is_empty():
		lines.append(overlap_warning)
		lines.append("\nMultiple skills with same triggers ALL get injected — they don't override each other. If they conflict, merge them into one skill.")
	lines.append("\nCall list_skills to verify. Auto-injection available after session restart.")
	return _ok("\n".join(lines))
