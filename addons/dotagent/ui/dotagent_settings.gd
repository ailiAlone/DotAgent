@tool
extends AcceptDialog
## DotAgent 统一设置对话框
##
## 管理 Provider、API、代理、模式和语言设置。
## LLM 共享字段使用 ConfigManager；模式特定字段
## （banyan pool_size、max_parallel）存储在同一配置文件的 [banyan] 段中。
##
## 模式切换: Legacy（单智能体）/ Banyan（自组织多智能体）

signal config_saved
signal mode_changed(mode: String)
signal reset_requested

# ============ 节点引用 ============

@onready var mode_option: OptionButton = $MainVBox/ModeSection/ModeRow/ModeOption
@onready var mode_hint: Label = $MainVBox/ModeSection/ModeHint
@onready var provider_option: OptionButton = $MainVBox/ProviderSection/ProviderOption
@onready var url_input: LineEdit = $MainVBox/URLSection/URLInput
@onready var key_input: LineEdit = $MainVBox/KeySection/KeyInput
@onready var proxy_check: CheckBox = $MainVBox/ProxySection/ProxyCheck
@onready var proxy_host: LineEdit = $MainVBox/ProxySection/ProxyHost
@onready var proxy_port: SpinBox = $MainVBox/ProxySection/ProxyPort
@onready var banyan_section: VBoxContainer = $MainVBox/BanyanSection
@onready var pool_spin: SpinBox = $MainVBox/BanyanSection/PoolRow/PoolSpin
@onready var parallel_spin: SpinBox = $MainVBox/BanyanSection/ParallelRow/ParallelSpin
@onready var lang_option: OptionButton = $MainVBox/LanguageSection/LangOption
@onready var reset_btn: Button = $MainVBox/DangerBar/ResetBtn
@onready var test_btn: Button = $MainVBox/TestBar/TestBtn
@onready var test_result: Label = $MainVBox/TestBar/TestResult

# ============ 常量 ============

const CONFIG_PATH: String = "res://addons/dotagent/config.cfg"

## 动态提供商列表（从 models.dev 缓存加载）
## 格式: [{"key": str, "name": str, "url": str, "format": str, "count": int}, ...]
## 末尾追加 "Custom" 条目，允许用户手动输入 URL。
var _providers: Array = []
var _model_fetcher: ModelFetcher = null

const MODE_LEGACY: String = "legacy"
const MODE_BANYAN: String = "banyan"

const MODE_HINTS: Dictionary = {
	"legacy": "Legacy: 单智能体模式，一个 Agent 处理所有任务",
	"banyan": "Banyan: 自组织多智能体，节点树自动分解和并行执行任务",
}

# ============ 状态 ============

var _config: ConfigManager = null
var _testing: bool = false
## 存储真实的 API Key（未脱敏），在对话框打开期间保持
var _real_api_key: String = ""
var _current_mode: String = MODE_BANYAN


func _ready() -> void:
	_config = ConfigManager.instance()
	_model_fetcher = ModelFetcher.new()

	# 从缓存加载提供商列表
	_providers = _model_fetcher.get_providers()
	_providers.append({"key": "custom", "name": "Custom", "url": "", "format": "openai", "count": 0})

	# 如果缓存为空，尝试在线下载
	if _providers.size() <= 1:
		_model_fetcher.refresh_database(self, func(success: bool, _msg: String):
			if success:
				_providers = _model_fetcher.get_providers()
				_providers.append({"key": "custom", "name": "Custom", "url": "", "format": "openai", "count": 0})
				_populate_provider_dropdown()
		)
	else:
		_populate_provider_dropdown()

	# 填充模式下拉
	mode_option.clear()
	mode_option.add_item("Legacy")
	mode_option.add_item("Banyan")

	# 加载当前值
	_load_values()

	# 连接信号
	mode_option.item_selected.connect(_on_mode_selected)
	provider_option.item_selected.connect(_on_provider_selected)
	url_input.text_submitted.connect(func(_t: String): _save())
	url_input.focus_exited.connect(_save)
	key_input.text_submitted.connect(func(_t: String): _on_key_submitted())
	key_input.focus_exited.connect(_on_key_submitted)
	proxy_check.toggled.connect(func(p: bool): _on_proxy_toggled(p); _save())
	proxy_host.text_submitted.connect(func(_t: String): _save())
	proxy_host.focus_exited.connect(_save)
	proxy_port.value_changed.connect(func(_v: float): _save())
	pool_spin.value_changed.connect(func(_v: float): _save())
	parallel_spin.value_changed.connect(func(_v: float): _save())
	lang_option.item_selected.connect(func(_idx: int): _save())
	test_btn.pressed.connect(_test_connection)
	reset_btn.pressed.connect(func(): reset_requested.emit())
	confirmed.connect(_save)


## 用动态加载的 _providers 列表填充 Provider 下拉框
func _populate_provider_dropdown() -> void:
	provider_option.clear()
	for p in _providers:
		var name: String = str(p.get("name", ""))
		var count: int = int(p.get("count", 0))
		if count > 0:
			provider_option.add_item("%s (%d)" % [name, count])
		else:
			provider_option.add_item(name)


# ============ 加载 ============

func _load_values() -> void:
	# 模式
	var cf: ConfigFile = ConfigFile.new()
	var err: Error = cf.load(CONFIG_PATH)
	if err == OK:
		_current_mode = str(cf.get_value("dotagent", "mode", MODE_BANYAN))
	else:
		_current_mode = MODE_BANYAN
	_apply_mode_ui()

	# Provider — 按保存的 base URL 匹配
	var current_url: String = _config.get_base_url().strip_edges().trim_suffix("/")
	var matched: bool = false
	for i in range(_providers.size()):
		var url: String = str(_providers[i].get("url", ""))
		if not url.is_empty() and url.strip_edges().trim_suffix("/") == current_url:
			provider_option.select(i)
			matched = true
			break
	if not matched:
		provider_option.select(_providers.size() - 1)

	# URL
	url_input.text = _config.get_base_url()

	# API key（从环境变量通过 ConfigManager 获取）
	_real_api_key = _config.get_api_key()
	if _real_api_key.is_empty():
		key_input.text = ""
		key_input.placeholder_text = "sk-..."
	else:
		key_input.text = _mask_key(_real_api_key)

	# 代理
	var proxy_enabled: bool = _config.is_proxy_enabled()
	proxy_check.button_pressed = proxy_enabled
	proxy_host.editable = proxy_enabled
	proxy_host.text = _config.get_effective_proxy_host() if proxy_enabled else ""
	proxy_port.editable = proxy_enabled
	proxy_port.value = _config.get_proxy_port() if proxy_enabled else -1

	# 语言（0 = 中文 / "zh"，1 = English / "en"）
	lang_option.select(1 if _config.get_language() == "en" else 0)

	# Banyan 专属设置（从 [banyan] 段读取）
	if err == OK:
		pool_spin.value = int(cf.get_value("banyan", "pool_size", 4))
		parallel_spin.value = int(cf.get_value("banyan", "max_parallel", 4))
	else:
		pool_spin.value = 4
		parallel_spin.value = 4


# ============ 保存 ============

func _save() -> void:
	# 确定 provider 名称
	var provider_idx: int = provider_option.selected
	var provider_name: String = "Custom"
	if provider_idx >= 0 and provider_idx < _providers.size():
		provider_name = str(_providers[provider_idx].get("name", "Custom"))

	var proxy_host_val: String = proxy_host.text.strip_edges() if proxy_check.button_pressed else ""
	var proxy_port_val: int = int(proxy_port.value) if proxy_check.button_pressed and proxy_port.value > 0 else -1
	var lang: String = "en" if lang_option.selected == 1 else "zh"

	# 使用真实 key（非脱敏显示）
	var api_key: String = _real_api_key

	# 通过 ConfigManager 保存共享 LLM 字段
	var err: Error = _config.save(
		url_input.text.strip_edges(),
		api_key,
		_config.get_model(),
		_config.get_context_limit(),
		lang,
		_config.get_max_tokens_k(),
		_config.get_vision_enabled(),
		proxy_host_val,
		proxy_port_val,
		provider_name,
	)
	if err != OK:
		push_warning("[DotAgent] Failed to save config: %d" % err)
		return

	# 保存模式 + banyan 专属字段
	var cf: ConfigFile = ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value("dotagent", "mode", _current_mode)
	cf.set_value("banyan", "pool_size", int(pool_spin.value))
	cf.set_value("banyan", "max_parallel", int(parallel_spin.value))
	var err2: Error = cf.save(CONFIG_PATH)
	if err2 != OK:
		push_warning("[DotAgent] Failed to save mode/banyan section: %d" % err2)

	print_rich("[color=#88cc88][DotAgent][/color] Settings saved (mode=%s)" % _current_mode)
	config_saved.emit()


func _on_key_submitted() -> void:
	var raw: String = key_input.text.strip_edges()
	if not raw.is_empty() and raw != _mask_key(_real_api_key):
		_real_api_key = raw
		OS.set_environment("DOTAGENT_API_KEY", raw)
		if _persist_api_key_system(raw):
			print_rich("[color=#88cc88][DotAgent][/color] API Key persisted to system environment")
		else:
			print_rich("[color=#ffaa66][DotAgent][/color] API Key set for this session only (persist failed)")
	_save()


# ============ 模式切换 ============

func _on_mode_selected(idx: int) -> void:
	if idx == 0:
		_current_mode = MODE_LEGACY
	else:
		_current_mode = MODE_BANYAN
	_apply_mode_ui()
	_save()
	mode_changed.emit(_current_mode)


func _apply_mode_ui() -> void:
	# 设置下拉选中状态（不触发信号）
	if _current_mode == MODE_LEGACY:
		mode_option.select(0)
	else:
		mode_option.select(1)

	# 更新提示文本
	mode_hint.text = MODE_HINTS.get(_current_mode, "")

	# Banyan 专属区域仅在该模式下显示
	banyan_section.visible = (_current_mode == MODE_BANYAN)


## 获取当前模式（供 plugin.gd 调用）
func get_agent_mode() -> String:
	return _current_mode


# ============ Provider 选择 ============

func _on_provider_selected(idx: int) -> void:
	if idx < 0 or idx >= _providers.size():
		return
	var provider: Dictionary = _providers[idx]
	var url: String = str(provider.get("url", ""))
	if not url.is_empty():
		url_input.text = url
		url_input.editable = false
	else:
		url_input.editable = true
	_save()


# ============ 代理切换 ============

func _on_proxy_toggled(pressed: bool) -> void:
	proxy_host.editable = pressed
	proxy_port.editable = pressed


# ============ 测试连接 ============

func _test_connection() -> void:
	if _testing:
		return
	_testing = true
	test_btn.disabled = true
	test_btn.text = "Testing..."
	test_result.text = ""

	var base: String = url_input.text.strip_edges().trim_suffix("/")
	var url: String = base + "/models"

	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.timeout = 10.0

	_apply_proxy(http)

	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		var body_str: String = body.get_string_from_utf8()
		if code == 0:
			test_result.text = "Connection failed (timeout or unreachable)"
			test_result.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		elif code == 401 or code == 403:
			test_result.text = "HTTP %d: Unauthorized" % code
			test_result.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		elif code != 200:
			test_result.text = "HTTP %d" % code
			test_result.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		else:
			var json: JSON = JSON.new()
			if json.parse(body_str) != OK:
				test_result.text = "OK but invalid JSON"
				test_result.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
			else:
				var data = json.data
				var models_arr: Array = []
				if data is Dictionary:
					models_arr = data.get("data", data.get("models", []))
				var count: int = models_arr.size()
				if count > 0:
					test_result.text = "OK (%d models)" % count
					test_result.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
				else:
					test_result.text = "OK but no models found"
					test_result.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
		_testing = false
		test_btn.disabled = false
		test_btn.text = "Test Connection"
		http.queue_free()
	)

	var headers: Array = ["Content-Type: application/json"]
	if not _real_api_key.is_empty():
		headers.append("Authorization: Bearer " + _real_api_key)
	http.request(url, headers, HTTPClient.METHOD_GET)


func _apply_proxy(http: HTTPRequest) -> void:
	var host: String = ""
	var port: int = -1
	if proxy_check.button_pressed:
		host = proxy_host.text.strip_edges()
		port = int(proxy_port.value)
	if host.is_empty() or port <= 0 or port > 65535:
		host = _config.get_effective_proxy_host()
		port = _config.get_proxy_port()
	if host.is_empty() or port <= 0 or port > 65535:
		return
	http.set_http_proxy(host, port)
	http.set_https_proxy(host, port)


# ============ 系统级持久化 ============

## 将 API Key 持久化到系统环境变量（跨平台）
## Windows: setx 写用户注册表; Unix: 写 shell rc 文件
## 失败时仅当前进程生效（OS.set_environment 已处理）
func _persist_api_key_system(key: String) -> bool:
	if key.is_empty():
		return false
	match OS.get_name():
		"Windows":
			return _persist_api_key_windows(key)
		"macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD":
			return _persist_api_key_unix(key)
		_:
			return false


func _persist_api_key_windows(key: String) -> bool:
	# setx 限制 1024 字符
	if key.length() > 1024:
		push_warning("[DotAgent] API Key exceeds setx 1024-char limit, skip persist")
		return false
	var output: Array = []
	var exit_code := OS.execute("setx", ["DOTAGENT_API_KEY", key], output, true)
	return exit_code == 0


func _persist_api_key_unix(key: String) -> bool:
	var home: String = OS.get_environment("HOME")
	if home.is_empty():
		return false
	# 按 shell 选择 rc 文件，回退到 ~/.profile
	var shell: String = OS.get_environment("SHELL")
	var rc_path: String = home + "/.profile"
	if shell.ends_with("/bash"):
		rc_path = home + "/.bashrc"
	elif shell.ends_with("/zsh"):
		rc_path = home + "/.zshrc"

	# 读取现有内容，移除旧的同名 export 行避免重复
	var content: String = ""
	var f := FileAccess.open(rc_path, FileAccess.READ)
	if f:
		content = f.get_as_text()
		f.close()

	var new_lines := PackedStringArray()
	for line in content.split("\n"):
		if not line.begins_with("export DOTAGENT_API_KEY="):
			new_lines.append(line)
	new_lines.append("export DOTAGENT_API_KEY=" + _shell_quote(key))

	var fw := FileAccess.open(rc_path, FileAccess.WRITE)
	if not fw:
		push_warning("[DotAgent] Cannot write %s (err=%d)" % [rc_path, FileAccess.get_open_error()])
		return false
	fw.store_string("\n".join(new_lines) + "\n")
	fw.close()
	return true


func _shell_quote(val: String) -> String:
	# 单引号包裹，转义内部单引号
	return "'" + val.replace("'", "'\\''") + "'"


# ============ 工具函数 ============

func _mask_key(key: String) -> String:
	if key.is_empty():
		return ""
	if key.length() <= 10:
		return key[0] + "****" + key[key.length() - 1]
	return key.substr(0, 6) + "****" + key.substr(key.length() - 4)
