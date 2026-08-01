extends SceneTree
## R18 韧性回归：
## 1. from_dict 残留瞬态归一化（RUNNING/LLM_REQUEST/TOOL_EXEC/RETRYING → FAILED）
## 2. wind_down 只置中止标志并递归传播，不改状态
## 3. abort 不覆写已到终态的节点

const AgentNode = preload("res://addons/dotagent/banyan_agent/tree/agent_node.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_from_dict_stale_states()
	_test_wind_down()
	_test_abort_terminal_guard()
	print("=== Results: %d/%d passed ===" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _test_from_dict_stale_states() -> void:
	for stale in ["RUNNING", "LLM_REQUEST", "TOOL_EXEC", "RETRYING"]:
		var n: AgentNode = AgentNode.from_dict({"node_id": "T", "state": stale})
		_check(n.state == "FAILED", "残留 %s 归一化为 FAILED" % stale)
	for terminal in ["IDLE", "COMPLETED", "FAILED"]:
		var n: AgentNode = AgentNode.from_dict({"node_id": "T", "state": terminal})
		_check(n.state == terminal, "终态 %s 保持不变" % terminal)


func _test_wind_down() -> void:
	var parent: AgentNode = AgentNode.new()
	var child: AgentNode = AgentNode.new()
	child.node_id = "child"
	parent._children["child"] = child
	parent.node_state = AgentNode.NodeState.RUNNING
	parent.wind_down()
	_check(parent._abort_requested, "wind_down 置父节点中止标志")
	_check(child._abort_requested, "wind_down 递归传播到子节点")
	_check(parent.node_state == AgentNode.NodeState.RUNNING, "wind_down 不强制改状态")
	parent.free()
	child.free()


func _test_abort_terminal_guard() -> void:
	var done_node: AgentNode = AgentNode.new()
	done_node.node_state = AgentNode.NodeState.COMPLETED
	done_node.abort()
	_check(done_node.node_state == AgentNode.NodeState.COMPLETED, "abort 不覆写 COMPLETED")
	_check(done_node._abort_requested, "abort 仍置中止标志")

	var running_node: AgentNode = AgentNode.new()
	running_node.node_state = AgentNode.NodeState.RUNNING
	running_node.abort()
	_check(running_node.node_state == AgentNode.NodeState.FAILED, "abort 将 RUNNING 改判 FAILED")
	done_node.free()
	running_node.free()
