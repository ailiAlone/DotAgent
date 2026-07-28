# triggers: 2d, node2d, platformer, game, side-scroller, top-down, sprite, player, enemy, star, coin, pickup, jump, gravity, tilemap, parallax, collision

# 2D Scene Template (Node2D-based)

## Root & Structure
- Root node: `Node2D`
- All game objects (player, enemies, platforms, pickups) under `Node2D`
- Rendering order: `z_index` (higher = front). Background z_index = -10, player = 0, effects = 10
- CanvasLayer 永远不要放游戏物体

## 层级分离
```
Node2D (根)
├── Background (Sprite2D/ColorRect, z_index = -10)
├── Platforms (StaticBody2D, z_index = 0)
├── Player (CharacterBody2D, z_index = 1)
├── Pickups (Area2D, z_index = 0)
└── Effects (z_index = 10)

UI (CanvasLayer, layer=10)          ← 一个 CanvasLayer 承载全部 UI
├── HUD (Control)                   ← 实例化 hud.tscn
├── PauseMenu (Control)             ← 实例化 pause_menu.tscn
└── ...                             ← 更多 UI 场景
```

## CanvasLayer — 渲染层容器，不是 UI 组件

CanvasLayer 是一个**渲染层容器**，唯一职责是把 UI 从 Node2D 物理世界中独立出来——让 UI 不受 2D transform、缩放、视口偏移影响。它回答的是"在哪个渲染层"的问题，不是"UI 长什么样"的问题。

**一个 2D 场景对应一个 CanvasLayer**：所有 UI 共享同一个 CanvasLayer 作为渲染层。多个 CanvasLayer 意味着需要手动协调 layer 值避免渲染错乱，且一个 2D 场景只需要一个独立的 UI 渲染层。这个关系是 1:1 的。

## UI 场景根节点用 Control，表达内容身份

UI .tscn 描述的是 **UI 内容**（布局、文字、按钮、信号连接），不是渲染方式。CanvasLayer 属于父场景的结构性组件，不属于 UI 自身。

**Control 做根节点实现复用**：
- UI 场景可跨场景组合——同样的 HUD.tscn 既可挂在 Game 的 CanvasLayer 下，也可挂在 Menu 场景的 Panel 内
- 父场景只有一个 CanvasLayer，所有 UI 场景都是它的子 Control，节点树扁平
- 场景描述的是"这个 UI 是什么"（内容身份），而非"它挂在哪"（容器身份）

## 静态场景组合优先于运行时装配

Godot 的 .tscn 系统本身就是声明式场景组合引擎。永久存在的 UI（HUD、暂停菜单、对话框）应该在父 .tscn 中通过 `instance=ExtResource` 静态组装，而不是在 _ready 中用 `preload().instantiate()` + `add_child()` 运行时创建。

```
# game.tscn — 静态声明
[ext_resource type="PackedScene" path="res://scenes/hud.tscn" id="1_hd"]
[node name="HUD" parent="UI" instance=ExtResource("1_hd")]

# game.gd — 静态引用
@onready var hud: Control = %HUD
```

**静态的优势是结构性的**：编辑器可见可调、@onready 在 _ready 前自动完成引用、无时序耦合、父场景打开就能看到完整 UI 布局。`instantiate()` 只用于运行时产生的动态对象（子弹、掉落物、特效实例），因为这些对象的生命周期与场景树无关，且不存在持久的结构定义。

## 2D-Specific Nodes
| Purpose | Node | Key |
|---------|------|-----|
| Sprite | `Sprite2D` | `texture` (or `PlaceholderTexture2D`: SET SIZE FIRST) |
| Animated | `AnimatedSprite2D` | `sprite_frames`, `animation`, `play()` |
| Player | `CharacterBody2D` | `velocity`, `move_and_slide()` |
| Enemy/Obj | `RigidBody2D` | `gravity_scale`, `linear_velocity` |
| Trigger | `Area2D` | `body_entered`, `area_entered` signals |
| Collision | `CollisionShape2D` | `shape` (CircleShape2D, RectangleShape2D) |
| Camera | `Camera2D` | `enabled`, `limit` (for scrolling) |
| Particles | `GpuParticles2D` | `material`, `amount`, `lifetime` |
| Timer | `Timer` | `wait_time`, `timeout` signal, `one_shot` |
| UI Text | `Label` | `text`, `theme_override_colors/font_color` |

## 2D Collision Checklist (CharacterBody2D)
- ✅ `CollisionShape2D` attached with a `shape` (Circle/Rectangle)
- ✅ `motion_mode` (FLOATING vs GROUND)
- ✅ `move_and_slide()` in `_physics_process(delta)`
- ✅ `collision_layer` and `collision_mask` set properly
- ✅ Gravity applied: `velocity.y += gravity * delta`

## Common Mistakes
- ❌ PlaceholderTexture2D without size → invisible. Fix: CALL `create_placeholder(size)` first
- ❌ Control-based UI scenes under Node2D → anchor failure. Fix: wrap in CanvasLayer
- ❌ Forgetting `move_and_slide()` → CharacterBody2D won't move
- ❌ CollisionShape2D without shape → error
- ❌ Sprite2D with `centered = false` but no offset → wrong position
