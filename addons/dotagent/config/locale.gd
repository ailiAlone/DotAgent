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
	"Model": {"en": "Model", "zh": "模型"},
	"Stop": {"en": "Stop", "zh": "停止"},
	"Send": {"en": "Send", "zh": "发送"},
	# Settings
	"AI Panel Settings": {"en": "AI Panel Settings", "zh": "AI 面板设置"},
	"OpenAI-compatible API config.": {
		"en": "OpenAI-compatible API config.",
		"zh": "OpenAI 兼容 API 格式 配置。"
	},
	"OpenAI-compatible API config. Stored in addons/dotagent/config.cfg (not in git).": {
		"en": "OpenAI-compatible API config. Stored in addons/dotagent/config.cfg (not in git).",
		"zh": "OpenAI 兼容 API 配置。存储在 addons/dotagent/config.cfg（不进 git）。"
	},
	"Provider:": {"en": "Provider:", "zh": "提供商:"},
	"Base URL:": {"en": "Base URL:", "zh": "Base URL:"},
	"API Key:": {"en": "API Key:", "zh": "API Key:"},
	"Model:": {"en": "Model:", "zh": "Model:"},
	"proxy:": {"en": "Proxy:", "zh": "代理:"},
	"enable": {"en": "Enable", "zh": "启用"},
	"Proxy Host:": {"en": "Proxy Host:", "zh": "代理主机:"},
	"Proxy Port:": {"en": "Proxy Port:", "zh": "代理端口:"},
	"Temperature:": {"en": "Temperature:", "zh": "Temperature:"},
	"Context Limit (K):": {"en": "Context Limit (K):", "zh": "上下文限制 (K):"},
	"Context Limit:": {"en": "Context Limit:", "zh": "上下文限制:"},
	"Vision:": {"en": "Vision:", "zh": "视觉:"},
	"Yes": {"en": "Yes", "zh": "是"},
	"No": {"en": "No", "zh": "否"},
	"Auto": {"en": "Auto", "zh": "自动"},
	"Language:": {"en": "Language:", "zh": "语言:"},
	"中文": {"en": "中文", "zh": "中文"},
	"English": {"en": "English", "zh": "English"},
	"Save": {"en": "Save", "zh": "保存"},
	"Test": {"en": "Test", "zh": "测试"},
	"Test Connection": {"en": "Test Connection", "zh": "测试连接"},
	"Cancel": {"en": "Cancel", "zh": "取消"},
	"Configure & Restart": {"en": "Configure & Restart", "zh": "配置并重启"},
	# API Key field status
	"please_select_model": {
		"en": "❌ Please select a model in the main Dock first",
		"zh": "❌ 请先在主 Dock 底部选择模型"
	},
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
	# Tooltips
	"api_key_hint_title": {
		"en": "Enter your API key, then click Configure & Restart.",
		"zh": "输入 API Key，点击「配置并重启」即可生效。"
	},
	"api_key_hint_body": {
		"en": "The key is stored in the DOTAGENT_API_KEY environment variable and never saved to config files.",
		"zh": "Key 存储在 DOTAGENT_API_KEY 环境变量中，不会写入配置文件。"
	},
	"language_hint": {
		"en": "Controls the language of the plugin UI text.\n\nNote: The Godot editor will force-localize some of the plugin's UI text.",
		"zh": "控制插件界面文字的语言。\n\n注意: Godot 编辑器 会强制本地化该插件的部分UI的文字内容。"
	},
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
