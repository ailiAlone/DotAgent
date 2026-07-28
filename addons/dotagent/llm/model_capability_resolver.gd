@tool
class_name ModelCapabilityResolver
extends RefCounted
## 模型能力解析器
##
## 三层信息源:
##   1. 内置知识数据库（精确，需维护）
##   2. API 运行时探测（自适应学习）
##   3. 保守默认值（兜底）
##
## ChannelManager 通过 resolve() 获取模型参数来配置并发策略。

# ============ 内置知识数据库 ============
# 数据来源: 各提供商官方文档 (截至 2026-07)
# 维护规则: 新模型发布时更新此表; 旧模型参数变化时更新

const KNOWN_MODELS := {
	# ================================================================
	#  OpenAI
	# ================================================================
	"gpt-4o": {
		"provider": "OpenAI",
		"context_window": 128000,
		"max_output": 16384,
		"vision": true,
		"max_concurrent": 5,
		"rate_limit_rpm": 500,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 2.50,
		"cost_per_1m_output": 10.00,
		"tier": "flagship",
	},
	"gpt-4o-mini": {
		"provider": "OpenAI",
		"context_window": 128000,
		"max_output": 16384,
		"vision": true,
		"max_concurrent": 10,
		"rate_limit_rpm": 2000,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 0.15,
		"cost_per_1m_output": 0.60,
		"tier": "lightweight",
	},
	"gpt-4.1": {
		"provider": "OpenAI",
		"context_window": 1047576,
		"max_output": 32768,
		"vision": true,
		"max_concurrent": 5,
		"rate_limit_rpm": 500,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 2.00,
		"cost_per_1m_output": 8.00,
		"tier": "flagship",
	},
	"gpt-4.1-mini": {
		"provider": "OpenAI",
		"context_window": 1047576,
		"max_output": 32768,
		"vision": true,
		"max_concurrent": 10,
		"rate_limit_rpm": 2000,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 0.40,
		"cost_per_1m_output": 1.60,
		"tier": "balanced",
	},
	"gpt-4.1-nano": {
		"provider": "OpenAI",
		"context_window": 1047576,
		"max_output": 32768,
		"vision": true,
		"max_concurrent": 15,
		"rate_limit_rpm": 5000,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 0.10,
		"cost_per_1m_output": 0.40,
		"tier": "lightweight",
	},
	"o3": {
		"provider": "OpenAI",
		"context_window": 200000,
		"max_output": 100000,
		"vision": true,
		"max_concurrent": 2,
		"rate_limit_rpm": 20,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 10.00,
		"cost_per_1m_output": 40.00,
		"tier": "reasoning",
	},
	"o4-mini": {
		"provider": "OpenAI",
		"context_window": 200000,
		"max_output": 100000,
		"vision": true,
		"max_concurrent": 5,
		"rate_limit_rpm": 100,
		"supports_tools": true,
		"supports_json_mode": true,
		"supports_structured_output": true,
		"cost_per_1m_input": 1.10,
		"cost_per_1m_output": 4.40,
		"tier": "reasoning",
	},

	# ================================================================
	#  Anthropic (Claude)
	# ================================================================
	"claude-opus-4-20250514": {
		"provider": "Anthropic",
		"context_window": 200000,
		"max_output": 32000,
		"vision": true,
		"max_concurrent": 2,
		"rate_limit_rpm": 50,
		"supports_tools": true,
		"supports_json_mode": false,
		"supports_cache_control": true,
		"supports_extended_thinking": true,
		"cost_per_1m_input": 15.00,
		"cost_per_1m_output": 75.00,
		"tier": "flagship",
	},
	"claude-sonnet-4-20250514": {
		"provider": "Anthropic",
		"context_window": 200000,
		"max_output": 16384,
		"vision": true,
		"max_concurrent": 3,
		"rate_limit_rpm": 50,
		"supports_tools": true,
		"supports_json_mode": false,
		"supports_cache_control": true,
		"supports_extended_thinking": true,
		"cost_per_1m_input": 3.00,
		"cost_per_1m_output": 15.00,
		"tier": "flagship",
	},
	"claude-3-7-sonnet-20250219": {
		"provider": "Anthropic",
		"context_window": 200000,
		"max_output": 16384,
		"vision": true,
		"max_concurrent": 3,
		"rate_limit_rpm": 50,
		"supports_tools": true,
		"supports_json_mode": false,
		"supports_cache_control": true,
		"supports_extended_thinking": true,
		"cost_per_1m_input": 3.00,
		"cost_per_1m_output": 15.00,
		"tier": "flagship",
	},
	"claude-3-5-sonnet-20241022": {
		"provider": "Anthropic",
		"context_window": 200000,
		"max_output": 8192,
		"vision": true,
		"max_concurrent": 5,
		"rate_limit_rpm": 50,
		"supports_tools": true,
		"supports_json_mode": false,
		"supports_cache_control": true,
		"cost_per_1m_input": 3.00,
		"cost_per_1m_output": 15.00,
		"tier": "balanced",
	},
	"claude-3-5-haiku-20241022": {
		"provider": "Anthropic",
		"context_window": 200000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 5,
		"rate_limit_rpm": 100,
		"supports_tools": true,
		"supports_json_mode": false,
		"supports_cache_control": true,
		"cost_per_1m_input": 0.80,
		"cost_per_1m_output": 4.00,
		"tier": "lightweight",
	},

	# ================================================================
	#  DeepSeek
	# ================================================================
	"deepseek-chat": {
		"provider": "DeepSeek",
		"context_window": 64000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 3,
		"rate_limit_rpm": 100,
		"supports_tools": true,
		"supports_json_mode": false,
		"cost_per_1m_input": 0.27,
		"cost_per_1m_output": 1.10,
		"tier": "balanced",
	},
	"deepseek-reasoner": {
		"provider": "DeepSeek",
		"context_window": 64000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 1,
		"rate_limit_rpm": 20,
		"supports_tools": false,
		"supports_json_mode": false,
		"cost_per_1m_input": 0.55,
		"cost_per_1m_output": 2.19,
		"tier": "reasoning",
	},

	# ================================================================
	#  Moonshot (Kimi)
	# ================================================================
	"moonshot-v1-128k": {
		"provider": "Moonshot",
		"context_window": 128000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 3,
		"rate_limit_rpm": 60,
		"supports_tools": true,
		"supports_json_mode": false,
		"cost_per_1m_input": 5.00,
		"cost_per_1m_output": 5.00,
		"tier": "balanced",
	},

	# ================================================================
	#  MiniMax
	# ================================================================
	"MiniMax-M3": {
		"provider": "MiniMax",
		"context_window": 1000000,
		"max_output": 16384,
		"vision": true,
		"max_concurrent": 2,
		"rate_limit_rpm": 60,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},
	"MiniMax-M2": {
		"provider": "MiniMax",
		"context_window": 200000,
		"max_output": 16384,
		"vision": true,
		"max_concurrent": 3,
		"rate_limit_rpm": 100,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "balanced",
	},

	# ================================================================
	#  Zhipu AI (GLM)
	# ================================================================
	"glm-4-plus": {
		"provider": "Zhipu",
		"context_window": 128000,
		"max_output": 4096,
		"vision": false,
		"max_concurrent": 3,
		"rate_limit_rpm": 60,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},
	"glm-4v-plus": {
		"provider": "Zhipu",
		"context_window": 128000,
		"max_output": 4096,
		"vision": true,
		"max_concurrent": 3,
		"rate_limit_rpm": 60,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},

	# ================================================================
	#  Qwen (DashScope / 通义)
	# ================================================================
	"qwen-max": {
		"provider": "Qwen",
		"context_window": 128000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 5,
		"rate_limit_rpm": 100,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},
	"qwen-plus": {
		"provider": "Qwen",
		"context_window": 128000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 5,
		"rate_limit_rpm": 200,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "balanced",
	},
	"qwen-turbo": {
		"provider": "Qwen",
		"context_window": 128000,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 10,
		"rate_limit_rpm": 500,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "lightweight",
	},
	"qwen-vl-max": {
		"provider": "Qwen",
		"context_window": 128000,
		"max_output": 8192,
		"vision": true,
		"max_concurrent": 3,
		"rate_limit_rpm": 50,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},

	# ================================================================
	#  Doubao (Volcengine / 豆包)
	# ================================================================
	"doubao-pro-128k": {
		"provider": "Doubao",
		"context_window": 128000,
		"max_output": 4096,
		"vision": false,
		"max_concurrent": 3,
		"rate_limit_rpm": 100,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},
	"doubao-lite-128k": {
		"provider": "Doubao",
		"context_window": 128000,
		"max_output": 4096,
		"vision": false,
		"max_concurrent": 5,
		"rate_limit_rpm": 200,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "lightweight",
	},

	# ================================================================
	#  xAI (Grok)
	# ================================================================
	"grok-3": {
		"provider": "xAI",
		"context_window": 131072,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 3,
		"rate_limit_rpm": 60,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "flagship",
	},
	"grok-3-mini": {
		"provider": "xAI",
		"context_window": 131072,
		"max_output": 8192,
		"vision": false,
		"max_concurrent": 5,
		"rate_limit_rpm": 120,
		"supports_tools": true,
		"supports_json_mode": false,
		"tier": "lightweight",
	},
}

# ============ 通配符规则 ============
# 用于匹配模型 ID 变体（如 gpt-4o-2024-11-20 匹配 gpt-4o）

const WILDCARD_RULES := [
	{"prefix": "gpt-4.1-nano", "base": "gpt-4.1-nano"},
	{"prefix": "gpt-4.1-mini", "base": "gpt-4.1-mini"},
	{"prefix": "gpt-4.1", "base": "gpt-4.1"},
	{"prefix": "gpt-4o-mini", "base": "gpt-4o-mini"},
	{"prefix": "gpt-4o", "base": "gpt-4o"},
	{"prefix": "o4-mini", "base": "o4-mini"},
	{"prefix": "o3", "base": "o3"},
	{"prefix": "claude-opus-4", "base": "claude-opus-4-20250514"},
	{"prefix": "claude-sonnet-4", "base": "claude-sonnet-4-20250514"},
	{"prefix": "claude-3-7-sonnet", "base": "claude-3-7-sonnet-20250219"},
	{"prefix": "claude-3-5-sonnet", "base": "claude-3-5-sonnet-20241022"},
	{"prefix": "claude-3-5-haiku", "base": "claude-3-5-haiku-20241022"},
	{"prefix": "deepseek-chat", "base": "deepseek-chat"},
	{"prefix": "deepseek-reasoner", "base": "deepseek-reasoner"},
	{"prefix": "moonshot-v1-128k", "base": "moonshot-v1-128k"},
	{"prefix": "moonshot-v1-32k", "base": "moonshot-v1-128k"},
	{"prefix": "MiniMax-M3", "base": "MiniMax-M3"},
	{"prefix": "MiniMax-M2", "base": "MiniMax-M2"},
	{"prefix": "glm-4v", "base": "glm-4v-plus"},
	{"prefix": "glm-4", "base": "glm-4-plus"},
	{"prefix": "qwen-vl-max", "base": "qwen-vl-max"},
	{"prefix": "qwen-max", "base": "qwen-max"},
	{"prefix": "qwen-plus", "base": "qwen-plus"},
	{"prefix": "qwen-turbo", "base": "qwen-turbo"},
	{"prefix": "doubao-pro", "base": "doubao-pro-128k"},
	{"prefix": "doubao-lite", "base": "doubao-lite-128k"},
	{"prefix": "grok-3-mini", "base": "grok-3-mini"},
	{"prefix": "grok-3", "base": "grok-3"},
]


# ============ 保守默认值 ============

const DEFAULT_CAPABILITIES := {
	"context_window": 8192,
	"max_output": 4096,
	"vision": false,
	"max_concurrent": 1,
	"rate_limit_rpm": 30,
	"supports_tools": true,
	"supports_json_mode": false,
	"_source": "default_conservative",
}

const OLLAMA_DEFAULTS := {
	"context_window": 8192,
	"max_output": 4096,
	"vision": false,
	"max_concurrent": 1,
	"rate_limit_rpm": 9999,
	"supports_tools": true,
	"supports_json_mode": false,
	"_source": "ollama_default",
}


# ============ 自适应探测器 ============

var _probes: Dictionary = {}  # provider/model → AdaptiveProbe
var _db = null  # ModelDatabase instance (lazy init)


func _get_db():
	if _db == null:
		var db_script = load("res://addons/dotagent/llm/model_database.gd")
		if db_script:
			_db = db_script.new()
	return _db


# ============ 核心接口 ============

## 解析模型能力。查找链: 硬编码精确 → 在线数据库 → 通配符 → Ollama → 探测 → 默认
func resolve(model_id: String, provider_name: String = "") -> Dictionary:
	# 1. 硬编码精确匹配（含 max_concurrent 等运行时参数）
	if KNOWN_MODELS.has(model_id):
		var caps: Dictionary = KNOWN_MODELS[model_id].duplicate(true)
		caps["_source"] = "known_exact"
		return caps

	# 2. 在线数据库查找（5794 模型，通过 _extract 返回标准化字段）
	var db = _get_db()
	if db:
		var online: Dictionary = db.get_model(model_id, provider_name)
		if not online.is_empty():
			var caps: Dictionary = {
				"context_window": int(online.get("max_context", 0)),
				"max_output": int(online.get("max_output", 0)),
				"vision": online.get("vision", false),
				"audio": online.get("audio", false),
				"supports_tools": online.get("tools", false),
				"supports_reasoning": online.get("reasoning", false),
				"supports_structured_output": online.get("structured_output", false),
				"provider_key": online.get("provider_key", ""),
				"provider_name_online": online.get("provider_name", ""),
				"max_concurrent": 2,
				"rate_limit_rpm": 60,
				"tier": _infer_tier_online(online),
				"_source": "online_db",
			}
			return caps

	# 3. 通配符匹配（按前缀长度降序，先匹配最具体的）
	var best_match: String = ""
	var best_len: int = 0
	for rule in WILDCARD_RULES:
		var prefix: String = rule.prefix
		if model_id.begins_with(prefix) and prefix.length() > best_len:
			best_match = rule.base
			best_len = prefix.length()
	if not best_match.is_empty() and KNOWN_MODELS.has(best_match):
		var caps: Dictionary = KNOWN_MODELS[best_match].duplicate(true)
		caps["_source"] = "known_wildcard"
		caps["_matched_base"] = best_match
		return caps

	# 4. Ollama 特殊处理
	if provider_name.to_lower() == "ollama" or model_id.begins_with("ollama:"):
		var caps: Dictionary = OLLAMA_DEFAULTS.duplicate(true)
		# 尝试从 Ollama 模型名推断 context window
		if "128k" in model_id or "131k" in model_id:
			caps.context_window = 131072
		elif "32k" in model_id:
			caps.context_window = 32768
		elif "70b" in model_id or "65b" in model_id:
			caps.context_window = 4096
		caps["_source"] = "ollama_inferred"
		return caps

	# 5. 自适应探测结果
	var probe_key := provider_name + "/" + model_id
	if _probes.has(probe_key):
		var probe: Dictionary = _probes[probe_key]
		var caps: Dictionary = DEFAULT_CAPABILITIES.duplicate(true)
		caps.max_concurrent = probe.get("probed_concurrent", 1)
		caps._source = "adaptive_probe"
		return caps

	# 6. 保守默认
	var caps: Dictionary = DEFAULT_CAPABILITIES.duplicate(true)
	return caps


## 记录请求结果，用于自适应探测
func record_request_result(model_id: String, provider_name: String, http_code: int, response_time_ms: float) -> void:
	var probe_key := provider_name + "/" + model_id
	if not _probes.has(probe_key):
		_probes[probe_key] = {
			"success_streak": 0,
			"error_429_count": 0,
			"probed_concurrent": 1,
			"avg_response_time": 0.0,
			"total_requests": 0,
		}
	var probe: Dictionary = _probes[probe_key]
	probe.total_requests += 1

	# 移动平均响应时间
	var alpha := 0.3
	probe.avg_response_time = probe.avg_response_time * (1.0 - alpha) + response_time_ms * alpha

	if http_code == 429:
		probe.error_429_count += 1
		probe.success_streak = 0
		# 降并发
		if probe.probed_concurrent > 1:
			probe.probed_concurrent -= 1
	elif http_code >= 200 and http_code < 300:
		probe.success_streak += 1
		probe.error_429_count = 0
		# 连续 10 次成功，试探增加并发（上限 5）
		if probe.success_streak >= 10 and probe.probed_concurrent < 5:
			probe.probed_concurrent += 1
			probe.success_streak = 0


## 获取所有已知模型 ID（供 UI 展示）
func get_all_known_model_ids() -> Array:
	return KNOWN_MODELS.keys()


## 按 tier 过滤模型
func get_models_by_tier(tier: String) -> Array:
	var result: Array = []
	for id in KNOWN_MODELS:
		if KNOWN_MODELS[id].get("tier", "") == tier:
			result.append(id)
	return result


## 为 Cortex 分层策略推荐模型
## 返回: {root: model_id, branch: model_id, worker: model_id}
func recommend_cortex_tier(provider_name: String, available_models: Array) -> Dictionary:
	var flagship: String = ""
	var balanced: String = ""
	var lightweight: String = ""

	for mid in available_models:
		var caps := resolve(mid, provider_name)
		var t: String = caps.get("tier", "")
		if t == "flagship" and flagship.is_empty():
			flagship = mid
		elif t == "balanced" and balanced.is_empty():
			balanced = mid
		elif t == "lightweight" and lightweight.is_empty():
			lightweight = mid

	# 回退: 如果某层没有对应 tier，向上借用
	if balanced.is_empty() and not flagship.is_empty():
		balanced = flagship
	if lightweight.is_empty() and not balanced.is_empty():
		lightweight = balanced
	if lightweight.is_empty() and not flagship.is_empty():
		lightweight = flagship

	return {
		"root": flagship if not flagship.is_empty() else available_models[0] if not available_models.is_empty() else "",
		"branch": balanced if not balanced.is_empty() else flagship,
		"worker": lightweight if not lightweight.is_empty() else balanced,
	}


## 从 _extract() 返回的标准化字段推断 tier
func _infer_tier_online(online: Dictionary) -> String:
	var ctx: int = int(online.get("max_context", 0))
	var mid: String = str(online.get("id", "")).to_lower()
	var reasoning: bool = online.get("reasoning", false)

	# Reasoning 模型（从字段或 model_id 关键词推断）
	if reasoning or "reasoner" in mid or "thinking" in mid or mid.begins_with("o1") or mid.begins_with("o3") or mid.begins_with("o4"):
		return "reasoning"

	# Flash/Nano/Mini/Haiku/Turbo → lightweight
	if "flash" in mid or "nano" in mid or "mini" in mid or "haiku" in mid or "turbo" in mid or "lite" in mid:
		return "lightweight"

	# 高 context (>500K) → flagship
	if ctx > 500000:
		return "flagship"

	# 中等 context (100K-500K) → balanced
	if ctx >= 100000:
		return "balanced"

	# 小 context (<100K) → lightweight
	return "lightweight"
