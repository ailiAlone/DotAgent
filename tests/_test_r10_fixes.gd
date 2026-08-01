@tool
extends SceneTree
## 验证 2026-08-01 R10 诊断修复:
## 1. configure_project input_actions — "action" 别名兼容 + 持久化到 ProjectSettings
## 2. execute_tool 本轮重复读取短路（拦截 + force 绕过 + 写后重读放行）
## 3. _build_delegation_hint 开局分工提示（命中点名 / 无子节点为空）
## 运行: godot --headless --path <project> --script res://tests/_test_r10_fixes.gd

const AgentNodeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_node.gd")
const ConfigTools = preload("res://addons/dotagent/tools/configuration_tools.gd")

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	_test_configure_project_alias_persist()
	_test_reread_shortcircuit()
	_test_delegation_hint()
	_test_jurisdiction_note()
	_test_as_array_lenient()
	_test_auto_claim_respects_ancestors()
	_test_jurisdiction_write_note()
	_test_script_property_safe()
	_test_scene_text_surgery_blocked()
	_test_find_uncovered_files()
	_test_partial_reread_and_lenient_array()
	print("=== Results: %d/%d passed ===" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)


func _t(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s" % name)


func _test_configure_project_alias_persist() -> void:
	# 会写 project.godot — 先备份，测完原样恢复
	var backup: String = FileAccess.get_file_as_string("res://project.godot")
	var module = ConfigTools.new()

	# 用模型爱用的 "action" 别名提交（此前连续失败 2 轮的元凶）
	var r1: Dictionary = module.call("_tool_configure_project", {
		"input_actions": {"add": [{"action": "test_alias_sprint", "deadzone": 0.3,
			"events": [{"type": "key", "keycode": "KEY_SHIFT"}]}]}})
	_t("alias 'action' 被接受 (ok)", r1.get("ok", false))
	_t("applied 含 input_add", "input_add:test_alias_sprint" in str(r1.get("content", "")))
	_t("InputMap 生效", InputMap.has_action("test_alias_sprint"))
	_t("持久化到 ProjectSettings", ProjectSettings.has_setting("input/test_alias_sprint"))

	# 清理：remove 同时清 InputMap 和 ProjectSettings
	var r2: Dictionary = module.call("_tool_configure_project", {
		"input_actions": {"remove": ["test_alias_sprint"]}})
	_t("remove ok", r2.get("ok", false))
	_t("ProjectSettings 已清除", not ProjectSettings.has_setting("input/test_alias_sprint"))

	# 缺 name/action 时报错且带示例
	var r3: Dictionary = module.call("_tool_configure_project", {
		"input_actions": {"add": [{"events": []}]}})
	_t("缺 name 报错", not r3.get("ok", false))
	_t("错误信息含示例", "KEY_SHIFT" in str(r3.get("content", "")))

	# 大小写宽容："Key"（R13 实测模型写法）也应解析出按键
	var r4: Dictionary = module.call("_tool_configure_project", {
		"input_actions": {"add": [{"name": "test_case_key", "events": [{"type": "Key", "keycode": 67}]}]}})
	_t("大写 Key 被接受 (ok)", r4.get("ok", false))
	_t("大写 Key 无警告", "未能解析" not in str(r4.get("content", "")))
	var ev4: Array = ProjectSettings.get_setting("input/test_case_key", {}).get("events", [])
	_t("大写 Key 按键已持久化", ev4.size() == 1)
	module.call("_tool_configure_project", {"input_actions": {"remove": ["test_case_key"]}})

	# class 风格："InputEventKey" 也应识别
	var r5: Dictionary = module.call("_tool_configure_project", {
		"input_actions": {"add": [{"name": "test_class_key", "events": [{"class": "InputEventKey", "keycode": 67}]}]}})
	var ev5: Array = ProjectSettings.get_setting("input/test_class_key", {}).get("events", [])
	_t("class 风格按键已持久化", ev5.size() == 1)
	module.call("_tool_configure_project", {"input_actions": {"remove": ["test_class_key"]}})

	# events 全部无法解析 → ok 但带警告（不再静默成功）
	var r6: Dictionary = module.call("_tool_configure_project", {
		"input_actions": {"add": [{"name": "test_bad_ev", "events": [{"type": "gamepad_button"}]}]}})
	_t("无法解析时仍 ok", r6.get("ok", false))
	_t("无法解析时带警告", "未能解析" in str(r6.get("content", "")))
	module.call("_tool_configure_project", {"input_actions": {"remove": ["test_bad_ev"]}})

	# 恢复 project.godot 磁盘内容
	var f := FileAccess.open("res://project.godot", FileAccess.WRITE)
	f.store_string(backup)
	f.close()


func _test_reread_shortcircuit() -> void:
	var node = AgentNodeScript.new()
	node.node_id = "TestNode"
	node._round_count = 3
	# 模拟本轮已全量读过 player.gd（第 1 轮）
	node._read_this_run["res://scripts/player.gd"] = {"round": 1, "full": true}

	# 重复读 → 短路拦截，不进 registry（registry 为 null，若放行会报 not available）
	var r1: Dictionary = await node.execute_tool("read_script", '{"path": "res://scripts/player.gd"}')
	_t("重复读取被拦截 (ok=true)", r1.get("ok", false))
	_t("拦截提示含轮次", "第 1 轮" in str(r1.get("content", "")))

	# force=true → 绕过短路，落到 registry（null → 报 not available，证明没被拦）
	var r2: Dictionary = await node.execute_tool("read_script", '{"path": "res://scripts/player.gd", "force": true}')
	_t("force 绕过短路", "not available" in str(r2.get("content", "")))

	# 写后重读 → 放行
	node._written_this_run.append("res://scripts/player.gd")
	var r3: Dictionary = await node.execute_tool("read_script", '{"path": "res://scripts/player.gd"}')
	_t("写后重读放行", "not available" in str(r3.get("content", "")))
	node._written_this_run.clear()

	# 残篇读（full=false）后全量重读 → 放行（拿全内容是正当需求）
	node._read_this_run["res://scripts/enemy.gd"] = {"round": 1, "full": false}
	var r3b: Dictionary = await node.execute_tool("read_script", '{"path": "res://scripts/enemy.gd"}')
	_t("残篇后全量读放行", "not available" in str(r3b.get("content", "")))

	# read_multiple_files 全部重复 → 拦截；部分重复 → 放行
	node._read_this_run["res://scripts/hud.gd"] = {"round": 2, "full": true}
	var r4: Dictionary = await node.execute_tool("read_multiple_files",
		'{"paths": ["res://scripts/player.gd", "res://scripts/hud.gd"]}')
	_t("批量读全重复被拦截", r4.get("ok", false) and "拦截" in str(r4.get("content", "")))
	var r5: Dictionary = await node.execute_tool("read_multiple_files",
		'{"paths": ["res://scripts/player.gd", "res://scripts/new_file.gd"]}')
	_t("批量读含新文件放行", "not available" in str(r5.get("content", "")))


func _test_jurisdiction_note() -> void:
	var root = AgentNodeScript.new()
	root.node_id = "Root"
	var ui = AgentNodeScript.new()
	ui.node_id = "Ui"
	ui.managed_files.append("res://scripts/hud.gd")
	root._children["Ui"] = ui

	# 读到子节点管辖文件 → 生成提醒
	var note: String = root._jurisdiction_note(["res://scripts/hud.gd"])
	_t("管辖提醒含子节点名", "Ui" in note and "管辖" in note)
	# 读非管辖文件 → 无提醒
	_t("非管辖文件无提醒", root._jurisdiction_note(["res://scripts/other.gd"]).is_empty())
	# 无子节点 → 无提醒
	var lone = AgentNodeScript.new()
	_t("无子节点无提醒", lone._jurisdiction_note(["res://scripts/hud.gd"]).is_empty())


func _test_as_array_lenient() -> void:
	var module = ConfigTools.new()
	# 纯 JSON 字符串
	_t("纯 JSON 字符串解析", module._as_array('[{"op": "add"}]').size() == 1)
	# markdown 包裹（模型高频错误）
	var wrapped: String = "```json\n[{\"op\": \"add\", \"name\": \"X\"}]\n```"
	_t("markdown 包裹宽容解析", module._as_array(wrapped).size() == 1)
	# 散文前缀
	_t("散文前缀宽容解析", module._as_array('Here are ops: [{"op": "set"}] done').size() == 1)
	# 真数组原样返回
	_t("真数组原样返回", module._as_array([{"op": "add"}]).size() == 1)
	# 垃圾输入返回空
	_t("垃圾输入返回空", module._as_array("no array here").is_empty())


func _test_delegation_hint() -> void:
	var root = AgentNodeScript.new()
	root.node_id = "Root"
	# 无子节点 → 无提示
	_t("无子节点无提示", root._build_delegation_hint("给 HUD 加冲刺显示").is_empty())

	var ui = AgentNodeScript.new()
	ui.node_id = "Ui"
	ui.managed_files.append("res://scripts/hud.gd")
	ui.managed_files.append("res://scenes/hud.tscn")
	root._children["Ui"] = ui

	# 任务提到 "HUD"（文件名 hud 词干命中，大小写不敏感）
	var hint_hit: String = root._build_delegation_hint("在 HUD 上显示冲刺状态文本")
	_t("命中时提示含子节点名", "Ui" in hint_hit)
	_t("命中时点名文件", "命中" in hint_hit and "hud" in hint_hit.to_lower())
	_t("命中时要求先委派", "route_to_child" in hint_hit)

	# 任务不涉及子节点文件 → 仍有紧凑管辖表但不点名
	var hint_miss: String = root._build_delegation_hint("给敌人加一个新行为")
	_t("未命中仍有管辖表", "Ui" in hint_miss and "Delegation Map" in hint_miss)
	_t("未命中不点名", "命中" not in hint_miss)


func _test_auto_claim_respects_ancestors() -> void:
	# 爷孙三代：Root 管辖 game.gd；Ui 是 Root 子节点
	var root = AgentNodeScript.new()
	root.node_id = "Root"
	root.managed_files.append("res://scripts/game.gd")
	var ui = AgentNodeScript.new()
	ui.node_id = "Ui"
	ui._parent_ref = weakref(root)

	# Ui 本轮"写"了 game.gd（代笔）+ 创建了全新的 new_widget.gd
	ui._files_created.append("res://scripts/game.gd")
	ui._files_created.append("res://scripts/new_widget.gd")
	ui._auto_claim_files()

	_t("代笔文件不认领", "res://scripts/game.gd" not in ui.managed_files)
	_t("新地盘正常认领", "res://scripts/new_widget.gd" in ui.managed_files)

	# 无父节点的 Root：全部认领
	var lone = AgentNodeScript.new()
	lone._files_created.append("res://scripts/anything.gd")
	lone._auto_claim_files()
	_t("Root 无祖先全认领", "res://scripts/anything.gd" in lone.managed_files)


func _test_jurisdiction_write_note() -> void:
	var root = AgentNodeScript.new()
	root.node_id = "Root"
	var ui = AgentNodeScript.new()
	ui.node_id = "Ui"
	ui.managed_files.append("res://scripts/hud.gd")
	ui.managed_files.append("res://scenes/hud.tscn")
	root._children["Ui"] = ui

	# 子节点独占管辖 → 强告诫
	var strong_note: String = root._jurisdiction_write_note(["res://scripts/hud.gd"])
	_t("写子节点独占文件强告诫", "管辖告诫" in strong_note and "route_to_child" in strong_note)

	# 自己也管辖（重叠）→ 降级为一致性提示
	root.managed_files.append("res://scenes/hud.tscn")
	var overlap_note: String = root._jurisdiction_write_note(["res://scenes/hud.tscn"])
	_t("重叠管辖降级提示", "管辖提示" in overlap_note and "管辖告诫" not in overlap_note)

	# 与子节点无关的文件 → 无告诫
	_t("无关文件无告诫", root._jurisdiction_write_note(["res://scripts/game.gd"]).is_empty())

	# 无子节点 → 无告诫
	var lone = AgentNodeScript.new()
	_t("无子节点写无告诫", lone._jurisdiction_write_note(["res://scripts/hud.gd"]).is_empty())


func _test_script_property_safe() -> void:
	var module = ConfigTools.new()
	# 临时脚本与场景
	var sf := FileAccess.open("res://tests/_tmp_script.gd", FileAccess.WRITE)
	sf.store_string("extends Node2D\n")
	sf.close()
	var cf := FileAccess.open("res://tests/_tmp_scene.tscn", FileAccess.WRITE)
	cf.store_string("[gd_scene format=3]\n\n[node name=\"Tmp\" type=\"Node2D\"]\n")
	cf.close()

	# 1) 字典 {path:...} → 挂接为 GDScript
	var n := Node2D.new()
	_t("dict 路径无错误", module._apply_node_property(n, "script", {"path": "res://tests/_tmp_script.gd"}).is_empty())
	_t("dict 挂接为 GDScript", n.get_script() is GDScript)
	n.free()

	# 2) 字符串路径 → 同样挂接
	var n2 := Node2D.new()
	_t("字符串路径挂接", module._apply_node_property(n2, "script", "res://tests/_tmp_script.gd").is_empty()
		and n2.get_script() is GDScript)
	n2.free()

	# 3) 坏字典（无 path 的 __uuid__）→ 拒绝且不挂接
	var n3 := Node2D.new()
	var err3: String = module._apply_node_property(n3, "script", {"__uuid__": "abc"})
	_t("坏字典被拒绝", not err3.is_empty())
	_t("坏字典未挂接", not (n3.get_script() is GDScript))
	n3.free()

	# 4) 全链路：patch_scene set script → 重载为 GDScript
	var r: Dictionary = module.call("_tool_patch_scene", {"path": "res://tests/_tmp_scene.tscn",
		"operations": [{"op": "set", "node_path": ".", "properties": {"script": {"path": "res://tests/_tmp_script.gd"}}}]})
	_t("patch_scene set script ok", r.get("ok", false))
	var packed = load("res://tests/_tmp_scene.tscn")
	if packed:
		var inst = packed.instantiate()
		_t("重载后 script 为 GDScript", inst.get_script() is GDScript)
		inst.free()
	else:
		_t("重载后 script 为 GDScript", false)

	DirAccess.remove_absolute("res://tests/_tmp_scene.tscn")
	DirAccess.remove_absolute("res://tests/_tmp_script.gd")


func _test_scene_text_surgery_blocked() -> void:
	var module = ConfigTools.new()
	# replace_in_file 拒绝 .tscn
	var st = preload("res://addons/dotagent/tools/script_tools.gd").new()
	var r1: Dictionary = st.call("_tool_replace_in_file", {"path": "res://scenes/hud.tscn",
		"old_text": "x", "new_text": "y"})
	_t("replace_in_file 拒绝 .tscn", not r1.get("ok", false))
	_t("拒绝信息指向 patch_scene", "patch_scene" in str(r1.get("content", "")))
	# .gd 不受影响（文件不存在错误证明通过了场景检查）
	var r2: Dictionary = st.call("_tool_replace_in_file", {"path": "res://scripts/_nonexist_xyz.gd",
		"old_text": "x", "new_text": "y"})
	_t(".gd 正常流程（报文件不存在）", "not found" in str(r2.get("content", "")).to_lower())

	# patch_scene set 回读：临时场景验证 readback 字段
	var cf := FileAccess.open("res://tests/_tmp_scene2.tscn", FileAccess.WRITE)
	cf.store_string("[gd_scene format=3]\n\n[node name=\"Tmp\" type=\"Node2D\"]\n")
	cf.close()
	var r3: Dictionary = module.call("_tool_patch_scene", {"path": "res://tests/_tmp_scene2.tscn",
		"operations": [{"op": "set", "node_path": ".", "properties": {"visible": true}}]})
	_t("patch_scene 含 readback", "readback" in str(r3.get("content", "")))
	DirAccess.remove_absolute("res://tests/_tmp_scene2.tscn")


func _test_find_uncovered_files() -> void:
	var root = AgentNodeScript.new()
	root.node_id = "Root"
	root.managed_files.append("res://scripts/game.gd")
	var ui = AgentNodeScript.new()
	ui.node_id = "Ui"
	ui.managed_files.append("res://scripts/hud.gd")
	root._children["Ui"] = ui

	root._read_files.append("res://scripts/game.gd")        # 自己的
	root._read_files.append("res://scripts/hud.gd")         # Ui 的
	root._read_files.append("res://scripts/powerup.gd")     # 无人管辖
	root._files_created.append("res://scripts/magnet_powerup.gd")  # 新建无人管辖

	var unc: Array = root._find_uncovered_files()
	_t("无人管辖文件被识别", unc.size() == 2
		and "res://scripts/powerup.gd" in unc
		and "res://scripts/magnet_powerup.gd" in unc)
	_t("自己/子节点文件不算", "res://scripts/game.gd" not in unc
		and "res://scripts/hud.gd" not in unc)


func _test_partial_reread_and_lenient_array() -> void:
	# 同工具残篇复读 → 拦截；换工具拿全量 → 放行
	var node = AgentNodeScript.new()
	node.node_id = "TestNode2"
	node._round_count = 5
	node._read_this_run["res://scripts/hud.gd"] = {"round": 2, "full": false, "tool": "read_file_tail"}
	var r1: Dictionary = await node.execute_tool("read_file_tail", '{"path": "res://scripts/hud.gd", "max_lines": 100}')
	_t("同工具残篇复读被拦截", r1.get("ok", false) and "拦截" in str(r1.get("content", "")))
	var r2: Dictionary = await node.execute_tool("read_script", '{"path": "res://scripts/hud.gd"}')
	_t("换工具拿全量放行", "not available" in str(r2.get("content", "")))

	# _as_array 宽容重试 2：字符串值里混入原始换行
	var module = ConfigTools.new()
	var messy: String = "[{\"op\": \"set\", \"properties\": {\"text\": \"line1\nline2\"}}]"
	_t("含原始换行的数组字符串可解析", module._as_array(messy).size() == 1)
