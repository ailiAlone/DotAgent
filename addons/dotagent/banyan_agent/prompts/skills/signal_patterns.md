# triggers: signal, connect, disconnect, pressed, timeout, body_entered, area_entered, button, callback, event, _on_, bind, emit, signal_bus, autoload

# 信号模式 — 连接、断开与发射

## 核心规则
**所有信号连接都通过代码完成。** 在脚本中用 `.connect()` / `.disconnect()` 实现。没有专门的信号连接工具。

## 静态连接（_ready）
最常见的模式 — 启动时连接 UI 和游戏信号：
```gdscript
func _ready():
    %StartButton.pressed.connect(_on_start_pressed)
    $Timer.timeout.connect(_on_timeout)
    $Area2D.body_entered.connect(_on_body_entered)
```

## 动态连接（运行时创建的节点）
创建节点后立即连接：
```gdscript
var btn := Button.new()
btn.pressed.connect(_on_dynamic_click)
add_child(btn)
```

## 临时绑定（连接后断开）
一次性或条件性信号处理：
```gdscript
func _on_area_entered(body):
    body.damaged.connect(_on_enemy_hit)   # 临时绑定

func _on_enemy_hit(amount):
    # 处理伤害
    if sender is Node and sender.damaged.is_connected(_on_enemy_hit):
        sender.damaged.disconnect(_on_enemy_hit)
```

## 绑定额外数据
用 `.bind()` 传递额外参数给回调：
```gdscript
for star in stars:
    star.body_entered.connect(_on_star_collected.bind(star))
```

## 发射自定义信号
```gdscript
signal health_changed(new_health: int)

func take_damage(amount: int):
    health -= amount
    health_changed.emit(health)
```

## 信号总线模式（全局通信）
对于跨模块通信，使用信号总线（autoload 单例）：
```gdscript
# signal_bus.gd — 注册为 Autoload
extends Node

signal player_died
signal score_changed(new_score: int)
signal level_completed(level_id: String)
signal game_paused(is_paused: bool)
```

使用方式：
```gdscript
# 发射方
SignalBus.score_changed.emit(new_score)

# 接收方
func _ready():
    SignalBus.score_changed.connect(_on_score_changed)
```

### 信号总线规则
- 信号总线只定义信号，不包含逻辑
- 模块间不直接引用，通过信号总线解耦
- Banyan 的 `configure_project` 工具可注册 autoload
- 信号命名用过去式（表示已发生的事）：`score_changed` 而非 `change_score`

## Banyan 合约验证中的信号
Branch 的 `define_contract` 工具定义模块间预期的 signals 和 methods。
Worker 完成后通过 `save_knowledge(category="interface")` 保存实际暴露的信号。
Branch 通过 `validate_contracts` 对比预期与实际，检测接口不一致。

## Worker 工具要点
- 信号连接通过 `update_script` 或 `build_script` 写入代码
- 验证连接：`read_script` 检查 .connect() 调用
- 语法检查：`check_script_syntax` 确认回调方法存在
- 信号总线注册：`configure_project`（添加 autoload）

## 工作流检查清单
1. `read_script` — 找到插入位置（通常是 `_ready()` 或事件回调）
2. `update_script` / `replace_in_file` — 插入 `.connect()` 行
3. `check_script_syntax` — 验证编译通过
4. `run_scene_capture` — 测试连接是否工作

## 常见错误
- 忘记先创建回调方法 → `check_script_syntax` 可捕获
- 在 `_process()` 中连接信号 → 每帧创建重复连接
- 不断开临时绑定 → 回调多次触发
- `node.signal_name.connect` 连不存在的信号 → 先用 `extract_script_interface` 检查
- 信号参数顺序搞反 → signal_args 在前，bind_args 在后
