@tool
extends VBoxContainer
## AI Panel 主 Dock - UI 层（纯前端，所有业务走 DockController）
##
## 职责:
## - 渲染消息流、按钮状态、进度倒计时
## - 接收用户输入(按钮、键盘)
## - 把所有业务调用转发给 DockController
##
## 子模块:
##   MessageRenderer  — 消息流渲染、滚动、流式状态
##   ThinkSectionRenderer — Think 折叠块
##   ModelPicker       — 模型选择器（弹窗 + 刷新 + 格式化）
##   SessionPanel      — 会话列表面板（已独立）

const MessageRendererScript = preload("res://addons/dotagent/ui/message_renderer.gd")

# 由 plugin.gd 注入
var plugin: EditorPlugin
var activity_panel: Control

# 业务后端
var _controller: DockController = null

# UI 节点引用
@onready var message_list: VBoxContainer = %MessageList
@onready var message_scroll: ScrollContainer = %MessageScroll
@onready var input_field: TextEdit = %InputField
@onready var send_button: Button = %SendButton
@onready var stop_button: Button = %StopButton
@onready var settings_button: Button = %SettingsButton
@onready var compact_button: Button = %CompactButton
@onready var model_settings_button: Button = %ModelSettingsButton
@onready var session_button: Button = %SessionButton
@onready var session_popup: PopupPanel = %SessionPopup
@onready var context_label: Label = %ContextLabel
@onready var model_bar: HBoxContainer = %ModelBar

# 进度状态
var _progress_node: RichTextLabel = null

# 子模块
var _renderer: MessageRenderer = null
var _model_picker: ModelPicker = null


func _ready() -> void:
	_renderer = MessageRendererScript.new(message_list, message_scroll)
	# 1. 业务后端
	_controller = DockController.new()
	_controller.setup(plugin, activity_panel, self)
	# 1b. 模型选择器: 直接用 tscn 里挂在 ModelBar 上的 ModelPicker
	_model_picker = model_bar as ModelPicker
	if _model_picker:
		_model_picker.set_controller(_controller)
		_model_picker.model_selected.connect(_on_model_picker_selected)
		_model_picker.set_current_model(_controller.get_config_manager().get_model())
	# 2. 订阅 controller signal
	_controller.stream_started.connect(_on_stream_started)
	_controller.stream_chunk.connect(_on_stream_chunk)
	_controller.round_complete.connect(_on_round_complete)
	_controller.stream_error.connect(_on_stream_error)
	_controller.progress_remaining.connect(_on_progress_remaining)
	_controller.progress_done.connect(_on_progress_done)
	_controller.config_changed.connect(_on_config_changed)
	_controller.session_changed.connect(_on_session_changed)
	_controller.tool_started.connect(_on_tool_started)
	_controller.tool_finished.connect(_on_tool_finished)
	_controller.loop_finished.connect(_on_loop_finished)

	# 3. 按钮绑定
	send_button.pressed.connect(_on_send_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	compact_button.pressed.connect(_on_compact_pressed)
	session_button.pressed.connect(_on_session_pressed)
	model_settings_button.pressed.connect(_on_model_settings_pressed)
	session_popup.set_controller(_controller)
	input_field.gui_input.connect(_on_input_gui_input)
	input_field.text_changed.connect(_on_input_text_changed)

	# 4. 启动
	_apply_locale()
	_update_context_label()
	_controller.bootstrap_session()

	if not _controller.get_config_manager().is_configured():
		_renderer.append_assistant_node(Locale.t("Please configure API in Settings first (Base URL / Key / Model)."))


# ============ Controller signal 订阅 ============

func _on_stream_started() -> void:
	_renderer.begin_stream()


func _on_stream_chunk(chunk: String) -> void:
	_renderer.receive_chunk(chunk)


func _on_round_complete(content: String, tool_calls: Array, tool_results: Array) -> void:
	_renderer.end_stream(tool_calls, tool_results)
	_update_context_label()


func _on_stream_error(error: String) -> void:
	_renderer.append_assistant_node("[color=#ff6666]❌ %s[/color]" % error)
	_update_context_label()


func _on_progress_remaining(remaining: float) -> void:
	if _progress_node == null or not is_instance_valid(_progress_node):
		_progress_node = RichTextLabel.new()
		_progress_node.bbcode_enabled = true
		_progress_node.fit_content = true
		message_list.add_child(_progress_node)
	_progress_node.clear()
	_progress_node.append_text("[color=#888888][i]Waiting for response... %ds timeout[/i][/color]" % int(remaining))
	_renderer._scroll_to_bottom(true)


func _on_loop_finished() -> void:
	_set_running(false)


func _on_progress_done() -> void:
	if _progress_node and is_instance_valid(_progress_node):
		_progress_node.queue_free()
		_progress_node = null


func _on_tool_started(tool_name: String) -> void:
	_renderer.append_tool_started(tool_name)


func _on_tool_finished(tool_name: String, ok: bool) -> void:
	_renderer.append_tool_finished(tool_name, ok)


func _on_config_changed() -> void:
	_apply_locale()
	_update_context_label()
	if _model_picker:
		_model_picker.on_locale_changed()
	if session_popup:
		session_popup.on_locale_changed()


func _on_session_changed(_session_id: String, _messages: Array) -> void:
	_renderer.rebuild(_messages)
	_update_context_label()


# ============ 按钮事件 ============

func _on_input_text_changed() -> void:
	# 根据内容行数自动扩展输入框高度（38-200px）
	var line_count := input_field.get_line_count()
	var line_height := 22.0
	var min_h := 38.0
	var max_h := 200.0
	var target := clamp(line_count * line_height + 12, min_h, max_h)
	input_field.custom_minimum_size.y = target


func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER and not event.shift_pressed:
		input_field.accept_event()
		_on_send_pressed()
		get_viewport().set_input_as_handled()


func _on_send_pressed() -> void:
	if _controller.is_running():
		return
	var text := input_field.text.strip_edges()
	if text.is_empty():
		return
	_renderer.append_user_node(text)
	input_field.text = ""
	_set_running(true)
	_controller.send_user_message(text)


func _on_stop_pressed() -> void:
	_controller.abort_current()


## ModelPicker 选中模型 → 写入 config（仅改模型名，vision/context 由模型设置页面管理）
func _on_model_picker_selected(model: String, _vision: bool, _context_limit: int) -> void:
	var cfg := _controller.get_config_manager()
	var old_model := cfg.get_model()

	var err := cfg.save(
		cfg.get_base_url(),
		cfg.get_api_key(),
		model,
		cfg.get_temperature(),
		cfg.get_context_limit(),
		cfg.get_language(),
		cfg.get_max_tokens_k(),
		cfg.get_vision_enabled(),
		cfg.get_proxy_host(),
		cfg.get_proxy_port(),
		cfg.get_provider_name(),
	)
	if err != OK:
		push_warning("[DotAgent] Failed to save model selection")
		return

	if model != old_model:
		print_rich("[color=#88cc88][DotAgent][/color] model: %s" % model)


func _on_settings_pressed() -> void:
	_controller.open_settings()


func _on_compact_pressed() -> void:
	_controller.compact_context()


func _on_session_pressed() -> void:
	if session_popup:
		session_popup.open()


func _on_model_settings_pressed() -> void:
	var dlg_scene := load("res://addons/dotagent/ui/modelsettings_dialog.tscn") as PackedScene
	if dlg_scene == null:
		return
	var dlg := dlg_scene.instantiate()
	dlg.model_settings_changed.connect(_on_model_settings_changed)
	add_child(dlg)
	dlg.popup_centered()


func _on_model_settings_changed() -> void:
	_update_context_label()
	if _model_picker:
		_model_picker.set_current_model(_controller.get_config_manager().get_model())
	# 通知 controller 刷新配置
	_controller.on_config_saved()


# ============ 工具方法 ============

func _set_running(running: bool) -> void:
	input_field.editable = not running
	send_button.disabled = running
	stop_button.disabled = not running


func _apply_locale() -> void:
	Locale.set_lang(_controller.get_config_manager().get_language())
	_set_text(session_button, Locale.t("Sessions"))
	_set_text(compact_button, Locale.t("Compact"))
	_set_text(settings_button, Locale.t("Settings"))
	_set_text(model_settings_button, Locale.t("Model"))
	_set_text(send_button, Locale.t("Send"))
	_set_text(stop_button, Locale.t("Stop"))
	input_field.placeholder_text = Locale.t("Ask AI to do something... (Enter to send, Shift+Enter for newline)")
	if context_label:
		context_label.text = ""
	# 会话面板自己处理本地化
	if session_popup:
		session_popup.on_locale_changed()


func _set_text(node: Node, text: String) -> void:
	if node and node is Button:
		node.text = text


func _update_context_label() -> void:
	if context_label == null or _controller == null:
		return
	var stats := _controller.estimate_context_usage()
	var used: int = stats.get("used_k", 0)
	var limit: int = stats.get("max_k", 0)
	var pct: int = stats.get("pct", 0)
	var color := Color(0.36, 0.84, 0.36)  # 绿色
	if pct > 80:
		color = Color(1.0, 0.27, 0.27)    # 红色
	elif pct > 60:
		color = Color(1.0, 0.67, 0.27)    # 橙色
	context_label.text = "📊 %dK / %dK (%d%%)" % [used, limit, pct]
	context_label.add_theme_color_override("font_color", color)


func on_config_saved() -> void:
	_apply_locale()
	_update_context_label()
	if _model_picker:
		_model_picker.set_current_model(_controller.get_config_manager().get_model())
		_model_picker.on_locale_changed()
	if session_popup:
		session_popup.on_locale_changed()
