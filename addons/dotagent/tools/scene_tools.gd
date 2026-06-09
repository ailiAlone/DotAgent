@tool
extends "res://addons/dotagent/core/tool_base.gd"
## 场景/节点工具集
##
## 工具:
## - create_scene
## - get_scene_tree
## - get_node
## - get_node_properties
## - set_node_property
## - add_node
## - remove_node
## - duplicate_node
## - reparent_node
## - undo_last




func get_tool_definitions() -> Array:
	return [
		{
			"name": "create_scene",
			"description": "Create a NEW scene file (.tscn) and open it in the editor immediately. Use this BEFORE add_node to create an empty scene with a root node. NEVER use execute_gdscript + FileAccess to write .tscn by hand — it's slow and the editor won't show changes in real-time. After create_scene succeeds, use add_node to build the scene node by node.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path for the new scene, e.g. 'res://player_stats.tscn'"},
					"root_type": {"type": "string", "description": "Root node class (default 'Control'). Use 'Control' for UI scenes, 'Node2D' for 2D games.", "default": "Control"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_create_scene",
			"dangerous": false,
		},
		{
			"name": "get_scene_tree",
			"description": "Get the scene tree as nested JSON. Defaults to current edited scene. Use scene_path to inspect other open scenes without switching to them.",
			"parameters": {
				"type": "object",
				"properties": {
					"max_depth": {"type": "integer", "description": "Max recursion depth (default 3, max 10)", "default": 3},
					"scene_path": {"type": "string", "description": "Optional res:// path to a specific scene. If omitted, uses the currently edited scene."},
				},
			},
			"method_name": "_tool_get_scene_tree",
			"dangerous": false,
		},
		{
			"name": "get_node",
			"description": "Get detailed info about a specific node at a path. Path is relative to the edited scene root (e.g. 'Player' or 'UI/HealthBar').",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path relative to scene root"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_get_node",
			"dangerous": false,
		},
		{
			"name": "get_node_properties",
			"description": "List all properties and current values of a node. Useful for inspecting before modification.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path relative to scene root"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_get_node_properties",
			"dangerous": false,
		},
		{
			"name": "set_node_property",
			"description": "Set a property on a node. Value is parsed as JSON (string/number/bool/Vector2/etc).",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path"},
					"name": {"type": "string", "description": "Property name"},
					"value": {"description": "New value (JSON)"},
				},
				"required": ["path", "name", "value"],
			},
			"method_name": "_tool_set_node_property",
			"dangerous": false,
		},
		{
			"name": "add_node",
			"description": "Add a child node to a parent. type is a class name (e.g. 'Sprite2D', 'Button', 'CharacterBody2D'). properties is a dict of {name: value} pairs. If unique_name is true, the node is registered for % access from the scene root (recommended for nodes referenced by @onready %Name).",
			"parameters": {
				"type": "object",
				"properties": {
					"parent_path": {"type": "string", "description": "Parent node path (use '.' or '' for scene root)"},
					"type": {"type": "string", "description": "Node class name (e.g. 'Sprite2D', 'Button')"},
					"name": {"type": "string", "description": "Name for the new node"},
					"properties": {"type": "object", "description": "Optional initial properties as {name: value} dict"},
					"unique_name": {"type": "boolean", "description": "Set unique_name_in_owner=true (for @onready %Name access)", "default": false},
				},
				"required": ["parent_path", "type", "name"],
			},
			"method_name": "_tool_add_node",
			"dangerous": false,
		},
		{
			"name": "remove_node",
			"description": "Remove a node and its children from the scene. DANGEROUS - cannot be undone via this tool.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path to remove"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_remove_node",
			"dangerous": true,
		},
		{
			"name": "reparent_node",
			"description": "Move a node to a new parent. The node keeps its name and all children.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path to move"},
					"new_parent_path": {"type": "string", "description": "New parent path"},
				},
				"required": ["path", "new_parent_path"],
			},
			"method_name": "_tool_reparent_node",
			"dangerous": false,
		},
		{
			"name": "undo_last",
			"description": "Undo the last scene operation by restoring the most recent backup. Safe — this tool REVERSES damage, not causes it.",
			"parameters": {"type": "object", "properties": {}},
			"method_name": "_tool_undo_last",
			"dangerous": false,
		},
		{
			"name": "list_nodes",
			"description": "Get a flat list of all nodes in the scene with name, type, path, and child count. Much shorter than get_scene_tree — one line per node. Use for quick overview of scene structure.",
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {"type": "string", "description": "Optional res:// path to a specific scene. If omitted, uses the currently edited scene."},
				},
			},
			"method_name": "_tool_list_nodes",
			"dangerous": false,
		},
		{
			"name": "get_signal_connections",
			"description": "List all signal connections on a node — both editor-connected (Inspector → Node tab) and script-connected (.connect()). Shows signal name, target node path, and target method. Use to understand what happens when a signal fires.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Node path, e.g. 'Center/MenuContainer/StartButton'"},
				},
				"required": ["path"],
			},
			"method_name": "_tool_get_signal_connections",
			"dangerous": false,
		},
	]


func call_method(method_name: String, args: Dictionary) -> Dictionary:
	match method_name:
		"_tool_create_scene": return _tool_create_scene(args)
		"_tool_get_scene_tree": return _tool_get_scene_tree(args)
		"_tool_get_node": return _tool_get_node(args)
		"_tool_get_node_properties": return _tool_get_node_properties(args)
		"_tool_set_node_property": return _tool_set_node_property(args)
		"_tool_add_node": return _tool_add_node(args)
		"_tool_remove_node": return _tool_remove_node(args)
		"_tool_reparent_node": return _tool_reparent_node(args)
		"_tool_undo_last": return _tool_undo_last(args)
		"_tool_list_nodes": return _tool_list_nodes(args)
		"_tool_get_signal_connections": return _tool_get_signal_connections(args)
	return {"ok": false, "content": "Unknown method: " + method_name}


# ============ 工具实现 ============

func _tool_create_scene(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "")
	var root_type: String = args.get("root_type", "Control")

	if path.is_empty():
		return _err("path is required")
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return _err("path must end with .tscn or .scn")
	if FileAccess.file_exists(path):
		return _err("Scene already exists: " + path + ". Use open_scene to open it.")
	if not ClassDB.class_exists(root_type):
		return _err("Unknown class: " + root_type)

	# 确保目录存在
	_ensure_dir(path)

	# 创建根节点
	var root: Node = ClassDB.instantiate(root_type)
	var scene_name := path.get_file().get_basename()
	root.name = scene_name

	# 打包成 PackedScene
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return _err("Failed to pack scene (err=%d). Try a different root_type." % err)

	# 保存到磁盘
	err = ResourceSaver.save(packed, path)
	if err != OK:
		return _err("Failed to save: " + error_string(err))

	# 立即在编辑器中打开 — 用户实时看到新场景
	_refresh_filesystem()
	var ei = _ei()
	if ei:
		ei.open_scene_from_path(path)
	else:
		return _ok("Created: " + path + " (EditorInterface unavailable, open it manually)")

	return _ok("Created and opened: " + path + " (root: " + root_type + "). Now use add_node to build it node by node.")


func _tool_get_scene_tree(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var scene_path: String = args.get("scene_path", "")
	var root: Node = null
	if not scene_path.is_empty():
		# 从文件加载场景（只读，不切换编辑器状态）
		if not FileAccess.file_exists(scene_path):
			return _err("Scene not found: " + scene_path)
		var packed := load(scene_path) as PackedScene
		if packed == null:
			return _err("Failed to load scene: " + scene_path + " (may not be a valid PackedScene)")
		root = packed.instantiate()
		if root == null:
			return _err("Failed to instantiate: " + scene_path)
	else:
		root = ei.get_edited_scene_root()
	if root == null:
		return _ok("No scene found.")

	var depth: int = int(args.get("max_depth", 3))
	depth = clamp(depth, 1, 10)
	var tree := _serialize_node(root, depth, 0)
	# 如果是临时加载的，释放
	if not scene_path.is_empty() and is_instance_valid(root):
		root.queue_free()
	return _ok(JSON.stringify(tree, "  "))


func _tool_get_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found: " + str(args.get("path", "")))
	return _ok(JSON.stringify(_serialize_node(node, 0, 0), "  "))


func _tool_get_node_properties(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var props := []
	for prop in node.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		var pname: String = prop.name
		# 过滤掉 AI 几乎不关心的"噪音"属性,避免返回超长列表
		if not _is_important_prop(pname):
			continue
		var val = node.get(pname)
		if val is Resource and val != null and val.resource_path != "":
			props.append({"name": pname, "type": _type_name(val), "value": val.resource_path})
		else:
			props.append({"name": pname, "type": _type_name(val), "value": str(val)})
	return _ok(JSON.stringify(props, "  "))


## 过滤 _tool_get_node_properties 的输出:只保留 AI 真正关心的属性
## 之前返回所有 storage 属性,动辄 100+ 行,AI 看着头大
func _is_important_prop(pname: String) -> bool:
	# 内部 / 隐藏
	if pname.begins_with("_"):
		return false
	# process / physics 调度
	if pname in ["process_mode", "process_priority", "process_physics_priority", "process_thread_group",
				 "physics_interpolation_mode"]:
		return false
	# 国际化 / 翻译
	if pname in ["auto_translate_mode", "localize_numeral_system"]:
		return false
	# 渲染层 / mask
	if pname in ["visibility_layer", "light_mask", "visibility_behavior_recursive"]:
		return false
	# mouse / focus / accessibility — 用户几乎不通过 AI 改
	if pname.begins_with("mouse_") or pname.begins_with("focus_") or pname.begins_with("accessibility_"):
		return false
	# 渲染细节
	if pname in ["top_level", "clip_children", "clip_contents",
				 "show_behind_parent", "y_sort_enabled", "use_parent_material",
				 "texture_filter", "texture_repeat", "material",
				 "editor_description"]:
		return false
	# tooltip / shortcut — 偶尔关心,但默认跳过
	if pname.begins_with("shortcut_") or pname == "tooltip_auto_translate_mode":
		return false
	# 默认:保留
	return true


func _tool_set_node_property(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var prop_name: String = args.get("name", "")
	if prop_name.is_empty():
		return _err("Missing 'name' parameter")
	if not args.has("value"):
		return _err("Missing 'value' parameter")
	var value = args["value"]
	node.set(prop_name, _parse_property_value(value))
	_emit_change()
	return _ok("Set %s.%s = %s" % [node.name, prop_name, str(value)])


func _tool_add_node(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root = ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open. Open a scene first.")

	var parent_path: String = args.get("parent_path", ".")
	var type_name: String = args.get("type", "")
	var node_name: String = args.get("name", "")

	if type_name.is_empty() or node_name.is_empty():
		return _err("type and name are required")

	var parent: Node = root if parent_path in [".", "", "/"] else _resolve_node(parent_path)
	if parent == null:
		return _err("Parent not found: " + parent_path)

	if not ClassDB.class_exists(type_name):
		return _err("Unknown class: " + type_name)

	var node := ClassDB.instantiate(type_name)
	if node == null:
		return _err("Failed to instantiate: " + type_name)
	node.name = node_name

	# unique_name_in_owner(必须在 add_child 之前或之后马上设)
	if bool(args.get("unique_name", false)):
		node.unique_name_in_owner = true

	# 设置属性
	var properties: Dictionary = args.get("properties", {})
	for k in properties.keys():
		node.set(k, properties[k])

	parent.add_child(node)
	node.owner = root  # 确保保存进场景

	_emit_change()
	return _ok("Added %s '%s' under '%s'%s. New path: %s" % [type_name, node_name, parent.name, " (unique_name)" if node.unique_name_in_owner else "", root.get_path_to(node)])


func _tool_remove_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var path := node.get_path()
	node.queue_free()
	_emit_change()
	return _ok("Removed: " + str(path))


func _tool_reparent_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(args.get("path", ""))
	if node == null:
		return _err("Node not found")
	var new_parent := _resolve_node(args.get("new_parent_path", ""))
	if new_parent == null:
		return _err("New parent not found")
	node.reparent(new_parent)
	_emit_change()
	return _ok("Reparented '%s' under '%s'" % [node.name, new_parent.name])


func _tool_undo_last(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var root = ei.get_edited_scene_root()
	if root == null:
		return _err("No scene open")
	var scene_path: String = root.scene_file_path
	if scene_path.is_empty():
		return _err("Scene not saved yet")
	var backups := _backup.list_backups()
	if backups.is_empty():
		return _err("No backups found")
	# 取最新的备份
	var latest: String = backups[backups.size() - 1]
	var backup_file: String = "res://.dotagent_backups/" + latest + "/" + scene_path.trim_prefix("res://")
	if not FileAccess.file_exists(backup_file):
		return _err("Backup file not found: " + backup_file)
	var f := FileAccess.open(backup_file, FileAccess.READ)
	if f == null:
		return _err("Cannot read backup")
	var content := f.get_as_text()
	f.close()
	var fw := FileAccess.open(scene_path, FileAccess.WRITE)
	if fw == null:
		return _err("Cannot write scene")
	fw.store_string(content)
	fw.close()
	_refresh_filesystem()
	if ei:
		ei.open_scene_from_path(scene_path)
	return _ok("Restored scene from backup: " + latest)


## 扁平列出场景所有节点（name, type, path, child_count），每节点一行
func _tool_list_nodes(args: Dictionary) -> Dictionary:
	var ei = _ei()
	if ei == null:
		return _err("EditorInterface unavailable")
	var scene_path: String = args.get("scene_path", "")
	var root: Node = null
	var temp_root := false
	if not scene_path.is_empty():
		if not FileAccess.file_exists(scene_path):
			return _err("Scene not found: " + scene_path)
		var packed := load(scene_path) as PackedScene
		if packed == null:
			return _err("Failed to load scene: " + scene_path)
		root = packed.instantiate()
		if root == null:
			return _err("Failed to instantiate: " + scene_path)
		temp_root = true
	else:
		root = ei.get_edited_scene_root()
	if root == null:
		return _ok("No scene found.")

	var result: Array = []
	_list_nodes_flat(root, result)

	if temp_root and is_instance_valid(root):
		root.queue_free()

	var lines: Array = []
	for item in result:
		lines.append("%-25s %-20s child=%d  %s" % [item["name"], item["type"], item["child_count"], item["path"]])
	return _ok("%d nodes:\n%s" % [result.size(), "\n".join(lines)])


func _list_nodes_flat(node: Node, out: Array) -> void:
	out.append({
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"child_count": node.get_child_count(),
	})
	for child in node.get_children():
		_list_nodes_flat(child, out)


## 列出节点的所有信号连接（编辑器 + 脚本）
	## 扫描 3 个来源：
	##   1. 脚本 .connect() 连接（静态分析场景中所有脚本的 .connect 调用）
	##   2. Inspector Node 标签页连接（.tscn 的 [connection] 段）
	##   3. get_signal_connection_list（编辑器内部连接，如 SceneTreeEditor）
	##   4. 传入连接（get_incoming_connections — 其他节点连到本节点的方法）
	func _tool_get_signal_connections(args: Dictionary) -> Dictionary:
		var node := _resolve_node(args.get("path", ""))
		if node == null:
			return _err("Node not found")

		var ei = _ei()
		var root = ei.get_edited_scene_root() if ei else null
		var result: Array = []

		# ---- 1. 脚本 .connect() 静态分析 ----
		# 扫描场景中所有脚本，找 node_path.signal_name.connect(method) 模式
		if root:
			var node_rel_path := str(root.get_path_to(node))
			var node_name := node.name
			var scripts_to_scan: Array = []
			# 收集场景中所有节点的脚本
			scripts_to_scan.append({"path": root.scene_file_path, "type": "tscn"})
			_collect_scripts(root, scripts_to_scan)

			var seen_pairs := {}  # 去重: "signal->method"
			for entry in scripts_to_scan:
				if entry.type == "gd":
					var f_script := FileAccess.open(entry.path, FileAccess.READ)
					if f_script == null:
						continue
					var script_content := f_script.get_as_text()
					f_script.close()
					var script_lines := script_content.split("
")
					for line_idx in range(script_lines.size()):
						var line := script_lines[line_idx].strip_edges()
						if line.begins_with("#") or line.begins_with("//"):
							continue
						# 匹配: %NodeName.signal_name.connect(method) 或 NodeName.signal_name.connect(method)
						# 也匹配: node_var.signal_name.connect(Callable(self, "method"))
						if not ".connect(" in line:
							continue
						# 检查是否指向目标节点: %Name, Name, 或 onready 变量引用
						var points_to_node := false
						if ("%" + node_name) in line or node_name in line:
							points_to_node = true
						# 也检查: node_rel_path 中的节点名片段
						if node_rel_path in line:
							points_to_node = true
						if not points_to_node:
							continue
						# 提取信号名和方法名
						var dot_idx := line.find(".connect(")
						if dot_idx < 0:
							continue
						var before_dot := line.substr(0, dot_idx).strip_edges()
						# 信号名在 . 之前的部分末尾: "btn.pressed" → "pressed"
						var space_idx := before_dot.rfind(" ")
						var sig_candidate := before_dot.substr(space_idx + 1).strip_edges()
						# 信号名也可能在 . 之前: %StartButton.pressed
						var last_dot := before_dot.rfind(".")
						if last_dot >= 0:
							sig_candidate = before_dot.substr(last_dot + 1).strip_edges()
						# 提取方法名: .connect(_on_start_pressed) 或 .connect(Callable(self, "method"))
						var paren_start := line.find("(", dot_idx)
						var paren_end := _find_matching_paren(line, paren_start)
						if paren_end < 0:
							continue
						var args_str := line.substr(paren_start + 1, paren_end - paren_start - 1)
						var method_name := ""
						if args_str.begins_with("Callable("):
							# Callable(self, "method_name")
							var parts := args_str.substr(9).split(",")
							if parts.size() >= 2:
								method_name = parts[1].strip_edges().strip_edges('"').strip_edges("'")
						else:
							# 直接方法名 .connect(method_name)
							method_name = args_str.strip_edges().strip_edges('"').strip_edges("'")

						if method_name.is_empty():
							continue
						var pair_key := sig_candidate + "->" + method_name
						if seen_pairs.has(pair_key):
							continue
						seen_pairs[pair_key] = true
						result.append({
							"signal": sig_candidate if sig_candidate.is_empty() else sig_candidate,
							"target": {"node": "(" + entry.path.get_file().get_basename() + ")", "method": method_name},
							"source": "script (" + entry.path.get_file() + ":" + str(line_idx + 1) + ")",
						})

		# ---- 2. Inspector 连接（从 .tscn 的 [connection] 段解析） ----
		if root and not root.scene_file_path.is_empty():
			var node_rel_path := str(root.get_path_to(node))
			var f_tscn := FileAccess.open(root.scene_file_path, FileAccess.READ)
			if f_tscn:
				var tscn_content := f_tscn.get_as_text()
				f_tscn.close()
				for line in tscn_content.split("
"):
					line = line.strip_edges()
					if not line.begins_with("[connection "):
						continue
					var sig_name := _extract_tscn_attr(line, "signal")
					var from_path := _extract_tscn_attr(line, "from")
					var to_path := _extract_tscn_attr(line, "to")
					var method := _extract_tscn_attr(line, "method")
					if sig_name.is_empty() or method.is_empty():
						continue
					if from_path == node_rel_path:
						result.append({
							"signal": sig_name,
							"target": {"node": to_path if to_path and to_path != "." else "(root)", "method": method},
							"source": "editor (inspector)",
						})

		# ---- 3. 运行时连接（get_signal_connection_list）----
		for sig in node.get_signal_list():
			var sig_name: String = sig["name"]
			var conns := node.get_signal_connection_list(sig_name)
			for c in conns:
				var target_obj = c.get("callable", null)
				if target_obj == null:
					continue
				var target_info := _describe_callable(target_obj)
				var pair_key := sig_name + "->" + target_info.get("method", "?")
				# 去重：避免和静态分析重复
				var already_seen := false
				for r in result:
					if r.get("signal") == sig_name and r.get("target", {}).get("method") == target_info.get("method", "?"):
						already_seen = true
						break
				if not already_seen:
					result.append({
						"signal": sig_name,
						"target": target_info,
						"source": "runtime",
					})

		# ---- 4. 传入连接 ----
		for inc in node.get_incoming_connections():
			var src_signal: String = inc.get("signal_name", "?")
			var target_callable = inc.get("callable", null)
			var ti := _describe_callable(target_callable)
			result.append({
				"signal": src_signal,
				"target": {"node": node.name, "method": ti.get("method", "?")},
				"direction": "incoming",
				"source": "incoming",
			})

		if result.is_empty():
			return _ok("(no signal connections found on '%s')" % node.name)

		var lines: Array = []
		lines.append("Signal connections on '%s' (%d total):" % [node.name, result.size()])
		for r in result:
			var sig: String = r.get("signal", "?")
			var tgt: Dictionary = r.get("target", {})
			if r.get("direction") == "incoming":
				lines.append("  ← %s.%s  [incoming]" % [tgt.get("node", "?"), tgt.get("method", "?")])
			else:
				var src := r.get("source", "?")
				lines.append("  %s → %s.%s  [%s]" % [sig, tgt.get("node", "?"), tgt.get("method", "?"), src])
		return _ok("
".join(lines))


	## 找匹配的右括号
	func _find_matching_paren(line: String, open_idx: int) -> int:
		var depth := 0
		for i in range(open_idx, line.length()):
			var ch := line[i]
			if ch == '(':
				depth += 1
			elif ch == ')':
				depth -= 1
				if depth == 0:
					return i
		return -1


	## 从 [connection signal="x" from="y" to="z" method="w"] 中提取属性值
	func _extract_tscn_attr(line: String, attr: String) -> String:
		var search := attr + '="'
		var start := line.find(search)
		if start < 0:
			return ""
		start += search.length()
		var end := line.find('"', start)
		if end < 0:
			return ""
		return line.substr(start, end - start)


	## 递归收集节点上的脚本路径
	func _collect_scripts(node: Node, out: Array) -> void:
		var script = node.get_script()
		if script != null and not script.resource_path.is_empty():
			var path = script.resource_path
			# 去重
			var already := false
			for entry in out:
				if entry.path == path:
					already = true
					break
			if not already:
				out.append({"path": path, "type": "gd"})
		for child in node.get_children():
			_collect_scripts(child, out)


	## 将 Callable 描述为可读信息
	func _describe_callable(c: Variant) -> Dictionary:
		if c == null:
			return {"node": "?", "method": "?"}
		var s := str(c)
		# Godot 4 Callable 的字符串格式: "NodeName::method_name"
		if s.contains("::"):
			var parts := s.split("::")
			return {"node": parts[0].trim_prefix("<").trim_suffix(">"), "method": parts[1]}
		return {"node": "?", "method": s}# ============ 辅助 ============

func _resolve_node(path: String) -> Node:
	var ei = _ei()
	if ei == null:
		return null
	var root = ei.get_edited_scene_root()
	if root == null:
		return null
	# 根节点自身的几种写法
	if path.is_empty() or path == "." or path == "/":
		return root
	# AI 经常用根节点名(比如 "MainMenu")访问,has_node 不认 self
	if path == root.name:
		return root
	if not root.has_node(path):
		return null
	return root.get_node(path)


func _serialize_node(node: Node, max_depth: int, current_depth: int) -> Dictionary:
	var data := {
		"name": node.name,
		"type": node.get_class(),
		"script": (node.get_script().resource_path if node.get_script() else ""),
	}
	if max_depth > 0 and current_depth < max_depth:
		var children := []
		for child in node.get_children():
			children.append(_serialize_node(child, max_depth, current_depth + 1))
		if not children.is_empty():
			data["children"] = children
	return data


func _reown(node: Node, root: Node) -> void:
	if node == root:
		return
	node.owner = root
	for child in node.get_children():
		_reown(child, root)


func _emit_change() -> void:
	var ei = _ei()
	if ei == null:
		return
	var root = ei.get_edited_scene_root()
	if root == null:
		return
	if root.scene_file_path.is_empty():
		_log_act("log_warning", "Scene has no file path (new scene). Save it manually first.")
		return
	# 保存前先备份磁盘上的旧版本，这样 undo_last 能找到备份
	_get_backup().backup(root.scene_file_path)
	ei.call_deferred("save_scene")
	_log_act("log_info", "✅ Auto-saved: " + root.scene_file_path)
	_logger.append("SCENE", "Auto-saved: " + root.scene_file_path)


func _type_name(v: Variant) -> String:
	if v == null:
		return "null"
	return type_string(typeof(v))
