# DotAgent — AI-Powered Godot Editor Assistant / AI 驱动的 Godot 编辑器助手

<p align="center">
  <b>中文</b> | <a href="#english">English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.5-blue?logo=godot-engine" alt="Godot 4.5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Tools-60+-orange" alt="60+ Tools">
</p>

---

直接在 Godot 编辑器内部运行的 AI 开发助手。支持 OpenAI 兼容 API（DeepSeek / MiniMax / Ollama 等），60+ 工具完整权限——场景搭建、脚本编写、截图分析、运行验证，全在编辑器内完成闭环。

## 特性

- **60+ 编辑器工具** — 场景/节点 CRUD、脚本读写、项目设置、截图分析、运行验证
- **ReAct 循环** — 思考 → 行动 → 观察，AI 自主完成多轮任务
- **视觉反馈闭环** — `screenshot_editor` + `analyze_image` 即时"截图→分析→修改→验证"
- **结构化日志** — `session.json` 数据 + `timeline.md` 报告 + 自动诊断
- **会话记忆** — 跨对话摘要，历史不污染当前上下文
- **多 API 兼容** — 任何 OpenAI 兼容接口均可使用

## 安装

1. 下载 [最新 Release](https://github.com/ailiAlone/dotagent/releases)
2. 将 `addons/dotagent/` 放入 Godot 项目的 `addons/` 目录
3. 编辑器 → Project → Project Settings → Plugins → 启用 **DotAgent**
4. 右下角出现 AI Panel，点击 **Settings** 配置 API

支持的 API：

| 服务商 | Base URL |
|--------|----------|
| OpenAI | `https://api.openai.com/v1` |
| DeepSeek | `https://api.deepseek.com/v1` |
| MiniMax | `https://api.minimaxi.com/v1` |
| Ollama (本地) | `http://localhost:11434/v1` |

## 使用

输入框打字，Enter 发送。AI 自动获取场景结构、选中节点、Godot 版本信息，然后决定调用哪些工具。

底部 **Activity** 面板实时展示工具调用过程。写操作自动备份到 `.dotagent_backups/`。

## 工具一览

| 类别 | 数量 | 示例 |
|------|------|------|
| 场景/节点 | 10 | `create_scene` `add_node` `set_node_property` `remove_node` |
| 脚本/文件 | 12 | `create_script` `update_script` `replace_in_file` `delete_file` |
| 读取查询 | 15 | `read_script` `get_node_properties` `search_in_scripts` `peek_scene` |
| 运行/调试 | 8 | `run_scene_capture` `execute_gdscript` `read_editor_output` |
| 截图/视觉 | 5 | `screenshot_editor` `analyze_image` `focus_editor_view` |
| 项目管理 | 8 | `get_project_info` `set_project_setting` `remember` `recall` |
| 其他 | 5 | `close_all_scenes` `list_open_scenes` `undo_last` |

## 架构

```
addons/dotagent/
├── controller/       业务逻辑 + 系统提示词
├── core/             ReAct 循环引擎
├── llm/              HTTP 客户端 + SSE 流式
├── log/              日志收集 + 诊断引擎
├── context/          上下文构建 + 消息压缩
├── session/          会话管理 + 记忆
├── tools/            60+ 工具实现
├── ui/               Dock 面板 + 设置弹窗
├── config/           配置持久化
├── backup/           自动备份
├── skill/            技能系统
└── skills/           技能文件 (builtin + custom)
```

## 要求

- Godot 4.5+

## 许可

MIT © 2026 ailiAlone

## 链接

- [GitHub](https://github.com/ailiAlone/dotagent)
- [Issues](https://github.com/ailiAlone/dotagent/issues)

---

<div id="english"></div>

## English

An AI development assistant running directly inside the Godot editor. OpenAI-compatible API, full tool-calling permissions — read scenes, write scripts, add nodes, run validation, all without leaving the editor.

### Features

- **60+ Editor Tools** — Scene/node CRUD, script I/O, project settings, screenshot analysis, runtime validation
- **ReAct Loop** — Think → Act → Observe, AI autonomously completes multi-step tasks
- **Visual Feedback Loop** — `screenshot_editor` + `analyze_image` for instant "capture → analyze → fix → verify" cycles
- **Structured Logging** — `session.json` structured data + `timeline.md` report + auto diagnostics
- **Session Memory** — Cross-conversation summaries, old history never pollutes current context
- **Multi-API Compatible** — Works with any OpenAI-compatible endpoint (OpenAI, DeepSeek, MiniMax, Ollama, etc.)

### Installation

1. Download the [latest Release](https://github.com/ailiAlone/dotagent/releases)
2. Copy `addons/dotagent/` into your Godot project's `addons/` folder
3. Editor → Project → Project Settings → Plugins → Enable **DotAgent**
4. The AI Panel appears in the bottom-right dock. Click **Settings** to configure your API.

Supported APIs:

| Provider | Base URL |
|----------|----------|
| OpenAI | `https://api.openai.com/v1` |
| DeepSeek | `https://api.deepseek.com/v1` |
| MiniMax | `https://api.minimaxi.com/v1` |
| Ollama (local) | `http://localhost:11434/v1` |

### Usage

Type in the input box, press Enter to send. The AI automatically sees your scene structure, selected nodes, and Godot version, then decides which tools to invoke.

The bottom **Activity** panel shows tool execution in real-time. Write operations are automatically backed up to `.dotagent_backups/`.

### Tools Overview

| Category | Count | Examples |
|----------|-------|----------|
| Scene / Node | 10 | `create_scene` `add_node` `set_node_property` `remove_node` |
| Script / File | 12 | `create_script` `update_script` `replace_in_file` `delete_file` |
| Read / Query | 15 | `read_script` `get_node_properties` `search_in_scripts` `peek_scene` |
| Run / Debug | 8 | `run_scene_capture` `execute_gdscript` `read_editor_output` |
| Screenshot / Vision | 5 | `screenshot_editor` `analyze_image` `focus_editor_view` |
| Project Management | 8 | `get_project_info` `set_project_setting` `remember` `recall` |
| Utilities | 5 | `close_all_scenes` `list_open_scenes` `undo_last` |

### Architecture

```
addons/dotagent/
├── controller/       Business logic + system prompt
├── core/             ReAct loop engine
├── llm/              HTTP client + SSE streaming
├── log/              Logging + diagnostics engine
├── context/          Context building + message compression
├── session/          Session management + memory
├── tools/            60+ tool implementations
├── ui/               Dock panel + settings dialog
├── config/           Configuration persistence
├── backup/           Auto-backup manager
├── skill/            Skill system
└── skills/           Skill files (builtin + custom)
```

### Requirements

- Godot 4.5+

### License

MIT © 2026 ailiAlone

### Links

- [GitHub](https://github.com/ailiAlone/dotagent)
- [Issues](https://github.com/ailiAlone/dotagent/issues)
