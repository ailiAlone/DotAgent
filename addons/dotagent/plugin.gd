@tool
extends EditorPlugin
## DotAgent — AI-powered Godot editor assistant
##
## 统一插件入口: 包含 Banyan 自组织节点树架构 + Legacy 单智能体引擎。
## 树即本体 — AgentNode 是唯一的节点类，持有领域知识并能执行 ReAct 循环。
## Legacy 工具系统提供底层能力支撑。

# ============ Preloads ============

const BanyanPool = preload("res://addons/dotagent/banyan_agent/http/http_client_pool.gd")
const DotAgentDockScene = preload("res://addons/dotagent/ui/dotagent_dock.tscn")
const SettingsScene = preload("res://addons/dotagent/ui/dotagent_settings.tscn")
const BanyanSessionPopupScene = preload("res://addons/dotagent/banyan_agent/ui/banyan_session_popup.tscn")
const LegacyActivityPanelScene = preload("res://addons/dotagent/legacy_agent/ui/activity_panel.tscn")
const BanyanBottomPanelScene = preload("res://addons/dotagent/banyan_agent/ui/banyan_bottom_panel.tscn")
const AgentTreeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_tree.gd")
const AgentNodeScript = preload("res://addons/dotagent/banyan_agent/tree/agent_node.gd")
const BanyanRunLogScript = preload("res://addons/dotagent/log/banyan_run_log.gd")

const DEFAULT_POOL_SIZE := 4  # 并行模式: 支持多个节点同时执行

# ============ 信号 ============

signal banyan_ready()
signal worker_progress(worker_id: String, chunk: String)
signal worker_done(worker_id: String, report: Dictionary)
signal worker_error(worker_id: String, error: String)
signal worker_tool_started(worker_id: String, tool_name: String)
signal worker_tool_finished(worker_id: String, tool_name: String, ok: bool)
signal banyan_done(report: Dictionary)

# ============ 核心组件 ============

var _host_node: Node = null
var _pool: BanyanPool = null
var _tool_registry = null
var _logger = null
var _root = null
var _banyan_dock = null  # BanyanDock instance
var _settings_dialog = null  # DotAgentSettings instance
var _session_popup = null  # BanyanSessionPopup instance

# Legacy 模式组件
var _legacy_dock = null  # Legacy Dock instance (shared dock)
var _activity_panel = null  # ActivityPanel instance
var _banyan_bottom_panel = null  # Banyan Nodes+Log bottom panel
var _legacy_controller = null  # Legacy DockController
var _agent_tree = null         # AgentTree 持久化树结构
var _tree_refresh_timer: Timer = null  # 节流 Agent Tree UI 刷新
var _tree_refresh_pending: bool = false

var _initialized: bool = false
var _current_mode: String = "banyan"  # "legacy" or "banyan"

# ============ 会话状态 ============

var _messages: Array = []  # 完整对话历史（含 system prompt）
var _session_id: String = ""
const SESSIONS_DIR := "res://addons/dotagent/banyan_agent/sessions"
const SYSTEM_PROMPT_TEMPLATE := """# DotAgent Banyan Node

You are a node in the DotAgent Banyan architecture.
You hold knowledge about a specific area of the project.

## How You Work
- Use your tools to understand and modify the project
- Read code before modifying it
- Verify your changes after writing
- Be concise in summaries

## Tools
- Perception: read_script, inspect_scene_structured, get_project_architecture
- Execution: update_script, build_scene, write_file
- Children: route_to_child (existing child), spawn_child (new child), wait_for_children
"""


func _enter_tree() -> void:
	# 共享基础设施始终初始化
	_init_shared()
	# 读取模式配置并启动对应面板
	_current_mode = _read_mode()
	_apply_mode()


func _exit_tree() -> void:
	_shutdown_current_mode()
	_shutdown_shared()


# ============ 共享基础设施 ============

func _init_shared() -> void:
	_logger = SessionLog.instance()
	_logger.append("CTX", "═══════════════════════════════════════")
	_logger.append("CTX", "DotAgent v0.2.0 — Init")
	_logger.append("CTX", "═══════════════════════════════════════")

	# 创建 host node
	_host_node = Node.new()
	_host_node.name = "DotAgentHost"
	add_child(_host_node)

	# 创建工具注册中心
	_tool_registry = _create_legacy_tool_registry()

	# 创建设置对话框（两种模式共用）
	_settings_dialog = SettingsScene.instantiate()
	_settings_dialog.config_saved.connect(_on_settings_saved)
	_settings_dialog.mode_changed.connect(_on_mode_changed)
	_settings_dialog.reset_requested.connect(_on_reset_requested)
	add_child(_settings_dialog)


func _shutdown_shared() -> void:
	if _settings_dialog:
		_settings_dialog.queue_free()
		_settings_dialog = null

	if _host_node:
		_host_node.queue_free()
		_host_node = null

	_tool_registry = null

	if _logger:
		_logger.append("CTX", "DotAgent shutdown")


## 读取 config.cfg 中的模式设置
func _read_mode() -> String:
	var cf: ConfigFile = ConfigFile.new()
	var err: Error = cf.load("res://addons/dotagent/config.cfg")
	if err == OK:
		return str(cf.get_value("dotagent", "mode", "banyan"))
	return "banyan"


## 根据当前模式启动对应面板
func _apply_mode() -> void:
	if _current_mode == "legacy":
		_init_legacy()
	else:
		_init_banyan()


## 关闭当前模式的面板
func _shutdown_current_mode() -> void:
	if _current_mode == "legacy":
		_shutdown_legacy()
	else:
		_shutdown_banyan()


# ============ Legacy 模式 ============

func _init_legacy() -> void:
	_logger.append("CTX", "Legacy mode init")

	# 创建 Activity Panel（底部面板）
	_activity_panel = LegacyActivityPanelScene.instantiate()
	add_control_to_bottom_panel(_activity_panel, "AI Activity")

	# 创建共享对话 Dock（右侧 Dock）
	_legacy_dock = DotAgentDockScene.instantiate()
	_legacy_dock.plugin = self
	# 设置标题为 Legacy
	var title_label: Label = _legacy_dock.get_node_or_null("Header/Title")
	if title_label:
		title_label.text = "Legacy"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _legacy_dock)

	# 创建 DockController 并注入依赖
	var controller = DockController.new()
	controller.setup(self, _activity_panel, _host_node)
	_legacy_controller = controller

	# 连接 Dock 输入信号 → DockController
	_legacy_dock.run_requested.connect(func(prompt: String, _mode: String):
		_legacy_dock.append_user_message(prompt)
		_legacy_dock.set_running(true)
		controller.send_user_message(prompt)
	)
	_legacy_dock.stop_requested.connect(func():
		controller.abort_current()
	)
	_legacy_dock.session_requested.connect(func(action: String, _id: String):
		if action == "new":
			controller.new_session()
	)
	_legacy_dock.settings_requested.connect(func(): _open_settings())
	_legacy_dock.model_change_requested.connect(func(): _fetch_and_populate_models(_legacy_dock))
	_legacy_dock.model_selected.connect(func(model_name: String): _on_model_selected(model_name, _legacy_dock))

	# 连接 DockController 输出信号 → 共享 Dock 显示方法
	controller.stream_started.connect(func(): _legacy_dock.begin_stream())
	controller.stream_chunk.connect(func(c: String): _legacy_dock.receive_chunk(c))
	controller.round_complete.connect(func(c: String, tc: Array, tr: Array):
		_legacy_dock.end_stream(tc, tr)
		_legacy_dock.set_running(false)
	)
	controller.stream_error.connect(func(e: String):
		_legacy_dock.append_error(e)
		_legacy_dock.set_running(false)
	)
	controller.tool_started.connect(func(tn: String): _legacy_dock.append_tool_started(tn))
	controller.tool_finished.connect(func(tn: String, ok: bool): _legacy_dock.append_tool_finished(tn, ok))
	controller.loop_finished.connect(func(): _legacy_dock.set_running(false))
	controller.config_changed.connect(func():
		var cfg: ConfigManager = ConfigManager.instance()
		_legacy_dock.set_model(cfg.get_model())
	)
	controller.session_changed.connect(func(sid, messages):
		_legacy_dock.rebuild_messages(messages)
	)

	# 显示模型
	var cfg: ConfigManager = ConfigManager.instance()
	_legacy_dock.set_model(cfg.get_model())

	# 引导会话
	controller.bootstrap_session()

	_initialized = true
	_logger.append("CTX", "Legacy initialized — tools=%d" % _tool_registry.get_tool_definitions().size())


func _shutdown_legacy() -> void:
	if _legacy_controller:
		_legacy_controller.abort_current()
		_legacy_controller = null

	if _legacy_dock:
		remove_control_from_docks(_legacy_dock)
		_legacy_dock.queue_free()
		_legacy_dock = null

	if _activity_panel:
		remove_control_from_bottom_panel(_activity_panel)
		_activity_panel.queue_free()
		_activity_panel = null

	_initialized = false
	_logger.append("CTX", "Legacy shutdown")


# ============ 初始化 / 关闭 ============

func _init_banyan() -> void:
	_logger.append("CTX", "═══════════════════════════════════════")
	_logger.append("CTX", "DotAgent Banyan v0.2.0 — Init")
	_logger.append("CTX", "═══════════════════════════════════════")

	# 1. 创建 HTTP 连接池
	_pool = BanyanPool.new(DEFAULT_POOL_SIZE)
	_pool.name = "BanyanPool"
	_host_node.add_child(_pool)

	_initialized = true
	_logger.append("CTX", "Banyan initialized — pool_size=%d, tools=%d" % [_pool.max_slots, _tool_registry.get_tool_definitions().size()])
	banyan_ready.emit()

	# 2. 创建底部面板（Nodes + Log）
	_banyan_bottom_panel = BanyanBottomPanelScene.instantiate()
	add_control_to_bottom_panel(_banyan_bottom_panel, "Agent Tree")

	# 5. 创建对话 Dock（纯对话流）
	_banyan_dock = DotAgentDockScene.instantiate()
	_banyan_dock.bottom_panel = _banyan_bottom_panel
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _banyan_dock)
	_banyan_dock.set_banyan_status("Idle", Color(0.6, 0.8, 0.6))

	# 设置 Dock 标题
	var title_label: Label = _banyan_dock.get_node_or_null("Header/Title")
	if title_label:
		title_label.text = "Banyan"

	# 6. Agent Tree — 持久化树结构
	_agent_tree = AgentTreeScript.new(_logger)
	_agent_tree.load()
	# 如果有已加载的树，更新底部面板
	if _agent_tree.get_node_count() > 0:
		_banyan_bottom_panel.update_tree(_agent_tree)

	# 连接底部面板信号
	_banyan_bottom_panel.prune_requested.connect(_on_prune_requested)

	# 设置模型显示
	var cfg: ConfigManager = ConfigManager.instance()
	_banyan_dock.set_model(cfg.get_model())

	# 连接插件信号到 Dock 更新
	worker_progress.connect(_on_dock_worker_progress)
	worker_done.connect(_on_dock_worker_done)
	worker_error.connect(_on_dock_worker_error)
	worker_tool_started.connect(_on_dock_tool_started)
	worker_tool_finished.connect(_on_dock_tool_finished)
	banyan_done.connect(_on_dock_banyan_done)

	# 连接 Dock 输入信号
	_banyan_dock.run_requested.connect(_on_dock_run_requested)
	_banyan_dock.stop_requested.connect(_on_dock_stop_requested)
	_banyan_dock.session_requested.connect(_on_dock_session_requested)
	_banyan_dock.settings_requested.connect(func(): _open_settings())
	_banyan_dock.model_change_requested.connect(func(): _fetch_and_populate_models(_banyan_dock))
	_banyan_dock.model_selected.connect(func(model_name: String): _on_model_selected(model_name, _banyan_dock))

	# 5. 会话初始化 — 恢复上次会话或新建
	_bootstrap_session()

	# 6. 创建 Banyan 会话弹窗
	_session_popup = BanyanSessionPopupScene.instantiate()
	_session_popup.session_new.connect(func(): _new_session())
	_session_popup.session_selected.connect(func(sid: String): _load_session(sid))
	_session_popup.session_deleted.connect(func(sid: String): _delete_session(sid))
	add_child(_session_popup)


func _shutdown_banyan() -> void:
	# 保存 Agent Tree
	if _agent_tree and _agent_tree.get_node_count() > 0:
		_agent_tree.save()

	# 断开 Dock 信号并移除
	if _banyan_dock:
		worker_progress.disconnect(_on_dock_worker_progress)
		worker_done.disconnect(_on_dock_worker_done)
		worker_error.disconnect(_on_dock_worker_error)
		worker_tool_started.disconnect(_on_dock_tool_started)
		worker_tool_finished.disconnect(_on_dock_tool_finished)
		banyan_done.disconnect(_on_dock_banyan_done)
		_banyan_dock.run_requested.disconnect(_on_dock_run_requested)
		_banyan_dock.stop_requested.disconnect(_on_dock_stop_requested)
		_banyan_dock.session_requested.disconnect(_on_dock_session_requested)
		remove_control_from_docks(_banyan_dock)
		_banyan_dock.queue_free()
		_banyan_dock = null

	if _session_popup:
		_session_popup.queue_free()
		_session_popup = null

	if _root:
		_root.abort()
		_root = null

	if _pool:
		_pool.release_all()
		_pool = null

	if _banyan_bottom_panel:
		_banyan_bottom_panel.prune_requested.disconnect(_on_prune_requested)
		remove_control_from_bottom_panel(_banyan_bottom_panel)
		_banyan_bottom_panel.queue_free()
		_banyan_bottom_panel = null

	_agent_tree = null
	_initialized = false

	if _logger:
		_logger.append("CTX", "Banyan shutdown")


# ============ 公共 API ============

## Banyan 是否已初始化
func is_ready() -> bool:
	return _initialized


## 获取 HTTP 连接池
func get_pool():
	return _pool


## 获取工具注册中心（Legacy 桥接）
func get_tool_registry() -> ToolRegistry:
	return _tool_registry


## 启动完整 Banyan 流程 — 创建节点，节点自然生长出子节点
##
## 用法:
##   banyan.run_banyan("给 Player 加护盾系统")
func run_banyan(user_request: String, base_url: String = "", api_key: String = "", model: String = ""):
	if not _initialized:
		push_error("[Banyan] Not initialized")
		return null

	var config: ConfigManager = ConfigManager.instance()
	var effective_url: String = base_url if not base_url.is_empty() else config.get_base_url()
	var effective_key: String = api_key if not api_key.is_empty() else config.get_api_key()
	var effective_model: String = model if not model.is_empty() else config.get_model()

	if effective_url.is_empty() or effective_key.is_empty():
		push_error("[Banyan] API not configured. Set Base URL and API Key.")
		return null

	# 加载统一工具定义和 system prompt
	var BanyanToolLoader = preload("res://addons/dotagent/banyan_agent/tools/tool_loader.gd")
	var tool_loader: RefCounted = BanyanToolLoader.new(_logger)
	var node_tools: Array = tool_loader.get_tools("node")

	var prompt_text: String = _load_file_or_default(
		"res://addons/dotagent/banyan_agent/prompts/node_prompt.md",
		_default_node_prompt()
	)

	# 从 AgentTree 获取或创建根节点 — 节点是持久的，不是每次新建
	_root = _agent_tree.ensure_root("Root")
	_root.setup(_pool, _tool_registry, _host_node, _logger)
	_root.configure_llm(effective_url, effective_key, effective_model)
	_root.system_prompt = prompt_text
	_root.tool_definitions = node_tools

	# 从 AgentTree 加载已有子节点到 Root — 让 route_to_child 能找到它们
	for nid in _agent_tree.get_all_nodes():
		var n: AgentNode = _agent_tree.get_all_nodes()[nid]
		if n.parent_id == "Root" and n.node_id != "Root":
			_root._children[n.node_id] = n
			n._parent_ref = weakref(_root)  # 轮数预算申请通道
			_root._pending_children[n.node_id] = true  # 标记为已完成（上次的状态）
	if _root._children.size() > 0:
		_logger.append("CTX", "Loaded %d existing children for Root" % _root._children.size())

	# 注入对话上下文 — 多轮对话支持
	_messages.append({"role": "user", "content": user_request})
	_save_session()
	if _messages.size() > 1:
		var prior: Array = []
		for i in range(1, _messages.size() - 1):
			prior.append(_messages[i])
		_root.prior_messages = prior

	# 连接信号 — 每次 run_banyan 都会执行到这里，而 _root 是持久节点，
	# 必须用稳定方法引用 + is_connected 守卫，防止处理器随对话轮数累积（消息重复入库的根因）
	if not _root.progress_chunk.is_connected(_on_root_chunk):
		_root.progress_chunk.connect(_on_root_chunk)
	if not _root.progress_done.is_connected(_on_root_done):
		_root.progress_done.connect(_on_root_done)
	if not _root.progress_error.is_connected(_on_root_error):
		_root.progress_error.connect(_on_root_error)
	# Agent Graph 实时刷新：整棵树的状态切换 + 工具调用开始/结束都会沿父链冒泡到 Root
	if not _root.state_changed.is_connected(_on_graph_dirty):
		_root.state_changed.connect(_on_graph_dirty)
	if not _root.progress_tool_started.is_connected(_on_graph_dirty):
		_root.progress_tool_started.connect(_on_graph_dirty)
	if not _root.progress_tool_finished.is_connected(_on_graph_dirty):
		_root.progress_tool_finished.connect(_on_graph_dirty)

	# 构建 ticket 并异步运行
	var ticket: Dictionary = {
		"ticket_id": "T-Root-%03d" % [Time.get_ticks_msec() % 1000],
		"type": "implement",
		"scope": "Root",
		"requirements": [user_request],
	}

	var runner: Callable = func():
		await _root.run(ticket)
	runner.call_deferred()

	# 更新 Dock 状态
	if _banyan_dock:
		_banyan_dock.set_banyan_status("Running", Color(1, 0.8, 0))
		_banyan_dock.add_log("Banyan started: %s" % user_request.substr(0, 60), "info")

	_logger.append("CTX", "Banyan started: '%s' (model=%s, tools=%d)" % [
		user_request.substr(0, 60), effective_model, node_tools.size(),
	])
	return _root


# ============ 内部 ============


# ============ 会话管理 ============

func _bootstrap_session() -> void:
	# 确保目录存在
	DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)
	# 尝试恢复最近的会话
	var sessions: Array = _list_sessions()
	if not sessions.is_empty():
		_load_session(sessions[0])  # sessions[0] 是最新的
	else:
		_new_session()


func _new_session() -> void:
	_session_id = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	_messages = [{"role": "system", "content": SYSTEM_PROMPT_TEMPLATE}]
	_save_session()
	if _banyan_dock:
		_banyan_dock.set_session_id(_session_id)
		_banyan_dock.clear_all()
	_logger.append("CTX", "New session: %s" % _session_id)


func _save_session() -> void:
	if _session_id.is_empty():
		return
	var dir: String = SESSIONS_DIR + "/" + _session_id
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(dir + "/messages.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_messages, "  "))
		f.close()


func _load_session(session_id: String) -> void:
	var path: String = SESSIONS_DIR + "/" + session_id + "/messages.json"
	if not FileAccess.file_exists(path):
		_new_session()
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_new_session()
		return
	var json: JSON = JSON.new()
	var err: Error = json.parse(f.get_as_text())
	f.close()
	if err != OK:
		_new_session()
		return
	var data = json.data
	if data is Array:
		_session_id = session_id
		_messages = data
		# 确保 system prompt 存在
		if _messages.is_empty() or _messages[0].get("role", "") != "system":
			_messages.insert(0, {"role": "system", "content": SYSTEM_PROMPT_TEMPLATE})
	else:
		_new_session()
		return

	if _banyan_dock:
		_banyan_dock.set_session_id(_session_id)
		_banyan_dock.rebuild_messages(_messages)
	_logger.append("CTX", "Loaded session: %s (%d msgs)" % [_session_id, _messages.size()])


func _list_sessions() -> Array:
	var result: Array = []
	var dir: DirAccess = DirAccess.open(SESSIONS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			result.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	# 按名称倒序（最新的在前）
	result.sort()
	result.reverse()
	return result


func _get_conversation_messages() -> Array:
	## 返回去掉 system prompt 的对话历史（用于 dock 显示）
	var result: Array = []
	for i in range(1, _messages.size()):
		result.append(_messages[i])
	return result


func _append_assistant_to_conversation(summary: String) -> void:
	if summary.is_empty():
		return
	# 幂等守卫：与最后一条完全相同则跳过（信号重复或重复完成的兜底）
	if not _messages.is_empty():
		var last: Dictionary = _messages.back()
		if last.get("role", "") == "assistant" and str(last.get("content", "")) == summary:
			return
	_messages.append({"role": "assistant", "content": summary})
	_save_session()
	if _banyan_dock:
		_banyan_dock.rebuild_messages(_get_conversation_messages())


## Root 信号处理器（稳定方法引用，保证跨任务只连接一次）
func _on_root_chunk(chunk: String) -> void:
	worker_progress.emit("Root", chunk)


func _on_root_done() -> void:
	var report: Dictionary = _root.generate_report()
	_logger.append("CTX", "Banyan complete: rounds=%d, children=%d, files=%d" % [
		report.get("rounds", 0),
		report.get("children_count", 0),
		report.get("files", []).size(),
	])
	# 先 emit 让 dock 正常收尾流式气泡，再入库并 rebuild —
	# 反过来的话 rebuild 的 clear_all 会先把 _stream_node 置空，
	# 导致 done 处理误判"无流式"而重复追加总结（对话栏出现两条相同总结）
	banyan_done.emit(report)
	_append_assistant_to_conversation(report.get("summary", ""))


func _on_root_error(err: String) -> void:
	worker_error.emit("Root", err)


# ============ 设置 & 会话 UI ============

func _open_settings() -> void:
	if _settings_dialog:
		_settings_dialog.popup_centered()


## 获取当前供应商的模型列表并填充到 Dock 的弹窗
func _fetch_and_populate_models(dock) -> void:
	var fetcher: ModelFetcher = ModelFetcher.new()
	var cfg: ConfigManager = ConfigManager.instance()
	var provider_name: String = cfg.get_provider_name()

	var cache_info: Dictionary = fetcher.get_cache_info()
	if cache_info.is_empty():
		# 无缓存，先下载数据库
		dock._model_button.text = "Downloading..."
		fetcher.refresh_database(_host_node, func(success: bool, _msg: String):
			if success:
				_fetch_and_populate_models(dock)
			else:
				dock.set_model(cfg.get_model())
		)
		return

	fetcher.fetch_models(provider_name, _host_node, func(success: bool, models: Array, _err: String):
		if success and not models.is_empty():
			dock.populate_models(models)
			# 自动弹出
			dock._on_model_button_pressed()
		else:
			_logger.append("CTX", "No models found for provider: %s" % provider_name)
	)


## 用户选择模型 — 保存到配置并刷新显示
func _on_model_selected(model_name: String, dock) -> void:
	var cfg: ConfigManager = ConfigManager.instance()
	var err: Error = cfg.save(
		cfg.get_base_url(),
		cfg.get_api_key(),
		model_name,
		cfg.get_context_limit(),
		cfg.get_language(),
		cfg.get_max_tokens_k(),
		cfg.get_vision_enabled(),
		cfg.get_effective_proxy_host(),
		cfg.get_proxy_port(),
		cfg.get_provider_name(),
	)
	if err != OK:
		push_warning("[DotAgent] Failed to save model: %d" % err)
		return
	dock.set_model(model_name)
	_logger.append("CTX", "Model changed: %s" % model_name)


## Legacy dock 通过 plugin.open_config_dialog() 打开设置
func open_config_dialog() -> void:
	_open_settings()


func _on_settings_saved() -> void:
	# 配置变更后刷新 dock 的模型显示
	if _banyan_dock:
		var cfg: ConfigManager = ConfigManager.instance()
		_banyan_dock.set_model(cfg.get_model())
	_logger.append("CTX", "Settings saved")


func _on_mode_changed(mode: String) -> void:
	if mode == _current_mode:
		return
	_logger.append("CTX", "Mode switching: %s → %s" % [_current_mode, mode])
	# 关闭当前模式面板
	_shutdown_current_mode()
	# 切换模式
	_current_mode = mode
	# 启动新模式面板
	_apply_mode()


func _on_reset_requested() -> void:
	var confirm: ConfirmationDialog = ConfirmationDialog.new()
	confirm.title = "Reset All Data"
	confirm.dialog_text = "确定要清除所有 Agent 数据吗？\n\n将删除：\n• 所有 Banyan/Legacy 会话历史\n• Agent 节点树和知识库\n• 运行日志和文件备份\n\n配置（API Key、URL、模式）将保留。"
	confirm.ok_button_text = "Reset"
	add_child(confirm)
	confirm.confirmed.connect(func():
		_do_reset_all_data()
		confirm.queue_free()
	)
	confirm.canceled.connect(func():
		confirm.queue_free()
	)
	confirm.popup_centered()


func _do_reset_all_data() -> void:
	_logger.append("CTX", "=== RESET: clearing all agent data ===")

	# 1. 关闭当前模式（保存前的状态丢弃）
	_shutdown_current_mode()

	# 2. 删除 Banyan 会话
	_remove_dir_contents("res://addons/dotagent/banyan_agent/sessions")
	# 3. 删除 Agent 节点树
	_remove_file("res://addons/dotagent/banyan_agent/persistence/agent_tree.json")
	# 4. 删除共享知识库
	_remove_file("res://addons/dotagent/banyan_agent/persistence/shared_knowledge.json")
	# 5. 删除 Legacy 会话
	_remove_dir_contents("res://addons/dotagent/legacy_agent/sessions")
	# 6. 删除 Legacy 日志
	_remove_dir_contents("res://addons/dotagent/legacy_agent/logs")
	# 7. 删除备份
	_remove_dir_contents("res://.dotagent_backups")

	# 8. 清理内存中的 Agent Tree
	if _agent_tree:
		_agent_tree.clear()

	# 9. 重新启动当前模式
	_apply_mode()
	_logger.append("CTX", "=== RESET complete ===")
	print_rich("[color=#ff8844][DotAgent][/color] All agent data has been reset.")


func _remove_dir_contents(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var full: String = dir_path + "/" + entry
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _remove_dir_recursive(dir_path: String) -> void:
	_remove_dir_contents(dir_path)
	DirAccess.remove_absolute(dir_path)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _delete_session(session_id: String) -> void:
	var dir_path: String = SESSIONS_DIR + "/" + session_id
	if DirAccess.dir_exists_absolute(dir_path):
		DirAccess.remove_absolute(dir_path + "/messages.json")
		DirAccess.remove_absolute(dir_path)
	_logger.append("CTX", "Deleted session: %s" % session_id)
	# 如果删除的是当前会话，新建一个
	if session_id == _session_id:
		_new_session()


## 加载 system prompt — 从 .md 文件或默认模板
func _load_file_or_default(path: String, default_content: String) -> String:
	if not FileAccess.file_exists(path):
		return default_content
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return default_content
	var content: String = f.get_as_text()
	f.close()
	return content if not content.is_empty() else default_content


func _default_node_prompt() -> String:
	return """# DotAgent Banyan Node

You are a node. You hold knowledge about a specific area of the project.

## How You Work

You use your tools to understand and modify the project. Read code, write code, inspect scenes, build things.

Start by doing the work yourself. Use list_files to see the project structure, then read the files relevant to your task. Only after you have started working and discovered depth should you consider spawning children.

## When to Spawn Children

While working, child nodes naturally emerge. You don't plan them upfront — you recognize them mid-work.

You're reading a scene and see it references 5 sub-scenes, each with its own script. Each is a domain with depth. Instead of reading all 5 yourself, spawn a child for each major subsystem. The child becomes an expert on that subsystem and holds the knowledge permanently.

You realize you've read 4 files about one system and there are still more. That system deserves its own node. Spawn a child. You move on; the child goes deep.

You're implementing a feature that touches code, scene, audio, and UI. Each area has its own concerns. Spawn children for the independent parts — they can work in parallel while you coordinate.

A child is a persistent expert that holds deep knowledge about its domain across all future conversations. When you spawn PlayerSystem, that node will forever understand the player.

## What NOT to Do

- Do NOT plan a decomposition before starting. Don't think "I need to analyze X, Y, Z, so I'll spawn three children." Start doing the work yourself. Spawn only when you encounter depth mid-work.
- Do NOT spawn children to avoid doing work. If a task only requires reading 3-5 files, do it yourself.
- Do NOT name children after roles. No "ScriptAnalyzer", "SceneExplorer". Name them after the domain: "Player", "EnemyAI", "UI_HUD", "Audio".
- Do NOT spawn a child to do what you haven't started. Before spawning, you should have already read some files and understand the area.

## Growing the Tree

- spawn_child(name, description) — create a new child with a domain name and mission. Children run their own ReAct loop. Spawn multiple for independent tasks — they execute in parallel.
- wait_for_children() — pause and collect your children's reports.
- route_to_child(child_name, task) — give work to an existing child that already knows its domain.
- list_children() — check who your children are and what they know.

Each child grows the tree. The tree is the agent.

## Your Tools

### Discovery (use these first!)
- list_files — list files under a directory, optionally filtered by pattern. Use this first to discover the project structure.
- list_scenes — list all .tscn scene files
- list_resources — list all .tres/.res resource files

### Perception
- read_script, read_multiple_files — read GDScript files in full (batch or single)
- read_file_tail — read end of very large non-script files (rarely needed)
- inspect_scene_structured, extract_script_interface
- get_scene_dependencies, inspect_resource_interface, analyze_signal_flow

### Execution
- update_script, build_scene, patch_scene, build_script
- replace_in_file, configure_resource, configure_project, check_script_syntax

### Knowledge
- save_knowledge, query_knowledge, search_knowledge

### File Ownership
- claim_files(paths, action) — declare which files belong to your domain. After exploring your area, call this to claim responsibility. This is YOUR active choice. action: set (replace), add (append), remove (release).

## Rules
- Discover first. Call list_files before reading files blindly.
- Read once, remember it. If your parent provided a File Index with summaries, use those instead of re-reading. Only read a file yourself if you need details the summary doesn't cover.
- Read before you write. Understand before you modify.
- Verify your changes.
- Structured summary. Distill the architecture, not list every file. Include: system modules, key functions/signals, dependencies, issues found.
- Don't re-read what you already know.
- Claim your files. After exploring and understanding your domain, call claim_files with the paths you are responsible for. This is how you declare ownership — a conscious decision, not automatic.
- If a tool fails, do not retry the same call.

## File Organization
This project uses domain-based directories (Godot style). Each domain has its own folder containing all related files.
When unsure about structure, read res://addons/dotagent/banyan_agent/prompts/project_structure.md
"""


func _load_system_prompt(path: String) -> String:
	if path.is_empty():
		return _default_node_prompt()

	if not FileAccess.file_exists(path):
		_logger.append("CTX", "Prompt file not found: %s — using default" % path)
		return _default_node_prompt()

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _default_node_prompt()

	var content: String = f.get_as_text()
	f.close()
	return content


## 创建 Legacy 工具注册中心 — 复用 Legacy 的所有工具模块
func _create_legacy_tool_registry() -> ToolRegistry:
	var registry: ToolRegistry = ToolRegistry.new()
	registry.set_editor_context(self, null)

	# 注册 Legacy 工具模块
	var tool_dir: String = "res://addons/dotagent/tools"
	var tool_scripts: Array = [
		"file_tools.gd",
		"scene_tools.gd",
		"script_tools.gd",
		"script_file_tools.gd",
		"node_query_tools.gd",
		"exec_tools.gd",
		"screenshot_tools.gd",
		"project_tools.gd",
		"perception_tools.gd",
		"configuration_tools.gd",
		"composite_tools.gd",
	]

	var loaded: int = 0
	for script_name in tool_scripts:
		var script_path: String = tool_dir.path_join(script_name)
		if not ResourceLoader.exists(script_path):
			_logger.append("CTX", "Tool module not found: %s" % script_path)
			continue
		var script_res: GDScript = load(script_path) as GDScript
		if script_res == null:
			_logger.append("CTX", "Failed to load tool module: %s" % script_path)
			continue
		var module = script_res.new()
		registry.register_module(module)
		loaded += 1

	_logger.append("CTX", "Loaded %d/%d Legacy tool modules" % [loaded, tool_scripts.size()])
	return registry


# ============ Prune 回调 ============

func _on_prune_requested(_node_id: String) -> void:
	if not _agent_tree:
		return
	var suggestions: Array = _agent_tree.analyze_for_prune()
	var total_pruned: int = 0
	for suggestion in suggestions:
		var count: int = _agent_tree.apply_prune(suggestion)
		total_pruned += count
	if total_pruned > 0:
		_agent_tree.save()
		if _banyan_bottom_panel:
			_banyan_bottom_panel.update_tree(_agent_tree)
			_banyan_bottom_panel.add_log("Pruned %d nodes" % total_pruned, "success")
		_logger.append("CTX", "Pruned %d nodes" % total_pruned)
	else:
		if _banyan_bottom_panel:
			_banyan_bottom_panel.add_log("No nodes to prune", "info")


# ============ Dock 回调 ============

func _on_dock_run_requested(prompt: String, _mode: String) -> void:
	if not _initialized:
		if _banyan_dock:
			_banyan_dock.add_log("Banyan not initialized", "error")
		return

	_banyan_dock.set_running(true)
	_banyan_dock.set_banyan_status("Running", Color(1, 0.8, 0))
	_banyan_dock.add_log(">>> %s" % prompt.substr(0, 80), "info")

	# 统一入口: 始终通过 Root 协调，由 Agent 自主决定是否拆分
	run_banyan(prompt)


func _on_dock_stop_requested() -> void:
	if _root:
		_root.abort()
	# 持久化当前树状态
	_sync_agent_tree()
	if _banyan_dock:
		_banyan_dock.set_running(false)
		_banyan_dock.set_banyan_status("Stopped", Color(0.8, 0.5, 0.2))
		_banyan_dock.add_log("Stopped by user", "warning")
		_banyan_dock.append_assistant_message("[已停止]")


func _on_dock_session_requested(action: String, id: String) -> void:
	match action:
		"new":
			_new_session()
		"open":
			# 显示会话管理弹窗
			if _session_popup:
				var sessions: Array = _list_sessions()
				_session_popup.refresh(sessions, _session_id)
				_session_popup.popup_centered()
		"load":
			if not id.is_empty():
				_load_session(id)


func _on_dock_worker_progress(wid: String, chunk: String) -> void:
	if _banyan_dock:
		# 流式输出到消息区
		_banyan_dock.receive_chunk(chunk, wid)
		# 截取前 80 字符作为活动日志
		var preview: String = chunk.substr(0, 80).replace("\n", " ")
		_banyan_dock.add_log("[%s] %s" % [wid, preview], "info")
		_throttled_tree_refresh()


func _on_dock_worker_done(wid: String, report: Dictionary) -> void:
	if _banyan_dock:
		var summary: String = report.get("summary", "")
		var had_stream: bool = _banyan_dock._stream_node != null
		_banyan_dock.end_stream()
		# 如果流式已输出，内容已在气泡中；否则用 summary 兜底显示
		if not had_stream and not summary.is_empty():
			_banyan_dock.append_assistant_message(summary, wid)
		_banyan_dock.set_running(false)
		_banyan_dock.set_banyan_status("Done", Color(0.2, 0.8, 0.2))
		_banyan_dock.add_log("[%s] Done: %s" % [wid, summary.substr(0, 60)], "success")
		_refresh_dock_tree()

		# 保存助手回复到对话历史
		_append_assistant_to_conversation(summary)


func _on_dock_tool_started(wid: String, tool_name: String) -> void:
	if _banyan_dock:
		_banyan_dock.append_tool_started(tool_name)
		_banyan_dock.add_log("[%s] Tool: %s" % [wid, tool_name], "tool")


func _on_dock_tool_finished(wid: String, tool_name: String, ok: bool) -> void:
	if _banyan_dock:
		_banyan_dock.append_tool_finished(tool_name, ok)


func _on_dock_worker_error(wid: String, error: String) -> void:
	if _banyan_dock:
		_banyan_dock.end_stream()
		_banyan_dock.append_error("[%s] %s" % [wid, error])
		_banyan_dock.add_log("[%s] Error: %s" % [wid, error], "error")
		_refresh_dock_tree()


func _on_dock_banyan_done(report: Dictionary) -> void:
	if _banyan_dock:
		_banyan_dock.end_stream()
		_banyan_dock.set_running(false)
		_banyan_dock.set_banyan_status("Completed", Color(0.2, 0.8, 0.2))

		# 总结的唯一渲染路径是 _append_assistant_to_conversation → rebuild_messages，
		# 这里不再兜底追加（否则与 rebuild 渲染的气泡重复）
		_banyan_dock.add_log("Banyan completed: rounds=%d, children=%d, files=%d" % [
			report.get("rounds", 0),
			report.get("children_count", 0),
			report.get("files", []).size(),
		], "success")

	# 刷新 Agent Tree 可视化 + 持久化
	_refresh_dock_tree()
	_sync_agent_tree()


## 节流版树刷新 — 运行期间最多每0.5秒刷新一次 Agent Graph
## 由 state_changed / progress_tool_started / progress_tool_finished 驱动；
## LLM 流式期间由节点的流式心跳（state_changed, ~2次/秒）驱动，图上有实时流入量
func _on_graph_dirty(_a = null, _b = null) -> void:
	_throttled_tree_refresh()


func _throttled_tree_refresh() -> void:
	if _tree_refresh_timer == null:
		_tree_refresh_timer = Timer.new()
		_tree_refresh_timer.one_shot = true
		_tree_refresh_timer.wait_time = 0.5
		_tree_refresh_timer.timeout.connect(_on_tree_refresh_timeout)
		if _host_node:
			_host_node.add_child(_tree_refresh_timer)
	if _tree_refresh_timer.is_stopped():
		# 首次调用 — 立即刷新，然后启动计时器防止后续快速刷新
		_refresh_dock_tree()
		_tree_refresh_timer.start()
	else:
		# 计时器运行中 — 标记待刷新，等计时器到期再刷
		_tree_refresh_pending = true


func _on_tree_refresh_timeout() -> void:
	if _tree_refresh_pending:
		_tree_refresh_pending = false
		_refresh_dock_tree()
		_tree_refresh_timer.start()


## 从 Root 状态构建 Dock 树形数据（轻量级 UI 刷新，不含 AgentTree 持久化）
func _refresh_dock_tree() -> void:
	if not _root:
		return

	# 构建底部面板的 Dictionary 数据
	var data: Dictionary = {
		"root_id": str(_root.node_id),
		"root_state": _state_to_string(_root.node_state),
		"rounds": _root.get_round_count(),
		"files": _root.managed_files.duplicate(),
		"ctx_size": _root.get_ctx_size(),
		"stream_chars": _root._stream_chars,
		"domain_knowledge": _root.domain_knowledge,
		"history": _root.history.duplicate() if _root.history is Array else [],
		"children": _build_child_tree_data(_root),
	}

	if _banyan_bottom_panel:
		_banyan_bottom_panel.update_tree(data)


## 同步运行时树到 AgentTree 并持久化（仅在完成/停止时调用）
func _sync_agent_tree() -> void:
	if not _root or not _agent_tree:
		return
	# 节点本身就是 AgentNode — 直接收集到树中
	_agent_tree.collect_runtime_nodes(_root)
	_agent_tree.save()
	# 写入运行日志
	_write_run_log()
	# 更新 prune 建议
	if _banyan_bottom_panel:
		var suggestions: Array = _agent_tree.analyze_for_prune()
		_banyan_bottom_panel.set_prune_suggestions(suggestions)
		# 用完整的 AgentTree 数据刷新面板（含历史知识）
		_banyan_bottom_panel.update_tree(_agent_tree)


## 写入 Banyan 运行日志 — 从根节点收集完整执行轨迹
func _write_run_log() -> void:
	if not _root or _session_id.is_empty():
		return
	var trace: Dictionary = _root.get_execution_trace()
	if trace.is_empty():
		return
	var run_log = BanyanRunLogScript.new(_session_id, _logger)
	var result: Dictionary = run_log.write(trace)
	if result.get("ok", false):
		_logger.append("CTX", "Run log written: %s" % result.get("json_path", ""))
	else:
		_logger.append("CTX", "Run log write failed: %s" % str(result.get("error", "")))


## 递归构建子节点树数据
func _build_child_tree_data(parent_node) -> Dictionary:
	var result: Dictionary = {}
	for cname in parent_node._children:
		var child = parent_node._children[cname]
		var child_data: Dictionary = {
			"state": _state_to_string(child.node_state),
			"rounds": child.get_round_count(),
			"files": child.managed_files.duplicate(),
			"ctx_size": child.get_ctx_size(),
			"stream_chars": child._stream_chars,
			"domain_knowledge": child.domain_knowledge,
			"history": child.history.duplicate() if child.history is Array else [],
			"children": _build_child_tree_data(child),
		}
		result[cname] = child_data
	return result


func _state_to_string(state: int) -> String:
	match state:
		0: return "IDLE"
		1: return "RUNNING"
		2: return "LLM_REQUEST"
		3: return "TOOL_EXEC"
		4: return "COMPLETED"
		5: return "FAILED"
		6: return "RETRYING"
		_: return "UNKNOWN"
