# triggers: 2d, node2d, platformer, game, side-scroller, top-down, sprite, player, enemy, star, coin, pickup, jump, gravity, tilemap, parallax, collision

# 2D Scene Template (Node2D-based)

## Root & Structure
- Root node: `Node2D`
- All game objects (player, enemies, platforms, pickups) under `Node2D`
- Rendering order: `z_index` (higher = front). Background z_index = -10, player = 0, effects = 10
- **CanvasLayer is ONLY for UI overlays** (score, health bar, pause menu) — NEVER for game objects

## Layer Separation
```
Node2D (root)
├── Background (Sprite2D/ColorRect, z_index = -10)
├── Platforms (StaticBody2D, z_index = 0)
├── Player (CharacterBody2D, z_index = 1)
├── Pickups (Area2D, z_index = 0)
└── Effects (z_index = 10)

CanvasLayer
└── UI (Label, Button, etc.) — always on top, ignores z_index
```

## 2D-Specific Nodes
| Purpose | Node | Key |
|---------|------|-----|
| Sprite | `Sprite2D` | `texture` (or `PlaceholderTexture2D`: SET SIZE FIRST) |
| Animated | `AnimatedSprite2D` | `sprite_frames`, `play("idle")` |
| Player/Body | `CharacterBody2D` | `move_and_slide()`, `velocity` |
| Platform/Wall | `StaticBody2D` | collision_layer = 1, collision_mask = 0 |
| Pickup/Trigger | `Area2D` | `body_entered` signal |
| Camera | `Camera2D` | `enabled = true`, `make_current()` |
| Background color | `ColorRect` | position + size (NOT anchors) |

## Collision Triple-Check (MANDATORY after creating physics nodes)
1. ✅ `CollisionShape2D` child exists + `shape` property set (RectangleShape2D/CircleShape2D)
2. ✅ `collision_layer` != 0 (which layer am I on?)
3. ✅ `collision_mask` != 0 (which layers do I detect?)

CharacterBody2D / Area2D failing? Verify all 3. Use `get_node_properties` to check.

## Physics Bodies Quick Reference
- `CharacterBody2D`: player/enemy — uses `move_and_slide()`, has velocity
- `StaticBody2D`: platforms/walls — doesn't move, collision_layer set, collision_mask=0
- `Area2D`: triggers/pickups — `body_entered`/`area_entered` signals
- `RigidBody2D`: physics-simulated — gravity, forces, bouncing

## Input (2D)
```gdscript
func _physics_process(delta):
    var direction := Input.get_axis("ui_left", "ui_right")
    velocity.x = direction * SPEED
    move_and_slide()
```
Actions must exist in Input Map. Use `get_input_actions` to check, `add_input_action` to add.

## Signals (code-based)
```gdscript
func _ready():
    $Area2D.body_entered.connect(_on_pickup)
    $Timer.timeout.connect(_on_timer)

# Dynamic (runtime-created nodes)
var star := Area2D.new()
star.body_entered.connect(_on_star_collected)

# Disconnect to prevent duplicate triggers
(sender as Node).signal_name.disconnect(_callback)
```

## Tool Checklist
- `create_scene(path, "Node2D")` — start here
- `set_node_property(path, "z_index", -10)` — layer ordering
- `set_node_property(path, "collision_layer", 1)` / `collision_mask` — MUST set
- DO NOT use `execute_gdscript` for properties — use `set_node_property` (persisted)
- `get_node_properties(path)` — verify collision layer/mask after setting

## Common Mistakes
- CanvasLayer for background/game objects → background covers everything
- Missing any of collision triple-check → player falls through floor
- `execute_gdscript` for collision_layer → lost on editor restart
- `PlaceholderTexture2D` without `size` → invisible sprite
- `:=` on const dictionary returns → compile error, use `=`
