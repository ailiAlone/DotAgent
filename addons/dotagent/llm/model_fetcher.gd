@tool
class_name ModelFetcher
extends RefCounted
## 共享模型获取工具
##
## 职责: 
##   - 从 ModelDatabase 获取提供商列表（UI 下拉框用）
##   - fetch_models(): 从本地缓存获取模型列表（兜底）
##   - fetch_account_models(): Provider API 实时拉取可用模型 × ModelDatabase 能力交叉引用
##
## 数据流:
##   Provider API (/v1/models) → 可用模型 ID 列表（实时、权威）
##   × ModelDatabase (models.dev) → 每个模型的能力数据（context/vision/tools）
##   = 既实时又信息完整的模型列表

var _db: ModelDatabase = null
var _resolver: ModelCapabilityResolver = null


func _init() -> void:
	_db = ModelDatabase.new()
	_resolver = ModelCapabilityResolver.new()


## 获取指定提供商的模型列表（仅从本地缓存，不做 API 调用）
## on_complete 回调签名: func(success: bool, models: Array[Dictionary], error_msg: String)
## models 中每个字典: {id, name, context, output, vision, tools}
func fetch_models(provider_name: String, _host_node: Node, on_complete: Callable) -> void:
	var raw_models: Array = _db.get_provider_models(provider_name)
	if raw_models.is_empty():
		var empty: Array[Dictionary] = []
		on_complete.call(false, empty, "No models found for provider: " + provider_name)
	else:
		var models: Array[Dictionary] = []
		for m in raw_models:
			models.append(m)
		on_complete.call(true, models, "")


## 获取该 account 真实可用的模型列表（Provider API）并交叉引用 ModelDatabase 能力
## 
## 流程:
##   1. 调用 Provider API GET {base_url}/models 拿可用模型 ID 列表
##   2. 对每个 ID，从 ModelDatabase 查询能力数据（context_window, vision, tools 等）
##   3. 返回交叉引用后的完整列表
##   4. Provider API 失败 → fallback 到纯 ModelDatabase
##
## on_complete 回调签名: func(success: bool, models: Array[Dictionary], error_msg: String)
## models 中每个字典: {id, name, context, output, vision, tools, source}
##   source = "api" | "api_fallback" | "api_only"
func fetch_account_models(provider_name: String, base_url: String, api_key: String, host_node: Node, on_complete: Callable) -> void:
	if api_key.is_empty() or base_url.is_empty():
		# 没有 API 凭证，直接用缓存
		fetch_models(provider_name, host_node, on_complete)
		return

	# 构建 /models 端点 URL
	var models_url: String = _build_models_url(base_url)

	# 发起 HTTP 请求
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 15
	http.accept_gzip = false

	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()

		if code != 200:
			# Provider API 不可用 → 回退到纯缓存
			fetch_models(provider_name, host_node, on_complete)
			return

		var text: String = body.get_string_from_utf8()
		var ids: Array = _parse_model_ids(text)
		if ids.is_empty():
			fetch_models(provider_name, host_node, on_complete)
			return

		# 交叉引用能力数据：ModelDatabase 优先 → ModelCapabilityResolver fallback
		var enriched: Array[Dictionary] = []
		for mid in ids:
			var info: Dictionary = _db.get_model(mid, provider_name)
			var source: String = "api"
			if info.is_empty():
				# ModelDatabase 没有 → 用内置 ModelCapabilityResolver（支持通配符匹配变体）
				var caps: Dictionary = _resolver.resolve(mid, provider_name)
				if caps.get("_source", "") != "default_conservative":
					info = caps
					source = "api_fallback"
				else:
					info = {}
					source = "api_only"

			if info.is_empty():
				# 仍然查不到 → 纯 API 来源，能力未知
				enriched.append({
					"id": mid,
					"name": mid,
					"context": 0,
					"output": 0,
					"vision": false,
					"tools": false,
					"source": "api_only",
				})
			else:
				# 统一字段名：ModelDatabase 用 max_context，resolver 用 context_window
				var ctx: int = int(info.get("max_context", info.get("context_window", 0)))
				var output: int = int(info.get("max_output", 0))
				var vision: bool = info.get("vision", false)
				var tools: bool = info.get("tools", info.get("supports_tools", false))
				var name: String = str(info.get("name", mid))
				enriched.append({
					"id": mid,
					"name": name,
					"context": ctx,
					"output": output,
					"vision": vision,
					"tools": tools,
					"source": source,
				})

		on_complete.call(true, enriched, "")
	)

	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key.strip_edges(),
		"Content-Type: application/json",
	])
	var err := http.request(models_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		fetch_models(provider_name, host_node, on_complete)


## 获取所有提供商定义（给 UI 渲染下拉框）
func get_providers() -> Array:
	return _db.get_providers()


## 获取已缓存的所有 Provider key 列表（启动时从 GitHub 目录列表获取）
func get_provider_list() -> Dictionary:
	return _db.get_provider_list()


## 按需加载指定 Provider 的完整数据（provider.toml + 全部 model TOML）
## on_complete 签名: func(success: bool, provider_key: String, model_count: int, error_msg: String)
func fetch_provider_models(provider_key: String, host_node: Node, on_complete: Callable) -> void:
	_db.fetch_provider_models(provider_key, host_node, on_complete)


## 刷新模型数据库（从 models.dev 重新下载）
## on_complete 回调签名: func(success: bool, message: String)
func refresh_database(host_node: Node, on_complete: Callable) -> void:
	_db.refresh(host_node, on_complete)


## 获取缓存信息
func get_cache_info() -> Dictionary:
	return _db.get_cache_info()


# ============ 内部 ============

## 从 base_url 构建 /models 端点 URL
func _build_models_url(base_url: String) -> String:
	var u: String = base_url.strip_edges().rstrip("/")
	# 处理各种 base_url 格式:
	#   https://api.openai.com/v1       → +/models
	#   https://api.minimaxi.com/anthropic/v1  → +/models
	#   https://api.example.com         → +/v1/models
	if u.ends_with("/v1") or u.ends_with("/v2") or u.ends_with("/v3"):
		return u + "/models"
	return u + "/v1/models"


## 解析 Provider API 响应，提取模型 ID 数组
## 支持 OpenAI 格式: {"data": [{"id": "gpt-4o"}, ...]}
## 支持 Anthropic 格式: {"data": [{"id": "claude-sonnet-4-20250514"}, ...]}
## 支持简单数组: [{"id": "model-1"}, ...]
func _parse_model_ids(text: String) -> Array:
	var json := JSON.new()
	if json.parse(text) != OK:
		return []

	var root = json.data
	if root == null:
		return []

	var items: Array = []
	if root is Dictionary:
		var data_field = root.get("data", null)
		if data_field is Array:
			items = data_field
		elif root.has("models"):
			var models_field = root.get("models", null)
			if models_field is Array:
				items = models_field
	elif root is Array:
		items = root

	var ids: Array = []
	for item in items:
		if item is Dictionary:
			var mid: String = str(item.get("id", ""))
			if not mid.is_empty():
				ids.append(mid)
	return ids
