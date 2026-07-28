# triggers: 3d, node3d, fps, shooter, platformer-3d, terrain, mesh, material, light, camera3d, characterbody3d, rigidbody3d, csg, wasd, movement, coin, collect, area3d

# 3D 游戏领域知识（Node3D-based）

## 场景结构
- 根节点：`Node3D`
- 空间坐标：`position = Vector3(x, y, z)` — Y 轴朝上
- 旋转：`rotation`（弧度），`rotation_degrees`（角度）
- CanvasLayer 只放 UI（分数、血量、菜单），不放游戏物体

## 层级分离
```
Node3D (根)
├── WorldEnvironment
├── DirectionalLight3D
├── Ground / Walls (StaticBody3D)
├── Player (CharacterBody3D)
├── Pickups / Triggers (Area3D)
└── Decor / Props (MeshInstance3D)

CanvasLayer (独立渲染层，始终在最前)
└── ScoreLabel / HealthBar / UI
```

## 常用节点
| 用途 | 节点 | 关键属性 |
|------|------|----------|
| 网格 | `MeshInstance3D` | `mesh`（BoxMesh, SphereMesh 等） |
| 碰撞 | `CollisionShape3D` | `shape`（BoxShape3D, SphereShape3D） |
| 玩家/角色 | `CharacterBody3D` | `move_and_slide()`, `velocity` |
| 静态几何 | `StaticBody3D` | collision_layer=1, collision_mask=0 |
| 触发区 | `Area3D` | `body_entered` 信号 |
| 物理物体 | `RigidBody3D` | mass, gravity, forces |
| 摄像机 | `Camera3D` | `current = true`, position |
| 灯光 | `DirectionalLight3D` | `light_energy`, `shadow_enabled` |
| 环境 | `WorldEnvironment` | `environment`（sky, fog, ambient） |
| 快速原型 | `CSGBox3D` / `CSGSphere3D` | CSG 原型建模 |

## 碰撞三重检查（必须）
1. `CollisionShape3D` 子节点存在且 `shape` 属性已设置
2. `collision_layer` != 0（我在哪个层？）
3. `collision_mask` != 0（我检测哪些层？）

## 物理体规则
- `CharacterBody3D`：玩家/敌人 — 手动 `move_and_slide()`
  - y 轴定位：CapsuleShape3D 默认高度=2（半径0.5），position.y=1.0 时底部在地面
  - 公式：`position.y = capsule_height / 2`
- `StaticBody3D`：地形/墙壁 — collision_layer=1, collision_mask=0
- `Area3D`：触发区 — collision_layer=0, collision_mask=1
- `RigidBody3D`：模拟物理 — 施加力，自动重力

## 输入处理（第一大坑区）

### 不要用 `ui_*` 动作
编辑器 3D 视口也用 W/A/S/D 做 freelook，运行场景时编辑器拦截 `ui_*` 快捷键。

### 正确方案：`Input.is_key_pressed()` 直接检测
```gdscript
func _physics_process(delta: float) -> void:
    var input_dir := Vector2.ZERO
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        input_dir.x = -1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        input_dir.x = 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        input_dir.y = -1.0    # W = -Z 方向
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        input_dir.y = 1.0     # S = +Z 方向

    var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
    velocity.x = direction.x * speed
    velocity.z = direction.z * speed
    move_and_slide()
```

### 备选：自定义 InputMap 动作
```gdscript
var ev = InputEventKey.new()
ev.keycode = KEY_W
InputMap.action_add_event("move_forward", ev)
```

### run_scene_capture 无法测试输入
headless 模式没有键盘设备，输入相关代码须真人测试。`run_scene_capture` 只能验证编译通过和无运行时 crash。

## 信号连接（代码方式）
一律在 `_ready()` 中用代码连接，不使用 connect_signal 工具：
```gdscript
func _ready():
    for child in $"..".get_children():
        if child is Area3D:
            child.body_entered.connect(_on_collected.bind(child))

func _on_collected(body: Node, coin: Node3D) -> void:
    if body != self:
        return
    # 处理收集逻辑
```

注意 Area3D 信号参数顺序：`body_entered(body)` 信号只带 body，`.bind(child)` 把 coin 绑到第二参数。

## Camera3D 定位
Camera3D 一般作为 Player 子节点：
```gdscript
Camera3D.position = Vector3(0, 4, 6)   # 头顶后方
Camera3D.current = true                  # 必须设为当前
```

## @onready 路径是相对于节点自身
```
scene_root (Node3D)
├── Player (脚本所在)    ← self
│   ├── Mesh             ← $Mesh
│   └── Camera3D         ← $Camera3D
├── UILayer (CanvasLayer) ← $"../UILayer"
│   └── ScoreLabel        ← $"../UILayer/ScoreLabel"
```

## Worker 工具要点
- 创建场景：`build_scene`（根节点 Node3D）
- 先加 WorldEnvironment + DirectionalLight3D（否则全黑/看不见）
- 修改场景：`patch_scene`
- 验证：`inspect_scene_structured` + `check_script_syntax` + `run_scene_capture`

## 常见错误
- `Input.get_vector("ui_left", ...)` 编辑器运行时没反应 → 用 `is_key_pressed(KEY_A)`
- CanvasLayer 放游戏物体 → 始终盖在 3D 世界上方
- 复制节点缺少子节点（CollisionShape3D）→ 穿模
- @onready 路径从场景根写 → 应从节点自身算起
- CharacterBody3D y 坐标错误 → 飘在空中或陷进地面
- 没设 `Camera3D.current = true` → 默认视角混乱
- `execute_gdscript` 改属性不持久化 → 用 `patch_scene`
