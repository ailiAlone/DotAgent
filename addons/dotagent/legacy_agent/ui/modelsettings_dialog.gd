@tool
extends Window
## 模型设置弹窗 — 视觉开关 / 上下文限制 / 自动压缩阈值
##
## 所有配置实时生效，无需保存按钮。

signal model_settings_changed()

@onready var vision_enable_label: Label = %VisionEnableLabel
@onready var vision_enable_checkbox: CheckBox = %VisionEnableCheckBox
@onready var context_length_label: Label = %ContextLengthLabel
@onready var context_length_line_edit: LineEdit = %ContextLengthLineEdit
@onready var automatic_compression_threshold_label: Label = %AutomaticCompressionThresholdLabel
@onready var automatic_compression_threshold_spin_box: SpinBox = %AutomaticCompressionThresholdSpinBox

var _config: ConfigManager = null


func _ready() -> void:
	_config = ConfigManager.instance()
	_load_values()
	_connect_signals()
	_apply_locale()


func _load_values() -> void:
	vision_enable_checkbox.button_pressed = _config.get_vision_enabled()
	context_length_line_edit.text = str(_config.get_context_limit())
	automatic_compression_threshold_spin_box.value = _config.get_compression_threshold()


func _connect_signals() -> void:
	vision_enable_checkbox.toggled.connect(func(_pressed: bool): _apply_change())
	context_length_line_edit.text_changed.connect(func(_new_text: String): _apply_change())
	automatic_compression_threshold_spin_box.value_changed.connect(func(_value: float): _apply_change())
	close_requested.connect(hide)


func _apply_change() -> void:
	var vision := vision_enable_checkbox.button_pressed
	var ctx_limit := int(context_length_line_edit.text)
	if ctx_limit <= 0:
		ctx_limit = ConfigManager.DEFAULT_CONTEXT_LIMIT
	var compression := int(automatic_compression_threshold_spin_box.value)

	var old_vision := _config.get_vision_enabled()
	var old_ctx := _config.get_context_limit()
	var old_compression := _config.get_compression_threshold()

	var err := _config.save_model_settings(vision, ctx_limit, compression)
	if err != OK:
		push_warning("[DotAgent] Failed to save model settings: %d" % err)
		return

	if vision != old_vision:
		print_rich("[color=#88cc88][DotAgent][/color] vision: %s" % ("on" if vision else "off"))
	elif ctx_limit != old_ctx:
		print_rich("[color=#88cc88][DotAgent][/color] context: %dK" % ctx_limit)
	elif compression != old_compression:
		print_rich("[color=#88cc88][DotAgent][/color] compress: %d%%" % compression)

	model_settings_changed.emit()


func _apply_locale() -> void:
	title = "模型设置"
	if vision_enable_label:
		vision_enable_label.text = "图片输入："
	if vision_enable_checkbox:
		vision_enable_checkbox.text = "启用"
	if context_length_label:
		context_length_label.text = "上下文限制："
	if automatic_compression_threshold_label:
		automatic_compression_threshold_label.text = "自动压缩阈值："
