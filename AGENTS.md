# DotAgent Project — Agent Working Agreement

This file is project memory for AI agents working on the `dotagent` Godot editor
plugin in `addons/dotagent/`. Read this before doing anything in the project.

## Primary directive (set 2026-06-07)

> **Optimize the AI and the tools. Do NOT modify the user's project files
> (main_menu.tscn, settings.tscn, game.tscn, the .gd scripts under res://).**

The user's game project under `res://` is a *test harness* for dotagent, not the
real product. The real product is the plugin itself. So:

- ✅ Edit anything under `addons/dotagent/`
- ✅ Add new tools in `addons/dotagent/tools/`
- ✅ Improve the system prompt in `addons/dotagent/dock.gd` (STATIC_SYSTEM_PROMPT)
- ✅ Adjust dock.tscn / activity_panel.tscn / config_dialog.tscn (UI of the plugin)
- ❌ Do NOT edit `main_menu.tscn`, `main_menu.gd`, `settings.tscn`, `settings.gd`, `game.tscn`
- ❌ Do NOT add new demo scenes or refactor the user's game logic
- ❌ Do NOT autonomously reorder / restyle the user's test scenes even if they look ugly

If the user reports something the AI panel did wrong inside a scene, the fix
goes in the **tool** that caused the mistake, not in the scene itself.

## API key strategy (set 2026-06-07, user-confirmed)

`ConfigManager.get_api_key()` reads in this priority:

1. **`config.cfg` `llm.api_key`** — primary path. The user fills this in
   the Settings dialog (config_dialog.tscn). This is the "user-entered" key.
2. **Windows user env `DeepSeek_APIKEY`** (variable name is case-sensitive:
   `DeepSeek_APIKEY`, NOT `DEEPSEEK_API_KEY`) — fallback only. Use case:
   config.cfg lost / never filled / fresh clone. The user keeps a key in
   `HKCU\Environment` as a safety net so the plugin still has *something* to
   call DeepSeek with.

**Do NOT reverse the priority.** Env-first breaks the "user-entered" UX flow
and surprises the user when they later update the key in Settings.

## DeepSeek specifics (verified 2026-06-07)

- **Base URL**: `https://api.deepseek.com/v1` (NOT including `/chat/completions`
  — that's the endpoint path, added by `LLMClient._normalize_url()`).
  Putting `/chat/completions` in `base_url` produces
  `…/chat/completions/chat/completions` and 404s.
- **Real model names** (verified by direct API call):
  - `deepseek-v4-pro` ✅ (pro tier)
  - `deepseek-v4-flash` ✅ (flash tier)
  - `deepseek-chat` / `deepseek-reasoner` / `deepseek-coder` ⚠️ all
    server-side aliased to `deepseek-v4-flash` — avoid using these as they
	obscure which tier you're paying for.

## Project layout

```
ai-plug/
├── project.godot                 # Godot project (main scene = main_menu.tscn)
├── main_menu.tscn / .gd          # USER's test scene — do not touch
├── settings.tscn / .gd           # USER's test scene — do not touch
├── game.tscn                     # USER's test scene — do not touch
└── addons/dotagent/              # THE PLUGIN — this is what we optimize
    ├── plugin.cfg / plugin.gd
    ├── dock.gd / dock.tscn       # main chat UI
    ├── activity_panel.gd / .tscn # bottom activity log
    ├── config_dialog.gd / .tscn  # settings popup
    ├── llm_client.gd             # OpenAI-compatible HTTP + SSE
    ├── tool_registry.gd          # tool dispatcher
    ├── logger.gd                 # per-session log to res://logs/<ts>/
    ├── config_manager.gd
    ├── backup_manager.gd
    └── tools/
        ├── tool_base.gd          # shared base: _ok/_err, _ei(), _walk_dir, etc.
        ├── scene_tools.gd        # get/add/remove/reparent + get/set props
        ├── script_tools.gd       # read/create/update/list/search scripts
        ├── project_tools.gd      # files, project settings, read resource as text
        ├── exec_tools.gd         # run scenes, execute_gdscript, open_scene
        └── session_tools.gd      # list/load/create/rename/fork/delete sessions
```

## Session vs Log (critical distinction)

- **Session** = 用户可见的对话历史。用户主动管理（新建/切换/重命名/fork/删除）。
  存储在 `addons/dotagent/sessions/<id>/`。由 `SessionStore` 管理。
- **Log** = 开发者调试用的运行流水。被动记录，不面向用户。
  存储在 `addons/dotagent/logs/<timestamp>/`。由 `SessionLog`（logger.gd）管理。

两者是完全不同的概念，不要混用。

## Logging convention

每次 AI 对话自动写入 `res://addons/dotagent/logs/<YYYY-MM-DD_HH-MM-SS>/`：
- `conversation.md` — 完整对话（system prompt + 工具 I/O）
- `editor_output.txt` — 时间戳日志 + LLM HTTP + 工具日志
- `messages.json` — 消息数组（机器可读）
- `meta.json` — 计数（消息数、工具调用数、用户消息数）

## Tool naming convention

所有工具模块继承 `ToolBase`（`addons/dotagent/tools/tool_base.gd`），通过路径继承：
`extends "res://addons/dotagent/tools/tool_base.gd"`
（不用 `class_name` — Godot 4.5 中 `@tool class_name` 脚本引用 EditorInterface 会导致注册失败，extends 回退到 RefCounted）
- `get_tool_definitions() -> Array` — `{name, description, parameters, method_name, dangerous}` 列表
- `call_method(method_name: String, args: Dictionary) -> Dictionary` — 分发
- `set_editor_context(plugin, activity)` — 由 ToolBase 提供，子类可 override 调 `super`

返回值格式：`{"ok": bool, "content": str}`。通过继承自 ToolBase 的 `_ok(content)` / `_err(content)` 封装。

ToolBase 还提供共享方法：`_ei()`、`_walk_dir()`、`_ensure_dir()`、`_refresh_filesystem()`。

Tool name uniqueness is checked at registry load time — if two modules declare
the same `name`, plugin fails to load (see `register_module` in tool_registry.gd).

## 2026-06-07 cleanup

- 删除了根目录泄漏的 4 个文件（conversation.md, editor_output.txt, messages.json, meta.json）
- 删除了 `tool_registry.gd` 的 `_confirm_dangerous()` 死方法（~55 行，不再弹窗）
- 删除了 `logger.gd` 的 `list_sessions()` 和 `load_session_messages()` 死方法
- 删除了 `exec_tools.gd` 的 `get_console_output` 空壳工具
- 清理了 23 个 session 碰撞重复目录（_1/_2/_3 后缀）
- 删除了空的 `tests/fixtures/` 目录
- 抽取了 5 个工具文件中重复的 `_ok/_err`（10 个定义 → 1 个 ToolBase）
- 统一了 `_walk_dir` 实现（script_tools + project_tools → ToolBase）
- 所有工具文件从 `extends RefCounted` 改为 `extends ToolBase`

## Known sharp edges (lessons learned)

- **`EditorInterface.open_scene_from_path()` returns void** in Godot 4.5 — do
  NOT assign its result to `err`. See `_tool_open_scene` in exec_tools.gd.
- **`_result` in execute_gdscript wrapper must be typed `String`, not `null`**
  — null gets inferred as Variant, breaks the `-> String` return type. Also
  the wrapper template must have **0 tabs** before `%s`; indentation is added
  by the caller, not the template.
- **Godot caches .tscn preloads** — EditorPlugin's `_enter_tree` only fires
  once per session. Editing dock.tscn / activity_panel.tscn / config_dialog.tscn
  requires a full editor restart (or disable+enable the plugin).
- **`EditorInterface.save_scene()` is the right call** for auto-save after
  scene writes. See `_emit_change` in scene_tools.gd.
- **`add_node` should set `unique_name_in_owner=true`** for any node that
  scripts will reference via `%Name` — see system prompt guidance.
- **`execute_gdscript` snippet receives `ei: EditorInterface` as the `run()` arg**
  — that's how the wrapper exposes the editor API. Do NOT use
  `EditorInterface.xxx` (that's a type) or `get_editor_interface()` (the
  RefCounted wrapper has no editor singleton access).
