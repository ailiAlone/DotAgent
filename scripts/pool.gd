extends Node

# 通用对象池：避免高频 instantiate / queue_free 触发 GC
# 用法：pool.acquire(scene_path) 拿到节点，pool.release(node) 归还

class_name Pool

var _pools: Dictionary = {}  # {scene_path: [node1, node2, ...]}

func acquire(scene_path: String) -> Node:
	if not _pools.has(scene_path):
		_pools[scene_path] = []
	var stack: Array = _pools[scene_path]
	if stack.is_empty():
		var n = load(scene_path).instantiate()
		return n
	return stack.pop_back()

func release(scene_path: String, node: Node):
	if not _pools.has(scene_path):
		_pools[scene_path] = []
	_pools[scene_path].append(node)
	# 停用
	node.set_process(false)
	node.set_physics_process(false)
	node.visible = false
	if node is CollisionObject2D:
		node.set_deferred("monitoring", false)
		node.set_deferred("monitorable", false)
