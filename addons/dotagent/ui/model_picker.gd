@tool
class_name ModelPicker
extends HBoxContainer
## 模型选择器（拆自 dock.gd）
##
## 节点结构（详见 dock.tscn 中的 ModelBar）:
##   ModelLabel  ModelButton  RefreshModelsButton  ModelPopup
##
## 职责:
##   - 显示当前模型名（按钮文本）
##   - 点击按钮 → 弹出 PopupMenu（在按钮上方）
##   - 刷新 → 调 ModelFetcher.fetch_models() 拉取并填充
##   - 选择 → 通过 model_selected(id, vision, context_length) 回调给 dock

signal model_selected(model_id: String, vision: bool, context_limit: int)

@onready var model_button: Button = %ModelButton
@onready var refresh_button: Button = %RefreshModelsButton
@onready var model_popup: PopupMenu = %ModelPopup
@onready var model_label: Label = $ModelLabel

var _fetcher: ModelFetcher = null
var _controller: DockController = null
var _fetched_models: Array[Dictionary] = []


func _ready() -> void:
	_fetcher = ModelFetcher.new()
	model_button.pressed.connect(_on_model_button_pressed)
	refresh_button.pressed.connect(_on_refresh_models_pressed)
	model_popup.index_pressed.connect(_on_model_selected)


## 由 dock 注入 controller
func set_controller(controller: DockController) -> void:
	_controller = controller


## 更新按钮文本（当前模型名）
func set_current_model(model_name: String) -> void:
	model_button.text = model_name if not model_name.is_empty() else Locale.t("(not configured)")


## 由 dock 在语言切换时调用
func on_locale_changed() -> void:
	if model_label:
		model_label.text = Locale.t("Model:")


func _on_model_button_pressed() -> void:
	if model_popup.item_count == 0:
		_on_refresh_models_pressed()
		return
	_show_model_popup_above()


func _on_refresh_models_pressed() -> void:
	_fetched_models.clear()
	model_popup.clear()
	model_button.disabled = true
	refresh_button.disabled = true
	refresh_button.tooltip_text = "Fetching..."

	if _controller == null:
		_on_models_fetched(false, [], "No controller")
		return
	var cfg := _controller.get_config_manager()
	var provider_name: String = cfg.get_provider_name()
	_fetcher.fetch_models(provider_name, self, func(success: bool, models: Array[Dictionary], error_msg: String):
		_on_models_fetched(success, models, error_msg)
	)


func _on_models_fetched(success: bool, models: Array[Dictionary], error_msg: String) -> void:
	model_button.disabled = false
	refresh_button.disabled = false
	model_popup.clear()
	_fetched_models = models.duplicate()
	if success and not models.is_empty():
		var current_model := model_button.text
		for info in models:
			var item_text := _format_model_item(info)
			model_popup.add_item(item_text)
			# 标记当前使用的模型
			if str(info.get("id", "")) == current_model:
				var idx := model_popup.item_count - 1
				model_popup.set_item_checked(idx, true)
		refresh_button.tooltip_text = "%d models available" % models.size()
		_show_model_popup_above()
	else:
		model_popup.add_item("(failed: %s)" % error_msg.substr(0, 40))
		refresh_button.tooltip_text = error_msg.substr(0, 120)


func _on_model_selected(idx: int) -> void:
	if idx < 0 or idx >= _fetched_models.size():
		return
	var info := _fetched_models[idx]
	var model := str(info.get("id", ""))
	if model.is_empty():
		return
	model_button.text = model
	# vision 和 context 由模型设置页面统一管理，此处不再从 API 数据推断
	model_selected.emit(model, false, 0)


func _show_model_popup_above() -> void:
	var btn_screen_pos := model_button.get_screen_position()
	model_popup.reset_size()
	var popup_size := model_popup.size
	if popup_size.y <= 0:
		popup_size.y = model_popup.item_count * 28
	var pos := Vector2i(int(btn_screen_pos.x), int(btn_screen_pos.y) - popup_size.y)
	model_popup.position = pos
	model_popup.popup()


## 格式化菜单项：仅显示模型名
func _format_model_item(info: Dictionary) -> String:
	return str(info.get("id", ""))
