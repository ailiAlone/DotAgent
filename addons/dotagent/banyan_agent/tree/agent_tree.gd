@tool
class_name AgentTree
extends RefCounted
## Agent Tree — 持久化的树结构 + 节点上下文
##
## 树 = 项目。一个 Godot 项目就是一棵树。
## 持久存在跨对话生长。持久化树结构 + 节点知识（非消息历史）。
##
## 持久化路径: banyan_agent/persistence/agent_tree.json

const TREE_PATH := "res://addons/dotagent/banyan_agent/persistence/agent_tree.json"

var _nodes: Dictionary = {}   # node_id → AgentNode
var _root_id: String = ""
var _logger = null


func _init(logger = null) -> void:
	_logger = logger


func clear() -> void:
	_nodes.clear()
	_root_id = ""


# ============ 节点操作 ============

## 获取根节点 ID
func get_root_id() -> String:
	return _root_id


## 获取节点
func get_node(node_id: String) -> AgentNode:
	return _nodes.get(node_id)


## 获取所有节点
func get_all_nodes() -> Dictionary:
	return _nodes


## 获取子节点列表
func get_children(parent_id: String) -> Array:
	var result: Array = []
	for nid in _nodes:
		var n: AgentNode = _nodes[nid]
		if n.parent_id == parent_id:
			result.append(n)
	return result


## 添加或更新节点
func upsert_node(node: AgentNode) -> void:
	if node.node_id.is_empty():
		return
	_nodes[node.node_id] = node
	if node.parent_id.is_empty() and _root_id.is_empty():
		_root_id = node.node_id


## 确保根节点存在
func ensure_root(root_id: String = "Root") -> AgentNode:
	if _root_id.is_empty():
		_root_id = root_id
	if _nodes.has(root_id):
		return _nodes[root_id]
	var root: AgentNode = AgentNode.new()
	root.node_id = root_id
	root.parent_id = ""
	root.state = "IDLE"
	_nodes[root_id] = root
	return root


## 从运行时节点递归收集所有子节点到树中
## 运行结束后调用，确保 spawn 的子节点被树管理
func collect_runtime_nodes(node) -> void:
	if node == null:
		return
	var nid: String = str(node.node_id)
	_nodes[nid] = node
	for cname in node._children:
		var child = node._children[cname]
		collect_runtime_nodes(child)


## 删除节点及其子树
func remove_subtree(node_id: String) -> int:
	var count: int = 0
	var to_remove: Array = [node_id]
	while not to_remove.is_empty():
		var nid: String = to_remove.pop_back()
		# 收集子节点
		for other_id in _nodes:
			var other: AgentNode = _nodes[other_id]
			if other.parent_id == nid:
				to_remove.append(other_id)
		if _nodes.has(nid) and nid != _root_id:
			_nodes.erase(nid)
			count += 1
	return count


# ============ 持久化 ============

## 保存到磁盘
func save() -> bool:
	var data: Dictionary = {
		"version": "1.0",
		"root_id": _root_id,
		"saved_at": Time.get_datetime_string_from_system(),
		"nodes": {},
	}
	for nid in _nodes:
		var n: AgentNode = _nodes[nid]
		data["nodes"][nid] = n.to_dict()

	var dir_path: String = TREE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var f: FileAccess = FileAccess.open(TREE_PATH, FileAccess.WRITE)
	if f == null:
		_log("Failed to save agent tree: %s" % TREE_PATH)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_log("Agent tree saved: %d nodes → %s" % [_nodes.size(), TREE_PATH])
	return true


## 从磁盘加载
func load() -> bool:
	if not FileAccess.file_exists(TREE_PATH):
		_log("No agent tree file found at %s" % TREE_PATH)
		return false

	var f: FileAccess = FileAccess.open(TREE_PATH, FileAccess.READ)
	if f == null:
		_log("Failed to open agent tree: %s" % TREE_PATH)
		return false

	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("Invalid agent tree JSON")
		return false

	var data: Dictionary = parsed
	_root_id = str(data.get("root_id", ""))
	_nodes.clear()

	var nodes_data: Dictionary = data.get("nodes", {})
	for nid in nodes_data:
		var nd = nodes_data[nid]
		if nd is Dictionary:
			_nodes[nid] = AgentNode.from_dict(nd)

	# 自动检测 root_id（如果没有存或为空）
	if _root_id.is_empty():
		for nid in _nodes:
			var n: AgentNode = _nodes[nid]
			if n.parent_id.is_empty():
				_root_id = nid
				break

	_log("Agent tree loaded: %d nodes from %s" % [_nodes.size(), TREE_PATH])
	return true


## 获取节点总数
func get_node_count() -> int:
	return _nodes.size()


# ============ Prune 分析 ============

## 分析树结构，返回可优化建议
## 返回: [{type: "merge"|"absorb"|"extract", nodes: [...], reason: String}]
func analyze_for_prune() -> Array:
	var suggestions: Array = []

	# 1. 发现可合并的重复节点（同一父节点下，domain_knowledge 相似度高）
	_merge_analysis(suggestions)

	# 2. 发现可被父节点吸收的简单子节点（rounds <= 2 且 files <= 2）
	_absorb_analysis(suggestions)

	# 3. 发现多个节点共有的模式 → 提取公共节点
	_extract_analysis(suggestions)

	return suggestions


## 执行修剪 — 应用用户确认的建议
func apply_prune(suggestion: Dictionary) -> int:
	var pruned: int = 0
	var ptype: String = str(suggestion.get("type", ""))
	var nodes_list: Array = suggestion.get("nodes", [])

	match ptype:
		"absorb":
			# 将子节点的知识合并到父节点，然后删除子节点
			for nid in nodes_list:
				var n: AgentNode = _nodes.get(nid)
				if n == null:
					continue
				var parent: AgentNode = _nodes.get(n.parent_id)
				if parent == null:
					continue
				# 合并知识
				if not n.domain_knowledge.is_empty():
					parent.domain_knowledge += "\n[从 %s 吸收] %s" % [nid, n.domain_knowledge]
				# 合并文件
				for f in n.managed_files:
					if not parent.managed_files.has(f):
						parent.managed_files.append(f)
				parent.add_history_entry("Absorbed %s" % nid)
			# 删除被吸收的节点
			for nid in nodes_list:
				if _nodes.has(nid) and nid != _root_id:
					_nodes.erase(nid)
					pruned += 1

		"merge":
			# 合并重复节点：保留第一个，其余合并后删除
			if nodes_list.size() < 2:
				return 0
			var keeper_id: String = str(nodes_list[0])
			var keeper: AgentNode = _nodes.get(keeper_id)
			if keeper == null:
				return 0
			for i in range(1, nodes_list.size()):
				var nid: String = str(nodes_list[i])
				var n: AgentNode = _nodes.get(nid)
				if n == null:
					continue
				if not n.domain_knowledge.is_empty():
					keeper.domain_knowledge += "\n[合并自 %s] %s" % [nid, n.domain_knowledge]
				for f in n.managed_files:
					if not keeper.managed_files.has(f):
						keeper.managed_files.append(f)
				keeper.add_history_entry("Merged %s" % nid)
				_nodes.erase(nid)
				pruned += 1

		"extract":
			# 提取公共模式为新节点（目前只做标记，实际创建由 LLM 决定）
			_log("Extract prune not yet automated — requires LLM analysis")

	return pruned


# ============ 内部：Prune 分析算法 ============

func _merge_analysis(suggestions: Array) -> void:
	# 按父节点分组
	var by_parent: Dictionary = {}
	for nid in _nodes:
		var n: AgentNode = _nodes[nid]
		if n.parent_id.is_empty():
			continue
		if not by_parent.has(n.parent_id):
			by_parent[n.parent_id] = []
		by_parent[n.parent_id].append(n)

	for pid in by_parent:
		var siblings: Array = by_parent[pid]
		if siblings.size() < 2:
			continue
		# 简单相似度检测：domain_knowledge 前 60 字符重叠
		for i in range(siblings.size()):
			for j in range(i + 1, siblings.size()):
				var a: AgentNode = siblings[i]
				var b: AgentNode = siblings[j]
				if _knowledge_similarity(a.domain_knowledge, b.domain_knowledge) > 0.6:
					suggestions.append({
						"type": "merge",
						"nodes": [a.node_id, b.node_id],
						"reason": "节点 '%s' 和 '%s' 知识高度相似，可合并" % [a.node_id, b.node_id],
					})


func _absorb_analysis(suggestions: Array) -> void:
	for nid in _nodes:
		var n: AgentNode = _nodes[nid]
		if n.node_id == _root_id:
			continue
		if n.get_round_count() <= 2 and n.managed_files.size() <= 2 and get_children(nid).is_empty():
			suggestions.append({
				"type": "absorb",
				"nodes": [nid],
				"reason": "节点 '%s' 工作量小 (%d轮, %d文件)，可被父节点 '%s' 吸收" % [
					nid, n.get_round_count(), n.managed_files.size(), n.parent_id
				],
			})


func _extract_analysis(suggestions: Array) -> void:
	# 发现多个节点引用同一文件 → 可能需要提取公共节点
	var file_owners: Dictionary = {}
	for nid in _nodes:
		var n: AgentNode = _nodes[nid]
		for f in n.managed_files:
			if not file_owners.has(f):
				file_owners[f] = []
			file_owners[f].append(nid)

	for f in file_owners:
		var owners: Array = file_owners[f]
		if owners.size() >= 3:
			suggestions.append({
				"type": "extract",
				"nodes": owners,
				"reason": "文件 '%s' 被 %d 个节点共同管理，建议提取公共节点" % [f, owners.size()],
			})


## 简单的文本相似度（基于共同词数 / 总词数）
func _knowledge_similarity(a: String, b: String) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	var words_a: Array = a.to_lower().split(" ", false)
	var words_b: Array = b.to_lower().split(" ", false)
	if words_a.is_empty() or words_b.is_empty():
		return 0.0
	var common: int = 0
	var set_b: Dictionary = {}
	for w in words_b:
		set_b[w] = true
	for w in words_a:
		if set_b.has(w):
			common += 1
	var total: int = maxi(words_a.size(), words_b.size())
	return float(common) / float(total)


# ============ 内部 ============

func _state_int_to_string(state: int) -> String:
	match state:
		0: return "IDLE"
		1: return "RUNNING"
		2: return "LLM_REQUEST"
		3: return "TOOL_EXEC"
		4: return "COMPLETED"
		5: return "FAILED"
		_: return "UNKNOWN"


func _log(msg: String) -> void:
	if _logger:
		_logger.append("TREE", msg)
