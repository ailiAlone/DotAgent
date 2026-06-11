# DotAgent — AI-Powered Godot Editor Assistant

An AI development assistant running directly inside the Godot editor. OpenAI-compatible API, full tool-calling permissions — read scenes, write scripts, add nodes, run validation, all without leaving the editor.

<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.5-blue?logo=godot-engine" alt="Godot 4.5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Tools-60+-orange" alt="60+ Tools">
</p>

## Features

- **60+ Editor Tools** — Scene/node CRUD, script I/O, project settings, screenshot analysis, runtime validation
- **ReAct Loop** — Think → Act → Observe, AI autonomously completes multi-step tasks
- **Visual Feedback Loop** — `screenshot_editor` + `analyze_image` for instant "capture → analyze → fix → verify" cycles
- **Structured Logging** — `session.json` structured data + `timeline.md` report + auto diagnostics
- **Session Memory** — Cross-conversation summaries, old history never pollutes current context
- **Multi-API Compatible** — Works with any OpenAI-compatible endpoint (OpenAI, DeepSeek, MiniMax, Ollama, etc.)

## Installation

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

## Usage

Type in the input box, press Enter to send. The AI automatically sees your scene structure, selected nodes, and Godot version, then decides which tools to invoke.

The bottom **Activity** panel shows tool execution in real-time. Write operations are automatically backed up to `.dotagent_backups/`.

## Tools Overview

| Category | Count | Examples |
|----------|-------|----------|
| Scene / Node | 10 | `create_scene` `add_node` `set_node_property` `remove_node` |
| Script / File | 12 | `create_script` `update_script` `replace_in_file` `delete_file` |
| Read / Query | 15 | `read_script` `get_node_properties` `search_in_scripts` `peek_scene` |
| Run / Debug | 8 | `run_scene_capture` `execute_gdscript` `read_editor_output` |
| Screenshot / Vision | 5 | `screenshot_editor` `analyze_image` `focus_editor_view` |
| Project Management | 8 | `get_project_info` `set_project_setting` `remember` `recall` |
| Utilities | 5 | `close_all_scenes` `list_open_scenes` `undo_last` |

## Architecture

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

## Requirements

- Godot 4.5+

## License

MIT © 2026 ailiAlone

## Links

- [GitHub](https://github.com/ailiAlone/dotagent)
- [Issues](https://github.com/ailiAlone/dotagent/issues)
