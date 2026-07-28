@tool
class_name ModelDatabase
extends RefCounted
## 模型数据库 — 直接使用 models.dev 原始 JSON
##
## 数据源: https://models.dev/api.json (3.2MB, 170 提供商, 5794 模型)
## 缓存: res://.dotagent/models_cache.json
## 解析耗时: ~120ms (Godot 4.5)
##
## 用法:
##   var db := ModelDatabase.new()
##   var info = db.get_model("gpt-4o", "OpenAI")
##   db.refresh(host_node, func(ok, msg): print(msg))

const API_URL := "https://models.dev/api.json"
const CACHE_DIR := "res://.dotagent"
const CACHE_PATH := "res://.dotagent/models_cache.json"

# DotAgent 提供商名 → models.dev provider key
const PROVIDER_KEYS := {
	"OpenAI": ["openai"],
	"DeepSeek": ["deepseek"],
	"Moonshot (Kimi)": ["moonshotai-cn", "moonshotai"],
	"MiniMax": ["minimax-cn", "minimax"],
	"Zhipu AI (GLM)": ["zhipuai", "zhipuai-coding-plan"],
	"Qwen (DashScope)": ["alibaba-cn", "alibaba"],
	"Doubao (Volcengine)": ["volcengine", "volcengine-coding-plan", "volcengine-token-plan"],
	"xAI (Grok)": ["xai"],
	"Anthropic (Claude)": ["anthropic"],
	"Google": ["google", "google-vertex"],
	"Mistral": ["mistral"],
	"Cohere": ["cohere"],
	"Groq": ["groq"],
	"Together AI": ["togetherai"],
	"SiliconFlow": ["siliconflow", "siliconflow-cn"],
	"StepFun": ["stepfun", "stepfun-ai"],
	"Xiaomi": ["xiaomi", "xiaomi-token-plan-cn"],
	"Tencent": ["tencent", "tencent-coding-plan"],
	"OpenRouter": ["openrouter"],
}

# models.dev 中缺少 api 字段的提供商的 URL 映射
const URL_OVERRIDES := {
	"openai": "https://api.openai.com/v1",
	"anthropic": "https://api.anthropic.com",
	"xai": "https://api.x.ai/v1",
	"google": "https://generativelanguage.googleapis.com/v1beta/openai",
	"google-vertex": "https://us-central1-aiplatform.googleapis.com/v1",
	"google-vertex-anthropic": "https://us-central1-aiplatform.googleapis.com/v1",
	"mistral": "https://api.mistral.ai/v1",
	"cohere": "https://api.cohere.ai/v1",
	"groq": "https://api.groq.com/openai/v1",
	"togetherai": "https://api.together.xyz/v1",
	"perplexity": "https://api.perplexity.ai",
	"deepinfra": "https://api.deepinfra.com/v1/openai",
	"venice": "https://api.venice.ai/api/v1",
	"vercel": "https://api.v0.dev/v1",
	"v0": "https://api.v0.dev/v1",
	"cerebras": "https://api.cerebras.ai/v1",
	"aihubmix": "https://aihubmix.com/v1",
	"volcengine": "https://ark.cn-beijing.volces.com/api/v3",
	"volcengine-coding-plan": "https://ark.cn-beijing.volces.com/api/coding/v3",
	"volcengine-token-plan": "https://ark.cn-beijing.volces.com/api/v3",
}

var _data: Dictionary = {}
var _loaded := false


# ============ 查询接口 ============

## 查询单个模型
func get_model(model_id: String, provider_name: String = "") -> Dictionary:
	_ensure_loaded()
	if _data.is_empty():
		return {}

	# 1. 通过 provider key map 查找
	var keys: Array = PROVIDER_KEYS.get(provider_name, [])
	for pk in keys:
		if not _data.has(pk):
			continue
		var models: Dictionary = _data[pk].get("models", {})
		if models.has(model_id):
			return _extract(model_id, models[model_id], pk)

	# 2. 遍历全部 provider
	for pk in _data:
		var models: Dictionary = _data[pk].get("models", {})
		if models.has(model_id):
			return _extract(model_id, models[model_id], pk)

	# 3. 前缀匹配 (gpt-4o-2024-11-20 → gpt-4o)
	var best := ""
	var best_pk := ""
	var best_len := 0
	for pk in _data:
		var models: Dictionary = _data[pk].get("models", {})
		for mid in models:
			if model_id.begins_with(mid) and mid.length() > best_len:
				best = mid
				best_pk = pk
				best_len = mid.length()
	if best_len > 0:
		return _extract(best, _data[best_pk]["models"][best], best_pk)

	return {}


## 获取提供商下所有模型
func get_provider_models(provider_name: String) -> Array:
	_ensure_loaded()
	var keys: Array = PROVIDER_KEYS.get(provider_name, [])
	# PROVIDER_KEYS 未命中 → 尝试从 _data 中按显示名反查 key
	if keys.is_empty():
		var name_lower := provider_name.to_lower()
		for pk in _data:
			var pname: String = str(_data[pk].get("name", ""))
			if pname.to_lower() == name_lower:
				keys = [pk]
				break
	# 最后兜底: 直接用 provider_name 的小写形式
	if keys.is_empty():
		keys = [provider_name.to_lower()]
	var result: Array = []
	var seen: Dictionary = {}
	for pk in keys:
		if not _data.has(pk):
			continue
		var models: Dictionary = _data[pk].get("models", {})
		for mid in models:
			if seen.has(mid):
				continue
			seen[mid] = true
			var m: Dictionary = models[mid]
			if not m is Dictionary:
				continue
			var limit: Dictionary = m.get("limit", {})
			var ctx: int = int(limit.get("context", 0))
			if ctx == 0:
				continue
			var input_mods: Array = m.get("modalities", {}).get("input", [])
			result.append({
				"id": mid,
				"name": str(m.get("name", mid)),
				"context": ctx,
				"output": int(limit.get("output", 0)),
				"vision": input_mods.has("image"),
				"tools": m.get("tool_call", false),
			})
	return result


## 获取所有提供商（含 URL 信息，供 UI 下拉框使用）
func get_providers() -> Array:
	_ensure_loaded()
	var result: Array = []
	for pk in _data:
		var provider: Dictionary = _data[pk]
		var models: Dictionary = provider.get("models", {})
		if models.size() == 0:
			continue
		var name: String = str(provider.get("name", pk))
		# URL: 优先用 models.dev 的 api 字段，缺失则用 URL_OVERRIDES
		var url: String = str(provider.get("api", ""))
		if url.is_empty():
			url = URL_OVERRIDES.get(pk, "")
		result.append({
			"key": pk,
			"name": name,
			"url": url,
			"format": "openai",
			"count": models.size(),
		})
	# 按名称首字母排序
	result.sort_custom(func(a, b): return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0)
	return result


## 缓存状态
func get_cache_info() -> Dictionary:
	_ensure_loaded()
	var total := 0
	for pk in _data:
		total += _data[pk].get("models", {}).size()
	return {
		"loaded": _loaded,
		"providers": _data.size(),
		"models": total,
		"has_cache": FileAccess.file_exists(CACHE_PATH),
	}


## 在线刷新：下载最新数据并缓存
func refresh(host_node: Node, on_complete: Callable) -> void:
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 60

	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			on_complete.call(false, "HTTP %d" % code)
			return
		var text: String = body.get_string_from_utf8()
		if text.is_empty():
			on_complete.call(false, "Empty response")
			return
		var json := JSON.new()
		if json.parse(text) != OK:
			on_complete.call(false, "JSON parse error")
			return
		_save_cache(text)
		_load_from_string(text)
		var total := 0
		for pk in _data:
			total += _data[pk].get("models", {}).size()
		on_complete.call(true, "%d providers, %d models" % [_data.size(), total])
	)

	var err := http.request(API_URL, [], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		on_complete.call(false, "Request failed: %d" % err)


# ============ 内部 ============

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(CACHE_PATH):
		var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
		if f:
			_load_from_string(f.get_as_text())
			f.close()


func _load_from_string(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
		_data = json.data
	else:
		_data = {}


func _save_cache(text: String) -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func _extract(model_id: String, m: Variant, provider_key: String) -> Dictionary:
	if not m is Dictionary:
		return {}
	var model: Dictionary = m
	var limit: Dictionary = model.get("limit", {})
	var modalities: Dictionary = model.get("modalities", {})
	var input_mods: Array = modalities.get("input", []) if modalities.get("input") is Array else []
	var cost: Dictionary = model.get("cost", {})

	return {
		"id": model_id,
		"name": str(model.get("name", model_id)),
		"provider_key": provider_key,
		"provider_name": _data.get(provider_key, {}).get("name", provider_key),
		"max_context": int(limit.get("context", 0)),
		"max_output": int(limit.get("output", 0)),
		"vision": input_mods.has("image"),
		"audio": input_mods.has("audio"),
		"tools": model.get("tool_call", false),
		"reasoning": model.get("reasoning", false),
		"structured_output": model.get("structured_output", false),
		"cost_input": float(cost.get("input", 0)),
		"cost_output": float(cost.get("output", 0)),
	}
