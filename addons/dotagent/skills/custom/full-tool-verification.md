# triggers: tool verification, toolbox, full test, verify tools, audit, register

# Tool Test Skill

This skill documents lessons learned during full tool verification (2026-06-10).

## What was tested
All 58 registered tools in the DotAgent toolbox, except `reload_project` (kills tool registry).

## Key findings
- `open_godot_docs` is documented in the toolbox but NOT registered — calling it returns "Tool not found".
- `add_node` properties dict may not set Vector2 position correctly in some cases — use `set_node_property` after add to be safe.
- `execute_gdscript` snippet can lose indentation through JSON encoding — prefer single-line or simple snippets; complex code should go in a .gd file via `create_script`/`update_script`.
- `replace_in_file` is preferred for large scripts over `update_script` (avoids massive JSON payload).
- `undo_last` restores from the most recent scene backup — it may revert MORE than the single last action (depends on what triggered the backup).
- `call_node_method` requires the target node to actually have the method (attach a script first or use built-in methods).

## Cleanup commands
- `cleanup_backups` — removes old backup directories to silence "Failed parse script" warnings.
- `delete_files` — batch delete, returns OK per file.
- `undo_last` — restore last scene from backup.
