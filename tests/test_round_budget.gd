extends SceneTree
## 轮数预算机制功能测试 — 验证"子节点向父级申请，Root 无限"的拨付链
## 运行: godot --headless --script tests/test_round_budget.gd

const AgentNodeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_node.gd")

var _results: Array = []

func _init():
	_test_root_unlimited()
	_test_parent_deducts_own_budget()
	_test_recursive_top_up()
	_test_orphan_denied()
	_test_partial_grant()

	var passed := 0
	for r in _results:
		if r.ok:
			passed += 1
		print("  [%s] %s" % ["PASS" if r.ok else "FAIL", r.name])
	print("=== Results: %d/%d passed ===" % [passed, _results.size()])
	quit(0 if passed == _results.size() else 1)


func _t(name: String, ok: bool) -> void:
	_results.append({"name": name, "ok": ok})


func _make_node(id: String, parent_id: String, budget: int, parent: AgentNode = null) -> AgentNode:
	var n: AgentNode = AgentNodeScript.new()
	n.node_id = id
	n.parent_id = parent_id
	n._round_budget = budget
	if parent:
		n._parent_ref = weakref(parent)
	return n


## Root（预算 -1）无限拨付
func _test_root_unlimited() -> void:
	var root := _make_node("Root", "", -1)
	var g1: int = await root.grant_rounds("A", 10)
	var g2: int = await root.grant_rounds("B", 10)
	_t("root grants unlimited (10+10, stays -1)", g1 == 10 and g2 == 10 and root._round_budget == -1)


## 非 Root 父节点从自己的预算中扣减
func _test_parent_deducts_own_budget() -> void:
	var root := _make_node("Root", "", -1)
	var mid := _make_node("Mid", "Root", 15, root)
	var g: int = await mid.grant_rounds("Child", 10)
	_t("parent deducts own budget (15-10=5)", g == 10 and mid._round_budget == 5)


## 父级预算不足 → 递归向上申请补充后再拨付
func _test_recursive_top_up() -> void:
	var root := _make_node("Root", "", -1)
	var mid := _make_node("Mid", "Root", 3, root)
	var g: int = await mid.grant_rounds("Child", 10)
	# mid 只有 3，差 7 → 向上申请 max(7, GRANT_SIZE)=10 → 13 → 拨付 10 → 剩 3
	_t("parent tops up from grandparent (3→13→3)", g == 10 and mid._round_budget == 3)


## 无父节点引用（孤儿/父链断开）→ 拒绝（0）
func _test_orphan_denied() -> void:
	var orphan := _make_node("Orphan", "Ghost", 0)
	var g: int = await orphan._request_rounds_from_parent()
	_t("orphan request denied (0)", g == 0)


## 父级预算不足且上级也有限 → 部分拨付
func _test_partial_grant() -> void:
	var grand := _make_node("Grand", "Ghost", 0)  # 无更上级，自己也没预算
	var mid := _make_node("Mid", "Grand", 4, grand)
	var g: int = await mid.grant_rounds("Child", 10)
	# mid 有 4 < 10 → 向上申请 → grand 无父 → top_up=0 → 只能拨付 4
	_t("partial grant when chain dry (4/10)", g == 4 and mid._round_budget == 0)
