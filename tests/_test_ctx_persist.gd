extends SceneTree
## 验证 ctx_size 随树持久化：注入值 → save → load → get_ctx_size 应恢复
## 运行前请备份 agent_tree.json，运行后恢复

const AgentTreeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_tree.gd")


func _initialize() -> void:
	var t = AgentTreeScript.new(null)
	t.load()
	var root_n = t.get_all_nodes().get("Root")
	if root_n == null:
		print("[FAIL] no Root node")
		quit(1)
		return
	root_n._persisted_ctx_size = 12345
	if not t.save():
		print("[FAIL] save")
		quit(1)
		return

	var t2 = AgentTreeScript.new(null)
	t2.load()
	var r2 = t2.get_all_nodes().get("Root")
	var got: int = r2.get_ctx_size()
	print("ctx after reload: %d (expect 12345)" % got)
	print("[PASS]" if got == 12345 else "[FAIL]")
	quit(0 if got == 12345 else 1)
