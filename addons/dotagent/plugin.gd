@tool
extends EditorPlugin
## AI Panel 插件入口
##
## 注册:
## - 主 Dock(右下):对话面板
## - 底部面板:活动日志(工具调用流)
## - 设置弹窗(由 Dock 触发)

# 关键:不要用 const preload .tscn — 那会在 plugin.gd 编译时把 .tscn 内容嵌进去,
# 改 .tscn 后必须重编译 plugin 才生效。改用 var + runtime load,
# 这样 disable + enable 插件就能立刻用最新 .tscn。
var _dock_scene: PackedScene = null
var _config_dialog_scene: PackedScene = null
var _activity_panel_scene: PackedScene = null

const ACTIVITY_PANEL_TITLE := "Activity"

var _dock: Control = null
var _activity_panel: Control = null
var _config_dialog: Window = null


func _enter_tree() -> void:
	# 运行时 load(每次 enable 插件都重新读 .tscn)
	_dock_scene = load("res://addons/dotagent/ui/dock.tscn")
	_config_dialog_scene = load("res://addons/dotagent/ui/config_dialog.tscn")
	_activity_panel_scene = load("res://addons/dotagent/ui/activity_panel.tscn")

	# 底部活动面板
	_activity_panel = _activity_panel_scene.instantiate()
	add_control_to_bottom_panel(_activity_panel, ACTIVITY_PANEL_TITLE)

	# 主 Dock
	_dock = _dock_scene.instantiate()
	_dock.plugin = self
	_dock.activity_panel = _activity_panel
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _dock != null and is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _activity_panel != null and is_instance_valid(_activity_panel):
		remove_control_from_bottom_panel(_activity_panel)
		_activity_panel.queue_free()
		_activity_panel = null
	if _config_dialog != null and is_instance_valid(_config_dialog):
		_config_dialog.queue_free()
		_config_dialog = null
	_dock_scene = null
	_config_dialog_scene = null
	_activity_panel_scene = null


## 弹出设置对话框
func open_config_dialog() -> void:
	if _config_dialog_scene == null:
		_config_dialog_scene = load("res://addons/dotagent/ui/config_dialog.tscn")
	if _config_dialog != null and is_instance_valid(_config_dialog):
		_config_dialog.popup_centered()
		return
	_config_dialog = _config_dialog_scene.instantiate()
	_config_dialog.config_saved.connect(_on_config_saved)
	get_editor_interface().get_base_control().add_child(_config_dialog)
	_config_dialog.popup_centered()


func _on_config_saved() -> void:
	if _dock != null and is_instance_valid(_dock) and _dock.has_method("on_config_saved"):
		_dock.on_config_saved()
