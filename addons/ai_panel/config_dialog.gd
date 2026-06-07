@tool
extends Window
## AI Panel 设置对话框

signal config_saved

@onready var base_url_field: LineEdit = %BaseUrlField
@onready var api_key_field: LineEdit = %ApiKeyField
@onready var model_field: LineEdit = %ModelField
@onready var max_tokens_field: SpinBox = %MaxTokensField
@onready var temp_field: SpinBox = %TempField
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton
@onready var test_button: Button = %TestButton
@onready var status_label: Label = %StatusLabel

var _config: ConfigManager
var _testing: bool = false


func _ready() -> void:
	_config = ConfigManager.new()
	_load_values()
	save_button.pressed.connect(_on_save)
	cancel_button.pressed.connect(_on_cancel)
	test_button.pressed.connect(_on_test)
	close_requested.connect(_on_cancel)


func _load_values() -> void:
	base_url_field.text = _config.get_base_url()
	api_key_field.text = _config.get_api_key()
	model_field.text = _config.get_model()
	max_tokens_field.value = _config.get_max_tokens()
	temp_field.value = _config.get_temperature()


func _on_save() -> void:
	var err := _config.save(
		base_url_field.text.strip_edges(),
		api_key_field.text,
		model_field.text.strip_edges(),
		int(max_tokens_field.value),
		float(temp_field.value),
	)
	if err != OK:
		_set_status("❌ Save failed: " + error_string(err), true)
		return
	config_saved.emit()
	_set_status("✅ Saved. Testing connection...", false)
	# 默认跑一次连接测试 — 失败也保留配置,但提示用户
	# 复用 _on_test 内部逻辑(await),但不用 test_button 倒计时显示(test 自己的 UI)
	_testing = true
	var client := LLMClient.new()
	client.set_host(self)
	var done := [false]
	var err_msg := [""]
	var ok_resp := [false]
	client.stream_finished.connect(func(_content, _tool_calls):
		ok_resp[0] = true
		done[0] = true
	)
	client.stream_error.connect(func(err):
		err_msg[0] = err
		done[0] = true
	)
	client.chat_stream([{"role": "user", "content": "ping"}], [], 10.0)
	while not done[0]:
		await Engine.get_main_loop().process_frame
	_testing = false
	if err_msg[0] != "":
		_set_status("⚠️ Saved, but connection test failed: " + err_msg[0].substr(0, 150), true)
		# 配置已存,等用户看完提示再关
		await get_tree().create_timer(2.5).timeout
	else:
		_set_status("✅ Saved & connection OK", false)
		await get_tree().create_timer(0.5).timeout
	hide()


func _on_cancel() -> void:
	hide()


func _on_test() -> void:
	if _testing:
		return
	_testing = true
	test_button.disabled = true
	test_button.text = "⏱ 10s"
	_set_status("Testing...", false)

	# 先存当前测试值
	_config.save(
		base_url_field.text.strip_edges(),
		api_key_field.text,
		model_field.text.strip_edges(),
		int(max_tokens_field.value),
		float(temp_field.value),
	)

	var client := LLMClient.new()
	client.set_host(self)
	var done := [false]
	var err_msg := [""]
	var ok_resp := [false]
	client.stream_finished.connect(func(_content, _tool_calls):
		ok_resp[0] = true
		done[0] = true
	)
	client.stream_error.connect(func(err):
		err_msg[0] = err
		done[0] = true
	)
	# 倒计时显示
	client.progress_remaining.connect(func(sec):
		if is_instance_valid(test_button):
			test_button.text = "⏱ %ds" % int(sec)
	)
	client.progress_done.connect(func():
		if is_instance_valid(test_button):
			test_button.text = "Test"
	)
	client.chat_stream([{"role": "user", "content": "ping"}], [], 10.0)  # Test Connection 用 10s 快速超时

	while not done[0]:
		await Engine.get_main_loop().process_frame

	# LLMClient 是 RefCounted,lambda 释放引用后自动回收,无需手动 free
	_testing = false
	test_button.disabled = false
	test_button.text = "Test"

	if err_msg[0] != "":
		_set_status("❌ " + err_msg[0].substr(0, 200), true)
	else:
		_set_status("✅ Connection OK", false)


func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.modulate = Color(0.95, 0.4, 0.4) if is_error else Color(0.5, 0.85, 0.5)
