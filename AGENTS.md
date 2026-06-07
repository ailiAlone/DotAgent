# DotAgent Project — Agent Working Agreement

This file is project memory for AI agents working on the `dotagent` Godot editor
plugin in `addons/ai_panel/`. Read this before doing anything in the project.

## Primary directive (set 2026-06-07)

> **Optimize the AI and the tools. Do NOT modify the user's project files
> (main_menu.tscn, settings.tscn, game.tscn, the .gd scripts under res://).**

The user's game project under `res://` is a *test harness* for dotagent, not the
real product. The real product is the plugin itself. So:

- ✅ Edit anything under `addons/ai_panel/`
- ✅ Add new tools in `addons/ai_panel/tools/`
- ✅ Improve the system prompt in `addons/ai_panel/dock.gd` (STATIC_SYSTEM_PROMPT)
- ✅ Adjust dock.tscn / activity_panel.tscn / config_dialog.tscn (UI of the plugin)
- ❌ Do NOT edit `main_menu.tscn`, `main_menu.gd`, `settings.tscn`, `settings.gd`, `game.tscn`
- ❌ Do NOT add new demo scenes or refactor the user's game logic
- ❌ Do NOT autonomously reorder / restyle the user's test scenes even if they look ugly

If the user reports something the AI panel did wrong inside a scene, the fix
goes in the **tool** that caused the mistake, not in the scene itself.

## Project layout

```
ai-plug/
├── project.godot                 # Godot project (main scene = main_menu.tscn)
├── main_menu.tscn / .gd          # USER's test scene — do not touch
├── settings.tscn / .gd           # USER's test scene — do not touch
├── game.tscn                     # USER's test scene — do not touch
└── addons/ai_panel/              # THE PLUGIN — this is what we optimize
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
        ├── scene_tools.gd        # get/add/remove/reparent + get/set props
        ├── script_tools.gd       # read/create/update/list/search scripts
        ├── project_tools.gd      # files, project settings, read resource as text
        └── exec_tools.gd         # run scenes, execute_gdscript, open_scene
```

## Logging convention

Every AI session writes to `res://logs/<YYYY-MM-DD_HH-MM-SS>/` with:
- `conversation.md` — full chat including system prompt + tool I/O
- `editor_output.txt` — timestamps + LLM HTTP + tool log lines
- `meta.json` — counts (messages, tool calls, user messages)

`get_debug_output` MCP tool reads `editor_output.txt` to see what the editor
printed during the session.

## Tool naming convention

Each `addons/ai_panel/tools/<name>.gd` extends `RefCounted` and exposes:
- `get_tool_definitions() -> Array` — list of `{name, description, parameters, method_name, dangerous}`
- `call_method(method_name: String, args: Dictionary) -> Dictionary` — dispatch
- `set_editor_context(plugin: EditorPlugin, activity: Control)` — injected by registry

Return shape: `{"ok": bool, "content": str}`. Wrap via `_ok(content)` / `_err(content)`.

Tool name uniqueness is checked at registry load time — if two modules declare
the same `name`, plugin fails to load (see `register_module` in tool_registry.gd).

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
