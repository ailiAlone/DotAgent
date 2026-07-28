extends SceneTree
## 验证本轮改动的脚本都能编译 + 面板增量更新行为
## 运行: godot --headless --script tests/test_ui_compile.gd

const PATHS := [
	"res://addons/dotagent/banyan_agent/tree/agent_node.gd",
	"res://addons/dotagent/plugin.gd",
	"res://addons/dotagent/banyan_agent/ui/banyan_bottom_panel.gd",
	"res://addons/dotagent/banyan_agent/ui/CustomNode/custom_node.gd",
	"res://addons/dotagent/banyan_agent/ui/connection_overlay.gd",
]

var _failed := 0

func _init():
	for p in PATHS:
		var s = load(p)
		if s == null:
			_failed += 1
			print("  [FAIL] %s" % p)
		else:
			print("  [PASS] %s" % p)
	# 场景测试推迟到首帧 — _init 阶段 SceneTree 尚未就绪
	_scene_tests.call_deferred()


func _scene_tests() -> void:
	var panel_scene = load("res://addons/dotagent/banyan_agent/ui/banyan_bottom_panel.tscn")
	if panel_scene == null:
		_failed += 1
		print("  [FAIL] banyan_bottom_panel.tscn load")
		_finish()
		return

	var panel = panel_scene.instantiate()
	if panel == null:
		_failed += 1
		print("  [FAIL] banyan_bottom_panel.tscn instantiate")
		_finish()
		return
	root.add_child(panel)

	# 第一次更新：Dictionary 数据驱动
	panel.update_tree({
		"root_id": "Root", "root_state": "RUNNING", "rounds": 3,
		"files": [], "ctx_size": 100, "domain_knowledge": "", "history": [],
		"children": {
			"A": {"state": "RUNNING", "rounds": 1, "files": [], "ctx_size": 50,
				"domain_knowledge": "", "history": [], "children": {}},
		},
	})
	var node_a = panel._graph.get_node_or_null("A")
	if node_a == null:
		_failed += 1
		print("  [FAIL] node A created")

	# 第二次更新：结构不变 — 节点实例必须保持，状态就地更新
	panel.update_tree({
		"root_id": "Root", "root_state": "RUNNING", "rounds": 4,
		"files": [], "ctx_size": 120, "domain_knowledge": "", "history": [],
		"children": {
			"A": {"state": "COMPLETED", "rounds": 2, "files": [], "ctx_size": 60,
				"domain_knowledge": "", "history": [], "children": {}},
		},
	})
	var node_a2 = panel._graph.get_node_or_null("A")
	if node_a != null and node_a == node_a2 and node_a2.agent_state == "COMPLETED":
		print("  [PASS] incremental update keeps node instance, updates state")
	else:
		_failed += 1
		print("  [FAIL] incremental update (kept: %s)" % [node_a == node_a2])

	# 第三次更新：新增子节点 — 结构变化，B 出现且 A 不被重建
	panel.update_tree({
		"root_id": "Root", "root_state": "RUNNING", "rounds": 5,
		"files": [], "ctx_size": 130, "domain_knowledge": "", "history": [],
		"children": {
			"A": {"state": "COMPLETED", "rounds": 2, "files": [], "ctx_size": 60,
				"domain_knowledge": "", "history": [], "children": {}},
			"B": {"state": "RUNNING", "rounds": 1, "files": [], "ctx_size": 10,
				"domain_knowledge": "", "history": [], "children": {}},
		},
	})
	if panel._graph.get_node_or_null("B") != null and panel._graph.get_node_or_null("A") == node_a:
		print("  [PASS] structure change adds node B, keeps A")
	else:
		_failed += 1
		print("  [FAIL] structure change handling")

	# 第四次更新：A 消失 — 节点应被移除
	panel.update_tree({
		"root_id": "Root", "root_state": "COMPLETED", "rounds": 6,
		"files": [], "ctx_size": 140, "domain_knowledge": "", "history": [],
		"children": {
			"B": {"state": "COMPLETED", "rounds": 3, "files": [], "ctx_size": 20,
				"domain_knowledge": "", "history": [], "children": {}},
		},
	})
	await process_frame  # queue_free 需要一帧生效
	if panel._graph.get_node_or_null("A") == null and panel._graph.get_node_or_null("B") != null:
		print("  [PASS] removed node A disappears, B stays")
	else:
		_failed += 1
		print("  [FAIL] node removal")

	panel.queue_free()

	# ============ 状态颜色独立性测试 ============
	# 两个不同状态的节点必须显示不同颜色（共享 StyleBox 回归）
	var node_scene = load("res://addons/dotagent/banyan_agent/ui/CustomNode/custom_node.tscn")
	var n_running = node_scene.instantiate()
	var n_done = node_scene.instantiate()
	var n_failed = node_scene.instantiate()
	root.add_child(n_running)
	root.add_child(n_done)
	root.add_child(n_failed)
	n_running.configure("R", "RUNNING", 1, Color.WHITE)
	n_done.configure("C", "COMPLETED", 2, Color.WHITE)
	n_failed.configure("F", "FAILED", 3, Color.WHITE)
	var s_running: StyleBoxFlat = n_running.panel_container.get_theme_stylebox("panel")
	var s_done: StyleBoxFlat = n_done.panel_container.get_theme_stylebox("panel")
	var s_failed: StyleBoxFlat = n_failed.panel_container.get_theme_stylebox("panel")
	if s_running != s_done and s_done != s_failed:
		print("  [PASS] each node owns an independent stylebox")
	else:
		_failed += 1
		print("  [FAIL] styleboxes are shared across nodes")
	if s_running.border_color != s_done.border_color \
		and s_done.border_color != s_failed.border_color \
		and s_running.border_color != s_failed.border_color:
		print("  [PASS] RUNNING/COMPLETED/FAILED have distinct colors")
	else:
		_failed += 1
		print("  [FAIL] state colors not distinct: %s %s %s" % [s_running.border_color, s_done.border_color, s_failed.border_color])
	# 状态切换时颜色就地更新
	n_running.configure("R", "COMPLETED", 4, Color.WHITE)
	if s_running.border_color == s_done.border_color:
		print("  [PASS] state change updates color in place")
	else:
		_failed += 1
		print("  [FAIL] state change color update")
	n_running.queue_free()
	n_done.queue_free()
	n_failed.queue_free()

	_finish()


func _finish() -> void:
	print("=== %s ===" % ("ALL PASS" if _failed == 0 else "%d FAILED" % _failed))
	quit(0 if _failed == 0 else 1)
