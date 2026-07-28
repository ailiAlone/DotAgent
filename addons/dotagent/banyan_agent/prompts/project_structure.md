# Project File Structure

This project uses **domain-based organization** (Godot style), NOT type-based organization (Unity style).

## The Rule

Each domain has its own directory. All files for that domain live together:

```
res://
├── player/              player.gd + player.tscn + player_theme.tres + sprites
├── enemies/             enemy scripts + scenes + configs
├── ui/                  UI scripts + scenes (subdirs per screen)
│   ├── hud/
│   └── settings/
├── core/                autoloads, managers
├── assets/              shared assets (audio, fonts, textures)
└── project.godot
```

## When Creating Files

Put new files in the correct domain directory:

| File type | Where it goes |
|-----------|---------------|
| Player script | `res://player/player_xxx.gd` |
| Player scene | `res://player/player_xxx.tscn` |
| Enemy config | `res://enemies/enemy_xxx.tres` |
| UI screen | `res://ui/screen_name/screen_name.gd` + `.tscn` |
| Shared asset | `res://assets/type/asset_name.ext` |

## What NOT to Do

Don't put all scripts in `scripts/`, all scenes in `scenes/`, all resources in `resources/`. That's Unity style. It separates related files and makes the project hard to navigate.

## Reading This File

If you're unsure about where to create a file, use `read_script` to read `res://project.godot` and `list_files` to understand the current structure, then place your file in the matching domain directory.

Full details: `res://addons/dotagent/ARCHITECTURE.md` (Section 14)
