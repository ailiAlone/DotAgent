@tool
class_name ModelDatabase
extends RefCounted
## 模型数据库 — GitHub API 下载 models.dev 模型数据
##
## 数据源: GitHub API (国内可直接访问)
## 缓存: res://.dotagent/models_cache.json
## 解析耗时: ~120ms (Godot 4.5)
##
## 用法:
##   var db := ModelDatabase.new()
##   var info = db.get_model("gpt-4o", "OpenAI")
##   db.refresh(host_node, func(ok, msg): print(msg))

## GitHub API 获取 models.dev 仓库数据（国内可直接访问）
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
## 从 zipball 解析出的 provider 元数据（name + api），供模型合并时查询
var _parsed_providers: Dictionary = {}


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


## 在线刷新：获取 GitHub 仓库中所有 Provider 目录名（1 请求）
func refresh(host_node: Node, on_complete: Callable) -> void:
	print("[DotAgent] Downloading provider list from GitHub API...")
	_fetch_provider_list(host_node, func(success: bool, msg: String):
		if success:
			print("[DotAgent] Found %d providers" % _parsed_providers.size())
		on_complete.call(success, msg)
	)


## 获取 providers 目录列表，提取所有 provider key 并更新 _parsed_providers
func _fetch_provider_list(host_node: Node, on_complete: Callable) -> void:
	var url := "https://api.github.com/repos/anomalyco/models.dev/contents/providers?ref=dev"
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 30
	var headers := PackedStringArray(["User-Agent: DotAgent/1.0"])

	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			on_complete.call(false, "Provider list HTTP %d" % code)
			return
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			on_complete.call(false, "Provider list parse error")
			return
		var arr = json.data
		if not arr is Array:
			on_complete.call(false, "Provider list format error")
			return
		_parsed_providers = {}
		for item in arr:
			if item is Dictionary and item.get("type") == "dir":
				var key := str(item.get("name", ""))
				if not key.is_empty():
					_parsed_providers[key] = {"name": _display_name(key)}
		print("[DotAgent] Found %d providers" % _parsed_providers.size())
		on_complete.call(true, "ok")
	)

	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		on_complete.call(false, "Provider list request error %d" % err)


## 从 provider key 派生显示名
func _display_name(key: String) -> String:
	for dot_name in PROVIDER_KEYS:
		if key in PROVIDER_KEYS[dot_name]:
			return dot_name
	return key.capitalize().replace("-", " ").replace("_", " ")


## 按需加载：获取指定 Provider 的 provider.toml + 全部 model TOML，并行下载
## on_complete 签名: func(success: bool, provider_key: String, model_count: int, error_msg: String)
func fetch_provider_models(provider_key: String, host_node: Node, on_complete: Callable) -> void:
	print("[DotAgent] Fetching models for: %s" % provider_key)

	# Step 1: 获取 provider.toml → name + api
	_fetch_single_file("providers/%s/provider.toml" % provider_key, host_node, func(ok1: bool, content1: String):
		var provider_name := _display_name(provider_key)
		var provider_api := URL_OVERRIDES.get(provider_key, "")
		if ok1:
			var parsed := _parse_toml_kv(content1)
			if parsed.has("name"):
				provider_name = parsed["name"]
			if parsed.has("api"):
				provider_api = parsed["api"]

		# Step 2: 获取模型目录列表
		_fetch_dir_listing("providers/%s/models" % provider_key, host_node, func(ok2: bool, model_files: Array):
			if not ok2:
				on_complete.call(false, provider_key, 0, "Cannot list models for %s" % provider_key)
				return
			if model_files.is_empty():
				# 没有模型文件，直接保存 provider 信息
				_data[provider_key] = {"name": provider_name, "api": provider_api, "models": {}}
				_save_cache_from_data()
				on_complete.call(true, provider_key, 0, "")
				return

			# Step 3: 并行获取所有模型 TOML
			var model_results: Dictionary = {}
			var pending := model_files.size()
			for mf in model_files:
				var model_id := mf.trim_suffix(".toml")
				_fetch_single_file("providers/%s/models/%s" % [provider_key, mf], host_node, func(_ok: bool, content: String):
					if _ok:
						model_results[model_id] = content
					pending -= 1
					if pending <= 0:
						# 全部完成，合并数据
						_merge_provider_models(provider_key, provider_name, provider_api, model_results)
						_save_cache_from_data()
						on_complete.call(true, provider_key, model_results.size(), "")
				)
		)
	)


## 获取单个文件的 base64 内容
func _fetch_single_file(path: String, host_node: Node, on_complete: Callable) -> void:
	var url := "https://api.github.com/repos/anomalyco/models.dev/contents/%s?ref=dev" % path
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 15
	http.set_follow_redirects(false)
	var headers := PackedStringArray(["User-Agent: DotAgent/1.0"])

	http.request_completed.connect(func(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			on_complete.call(false, "")
			return
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			on_complete.call(false, "")
			return
		var root = json.data
		if not root is Dictionary or root.get("encoding") != "base64":
			on_complete.call(false, "")
			return
		var b64 := str(root.get("content", "")).replace("\n", "").replace("\r", "")
		on_complete.call(true, Marshalls.base64_to_utf8(b64))
	)

	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		on_complete.call(false, "")


## 获取目录下的文件列表
func _fetch_dir_listing(dir_path: String, host_node: Node, on_complete: Callable) -> void:
	var url := "https://api.github.com/repos/anomalyco/models.dev/contents/%s?ref=dev" % dir_path
	var http := HTTPRequest.new()
	host_node.add_child(http)
	http.timeout = 15
	http.set_follow_redirects(false)
	var headers := PackedStringArray(["User-Agent: DotAgent/1.0"])

	http.request_completed.connect(func(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200:
			on_complete.call(false, [])
			return
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			on_complete.call(false, [])
			return
		var arr = json.data
		if not arr is Array:
			on_complete.call(false, [])
			return
		var files: Array = []
		for item in arr:
			if item is Dictionary and item.get("type") == "file" and str(item.get("name", "")).ends_with(".toml"):
				files.append(item["name"])
		on_complete.call(true, files)
	)

	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		on_complete.call(false, [])


## 合并 Provider 模型数据到 _data
func _merge_provider_models(provider_key: String, provider_name: String, provider_api: String, model_contents: Dictionary) -> void:
	var models := {}
	for model_id in model_contents:
		var toml := _parse_toml_kv(model_contents[model_id])
		if toml.is_empty():
			continue
		var limit := _parse_toml_section(model_contents[model_id], "limit")
		var cost := _parse_toml_section(model_contents[model_id], "cost")
		models[model_id] = {
			"id": model_id,
			"name": toml.get("name", model_id),
			"cost": cost,
			"limit": {
				"context": int(cost.get("context", 0) if cost.has("context") else limit.get("context", 0)),
				"output": int(limit.get("output", 0)),
			},
			"modalities": {"input": _parse_modalities(model_contents[model_id])},
			"tool_call": toml.get("tool_call", "false") == "true",
			"reasoning": toml.get("reasoning", "false") == "true",
			"structured_output": toml.get("structured_output", "false") == "true",
		}
	_data[provider_key] = {"name": provider_name, "api": provider_api, "models": models}


## 简单 TOML key=value 解析（仅顶层）
func _parse_toml_kv(content: String) -> Dictionary:
	var result := {}
	for line in content.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#") or s.begins_with("["):
			continue
		var eq := s.find("=")
		if eq == -1:
			continue
		var key := s.substr(0, eq).strip_edges()
		var val := s.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		result[key] = val
	return result


## 解析 TOML [section] 下的 key=value
func _parse_toml_section(content: String, section: String) -> Dictionary:
	var result := {}
	var in_section := false
	for line in content.split("\n"):
		var s := line.strip_edges()
		if s == "[%s]" % section:
			in_section = true
			continue
		if s.begins_with("[") and in_section:
			break
		if not in_section:
			continue
		var eq := s.find("=")
		if eq == -1:
			continue
		var key := s.substr(0, eq).strip_edges()
		var val := s.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		result[key] = val
	return result


## 从 TOML [modalities] 解析 input 列表
func _parse_modalities(content: String) -> Array:
	for line in content.split("\n"):
		var s := line.strip_edges()
		if s == "[modalities]":
			continue
		var eq := s.find("=")
		if eq == -1:
			continue
		var key := s.substr(0, eq).strip_edges()
		if key == "input":
			var val := s.substr(eq + 1).strip_edges().trim_prefix("[").trim_suffix("]")
			var result: Array = []
			for item in val.split(","):
				result.append(item.strip_edges().trim_prefix("\"").trim_suffix("\""))
			return result
		if s.begins_with("["):
			break
	return []


## 缓存当前 _data 到文件
func _save_cache_from_data() -> void:
	var cache_json := JSON.stringify(_data, "\t")
	if not cache_json.is_empty():
		_save_cache(cache_json)


## 获取已缓存的 provider 列表（从 _parsed_providers）
func get_provider_list() -> Dictionary:
	return _parsed_providers.duplicate()


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
