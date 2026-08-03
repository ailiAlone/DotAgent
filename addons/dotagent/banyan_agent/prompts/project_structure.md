# Project File Structure

This project uses **domain-based organization** (Godot style), NOT type-based organization (Unity style).

## Current State (Transition Period)

The project has existing files in flat directories (`scripts/`, `scenes/`). These are legacy — they stay where they are. But **all new files MUST go in domain directories**:

```
res://
├── scripts/             ← EXISTING files only (do NOT create new files here)
├── scenes/              ← EXISTING files only (do NOT create new files here)
├── player/              ← NEW player-related files go here
├── enemies/             ← NEW enemy/boss/bullet files go here
├── ui/                  ← NEW UI/HUD/menu files go here
│   ├── hud/
│   └── settings/
├── core/                ← NEW autoloads, managers, game logic
├── assets/              ← NEW shared assets (audio, fonts, textures)
├── project.godot
└── export_presets.cfg
```

## The Rule

**When creating ANY new file, place it in the correct domain directory.** Never create new files in `scripts/`, `scenes/`, or `resources/`.

### Domain Mapping — Where New Files Go

| What you're creating | Domain directory | Example path |
|---|---|---|
| Player script/scene | `res://player/` | `res://player/player_shield.gd` |
| Enemy/boss/bullet | `res://enemies/` | `res://enemies/boss_phase2.gd` |
| UI screen/HUD element | `res://ui/` | `res://ui/settings/settings_menu.tscn` |
| Game manager/autoload | `res://core/` | `res://core/save_manager.gd` |
| Audio/sound effect | `res://assets/audio/` | `res://assets/audio/shield_activate.ogg` |
| Sprite/texture | `res://assets/textures/` | `res://assets/textures/player_shield.png` |
| Config/data resource | `res://core/` | `res://core/difficulty_config.tres` |

### When Modifying Existing Files

Modifying files that already exist in `scripts/` or `scenes/` is fine — use `update_script`, `replace_in_file`, or `patch_scene` with the existing path. The path validation only blocks **creating new files** in flat directories.

### Scene Cross-References

When a new script in a domain directory is attached to an existing scene, update the scene's `ext_resource` path:
```
# OLD (flat):
[ext_resource type="Script" path="res://scripts/player_shield.gd" id="2"]

# NEW (domain):
[ext_resource type="Script" path="res://player/player_shield.gd" id="2"]
```

### Autoload Registration

If creating a new autoload singleton, register it in `project.godot` under `[autoload]`:
```
NewManager="*res://core/new_manager.gd"
```
**Important:** Do NOT add `class_name` to autoload scripts — Godot rejects `class_name` that shadows an autoload name.

## What NOT to Do

- ❌ `res://scripts/new_feature.gd` — flat directory, rejected by path validation
- ❌ `res://scenes/new_feature.tscn` — flat directory, rejected by path validation
- ❌ `res://resources/new_config.tres` — flat directory, rejected by path validation

## Discovering Structure

Use `list_files` to see the current project layout before creating files. Check which domain directories exist and where related files already live.

Full details: `res://addons/dotagent/ARCHITECTURE.md` (Section 14)
