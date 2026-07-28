extends SceneTree
## 验证本轮修改的三个文件是否能正常编译和解析

func _init():
	var results: Array = []

	results.append(_test_agent_node_compiles())
	results.append(_test_plugin_compiles())
	results.append(_test_node_tools_json())
	results.append(_test_node_prompt_exists())
	results.append(_test_list_files_available())

	var json: String = JSON.stringify({"tests": results}, "\t")
	var f: FileAccess = FileAccess.open("res://tests/results.json", FileAccess.WRITE)
	f.store_string(json)
	f.close()

	var passed: int = results.filter(func(r: Dictionary): return r.ok).size()
	var total: int = results.size()
	print("=== Results: %d/%d passed ===" % [passed, total])
	for r in results:
		var status: String = "PASS" if r.ok else "FAIL"
		print("  [%s] %s" % [status, r.name])
		if not r.ok:
			print("         ", r.detail)

	quit(0 if passed == total else 1)


func _test_agent_node_compiles() -> Dictionary:
	var script: GDScript = load("res://addons/dotagent/banyan_agent/tree/agent_node.gd") as GDScript
	if script == null:
		return {"name": "agent_node.gd compiles", "ok": false, "detail": "Failed to load script"}

	# 验证实例化
	var node = AgentNode.new()
	if node == null:
		return {"name": "agent_node.gd compiles", "ok": false, "detail": "Failed to instantiate AgentNode"}

	# 验证新增的 _read_files 变量存在
	if not node.has_method("execute_tool"):
		return {"name": "agent_node.gd compiles", "ok": false, "detail": "execute_tool method missing"}

	# 检查 _read_files 属性
	node.set("_read_files", ["test.gd"])
	var read_files: Array = node.get("_read_files")
	if read_files.size() != 1 or read_files[0] != "test.gd":
		return {"name": "agent_node.gd compiles", "ok": false, "detail": "_read_files property not working"}

	return {"name": "agent_node.gd compiles + _read_files", "ok": true, "detail": "OK"}


func _test_plugin_compiles() -> Dictionary:
	var script: GDScript = load("res://addons/dotagent/plugin.gd") as GDScript
	if script == null:
		return {"name": "plugin.gd compiles", "ok": false, "detail": "Failed to load plugin.gd"}
	return {"name": "plugin.gd compiles", "ok": true, "detail": "OK"}


func _test_node_tools_json() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://addons/dotagent/banyan_agent/tools/definitions/node_tools.json", FileAccess.READ)
	if f == null:
		return {"name": "node_tools.json valid", "ok": false, "detail": "Cannot open file"}

	var content: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		return {"name": "node_tools.json valid", "ok": false, "detail": "JSON parse error"}

	if not parsed is Dictionary:
		return {"name": "node_tools.json valid", "ok": false, "detail": "Expected Dictionary"}

	var tools: Array = parsed.get("tools", [])
	var tool_names: Array = []
	for t in tools:
		tool_names.append(t.get("function", {}).get("name", ""))

	# 验证新增的发现工具
	var required_new: Array = ["list_files", "list_scenes", "list_resources", "read_multiple_files"]
	var missing: Array = []
	for name in required_new:
		if name not in tool_names:
			missing.append(name)

	if not missing.is_empty():
		return {"name": "node_tools.json valid", "ok": false, "detail": "Missing tools: %s" % ", ".join(missing)}

	return {"name": "node_tools.json valid (has %d tools including new discovery tools)" % tools.size(), "ok": true, "detail": "OK"}


func _test_node_prompt_exists() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://addons/dotagent/banyan_agent/prompts/node_prompt.md", FileAccess.READ)
	if f == null:
		return {"name": "node_prompt.md content", "ok": false, "detail": "Cannot open file"}

	var content: String = f.get_as_text()
	f.close()

	var checks: Array = ["What NOT to Do", "list_files", "Discovery", "Do NOT plan a decomposition", "Do NOT name children after roles"]
	var missing: Array = []
	for check in checks:
		if check not in content:
			missing.append(check)

	if not missing.is_empty():
		return {"name": "node_prompt.md content", "ok": false, "detail": "Missing sections: %s" % ", ".join(missing)}

	return {"name": "node_prompt.md content", "ok": true, "detail": "All required sections present"}


func _test_list_files_available() -> Dictionary:
	# 验证 list_files 工具在 Legacy ToolRegistry 中可用
	var ToolRegistry = load("res://addons/dotagent/tools/tool_registry.gd")
	if ToolRegistry == null:
		return {"name": "list_files in ToolRegistry", "ok": false, "detail": "Cannot load ToolRegistry"}

	# 尝试加载 file_tools 模块
	var FileTools = load("res://addons/dotagent/tools/file_tools.gd")
	if FileTools == null:
		return {"name": "list_files in ToolRegistry", "ok": false, "detail": "Cannot load file_tools.gd"}

	var ft = FileTools.new()
	var defs: Array = ft.get_tool_definitions()
	var tool_names: Array = []
	for d in defs:
		tool_names.append(d.get("name", ""))

	if "list_files" not in tool_names:
		return {"name": "list_files in ToolRegistry", "ok": false, "detail": "list_files not in tool definitions"}

	return {"name": "list_files in ToolRegistry", "ok": true, "detail": "list_files is registered in file_tools.gd"}
