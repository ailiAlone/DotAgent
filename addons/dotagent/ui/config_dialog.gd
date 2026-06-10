@tool
extends Window
## AI Panel 设置对话框
signal config_saved

@onready var base_url_field: LineEdit = %BaseUrlField
@onready var api_key_field: Label = %ApiKeyField
@onready var vision_checkbox: CheckBox = %VisionCheckBox
@onready var model_field: LineEdit = %ModelField
@onready var temp_field: SpinBox = %TempField
@onready var context_limit_field: SpinBox = %ContextLimitField
@onready var language_field: OptionButton = %LanguageField
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton
@onready var test_button: Button = %TestButton
@onready var status_label: Label = %StatusLabel

var _config: ConfigManager
var _testing: bool = false


func _ready() -> void:
	_config = ConfigManager.instance()
	Locale.set_lang(_config.get_language())
	_load_values()
	save_button.pressed.connect(_on_save)
	cancel_button.pressed.connect(_on_cancel)
	test_button.pressed.connect(_on_test)
	close_requested.connect(_on_cancel)
	language_field.item_selected.connect(_on_lang_changed)


func _load_values() -> void:
	base_url_field.text = _config.get_base_url()
	# API key only from DOTAGENT_API_KEY env var
	var key := _config.get_api_key()
	if key.is_empty():
		api_key_field.text = "❌ Not set — run: setx DOTAGENT_API_KEY \"ey-...\" then restart Godot"
	else:
		api_key_field.text = "✅ Loaded from DOTAGENT_API_KEY"
	vision_checkbox.button_pressed = _config.get_vision_enabled()
	model_field.text = _config.get_model()
	temp_field.value = _config.get_temperature()
	context_limit_field.value = _config.get_context_limit()
	language_field.select(1 if _config.get_language() == "en" else 0)


func _on_lang_changed(idx: int) -> void:
	Locale.set_lang("en" if idx == 1 else "zh")
	_update_ui_texts()
	config_saved.emit()

func _update_ui_texts() -> void:
	title = Locale.t("AI Panel Settings")
	if save_button: save_button.text = Locale.t("Save")
	if cancel_button: cancel_button.text = Locale.t("Cancel")
	if test_button: test_button.text = Locale.t("Test")
	# 更新 Form 标签
	var form := $Root/Form if has_node("Root/Form") else null
	if form == null:
		return
	_set_label(form, "BaseUrlLabel", Locale.t("Base URL:"))
	_set_label(form, "ApiKeyLabel", Locale.t("API Key:"))
	_set_label(form, "ModelLabel", Locale.t("Model:"))
	_set_label(form, "TempLabel", Locale.t("Temperature:"))
	_set_label(form, "ContextLimitLabel", Locale.t("Context Limit (K):"))
	_set_label(form, "LanguageLabel", Locale.t("Language:"))


func _set_label(form: Node, name: String, text: String) -> void:
	if form.has_node(name):
		var label := form.get_node(name)
		if label is Label:
			label.text = text

func _on_save() -> void:
	var err := _config.save(
		base_url_field.text.strip_edges(),
		_config.get_api_key(),
		model_field.text.strip_edges(),
		float(temp_field.value),
		int(context_limit_field.value),
		"en" if language_field.selected == 1 else "zh",
		_config.get_max_tokens_k(),
		vision_checkbox.button_pressed,
	)
	if err != OK:
		_set_status("❌ Save failed: " + error_string(err), true)
		return
	config_saved.emit()
	_set_status("✅ Saved. Testing connection...", false)
	_testing = true
	_test_connection()
	while _testing:
		await Engine.get_main_loop().process_frame
	if _test_ok:
		_set_status("✅ Saved & connection OK", false)
		await get_tree().create_timer(0.5).timeout
	else:
		_set_status("⚠️ Saved, but connection test failed: " + _test_err.substr(0, 150), true)
		await get_tree().create_timer(2.5).timeout
	hide()


func _on_cancel() -> void:
	hide()


var _test_ok: bool = false
var _test_err: String = ""


func _test_connection() -> void:
	var base := base_url_field.text.strip_edges().trim_suffix("/")
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5
	http.request_completed.connect(func(_result, code, _headers, _body):
		_test_ok = code >= 200 and code < 300
		if not _test_ok:
			_test_err = "HTTP %d: %s" % [code, _body.get_string_from_utf8().substr(0, 200)]
		_testing = false
		http.queue_free()
	)
	var body := JSON.stringify({
		"model": model_field.text.strip_edges(),
		"messages": [{"role": "user", "content": "hi"}],
		"max_tokens": 1,
		"stream": false,
	})
	http.request(base + "/chat/completions", ["Content-Type: application/json", "Authorization: Bearer " + _config.get_api_key()], HTTPClient.METHOD_POST, body)


func _on_test() -> void:
	if _testing:
		return
	_testing = true
	test_button.disabled = true
	test_button.text = "…"
	_set_status(Locale.t("Testing..."), false)
	_config.save(
		base_url_field.text.strip_edges(),
		_config.get_api_key(),
		model_field.text.strip_edges(),
		float(temp_field.value),
		int(context_limit_field.value),
		"en" if language_field.selected == 1 else "zh",
		_config.get_max_tokens_k(),
		vision_checkbox.button_pressed,
	)
	_test_connection()
	while _testing:
		await Engine.get_main_loop().process_frame
	test_button.disabled = false
	test_button.text = "Test"
	if _test_ok:
		_set_status("✅ Connection OK", false)
	else:
		_set_status("❌ " + _test_err, true)


func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.modulate = Color(0.95, 0.4, 0.4) if is_error else Color(0.5, 0.85, 0.5)
