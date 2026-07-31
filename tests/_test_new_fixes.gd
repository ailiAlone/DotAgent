@tool
extends SceneTree
## 临时验证：2026-07-31 一致性修复
## 1. skills 关键词注入（_match_skills）
## 2. 全深度树重载（Root → A → B 孙节点挂接）
## 运行: godot --headless --path <project> --script res://tests/_test_new_fixes.gd

const AgentNodeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_node.gd")
const AgentTreeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_tree.gd")

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	_test_skills_injection()
	_test_full_depth_restore()
	print("=== Results: %d/%d passed ===" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)


func _t(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s" % name)


func _test_skills_injection() -> void:
	var node = AgentNodeScript.new()

	var msg_2d: String = node._match_skills("给玩家加一个 2D platformer 跳跃功能")
	_t("2d task injects 2d_game.md", msg_2d.contains("2D 游戏领域知识"))

	var msg_ui: String = node._match_skills("添加一个设置菜单系统 settings menu")
	_t("ui task injects ui_scene.md", msg_ui.contains("UI 场景领域知识"))

	var msg_none: String = node._match_skills("zqwxv 无意义字符串不会命中任何关键词")
	_t("unrelated task injects nothing", msg_none.is_empty())


func _test_full_depth_restore() -> void:
	# 构造三层树：Root → A → B（B 是孙节点）
	var tree = AgentTreeScript.new()
	var root = tree.ensure_root("Root")
	var a = AgentNodeScript.new()
	a.node_id = "A"
	a.parent_id = "Root"
	var b = AgentNodeScript.new()
	b.node_id = "B"
	b.parent_id = "A"
	tree.upsert_node(a)
	tree.upsert_node(b)

	# 复刻 plugin.gd 的全深度恢复逻辑
	var all_nodes: Dictionary = tree.get_all_nodes()
	for nid in all_nodes:
		var n = all_nodes[nid]
		if n.node_id == root.node_id or n.parent_id.is_empty():
			continue
		var parent = all_nodes.get(n.parent_id)
		if parent == null:
			continue
		parent._children[n.node_id] = n
		n._parent_ref = weakref(parent)
		parent._pending_children[n.node_id] = true

	_t("Root has direct child A", root._children.has("A"))
	_t("A has grandchild B restored", a._children.has("B"))
	_t("B parent_ref chain alive", b._parent_ref.get_ref() == a)

	# collect_runtime_nodes 递归收集后树应保持 3 节点
	var tree2 = AgentTreeScript.new()
	tree2.ensure_root("Root")
	tree2._nodes["Root"] = root
	tree2.collect_runtime_nodes(root)
	_t("collect_runtime_nodes keeps all 3 nodes", tree2.get_node_count() == 3)
