# triggers: 2d, node2d, platformer, game, side-scroller, top-down, sprite, player, enemy, star, coin, pickup, jump, gravity, tilemap, parallax, collision

# 2D 游戏领域知识（Node2D-based）

## 场景结构
- 根节点：`Node2D`
- 所有游戏物体（player, enemies, platforms, pickups）在 `Node2D` 下
- 渲染顺序：`z_index`（越大越靠前）。Background=-10, player=0, effects=10
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

## CanvasLayer 规则
CanvasLayer 是**渲染层容器**，唯一职责是把 UI 从 Node2D 物理世界中独立出来。一个 2D 场景对应一个 CanvasLayer。UI 场景根节点用 `Control`，表达内容身份。

## 静态场景组合优先
永久存在的 UI（HUD、暂停菜单、对话框）应该在父 .tscn 中通过 `instance=ExtResource` 静态组装，而不是在 _ready 中用 `preload().instantiate()` + `add_child()` 运行时创建。`instantiate()` 只用于运行时动态对象（子弹、掉落物、特效）。

## 常用节点
| 用途 | 节点 | 关键属性 |
|------|------|----------|
| 精灵 | `Sprite2D` | `texture`（PlaceholderTexture2D 须先设 size） |
| 动画 | `AnimatedSprite2D` | `sprite_frames`, `animation`, `play()` |
| 玩家 | `CharacterBody2D` | `velocity`, `move_and_slide()` |
| 物理物体 | `RigidBody2D` | `gravity_scale`, `linear_velocity` |
| 触发区 | `Area2D` | `body_entered`, `area_entered` 信号 |
| 碰撞 | `CollisionShape2D` | `shape`（CircleShape2D, RectangleShape2D） |
| 摄像机 | `Camera2D` | `enabled`, `limit` |
| 粒子 | `GpuParticles2D` | `material`, `amount`, `lifetime` |
| 计时器 | `Timer` | `wait_time`, `timeout` 信号, `one_shot` |

## 碰撞检查清单（CharacterBody2D）
- `CollisionShape2D` 已附加且 `shape` 已设置
- `motion_mode` 正确（FLOATING vs GROUND）
- `_physics_process(delta)` 中调用 `move_and_slide()`
- `collision_layer` 和 `collision_mask` 正确设置
- 重力已应用：`velocity.y += gravity * delta`

## Worker 工具要点
- 创建场景：`build_scene`（指定根节点类型 Node2D）
- 修改场景：`patch_scene`（结构化 patch，不直接编辑 .tscn）
- 创建脚本：`build_script`
- 验证：`inspect_scene_structured` + `check_script_syntax`
- **禁止**直接读写 .tscn/.tres 文件

## 常见错误
- PlaceholderTexture2D 不设 size → 不可见。须调用 `create_placeholder(size)`
- Control-based UI 放在 Node2D 下 → 锚点失效。须用 CanvasLayer 包裹
- 忘记 `move_and_slide()` → CharacterBody2D 不会移动
- CollisionShape2D 不设 shape → 报错
- Sprite2D `centered = false` 不设 offset → 位置错误
