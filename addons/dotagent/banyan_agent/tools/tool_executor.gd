@tool
extends RefCounted
## 工具执行器 — 路由 Banyan 工具调用到正确的处理器。
##
## Banyan 工具有两类:
##   1. Legacy 工具 — 桥接到 ToolRegistry.execute_tool()
##   2. Banyan 管理工具 — 由节点脚本内部处理（create_branch, create_worker 等）
##
## 本类负责区分两类并路由到正确的执行路径。
##
## 用法:
##   var executor := BanyanToolExecutor.new()
##   executor.setup(tool_registry, logger)
##   var result := await executor.execute("build_scene", '{"path": "res://..."}')

const BANYAN_MANAGEMENT_TOOLS := [
	# 统一的子节点管理工具 — 所有节点共享
	"spawn_child",
	"route_to_child",
	"wait_for_children",
	"list_children",
	"claim_files",
	# Knowledge 工具（可选，保留向后兼容）
	"save_knowledge",
	"query_knowledge",
	"search_knowledge",
]

var _tool_registry = null  # ToolRegistry
var _logger: SessionLog = null
var _management_handler: Callable = Callable()  # 管理工具回调


func _init() -> void:
	_logger = SessionLog.instance()


## 注入依赖
func setup(tool_reg, logger: SessionLog = null) -> void:
	_tool_registry = tool_reg
	_logger = logger if logger else SessionLog.instance()


## 注册管理工具处理器 — 当 LLM 调用 Banyan 管理工具时，由此 Callable 处理
## 签名: func(tool_name: String, args: Dictionary) -> Dictionary
func set_management_handler(handler: Callable) -> void:
	_management_handler = handler


## 执行工具 — 返回 {"ok": bool, "content": String}
## tc_name: 工具名
## args_raw: JSON 字符串格式的参数
func execute(tc_name: String, args_raw: String) -> Dictionary:
	if _is_management_tool(tc_name):
		return await _execute_management(tc_name, args_raw)
	else:
		return await _execute_legacy(tc_name, args_raw)


## 检查是否为 Banyan 管理工具
func _is_management_tool(tc_name: String) -> bool:
	return tc_name in BANYAN_MANAGEMENT_TOOLS


## 执行管理工具（async — 处理器可能需要 await Legacy 工具调用）
func _execute_management(tc_name: String, args_raw: String) -> Dictionary:
	if not _management_handler.is_valid():
		return {
			"ok": false,
			"content": "Management tool '%s' called but no handler registered" % tc_name,
		}

	var args: Variant = JSON.parse_string(args_raw)
	if args == null:
		args = {}

	if _logger:
		_logger.append("TOOLS", "Management tool: %s(%s)" % [tc_name, args_raw.substr(0, 100)])

	var result: Dictionary = await _management_handler.call(tc_name, args)
	return result


## 执行 Legacy 工具 — 桥接到 ToolRegistry
func _execute_legacy(tc_name: String, args_raw: String) -> Dictionary:
	if _tool_registry == null:
		return {"ok": false, "content": "ToolRegistry not available"}

	if _logger:
		_logger.append("TOOLS", "Legacy tool: %s" % tc_name)

	var result: Dictionary = await _tool_registry.execute_tool(tc_name, args_raw)
	return result


## 获取工具是否为管理工具（静态查询）
static func is_management_tool(tc_name: String) -> bool:
	return tc_name in BANYAN_MANAGEMENT_TOOLS
