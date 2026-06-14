@tool
extends Window
## AI Panel 设置对话框
##
## 所有配置实时生效，无需保存按钮。
##
## 控件结构（详见 config_dialog.tscn）:
##   Provider_and_BaseURL: ProviderSelect + BaseUrlField
##   APIKEY:               ApiKeyLabel + ApiKeyField
##   Proxy:                Label + CheckBox + Label2 + ProxyHostField + ProxyPortField
##   Language:             LanguageLabel + LanguageField
##   Buttons:              TestButton
##
## Model 选择器在主 Dock 底部管理，不在此处展示。

signal config_saved

@onready var hint_label: Label = $MarginContainer/Root/HintLabel
@onready var provider_label: Label = $MarginContainer/Root/Provider/Label
@onready var provider_select: OptionButton = $MarginContainer/Root/Provider/ProviderSelect
@onready var base_url_field: LineEdit = $MarginContainer/Root/BaseUrlField
@onready var api_key_label: Label = $MarginContainer/Root/APIKEY/ApiKeyLabel
@onready var api_key_input: LineEdit = $MarginContainer/Root/APIKEY/ApiKeyLineEdit
@onready var apply_restart_button: Button = $MarginContainer/Root/APIKEY/HBoxContainer/ApplyAndRestartButton
@onready var proxy_label: Label = $MarginContainer/Root/Proxy/Label
@onready var proxy_enabled_checkbox: CheckBox = $MarginContainer/Root/Proxy/CheckBox
@onready var proxy_host_field: LineEdit = $MarginContainer/Root/Proxy/ProxyHostField
@onready var proxy_port_field: SpinBox = $MarginContainer/Root/Proxy/ProxyPortField
@onready var language_label: Label = $MarginContainer/Root/Language/LanguageLabel
@onready var language_field: OptionButton = $MarginContainer/Root/Language/LanguageField
@onready var test_button: Button = $MarginContainer/Root/APIKEY/HBoxContainer/TestButton

const API_KEY_HINT_TITLE := "api_key_hint_title"
const API_KEY_HINT_BODY := "api_key_hint_body"
const LANGUAGE_HINT := "language_hint"

var _config: ConfigManager = null
var _model_fetcher: ModelFetcher = null
var _testing: bool = false
var _test_ok: bool = false
var _test_err: String = ""
var _test_model_count: int = 0


func _ready() -> void:
	_config = ConfigManager.instance()
	_model_fetcher = ModelFetcher.new()
	Locale.set_lang(_config.get_language())
	_populate_provider_list()
	_load_values()
	# 初始化时不应用预设（避免覆盖用户已保存的 vision）
	if provider_select.selected >= 0:
		_on_provider_selected(provider_select.selected, false)
	_apply_locale()
	_connect_signals()
	_setup_tooltips()


## 给 API Key 标签添加悬浮提示，说明如何配置环境变量
func _setup_tooltips() -> void:
	var api_key_hint := Locale.t(API_KEY_HINT_TITLE) + "\n\n" + Locale.t(API_KEY_HINT_BODY)
	if api_key_label:
		api_key_label.tooltip_text = api_key_hint
		api_key_label.mouse_filter = Control.MOUSE_FILTER_STOP
	if language_label:
		language_label.tooltip_text = Locale.t(LANGUAGE_HINT)
		language_label.mouse_filter = Control.MOUSE_FILTER_STOP


func _connect_signals() -> void:
	provider_select.item_selected.connect(_on_provider_selected)
	base_url_field.focus_exited.connect(_apply_change)
	proxy_enabled_checkbox.toggled.connect(func(_pressed: bool): _on_proxy_enabled_toggled(_pressed); _apply_change())
	proxy_host_field.focus_exited.connect(_apply_change)
	proxy_port_field.value_changed.connect(func(_value: float): _apply_change())
	language_field.item_selected.connect(func(_idx: int): _apply_change())
	apply_restart_button.pressed.connect(_on_apply_and_restart)
	test_button.pressed.connect(_on_test)
	close_requested.connect(hide)


func _populate_provider_list() -> void:
	provider_select.clear()
	for p in _model_fetcher.get_providers():
		provider_select.add_item(p.name)
	# 尝试匹配当前 Base URL
	var current_url := _config.get_base_url().strip_edges().trim_suffix("/")
	for i in range(provider_select.item_count):
		var url: String = str(_model_fetcher.get_providers()[i].get("url", ""))
		if url.strip_edges().trim_suffix("/") == current_url:
			provider_select.select(i)
			return
	# 默认选中 Custom
	for i in range(provider_select.item_count):
		if _model_fetcher.get_providers()[i].get("name", "") == "Custom":
			provider_select.select(i)
			return


func _on_provider_selected(idx: int, apply_presets: bool = true) -> void:
	if idx < 0:
		return
	var providers := _model_fetcher.get_providers()
	if idx >= providers.size():
		return
	var p: Dictionary = providers[idx]
	if apply_presets:
		var url: String = str(p.get("url", ""))
		if not url.is_empty():
			base_url_field.text = url
			base_url_field.editable = false
		else:
			# Custom：允许手动编辑
			base_url_field.editable = true
		# 实时保存（URL 已更新）
		_apply_change()


func _on_proxy_enabled_toggled(button_pressed: bool) -> void:
	proxy_host_field.editable = button_pressed
	proxy_port_field.editable = button_pressed


func _load_values() -> void:
	base_url_field.text = _config.get_base_url()
	_refresh_api_key_status()
	# Proxy 启用状态
	var proxy_enabled := _config.is_proxy_enabled()
	proxy_enabled_checkbox.button_pressed = proxy_enabled
	proxy_host_field.editable = proxy_enabled
	proxy_port_field.editable = proxy_enabled
	proxy_host_field.text = _config.get_effective_proxy_host()
	proxy_port_field.value = _config.get_proxy_port()
	language_field.select(1 if _config.get_language() == "en" else 0)


func _apply_change() -> void:
	# 保存前捕获旧值
	var old_url := _config.get_base_url().strip_edges().trim_suffix("/")
	var old_provider := _config.get_provider_name()
	var old_lang := _config.get_language()
	var old_proxy_enabled := _config.is_proxy_enabled()
	var old_proxy_host := _config.get_effective_proxy_host()
	var old_proxy_port := _config.get_proxy_port()

	var proxy_host := proxy_host_field.text.strip_edges() if proxy_enabled_checkbox.button_pressed else ""
	var proxy_port := int(proxy_port_field.value) if proxy_enabled_checkbox.button_pressed and proxy_port_field.value > 0 else -1
	var provider_name := "Custom"
	if provider_select.selected >= 0 and provider_select.selected < _model_fetcher.get_providers().size():
		provider_name = _model_fetcher.get_providers()[provider_select.selected].get("name", "Custom")
	var new_url := base_url_field.text.strip_edges().trim_suffix("/")
	var new_lang := "en" if language_field.selected == 1 else "zh"
	var new_proxy_enabled := proxy_enabled_checkbox.button_pressed

	var err := _config.save(
		base_url_field.text.strip_edges(),
		_config.get_api_key(),
		_config.get_model(),
		0.2,
		_config.get_context_limit(),
		new_lang,
		_config.get_max_tokens_k(),
		_config.get_vision_enabled(),
		proxy_host,
		proxy_port,
		provider_name,
	)
	if err != OK:
		push_warning("[DotAgent] Failed to save config: %d" % err)
		return

	# 语言变更时立即刷新当前弹窗
	Locale.set_lang(new_lang)
	_apply_locale()

	# 只输出变更项
	if provider_name != old_provider:
		print_rich("[color=#88cc88][DotAgent][/color] provider: %s" % provider_name)
	elif new_url != old_url:
		print_rich("[color=#88cc88][DotAgent][/color] URL: %s" % base_url_field.text.strip_edges())
	elif new_lang != old_lang:
		print_rich("[color=#88cc88][DotAgent][/color] lang: %s" % ("English" if new_lang == "en" else "中文"))
	elif new_proxy_enabled != old_proxy_enabled or proxy_host != old_proxy_host or proxy_port != old_proxy_port:
		if new_proxy_enabled:
			print_rich("[color=#88cc88][DotAgent][/color] proxy: %s:%d" % [proxy_host, proxy_port])
		else:
			print_rich("[color=#88cc88][DotAgent][/color] proxy: off")

	config_saved.emit()


func _refresh_api_key_status() -> void:
	var key := _config.get_api_key()
	if key.is_empty():
		api_key_input.text = ""
		api_key_input.placeholder_text = "sk-..."
	else:
		api_key_input.text = _mask_key(key)


func _mask_key(key: String) -> String:
	if key.length() <= 10:
		return key[0] + "****" + key[key.length() - 1]
	return key.substr(0, 6) + "****" + key.substr(key.length() - 4)


func _on_apply_and_restart() -> void:
	var key := api_key_input.text.strip_edges()
	if key.is_empty():
		print_rich("[color=#ff6666][DotAgent][/color] API Key is empty")
		return

	# 即时生效
	OS.set_environment("DOTAGENT_API_KEY", key)
	# 持久化到系统环境变量
	var output: Array = []
	var exit_code := OS.execute("setx", ["DOTAGENT_API_KEY", key], output, true)
	if exit_code != 0:
		print_rich("[color=#ff6666][DotAgent][/color] setx failed (exit %d)" % exit_code)
		return

	print_rich("[color=#88cc88][DotAgent][/color] API Key saved. Restarting...")
	_refresh_api_key_status()
	api_key_input.text = ""

	# 优先用非 console 版 Godot（GUI 模式，无终端黑窗）
	var godot_exe := OS.get_executable_path()
	var gui_exe := godot_exe.replace("_console.exe", ".exe")
	if not FileAccess.file_exists(gui_exe):
		gui_exe = godot_exe  # 回退

	# 批处理：等 3s → 强杀旧进程 → 启动新编辑器（无终端窗口）
	var proj_path := ProjectSettings.globalize_path("res://")
	var pid := OS.get_process_id()
	var bat := "@echo off\r\n"
	bat += "ping 127.0.0.1 -n 3 > nul\r\n"
	bat += "taskkill /F /PID %d > nul 2>&1\r\n" % pid
	bat += "start \"\" /B \"%s\" --editor --path \"%s\"\r\n" % [gui_exe, proj_path]
	var bat_path := OS.get_temp_dir().path_join("dotagent_restart.bat")
	var f := FileAccess.open(bat_path, FileAccess.WRITE)
	if f:
		f.store_string(bat)
		f.close()
		OS.execute("cmd", ["/c", "start", "", "/B", bat_path], [], false)
	else:
		OS.execute(gui_exe, ["--editor", "--path", proj_path], [], false)


func _on_test() -> void:
	if _testing:
		return
	_testing = true
	test_button.disabled = true
	test_button.text = Locale.t("Testing...")
	_log("🔌 Testing connection: GET %s/models ..." % base_url_field.text.strip_edges().trim_suffix("/"), false)
	_test_connection()
	while _testing:
		await Engine.get_main_loop().process_frame
	test_button.disabled = false
	test_button.text = Locale.t("Test")
	if _test_ok:
		_log("✅ Connection OK (%d models)" % _test_model_count, false)
	else:
		_log("❌ " + _test_err, true)


## 测试连接：调用 GET /models 拉取模型列表。
## 200 OK 且能解析出至少 1 个 model 视为通过，否则失败。
func _test_connection() -> void:
	var base := base_url_field.text.strip_edges().trim_suffix("/")
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 10
	_apply_proxy(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		var body_str: String = body.get_string_from_utf8()
		if code == 0:
			_test_ok = false
			_test_err = "无法连接（超时或网络不通）"
		elif code == 401 or code == 403:
			_test_ok = false
			_test_err = "HTTP %d: %s" % [code, body_str.substr(0, 200)]
		elif code != 200:
			_test_ok = false
			_test_err = "HTTP %d: %s" % [code, body_str.substr(0, 200)]
		else:
			# 200 OK：尝试解析模型列表，能解析出至少 1 个 model 就算通过
			var json := JSON.new()
			if json.parse(body_str) != OK:
				_test_ok = false
				_test_err = "返回数据无法解析为 JSON"
			else:
				var data: Dictionary = json.data
				var models_arr: Array = data.get("data", [])
				if models_arr.is_empty():
					models_arr = data.get("models", [])
				_test_model_count = models_arr.size()
				_test_ok = _test_model_count > 0
				if not _test_ok:
					_test_err = "返回了 200 但模型列表为空"
				else:
					_test_err = ""
		_testing = false
		http.queue_free()
	)
	var url := base + "/models"
	var api_key := _config.get_api_key()
	var headers := ["Content-Type: application/json"]
	if not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	http.request(url, headers, HTTPClient.METHOD_GET)


func _apply_proxy(http: HTTPRequest) -> void:
	# 同时支持：UI 复选框 + 配置里已经保存了有效代理配置
	# 当 host+port 都有值时，即使 UI 复选框没勾，也走代理（避免忘记勾）
	var host := ""
	var port := -1
	if proxy_enabled_checkbox != null and proxy_enabled_checkbox.button_pressed:
		host = proxy_host_field.text.strip_edges()
		port = int(proxy_port_field.value)
	# 如果 UI 复选框未勾，但用户之前保存过代理配置，也尝试启用
	if host.is_empty() or port <= 0 or port > 65535:
		host = _config.get_effective_proxy_host()
		port = _config.get_proxy_port()
	if host.is_empty() or port <= 0 or port > 65535:
		return
	http.set_http_proxy(host, port)
	http.set_https_proxy(host, port)


func _apply_locale() -> void:
	title = Locale.t("DotAgent Settings")
	# 顶部提示
	if hint_label:
		hint_label.text = Locale.t("OpenAI-compatible API config.")
	# Provider 行
	if provider_label:
		provider_label.text = Locale.t("Provider:")
	# API Key 行（label 上的 ⓘ 图标始终保留）
	if api_key_label:
		api_key_label.text = "ⓘ  " + Locale.t("API Key:")
	if api_key_input:
		api_key_input.placeholder_text = "sk-..."
	if apply_restart_button:
		apply_restart_button.text = Locale.t("Configure & Restart")
	# Proxy 行
	if proxy_label:
		proxy_label.text = Locale.t("proxy:")
	if proxy_enabled_checkbox:
		proxy_enabled_checkbox.text = Locale.t("enable")
	# Language 行
	if language_label:
		language_label.text = "ⓘ  " + Locale.t("Language:")
	if test_button:
		test_button.text = Locale.t("Test")

## 把配置页的状态/结果输出到 Godot 编辑器 Output 面板
func _log(text: String, is_error: bool = false) -> void:
	if is_error:
		push_error("[DotAgent] " + text)
	else:
		print_rich("[color=#aaaaaa][DotAgent][/color] " + text)
