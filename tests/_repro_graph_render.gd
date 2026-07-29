extends SceneTree
## 可视化复现：真实渲染 Agent Graph 并截图，验证连线是否实际画出。
## 模拟编辑器重载场景：面板不可见时就收到 update_tree（底部面板初始隐藏），
## 之后再显示 — 连线丢失若与可见性/时序有关，这里会暴露。
## 运行（不要加 --headless）:
##   godot --path <project> --script res://tests/_repro_graph_render.gd

const AgentTreeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_tree.gd")
const PanelScene = preload("res://addons/dotagent/banyan_agent/ui/banyan_bottom_panel.tscn")


func _initialize() -> void:
	call_deferred("_main")


func _main() -> void:
	var agent_tree = AgentTreeScript.new(null)
	agent_tree.load()
	print("[LOAD] nodes=%d root_id=%s" % [agent_tree.get_node_count(), agent_tree.get_root_id()])

	var panel = PanelScene.instantiate()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(1100, 600)
	root.add_child(panel)
	await process_frame
	await process_frame

	# 模拟编辑器重载：底部面板隐藏状态下收到 update_tree
	panel.visible = false
	panel.update_tree(agent_tree)
	for i in 10:
		await process_frame

	# 用户点开底部面板
	panel.visible = true
	for i in 20:
		await process_frame

	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://tests/_repro_shot.png")
	print("[SHOT] saved")
	print("[OVERLAY] visible=%s pos=%s size=%s z=%d" % [
		panel._overlay.visible, panel._overlay.global_position, panel._overlay.size, panel._overlay.z_index])
	print("[GRAPH] pos=%s size=%s scroll=%s zoom=%s" % [
		panel._graph.global_position, panel._graph.size, panel._graph.scroll_offset, panel._graph.zoom])
	print("[CONNECTIONS] %d" % panel._connections.size())
	for conn in panel._connections:
		print("  %s -> %s from_dir=%s to_dir=%s" % [conn.get("from"), conn.get("to"), conn.get("_from_dir", "<none>"), conn.get("_to_dir", "<none>")])
	for child in panel._graph.get_children():
		if child is GraphElement:
			print("  node=%s global_pos=%s size=%s" % [child.name, child.global_position, child.size])

	# 场景 2：编辑器里首次布局会把视图居中到 Root — scroll_offset 非 0，
	# 再叠加用户缩放，验证平移/缩放下连线是否仍然贴着端口
	panel._graph.scroll_offset = Vector2(-300, -200)
	panel._graph.zoom = 0.7
	for i in 10:
		await process_frame
	var img2: Image = root.get_viewport().get_texture().get_image()
	img2.save_png("res://tests/_repro_shot2.png")
	print("[SHOT2] saved (scroll=-300,-200 zoom=0.7)")
	for child in panel._graph.get_children():
		if child is GraphElement:
			print("  node=%s global_pos=%s" % [child.name, child.global_position])

	# 场景 3：运行时自动更新 — 节点内容变化（CTX 数字变长）撑大卡片，
	# scroll/zoom 不变。连线必须跟着端口走，不能冻在旧位置
	panel._graph.scroll_offset = Vector2(0, 0)
	panel._graph.zoom = 1.0
	for i in 5:
		await process_frame
	var root_node = panel._graph.get_node_or_null("Root")
	var size_before: Vector2 = root_node.size if root_node else Vector2.ZERO
	panel.update_tree({
		"root_id": "Root", "root_state": "LLM_REQUEST", "rounds": 99,
		"files": ["res://a.gd", "res://b.gd", "res://c.gd"], "ctx_size": 123456,
		"stream_chars": 7890, "domain_knowledge": "", "history": [],
		"children": {
			"AudioGlobals": {"state": "COMPLETED", "rounds": 5, "files": [], "ctx_size": 50000,
				"domain_knowledge": "", "history": [], "children": {}},
			"PlayerCombat": {"state": "RUNNING", "rounds": 7, "files": ["res://x.gd"], "ctx_size": 98765,
				"domain_knowledge": "", "history": [], "children": {}},
		},
	})
	for i in 15:
		await process_frame
	var size_after: Vector2 = root_node.size if root_node else Vector2.ZERO
	var img3: Image = root.get_viewport().get_texture().get_image()
	img3.save_png("res://tests/_repro_shot3.png")
	print("[SHOT3] saved (content update, root size %s -> %s)" % [size_before, size_after])

	# 场景 4：用户手动拖动节点 — 把 PlayerCombat 拖到 Root 上方（不经过 update_tree），
	# 槽位必须按新的相对位置关系重选（原来 Root.bottom→PlayerCombat.top，应翻转为 Root.top→PlayerCombat.bottom）
	var pc = panel._graph.get_node_or_null("PlayerCombat")
	if pc:
		pc.position_offset = Vector2(400, 60)
	for i in 15:
		await process_frame
	var img4: Image = root.get_viewport().get_texture().get_image()
	img4.save_png("res://tests/_repro_shot4.png")
	for conn in panel._connections:
		if str(conn.get("to")) == "PlayerCombat":
			print("[SHOT4] saved — Root->PlayerCombat from_dir=%s to_dir=%s (期望 top->bottom)" % [conn.get("_from_dir", "?"), conn.get("_to_dir", "?")])

	# 场景 5：缩放状态下拖动节点（用户反馈的偏差场景）— zoom 0.7 + scroll，
	# 把 Root 向右下拖 200px，连线端点必须仍然精确贴边，不能有固定偏差
	panel._graph.scroll_offset = Vector2(-150, -100)
	panel._graph.zoom = 0.7
	var rn = panel._graph.get_node_or_null("Root")
	if rn:
		rn.position_offset += Vector2(200, 150)
	for i in 15:
		await process_frame
	var img5: Image = root.get_viewport().get_texture().get_image()
	img5.save_png("res://tests/_repro_shot5.png")
	print("[SHOT5] saved (zoom=0.7 + drag Root)")

	quit(0)
