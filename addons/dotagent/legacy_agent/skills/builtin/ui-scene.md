# triggers: ui, control, panel, button, label, menu, settings, hud, interface, widget, dialog, form

# UI Scene Template (Control-based)

## Root & Structure
- Root node: `Control` (or `Panel`, `MarginContainer`, `VBoxContainer`)
- All children inherit Control — no Node2D/Node3D in UI scenes
- Layout: use anchors (`layout_mode = 1`), NOT position/size pixel values
- Containers: `VBoxContainer`, `HBoxContainer`, `MarginContainer`, `GridContainer`

## Common Controls
| Purpose | Node | Key Property |
|---------|------|-------------|
| Text | `Label` | `text` |
| Button | `Button` | `text`, `pressed` signal |
| Input | `LineEdit` | `text`, `placeholder_text` |
| Checkbox | `CheckBox` | `button_pressed`, `toggled` signal |
| Slider | `HSlider` / `VSlider` | `value`, `min_value`, `max_value` |
| Image | `TextureRect` | `texture`, `expand_mode` |
| Background | `ColorRect` | `color`, anchors full-screen |
| Scroll | `ScrollContainer` | child inside scrolls |

## Styling & Colors
- Background: `ColorRect` with anchors (0,0,1,1) + `color`
- Text color: `add_theme_color_override("font_color", Color(...))` ✅
- DO NOT: `theme_override_colors["font_color"] = Color(...)` ❌ (read-only)
- Font size: `add_theme_font_size_override("font_size", 24)`
- Rounded panels: `StyleBoxFlat` + `corner_radius` → `add_theme_stylebox_override("panel", style)`

## Signals (code-based, in script)
```gdscript
func _ready():
    %Button.pressed.connect(_on_click)
    %Slider.value_changed.connect(_on_value_changed)
    %CheckBox.toggled.connect(_on_toggled)
    %LineEdit.text_changed.connect(_on_text_changed)
```

## Tool Checklist
- `create_scene(path, "Control")` — start here
- `add_node(parent, "Button", name, true)` — unique_name=true for % access
- `set_node_property(path, "text", value)` — change properties (persisted)
- DO NOT use `execute_gdscript` to set node properties — not persisted

## Common Mistakes
- Setting `position`/`size` instead of `anchors_preset` — UI doesn't use pixel positions
- Using `Node2D` as root for UI — use `Control`
- `theme_override_colors["key"] = val` — use `add_theme_color_override`
- `:=` on const dictionary returns — use `=`
