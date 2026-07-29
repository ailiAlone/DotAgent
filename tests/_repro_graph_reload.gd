extends SceneTree
## 复现"重新加载项目后图无连线 + 名称异常"
## 用真实 agent_tree.json 走 AgentTree 加载路径，检查渲染结果

const AgentTreeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_tree.gd")
const PanelScene = preload("res://addons/dotagent/banyan_agent/ui/banyan_bottom_panel.tscn")


func _initialize() -> void:
	call_deferred("_main")


func _main() -> void:
	var agent_tree = AgentTreeScript.new(null)
	agent_tree.load()
	print("[LOAD] nodes=%d root_id=%s" % [agent_tree.get_node_count(), agent_tree.get_root_id()])

	var panel = PanelScene.instantiate()
	root.add_child(panel)
	await process_frame
	await process_frame

	panel.update_tree(agent_tree)
	await process_frame
	await process_frame
	await process_frame

	print("[TREE_DATA] keys=%s" % str(panel._tree_data.keys()))
	for nid in panel._tree_data:
		print("  key=%s state=%s parent=%s" % [nid, panel._tree_data[nid].get("state"), panel._tree_data[nid].get("parent_id")])

	print("[GRAPH] children:")
	for child in panel._graph.get_children():
		if child is GraphElement:
			var lbl = child.get_node_or_null("GridContainer/PanelContainer/ContentContainer/NameLabel")
			print("  name=%s label=%s pos_offset=%s global_pos=%s size=%s" % [
				child.name, lbl.text if lbl else "?", child.position_offset, child.global_position, child.size])

	print("[CONNECTIONS] %d" % panel._connections.size())
	for conn in panel._connections:
		print("  %s -> %s from_dir=%s to_dir=%s" % [conn.get("from"), conn.get("to"), conn.get("_from_dir", "<none>"), conn.get("_to_dir", "<none>")])

	quit(0)
