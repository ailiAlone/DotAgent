# DotAgent — AI-Powered Godot Editor Assistant

<p align="center">
  <b>English</b> | <a href="#dotagent--ai-驱动的-godot-编辑器助手">中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.5-blue?logo=godot-engine" alt="Godot 4.5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Tools-58+-orange" alt="58+ Tools">
</p>

---

直接在 Godot 编辑器内部运行的 AI 开发助手。支持 OpenAI 兼容 API（DeepSeek / MiniMax / Ollama / Moonshot 等），58+ 工具完整权限——场景搭建、脚本编写、截图分析、运行验证，全在编辑器内完成闭环。

## 🚀 快速开始

**1. 安装**：将 `addons/dotagent/` 文件夹复制到你 Godot 项目根目录的 `addons/` 下。

```
your-project/
├── addons/
│   └── dotagent/          ← 复制到这里
│       ├── plugin.cfg
│       ├── plugin.gd
│       └── ...
├── project.godot
└── ...
```

**2. 启用插件**：Godot 编辑器 → Project → Project Settings → Plugins → 勾选 **DotAgent**。

**3. 配置 API**：点击编辑器右下角 AI Panel 右上角的 **Settings**：

| 配置项 | 说明 | 示例 |
|--------|------|------|
| Provider | API 提供商 | DeepSeek / OpenAI / MiniMax |
| Base URL | API 地址 | `https://api.deepseek.com` |
| API Key | 密钥 | 面板内输入，点击 Configure & Restart |
| Model | 模型名 | 主面板底部下拉选择 |

**API Key 面板内直接输入**，点击 Configure & Restart 自动写入系统环境变量并重启编辑器。

## 特性

- **58+ 编辑器工具** — 场景/节点 CRUD、脚本读写、项目设置、截图分析、运行验证
- **ReAct 循环** — 思考 → 行动 → 观察，AI 自主完成多轮任务
- **视觉反馈闭环** — `screenshot_editor` + `analyze_image` 即时"截图→分析→修改→验证"
- **实时配置** — 所有设置即时生效，差异化日志输出
- **API Key 面板** — 输入 key 一键配置到环境变量并重启
- **模型设置弹窗** — 视觉开关、上下文大小、压缩阈值统一管理
- **结构化日志** — `session.json` + `timeline.md` + 自动诊断
- **会话记忆** — 跨对话摘要，历史不污染当前上下文
- **多 API 兼容** — 任何 OpenAI 兼容接口均可使用

## 支持的服务商

| 服务商 | Base URL |
|--------|----------|
| OpenAI | `https://api.openai.com/v1` |
| DeepSeek | `https://api.deepseek.com` |
| MiniMax | `https://api.minimaxi.com/v1` |
| Moonshot (Kimi) | `https://api.moonshot.cn/v1` |
| Zhipu AI (GLM) | `https://open.bigmodel.cn/api/paas/v4` |
| Qwen (DashScope) | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| Doubao | `https://ark.cn-beijing.volces.com/api/v3` |
| xAI (Grok) | `https://api.x.ai/v1` |
| Ollama (本地) | `http://localhost:11434/v1` |
| Custom | 任意 OpenAI 兼容端点 |

## 使用

输入框打字，Enter 发送，Shift+Enter 换行。AI 自动获取场景结构、选中节点、Godot 版本信息，决定调用哪些工具。底部 **Activity** 面板实时展示工具调用过程。写操作自动备份到 `.dotagent_backups/`。

## 工具一览

| 类别 | 数量 | 示例 |
|------|------|------|
| 场景/节点 | 10+ | `create_scene` `add_node` `set_node_property` `remove_node` |
| 脚本/文件 | 12+ | `create_script` `update_script` `replace_in_file` `delete_file` |
| 读取查询 | 15+ | `read_script` `get_node_properties` `search_in_scripts` |
| 运行/调试 | 8+ | `run_scene_capture` `execute_gdscript` `check_script_syntax` |
| 截图/视觉 | 5 | `screenshot_editor` `analyze_image` `focus_editor_view` |
| 项目管理 | 8 | `get_project_info` `set_project_setting` `remember` `recall` |

## 架构

```
addons/dotagent/
├── plugin.gd             插件入口
├── controller/           业务逻辑 + 系统提示词
├── core/                 ReAct 循环引擎
├── llm/                  HTTP + SSE 流式 + Provider 抽象层
│   └── providers/        OpenAI / Anthropic / Ollama 适配
├── log/                  日志收集 + 诊断引擎
├── context/              上下文构建 + 消息压缩
├── session/              会话管理 + 记忆
├── tools/                58+ 工具实现
├── ui/                   Dock / ModelPicker / Settings / Session
├── config/               配置持久化 + 本地化
└── skill/                技能系统
```

## License

MIT

---

# DotAgent — AI 驱动的 Godot 编辑器助手

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.5-blue?logo=godot-engine" alt="Godot 4.5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Tools-58+-orange" alt="58+ Tools">
</p>

---

直接在 Godot 编辑器内部运行的 AI 开发助手。支持 OpenAI 兼容 API（DeepSeek / MiniMax / Ollama / Moonshot 等），58+ 工具完整权限——场景搭建、脚本编写、截图分析、运行验证，全在编辑器内完成闭环。

## 🚀 快速开始

**1. 安装**：将 `addons/dotagent/` 文件夹复制到 Godot 项目根目录的 `addons/` 下。

```
your-project/
├── addons/
│   └── dotagent/          ← 复制到这里
│       ├── plugin.cfg
│       ├── plugin.gd
│       └── ...
├── project.godot
└── ...
```

**2. 启用插件**：Godot 编辑器 → Project → Project Settings → Plugins → 勾选 **DotAgent**。

**3. 配置 API**：点击编辑器右下角 AI Panel 右上角的 **Settings**：

| 配置项 | 说明 | 示例 |
|--------|------|------|
| Provider | API 提供商 | DeepSeek / OpenAI / MiniMax |
| Base URL | API 地址 | `https://api.deepseek.com` |
| API Key | 密钥 | 面板内输入，点击「配置并重启」 |
| Model | 模型名 | 主面板底部下拉选择 |

**API Key 面板内直接输入**，点击「配置并重启」自动写入系统环境变量并重启编辑器。

## 特性

- **58+ 编辑器工具** — 场景/节点 CRUD、脚本读写、项目设置、截图分析、运行验证
- **ReAct 循环** — 思考 → 行动 → 观察，AI 自主完成多轮任务
- **视觉反馈闭环** — `screenshot_editor` + `analyze_image` 即时"截图→分析→修改→验证"
- **实时配置** — 所有设置即时生效，差异化日志输出
- **API Key 面板** — 输入 key 一键配置到环境变量并重启
- **模型设置弹窗** — 视觉开关、上下文大小、压缩阈值统一管理
- **结构化日志** — `session.json` + `timeline.md` + 自动诊断
- **会话记忆** — 跨对话摘要，历史不污染当前上下文
- **多 API 兼容** — 任何 OpenAI 兼容接口均可使用

## 支持的服务商

| 服务商 | Base URL |
|--------|----------|
| OpenAI | `https://api.openai.com/v1` |
| DeepSeek | `https://api.deepseek.com` |
| MiniMax | `https://api.minimaxi.com/v1` |
| Moonshot (Kimi) | `https://api.moonshot.cn/v1` |
| Zhipu AI (GLM) | `https://open.bigmodel.cn/api/paas/v4` |
| Qwen (DashScope) | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| Doubao | `https://ark.cn-beijing.volces.com/api/v3` |
| xAI (Grok) | `https://api.x.ai/v1` |
| Ollama (本地) | `http://localhost:11434/v1` |
| Custom | 任意 OpenAI 兼容端点 |

## 使用

输入框打字，Enter 发送，Shift+Enter 换行。AI 自动获取场景结构、选中节点、Godot 版本信息，决定调用哪些工具。底部 **Activity** 面板实时展示工具调用过程。写操作自动备份到 `.dotagent_backups/`。

## 工具一览

| 类别 | 数量 | 示例 |
|------|------|------|
| 场景/节点 | 10+ | `create_scene` `add_node` `set_node_property` `remove_node` |
| 脚本/文件 | 12+ | `create_script` `update_script` `replace_in_file` `delete_file` |
| 读取查询 | 15+ | `read_script` `get_node_properties` `search_in_scripts` |
| 运行/调试 | 8+ | `run_scene_capture` `execute_gdscript` `check_script_syntax` |
| 截图/视觉 | 5 | `screenshot_editor` `analyze_image` `focus_editor_view` |
| 项目管理 | 8 | `get_project_info` `set_project_setting` `remember` `recall` |

## 架构

```
addons/dotagent/
├── plugin.gd             插件入口
├── controller/           业务逻辑 + 系统提示词
├── core/                 ReAct 循环引擎
├── llm/                  HTTP + SSE 流式 + Provider 抽象层
│   └── providers/        OpenAI / Anthropic / Ollama 适配
├── log/                  日志收集 + 诊断引擎
├── context/              上下文构建 + 消息压缩
├── session/              会话管理 + 记忆
├── tools/                58+ 工具实现
├── ui/                   Dock / ModelPicker / Settings / Session
├── config/               配置持久化 + 本地化
└── skill/                技能系统

---

<p align="center">
  <b><a href="#dotagent--ai-powered-godot-editor-assistant">English</a></b> | <b>中文</b>
</p>

# DotAgent — AI 驱动的 Godot 编辑器助手
