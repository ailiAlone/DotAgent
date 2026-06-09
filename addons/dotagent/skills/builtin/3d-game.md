# triggers: 3d, node3d, fps, shooter, platformer-3d, terrain, mesh, material, light, camera3d, characterbody3d, rigidbody3d, csg, wasd, movement, coin, collect, area3d

# 3D Scene Template (Node3D-based)

## Root & Structure
- Root node: `Node3D`
- All game objects (player, terrain, props, lights) under `Node3D`
- Spatial coordinates: `position = Vector3(x, y, z)` — Y is UP in Godot
- Rotations: `rotation` in radians, `rotation_degrees` in degrees
- **CanvasLayer 只放 UI**（分数、血量、菜单），不要放游戏物体——CanvasLayer 无视 z_index，始终盖在 Node3D 世界之上

## Layer Separation
```
Node3D (root)
├── WorldEnvironment
├── DirectionalLight3D
├── Ground / Walls (StaticBody3D)
├── Player (CharacterBody3D)
├── Pickups / Triggers (Area3D)
└── Decor / Props (MeshInstance3D)

CanvasLayer  (separate render pass, always on top)
└── ScoreLabel / HealthBar / UI
```

## Essential Nodes
| Purpose | Node | Key |
|---------|------|-----|
| Mesh | `MeshInstance3D` | `mesh` (BoxMesh, SphereMesh, etc.) |
| Collision | `CollisionShape3D` | `shape` (BoxShape3D, SphereShape3D) |
| Player/Body | `CharacterBody3D` | `move_and_slide()`, `velocity` |
| Static geometry | `StaticBody3D` | collision_layer=1, collision_mask=0 |
| Trigger zone | `Area3D` | `body_entered` signal |
| Physics object | `RigidBody3D` | mass, gravity, forces |
| Camera | `Camera3D` | `current = true`, position |
| Light | `DirectionalLight3D` | `light_energy`, `shadow_enabled` |
| Environment | `WorldEnvironment` | `environment` (sky, fog, ambient) |
| Quick shapes | `CSGBox3D` / `CSGSphere3D` | CSG for prototyping |

## Collision Triple-Check (MANDATORY)
1. ✅ `CollisionShape3D` child exists + `shape` property set
2. ✅ `collision_layer` != 0 (which layer am I on?)
3. ✅ `collision_mask` != 0 (which layers do I detect?)

## Physics Bodies
- `CharacterBody3D`: player/enemy — manual movement with `move_and_slide()`
  - **y 轴定位**：CapsuleShape3D 默认高度 = 2（半径 0.5），所以 position.y = 1.0 时底部刚好在地面
    如果你用 height=1 的 CapsuleShape3D，position.y = 0.5
    公式：`position.y = capsule_height / 2`
- `StaticBody3D`: terrain/walls — collision_layer=1, collision_mask=0
- `Area3D`: triggers/zones — `body_entered`/`area_entered` signals
  - collision_layer=0（它不"属于"任何层）, collision_mask=1（它检测 layer 1 的物体进入）
- `RigidBody3D`: simulated physics — apply forces, gravity auto

## Input (3D) — ⚠️ 第一大坑区

### ❌ 不要用 `ui_*` 动作（编辑器会拦截）
```gdscript
# ❌ 跑场景时编辑器拦截了 ui_left/ui_right/ui_up/ui_down 快捷键
var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
```
Godot 编辑器的 3D 视口也用了 W/A/S/D 做 freelook。当你 `run_current_scene()` 时，编辑器仍然持有键盘焦点，_physics_process 收不到 `ui_*` 动作！

### ✅ 正确方案：`Input.is_key_pressed()` 直接检测
```gdscript
func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x = -1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x = 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y = -1.0    # 注意：W 是 -Y（3D 坐标的"前"）
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y = 1.0     # 注意：S 是 +Y（3D 坐标的"后"）

	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
```

### ✅ 备选方案：自定义 InputMap 动作（手动绑定）
如果非要走 InputMap，不要用 `add_input_action` 工具（事件绑定有 bug），用代码：
```gdscript
var ev = InputEventKey.new()
ev.keycode = KEY_W
InputMap.action_add_event("move_forward", ev)
```

### ⚠️ `run_scene_capture` 无法测试输入
`run_scene_capture` 是 headless 模式，**没有键盘设备**。输入相关的代码必须 `run_current_scene()` 后真人测试。`run_scene_capture` 只能验证代码不报错（编译通过 + 无运行时 crash）。

## Signals (code-based, do NOT use connect_signal tool)
Always connect signals in `_ready()` using code:

### 动态连接：Area3D 收集金币模式
```gdscript
func _ready():
	# 遍历兄弟节点，找到所有 Area3D 做触发区
	for child in $"..".get_children():
		if child is Area3D:
			# .bind(child) 把 coin 实例作为额外参数传入回调
			# 回调签名为 _on_collected(body, coin)
			child.body_entered.connect(_on_collected.bind(child))

func _on_collected(body: Node, coin: Node3D) -> void:
	if body != self:   # 先检查谁碰到触发区
		return
	score += 1
	score_label.text = "Score: " + str(score)
	# 重新随机放置金币
	coin.position = Vector3(randf_range(-15, 15), 1.0, randf_range(-15, 15))
```

### 注意 Area3D 信号参数顺序
`body_entered(body: Node)` 信号只带 body 参数。用 `.bind(child)` 把 coin 绑到第二个参数：
- 回调签名为 `_on_collected(body, coin)` — body 是信号给的，coin 是 bind 绑的
- 不要写成 `_on_collected(coin, body)` — 参数顺序是 signal_args 在前，bind_args 在后

### 静态连接：已知节点
```gdscript
func _ready():
    %Timer.timeout.connect(_on_timer)
```

## Node Duplication
When copying a node at runtime via `duplicate()`:
```gdscript
var copy = template.duplicate(8)  # 8 = DUPLICATE_GROUPS + DUPLICATE_SIGNALS
copy.name = "NewName"
copy.position = Vector3(x, y, z)
root.add_child(copy)
copy.owner = root  # ⚠️ MUST set owner for scene persistence
```

### ⚠️ 设计时节点复制（编辑器中 add_node 的坑）
当你在编辑器中复制节点时（比如 Coin1 复制出 Coin2~Coin9），**子节点不会自动复制**！
```
Coin1 (Area3D)          ← 有 Mesh + CollisionShape3D → ✅ 能碰撞
  ├── Mesh
  └── CollisionShape3D
Coin2 (Area3D)          ← 只有 Area3D，没有子节点 → ❌ 没有碰撞，穿过去
```
**修复方案**：用 `add_node` 创建完整的模板节点（含 Mesh + CollisionShape3D），设好 shape，再手工设坐标。

## Camera3D 定位
Camera3D 一般作为 Player 的子节点，跟着玩家走：
```gdscript
# 位置：玩家头顶后方 (x, y高度, z距离)
Camera3D.position = Vector3(0, 4, 6)
Camera3D.current = true   # 必须设为当前摄像机
```
- `y` 值 = 从地面到摄像机高度（玩家在 y=0.5，摄像机在 y=4 大约俯瞰）
- `z` 值 = 摄像机在玩家后方多远
- 别忘了 `current = true`，否则场景用默认摄像机（视角混乱）

## Relative Paths in @onready
Paths in `@onready` are relative to the node itself, NOT the scene root:
```
coin_collector_3d (Node3D)      ← scene root (访问 %Name 用这个)
├── Player (CharacterBody3D)    ← self (this script)
│   ├── Mesh                    ← $Mesh
│   ├── CollisionShape3D        ← $CollisionShape3D
│   └── Camera3D                ← $Camera3D
├── UILayer (CanvasLayer)       ← $"../UILayer"  (one level up from Player)
│   └── ScoreLabel              ← $"../UILayer/ScoreLabel"
└── Ground (StaticBody3D)       ← $"../Ground"  (sibling from Player)

⚠️ 经典错误：从 Player 脚本里写 $UILayer/ScoreLabel — 这是从场景根找的路径
✅ 正确写法：$"../UILayer/ScoreLabel" — 从 Player 往上到 root，再下到 UILayer
```

## Materials
- Quick color: `StandardMaterial3D` → `albedo_color`
- Textured: `StandardMaterial3D` → `albedo_texture`
- DO NOT use `Sprite3D` for 2D-in-3D unless intentional (billboard)

## Tool Checklist (验证过的工作流)
1. `create_scene("res://xxx.tscn", "Node3D")` — 创建场景
2. `add_node(".", "WorldEnvironment", "WorldEnvironment")` — 先加环境（不然全黑）
3. `add_node(".", "DirectionalLight3D", "DirectionalLight")` — 再加灯光（不然看不见）
4. `add_node(".", "StaticBody3D", "Ground")` → 加 Mesh + CollisionShape3D 子节点
5. `add_node(".", "CharacterBody3D", "Player")` → 加 Mesh + CollisionShape3D + Camera3D 子节点
6. `add_node(".", "CanvasLayer", "UILayer")` → 加 UI（与3D世界分开渲染）
7. `set_node_property("Player", "position", Vector3(0, 1, 0))` — 定位角色
8. `set_node_property("Player/Camera3D", "current", true)` — 激活摄像机
9. `set_node_property("Ground/CollisionShape3D", "shape", ...)` — 用 create_resource 创建 shape
10. `create_script("res://player.gd", content)` + 绑定脚本
11. `run_scene_capture("res://xxx.tscn")` — 验证无报错（但不能测输入）
12. `run_current_scene()` — 真人测试 WASD 移动
13. 发现问题 → `stop_running_scene()` → 修改 → 回到 11

## Common Mistakes (来自真实踩坑经验)

### 🎮 输入类
- ❌ `Input.get_vector("ui_left", ...)` 在编辑器运行时没反应 → 编辑器拦截了 `ui_*` 快捷键。**用 `Input.is_key_pressed(KEY_A)` 代替**
- ❌ `add_input_action` 工具的 `events` 参数绑定失败 → 用 `execute_gdscript` + `InputEventKey.new()` + `InputMap.action_add_event()` 手动绑定
- ❌ 用 `run_scene_capture` 验证 WASD 移动 → headless 没有键盘设备，**无法接收输入**。只能真人跑 `run_current_scene()` 测
- ❌ W/S 方向搞反 → Godot 3D 中，`W = -Z 方向`，对应 input_dir.y = -1.0；`S = +Z 方向`，对应 input_dir.y = 1.0

### 🏗️ 场景结构类
- ❌ CanvasLayer 里放游戏物体（背景、平台、敌人）→ CanvasLayer 无视 z_index，始终盖在 3D 世界之上
- ❌ 复制节点（Coin2~Coin9）只有 Area3D，没有子节点 → **没有 CollisionShape3D，走过去穿模**。每个 Area3D 都需要 Mesh + CollisionShape3D
- ❌ `@onready var label := $UILayer/ScoreLabel` 从 Player 脚本写 → **@onready 路径相对于节点自己**，不是场景根。Player 脚本里要用 `$"../UILayer/ScoreLabel"`
- ❌ CharacterBody3D 的 y 坐标设错 → 玩家飘在空中或陷进地面。CapsuleShape3D height=2 时 position.y=1.0；height=1 时 position.y=0.5

### 💥 碰撞类
- ❌ 忘记 `CollisionShape3D` → 没有碰撞，直接穿透
- ❌ `CollisionShape3D` 存在但 `shape` 没赋值 → 也是穿透！（编辑器显示黄色警告）
- ❌ `collision_mask` 设为 0 → CharacterBody3D 检测不到任何物体，掉出世界
- ❌ Area3D 用了 `collision_layer=1` 而不是 `collision_mask=1` → Area3D 应该**被检测**，不是去检测别人
  - 正确：Area3D.collision_layer=0, collision_mask=1
  - 正确：CharacterBody3D.collision_layer=1, collision_mask=1

### 📐 摄像机类
- ❌ 没设 `Camera3D.current = true` → 场景用默认视角，一片混乱
- ❌ Camera3D 放在场景根而不是 Player 子节点 → 摄像机不跟玩家走，玩家跑出视野
- ❌ Camera3D 位置太近（如 y=1）→ 视角贴地，看不到前方

### 🔧 工具使用类
- ❌ `execute_gdscript` 改属性（位置、颜色、文本）→ **重启就丢**，用 `set_node_property`
- ❌ `connect_signal` 工具 → 已被移除。一律在 `_ready()` 里写 `.connect()`
- ❌ 用 `execute_gdscript` 手写 .tscn → 6 轮低效操作。用 `create_scene` + `add_node`
- ❌ 直接用 `update_script` 改大文件的少量内容 → 15KB+ 的文件用 `replace_in_file`（只传要改的部分）

### 🐞 GDScript 语法类
- ❌ `:=` on const dictionary returns → compile error, use `=`
- ❌ 拼错变量名（如 `emoj_label` 写成 `emoji_label`）→ Godot 4 编译直接失败，错误信息不友好。写完立刻 `check_script_syntax`
- ❌ `execute_gdscript` 里用 `func` 定义工具函数 → snippet 执行环境不允许内嵌函数定义。用变量+内联代码代替