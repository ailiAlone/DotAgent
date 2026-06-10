@tool
class_name Locale
extends RefCounted
## 简单的中英文 UI 翻译

const LANG_EN := "en"
const LANG_ZH := "zh"

static var _current: String = LANG_EN

static var _dict := {
	# Header
	"Sessions": {"en": "Sessions", "zh": "会话"},
	"Clear": {"en": "Clear", "zh": "清除"},
	"Settings": {"en": "Settings", "zh": "设置"},
	"Compact": {"en": "Compact", "zh": "压缩"},
	"Stop": {"en": "Stop", "zh": "停止"},
	"Send": {"en": "Send", "zh": "发送"},
	# Settings
	"AI Panel Settings": {"en": "AI Panel Settings", "zh": "AI 面板设置"},
	"OpenAI-compatible API config. Stored in addons/dotagent/config.cfg (not in git).": {
		"en": "OpenAI-compatible API config. Stored in addons/dotagent/config.cfg (not in git).",
		"zh": "OpenAI 兼容 API 配置。存储在 addons/dotagent/config.cfg（不进 git）。"
	},
	"Base URL:": {"en": "Base URL:", "zh": "Base URL:"},
	"API Key:": {"en": "API Key:", "zh": "API Key:"},
	"Model:": {"en": "Model:", "zh": "Model:"},
	"Temperature:": {"en": "Temperature:", "zh": "Temperature:"},
	"Context Limit (K):": {"en": "Context Limit (K):", "zh": "上下文限制 (K):"},
	"Language:": {"en": "Language:", "zh": "语言:"},
	"Save": {"en": "Save", "zh": "保存"},
	"Test": {"en": "Test", "zh": "测试"},
	"Test Connection": {"en": "Test Connection", "zh": "测试连接"},
	# Input
	"Ask AI to do something... (Enter to send, Shift+Enter for newline)": {
		"en": "Ask AI to do something... (Enter to send, Shift+Enter for newline)",
		"zh": "让 AI 做点什么...（回车发送，Shift+回车换行）"
	},
	# Status
	"Testing...": {"en": "Testing...", "zh": "测试中..."},
	"Connection OK": {"en": "Connection OK", "zh": "连接成功"},
	"Saved. Testing connection...": {"en": "Saved. Testing connection...", "zh": "已保存。正在测试连接..."},
	"Saved & connection OK": {"en": "Saved & connection OK", "zh": "已保存 & 连接成功"},
	"Save failed": {"en": "Save failed", "zh": "保存失败"},
	"Please configure API in Settings first (Base URL / Key / Model).": {
		"en": "⚠️ Please configure API in Settings first (Base URL / Key / Model).",
		"zh": "⚠️ 请先在设置中配置 API（Base URL / Key / Model）。"
	},
	"Configuration saved.": {"en": "✅ Configuration saved.", "zh": "✅ 配置已保存。"},
	"Please configure API in Settings first.": {
		"en": "⚠️ Please configure API in Settings first.",
		"zh": "⚠️ 请先在设置中配置 API。"
	},
	# Session
	"New": {"en": "New", "zh": "新建"},
	"Switch": {"en": "Switch", "zh": "切换"},
	"Rename": {"en": "Rename", "zh": "重命名"},
	"Fork": {"en": "Fork", "zh": "分支"},
	"Delete": {"en": "Delete", "zh": "删除"},
	"Close": {"en": "Close", "zh": "关闭"},
	"search…": {"en": "search…", "zh": "搜索…"},
	"Rename session": {"en": "Rename session", "zh": "重命名会话"},
	"New name:": {"en": "New name:", "zh": "新名称:"},
	"Delete session?": {"en": "Delete session?", "zh": "删除会话?"},
	"Delete session %s?\nThis cannot be undone.": {
		"en": "Delete %s?\nThis cannot be undone.",
		"zh": "删除 %s？\n此操作不可撤销。"
	},
	"(no sessions yet — click New)": {
		"en": "(no sessions yet — click New)",
		"zh": "（暂无会话 — 点击新建）"
	},
	# Chat
	"LLM error": {"en": "LLM error", "zh": "LLM 错误"},
	"Waiting for response... %ds timeout": {"en": "⏱ Waiting for response... %ds timeout", "zh": "⏱ 等待响应中... %ds 超时"},
	"— cleared —": {"en": "— cleared —", "zh": "— 已清除 —"},
	"— done —": {"en": "— done —", "zh": "— 完成 —"},
	"— Round done: %d ok, %d failed —": {"en": "— Round done: %d ok, %d failed —", "zh": "— 本轮完成: %d 成功, %d 失败 —"},
	"— Round done: %d tools all ok —": {"en": "— Round done: %d tools all ok —", "zh": "— 本轮完成: %d 工具全部成功 —"},
	"— compacted %d → %d msgs —": {"en": "— compacted %d → %d msgs —", "zh": "— 已压缩 %d → %d 条消息 —"},
	"loading...": {"en": "loading...", "zh": "加载中..."},
	"(not configured)": {"en": "(not configured)", "zh": "（未配置）"},
	# Activity
	"Tool Activity": {"en": "Tool Activity", "zh": "工具活动"},
	# Time
	"Activity": {"en": "Activity", "zh": "活动"},
}


static func t(key: String) -> String:
	var entry: Dictionary = _dict.get(key, {})
	if entry.is_empty():
		return key
	return entry.get(_current, entry.get(LANG_EN, key))


static func set_lang(lang: String) -> void:
	if lang == LANG_EN or lang == LANG_ZH:
		_current = lang


static func get_lang() -> String:
	return _current
