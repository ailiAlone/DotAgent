# DotAgent Cortex 架构设计文档
# DotAgent Cortex Architecture Design Document

**版本**: 1.0  
**日期**: 2026-06-15  
**状态**: 设计冻结（Design Freeze）  

---

## 1. 设计目标（Design Goals）

DotAgent Cortex 是一个运行在 Godot 编辑器内部的**层级化多智能体插件**。它通过将传统"单中心 LLM + 扁平工具集"架构重构为**树状神经节点拓扑**，实现以下目标：

- **支持正常规模游戏开发**（如 Hollow Knight 级别），而非仅小游戏原型
- **极小化单节点上下文需求**：每个 Worker 只持有其职责范围内的知识与工具
- **注意力高度聚焦**：通过物理隔离的上下文（messages 数组）防止知识域互相干扰
- **动态按需生长**：节点在开发过程中自行发现复杂子任务并申请创建子节点
- **父节点授权自治**：Branch 节点获得任务后自行调度子节点，无需逐轮请示 Root
- **LLM 请求原子不可中断**：正常状态（思考中、交谈中、工具调用中）的 Slot 不可被清理

---

## 2. 核心哲学（Core Philosophy）

### 2.1 不是 Godot 节点，是脑神经节点

每个节点不是编辑器场景树中的 `Node` 对象，而是**内存中独立的 LLM 上下文会话**：

- 独立的 `messages` 历史数组
- 独立的 `system_prompt`（`.md` 文件加载）
- 独立的工具子集（`.json` 定义）
- 独立的知识域（KnowledgeBase 查询）

### 2.2 信息隔离三原则

1. **每个节点只对自己和直属上下节点负责**
2. **每个节点只能获取：自己的信息 + 上级下达的任务 + 下级反馈的汇报**
3. **同级节点不可直接通信**，跨模块需求通过 Parent 中转

### 2.3 从"全能大脑"到"分工皮层"

| 维度 | 传统 DotAgent（星型） | DotAgent Cortex（树状） |
|------|----------------------|------------------------|
| 拓扑 | 单中心 LLM + 58 工具辐射 | Root → Branch → Worker 层级委托 |
| 上下文 | 10K+ tokens（全项目 + 全工具） | Worker 层 2K- tokens（模块知识 + 8 工具） |
| 注意力 | 同时处理 UI/物理/音频/存档 | 一次只处理 Player 移动或 Enemy 射击 |
| 错误范围 | 一次幻觉可能破坏整个场景树 | 错误只影响当前 Worker 的模块 |
| 复杂度天花板 | O(n²) 上下文爆炸 | O(n) 层级分解 |

---

## 3. 系统概览（System Overview）

### 3.1 高层架构

```
[User Input]
    │
    ▼
┌──────────────────────────────────────┐
│  Root Coordinator                    │
│  - 需求翻译 / 任务分解 / 遍历决策      │
│  - 不持有工具，不操作文件              │
└──────────────────────────────────────┘
    │
    ├─────────────────┬─────────────────┐
    ▼                 ▼                 ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ Gameplay │   │   UI     │   │  Audio   │
│  Branch  │   │  Branch  │   │  Branch  │
│(LLM ctx) │   │(LLM ctx) │   │(LLM ctx) │
└──────────┘   └──────────┘   └──────────┘
    │
    ├──────────┬──────────┐
    ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐
│ Player │ │ Enemy  │ │ Weapon │
│ Worker │ │ Worker │ │ Worker │
│(LLM    │ │(LLM    │ │(LLM    │
│ ctx)   │ │ ctx)   │ │ ctx)   │
└────────┘ └────────┘ └────────┘
```

### 3.2 数据流

```
User → Root: "做一个完整的 2D 银河恶魔城"
Root → Root: 分析 → 决定 SKELETON_FIRST
Root → Gameplay Branch: TaskTicket {type: skeleton, scope: Gameplay, modules: [Player,Enemy,Weapon,Level]}
Root → UI Branch: TaskTicket {type: skeleton, scope: UI, modules: [HUD,Menu,Dialogue]}
Root → Audio Branch: TaskTicket {type: skeleton, scope: Audio, modules: [BGM,SFX,Ambient]}

Gameplay Branch → Player Worker: TaskTicket {type: skeleton, module: Player, deliverable: interface_only}
Player Worker → LLM (via Slot): 生成 Player 接口定义（信号 + 空方法）
Player Worker → Gameplay Branch: WorkerReport {status: COMPLETED, files: [player.tscn, player.gd], interfaces: [signals, methods]}
Gameplay Branch: 收集 Player + Enemy + Weapon 接口 → 确认一致性 → 锁定契约

Gameplay Branch → Player Worker: TaskTicket {type: implement, module: Player, feature: Movement}
Player Worker → LLM (via Slot): 填充 Movement 逻辑 → 工具调用 → 验证
Player Worker → Gameplay Branch: WorkerReport {status: COMPLETED, knowledge: [...]}

...（逐个 Worker 深度填充）...

Root → Integration Worker: TaskTicket {type: integration, scope: global}
Integration Worker → 运行完整场景 → 验证 → 返回
Root → User: "项目骨架已完成，Player Movement 已实现，Enemy AI 开发中..."
```

---

## 4. 节点层级（Node Hierarchy）

### 4.1 Root Coordinator（根协调器）

**唯一，始终驻留**

- **职责**：
  - 接收用户自然语言输入，翻译为结构化需求
  - 根据任务类型决定遍历策略（SKELETON_FIRST / DEPTH_FIRST）
  - 创建 Branch 节点，分配任务工单
  - 审核 Branch 交付物，决定下一步
  - 处理知识库冲突（最终仲裁）
  - 向用户汇报全局进度

- **持有数据**：
  - 项目高层架构摘要（模块列表 + 依赖关系）
  - 各 Branch 的接口契约汇总
  - 遍历策略 skill（`.md`）

- **不可见**：
  - 任何直接操作文件、场景、脚本、节点的工具
  - 具体代码内容
  - 具体场景树结构

### 4.2 Branch Node（分支节点）

**按子系统划分，如 Gameplay、UI、Audio、Level、Save**

- **职责**：
  - 接收 Root 的任务工单，进一步分解或自行执行
  - 创建和管理 Worker 节点
  - 协调子节点间的接口契约（收集 → 确认 → 锁定）
  - 处理 Worker 的 BLOCKED / EXPAND / FAILED 状态
  - 审核 Worker 交付物，合并知识条目到全局知识库
  - 调度任务队列（决定下一个激活哪个 Worker）

- **持有数据**：
  - 本子系统的领域知识（`.md` skill）
  - 子节点列表及当前状态
  - 任务队列（`task_queue`）和休眠队列（`blocked_queue`）
  - 已锁定的接口契约

- **不可见**：
  - 其他 Branch 的内部工具
  - Root 层的分支管理工具
  - 具体 Godot 编辑器操作工具（由 Worker 持有）

### 4.3 Worker Node（工作节点）

**按模块划分，如 Player、EnemySpawner、HUD、AudioManager**

- **职责**：
  - 接收 Parent 的任务工单，执行具体开发任务
  - 调用工具操作 Godot 编辑器（创建场景、写脚本、设置属性、运行验证）
  - 在开发过程中发现子任务过于复杂时，向 Parent 申请创建子 Worker
  - 完成后向 Parent 提交 WorkerReport（交付物 + 知识条目）

- **持有数据**：
  - 自己负责模块的完整知识（如 Player 的移动、射击、受伤逻辑）
  - 自己的 `messages` 历史（独立上下文）
  - 自己的工具子集（5-8 个工具，不是 58 个）
  - 上级任务工单

- **可见工具示例（Player Worker）**：
  - `create_scene` / `add_node` / `set_node_property`
  - `update_script` / `replace_in_file` / `check_script_syntax`
  - `run_scene_capture` / `screenshot_editor`
  - `report_to_parent`

---

## 5. 核心模块（Core Modules）

### 5.1 HTTPClientPool（HTTP 连接池）

```gdscript
# res://addons/dotagent_cortex/http/http_client_pool.gd
class_name HTTPClientPool extends RefCounted

var slots: Array[RequestSlot] = []
var max_slots: int = 1  # 串行=1，并行可扩展为 N

func _init(pool_size: int = 1):
    max_slots = pool_size
    for i in range(pool_size):
        slots.append(RequestSlot.new(i))

func acquire_slot(worker_id: String) -> RequestSlot:
    for slot in slots:
        if slot.is_idle():
            slot.claim(worker_id)
            return slot
    return null

func release_slot(slot: RequestSlot):
    slot.reset()
```

**设计要点**：
- 串行模式下 `pool_size = 1`，只有一个 Slot 被激活
- 并行扩展时改配置为 N，调度器逻辑不变
- 每个 Slot 包装独立的 `HTTPClient` + SSE 解析状态 + Watchdog 计时器

### 5.2 RequestSlot（请求槽）

```gdscript
# res://addons/dotagent_cortex/http/request_slot.gd
class_name RequestSlot extends RefCounted

enum State {
    IDLE,           # 空闲
    CONNECTING,     # 连接中
    SENDING,        # 发送请求中
    STREAMING,      # 接收 SSE 流中（原子状态，不可中断）
    TOOL_EXEC,      # 工具执行中（原子状态，不可中断）
    COMPLETED,      # 请求完成
    FAILED,         # 错误（连接失败、解析错误、超时）
    FROZEN          # 冻结（保留，未来扩展）
}

var state: State = State.IDLE
var worker_id: String = ""
var client: HTTPClient
var sse_buffer: String = ""
var accumulated_content: String = ""
var accumulated_tool_calls: Array = []
var watchdog_timer: float = 0.0
var request_start_time: int = 0
```

**原子状态规则**：
- `STREAMING` 和 `TOOL_EXEC` 为原子状态，不可被 BLOCKED 或清理
- 只有 `IDLE` 和 `FAILED` 状态的 Slot 可以被重新分配
- 正常状态（思考中、交谈中、工具调用中）不可被清理；错误状态必须被清理

### 5.3 NodeScheduler（节点调度器）

```gdscript
# res://addons/dotagent_cortex/core/node_scheduler.gd
class_name NodeScheduler extends RefCounted

var root: RootCoordinator
var active_pool: HTTPClientPool
var task_queue: Array[TaskTicket] = []
var blocked_workers: Array[BlockedWorker] = []

func schedule_next() -> WorkerNode:
    # 1. 检查任务队列
    if not task_queue.is_empty():
        return _activate_worker(task_queue.pop_front())
    # 2. 检查是否有依赖已满足的休眠 Worker
    var awakened := _check_blocked_dependencies()
    if awakened != null:
        return _restore_worker(awakened)
    # 3. 无可执行任务，返回 null
    return null
```

**调度策略**：
- 串行模式下，同一时刻只有一个 Worker 在激活推理
- 任务队列按优先级排序：BLOCKED_DEPENDENCY > NORMAL > BACKGROUND
- Worker 休眠时，其完整 state + messages 序列化到磁盘，释放 Slot
- 依赖满足后，从磁盘恢复 context，重新申请 Slot 继续工作

### 5.4 WorkerExecutor（工作执行器）

封装单个 Worker 的完整生命周期：
- 加载任务工单
- 加载/构建 system prompt（`.md` + 动态上下文）
- 加载工具定义（`.json` 子集）
- 申请 Slot → 发送 LLM 请求 → 处理响应 → 执行工具 → 循环
- 完成后生成 WorkerReport
- 如被 BLOCKED，保存 context 到磁盘，释放 Slot

### 5.5 KnowledgeBase（知识库）

```gdscript
# res://addons/dotagent_cortex/knowledge/knowledge_base.gd
class_name KnowledgeBase extends RefCounted

const KNOWLEDGE_ROOT := "res://dotagent_cortex/knowledge/"

func add_entry(entry: KnowledgeEntry) -> void:
    # 审核、去重、冲突检测
    pass

func query(filter: KnowledgeFilter) -> Array[KnowledgeEntry]:
    # 按模块、类型、标签查询
    pass

func detect_conflict(new_entry: KnowledgeEntry) -> Array[KnowledgeEntry]:
    # 返回与 new_entry 冲突的已有条目
    pass
```

### 5.6 SignalBusManager（信号总线管理器）

负责生成和维护全局 `SignalBus.gd`（autoload）：
- 收集所有 Branch 声明的跨模块信号
- 生成/更新 `SignalBus.gd` 文件
- 确保信号声明格式正确：`signal GameStart()` / `signal GameOver(score: int)`
- 禁止在模块内直接声明跨模块信号

---

## 6. 通信协议（Communication Protocol）

### 6.1 下行：Task Ticket（任务工单）

```json
{
  "ticket_id": "T-20260615-001",
  "type": "skeleton | implement | integrate | refactor",
  "scope": "Player",
  "parent_branch": "Gameplay",
  "priority": "critical | high | normal | low",
  "requirements": [
    "WASD 移动，速度 420",
    "Space/J 射击，Shift 散射",
    "L 键 Dash，0.15s 冲刺，0.8s 冷却"
  ],
  "constraints": [
    "必须 extends Area2D",
    "必须连接 died/shoot/hit 信号",
    "零外部资源，程序化生成"
  ],
  "interfaces_expected": [
    {"signal": "died", "params": []},
    {"signal": "shoot", "params": ["bullet_path", "position", "direction"]},
    {"method": "take_damage", "params": ["amount: int"], "returns": "void"}
  ],
  "deliverables": ["scene", "script", "tests"],
  "deadline_rounds": null,
  "metadata": {
    "game_type": "metroidvania",
    "target_complexity": "hollow_knight_level"
  }
}
```

### 6.2 上行：Worker Report（工作汇报）

```json
{
  "ticket_id": "T-20260615-001",
  "worker_id": "Worker:Player:001",
  "status": "COMPLETED | BLOCKED | EXPAND | FAILED",
  "summary": "Player 模块已创建：包含 Movement、Shooting、Dash、Weapon Level 系统",
  "files": [
    "res://scenes/player.tscn",
    "res://scripts/player.gd"
  ],
  "interfaces_actual": [
    {"signal": "died", "params": []},
    {"signal": "shoot", "params": ["bullet_path", "position", "direction"]}
  ],
  "dependencies": [
    {"module": "Audio", "need": "dash_sfx 信号", "urgency": "high"}
  ],
  "block_reason": {
    "type": "dependency_missing",
    "missing_module": "Enemy",
    "missing_interface": "signal enemy_died(score, position)",
    "can_wait": true
  },
  "expand_request": {
    "sub_module": "PlayerTrail",
    "reason": "拖尾系统需要独立粒子管理，超出 Player Worker 当前范围",
    "estimated_scope": "small"
  },
  "knowledge_report": [
    {
      "type": "technical_decision",
      "scope": "Player.Movement",
      "content": "使用 Area2D 而非 CharacterBody2D，因为不需要物理引擎自动响应",
      "confidence": "high"
    }
  ],
  "next_tasks": ["Player Trail 特效", "Weapon Level HUD 显示"]
}
```

### 6.3 阻塞与唤醒协议

当 Worker 状态为 `BLOCKED`：

1. Worker 保存当前完整 context 到磁盘：`dotagent_cortex/nodes/{worker_id}_context.json`
2. Parent 将 Worker 移入 `blocked_queue`，标记 `blocking_dependencies`
3. Parent 继续调度任务队列中的其他 Worker
4. 当依赖模块完成时，Parent 检查 `blocked_queue`：
   - 若 `blocking_dependencies` 全部满足 → 将 Worker 移回 `task_queue`，标记优先级为 `BLOCKED_DEPENDENCY`（最高）
   - 调度器下一个激活该 Worker，从磁盘恢复 context

---

## 7. 生命周期与状态机（Lifecycle & State Machines）

### 7.1 Worker 生命周期状态机

```
                    ┌─────────────────┐
                    │    CREATED      │  ← Parent 创建，尚未激活
                    └────────┬────────┘
                             │ activate()
                             ▼
                    ┌─────────────────┐
         ┌─────────│    ACTIVATED    │  ← 持有 Slot，开始工作
         │         └────────┬────────┘
         │                  │ request_llm()
         │                  ▼
         │         ┌─────────────────┐
         │         │   LLM_REQUEST   │  ← 原子状态：发送请求、接收 SSE
         │         │   (atomic)      │     不可被 BLOCKED/清理
         │         └────────┬────────┘
         │                  │ parse_response()
         │                  ▼
         │         ┌─────────────────┐
         │         │   TOOL_EXEC     │  ← 原子状态：执行工具
         │         │   (atomic)      │     不可被 BLOCKED/清理
         │         └────────┬────────┘
         │                  │ tool_complete()
         │                  │ (if more tool_calls) ──→ LLM_REQUEST
         │                  │ (if finish_reason=stop)
         │                  ▼
         │         ┌─────────────────┐
         │         │   DELIVERING    │  ← 准备汇报，可被 BLOCKED
         │         └────────┬────────┘
         │                  │ generate_report()
         │                  ▼
         │         ┌─────────────────┐
         │  ┌─────│    COMPLETED    │  ← 任务完成，可销毁
         │  │      └─────────────────┘
         │  │
         │  │      ┌─────────────────┐
         │  └─────│     BLOCKED     │  ← 依赖缺失，保存 context → 休眠
         │         │   (hibernate)   │     Slot 释放，等待唤醒
         │         └────────┬────────┘
         │                  │ (dependency satisfied)
         │                  ▼
         │         ┌─────────────────┐
         └─────────│    RESTORING    │  ← 从磁盘恢复 context，重新申请 Slot
                   └────────┬────────┘
                            │ resume()
                            └──────────────→ ACTIVATED

         │         ┌─────────────────┐
         └─────────│     EXPAND      │  ← 申请创建子 Worker
                   │    (paused)     │     自己暂停，等待子 Worker 完成
                   └────────┬────────┘
                            │ (child completed)
                            ▼
                   ┌─────────────────┐
                   │    RESUMING     │  ← 子 Worker 完成，自己继续
                   └────────┬────────┘
                            │ continue_task()
                            └──────────────→ ACTIVATED

         │         ┌─────────────────┐
         └─────────│     FAILED      │  ← 连续失败（≥2 次）
                   │  (report_up)    │     上报 Parent，由 Parent 决定重试/重构/上报
                   └─────────────────┘
```

### 7.2 RequestSlot 状态机

```
IDLE ──claim()──→ CONNECTING ──connected──→ SENDING ──sent──→ STREAMING
                                                         │
                                                         │ (SSE done)
                                                         ▼
                                               ┌─────────────────┐
                                               │   TOOL_EXEC     │  ← 由 Worker 控制
                                               │   (atomic)      │
                                               └────────┬────────┘
                                                        │ (tools done)
                                                        ▼
                                               ┌─────────────────┐
                                               │    COMPLETED    │  ──release()──→ IDLE
                                               └─────────────────┘

错误路径：
  CONNECTING / SENDING / STREAMING 中失败 ──→ FAILED ──reset()──→ IDLE
```

### 7.3 工单（Task Ticket）状态机

```
CREATED ──assign()──→ ASSIGNED ──activate()──→ IN_PROGRESS
                                                      │
                              ┌───────────────────────┼───────────────────────┐
                              │                       │                       │
                              ▼                       ▼                       ▼
                         COMPLETED                BLOCKED                 FAILED
                              │                       │                       │
                              │                       │ (dependency met)      │ (retry < 2)
                              │                       ▼                       ▼
                              │                  RESTORING                 RETRYING
                              │                       │                       │
                              │                       └──────→ IN_PROGRESS ←──┘
                              │
                              └──────────────────────────→ ARCHIVED
```

---

## 8. 上下文管理（Context Management）

### 8.1 每个节点的 Context 组成

```gdscript
# Worker Context 结构（内存中）
class WorkerContext:
    var worker_id: String
    var ticket: TaskTicket
    var messages: Array[Dictionary]  # 独立的消息历史
    var system_prompt: String         # 从 .md 加载 + 动态注入
    var tool_definitions: Array       # 从 .json 加载的本层工具子集
    var execution_state: Dictionary   # 执行进度（当前步骤、已完成工具、中间结果）
    var parent_messages: Array        # 上级任务指令（注入为 system prompt 的一部分）
```

### 8.2 休眠与恢复

当 Worker 被 BLOCKED：

**保存到磁盘**（`dotagent_cortex/nodes/{worker_id}_context.json`）：
```json
{
  "worker_id": "Worker:Player:001",
  "ticket_id": "T-20260615-001",
  "state": "BLOCKED",
  "block_reason": {
    "type": "dependency_missing",
    "missing": "Enemy.enemy_died"
  },
  "messages": [...],
  "execution_state": {
    "current_step": "implement_combat_system",
    "completed": ["Movement", "Shooting"],
    "pending": ["ComboSystem", "DamageFlash"]
  },
  "knowledge_accumulated": [...]
}
```

**恢复时**：
1. 从磁盘读取 JSON
2. 重建 `messages` 数组
3. 重建 `execution_state`
4. 重新申请 Slot
5. 继续执行 `pending` 中的任务

### 8.3 消息构建策略

每个 Worker 发送给 LLM 的消息：
- **system 消息**：Worker 层 system prompt（`.md`）+ 动态上下文（当前任务 + 工具集）
- **user 消息**：上级任务指令（第一次）或 工具执行结果（后续轮次）
- **assistant 消息**：AI 的思考 + tool_calls
- **tool 消息**：工具执行结果

**不包含**：其他 Worker 的消息、其他 Branch 的代码、Root 的战略规划。

---

## 9. 知识系统（Knowledge System）

### 9.1 知识条目格式（Knowledge Entry）

```json
{
  "entry_id": "ke-20260615-001",
  "timestamp": "2026-06-15T10:30:00Z",
  "source": {
    "worker_id": "Worker:Player:001",
    "task_id": "T-20260615-001",
    "round": 3
  },
  "type": "technical_decision | interface | implementation | bug_fix | design_pattern | constraint",
  "scope": {
    "module": "Player",
    "sub_module": "Movement",
    "file": "res://scripts/player.gd"
  },
  "content": {
    "summary": "Player 使用 Area2D 而非 CharacterBody2D",
    "detail": "因为项目使用手动碰撞检测（_collisions_check），不需要 Godot 物理引擎的自动响应。Area2D 更轻量。",
    "alternatives_considered": ["CharacterBody2D", "RigidBody2D"],
    "rationale": "街机射击不需要真实物理，手动检测更可控。"
  },
  "tags": ["collision", "node_type", "performance"],
  "confidence": "high | medium | low",
  "supersedes": null,
  "superseded_by": null
}
```

### 9.2 知识提取流程

1. Worker 完成任务，在 `WorkerReport` 中附带 `knowledge_report`
2. Parent 收到后，审核每个知识条目（检查与现有知识是否冲突）
3. 无冲突 → 写入 `dotagent_cortex/knowledge/{module}.json`
4. 有冲突 → 标记 `conflict`，上报 Root 仲裁
5. Root 决定采用哪个版本，或要求重新验证

### 9.3 知识查询接口

```json
// 查询请求
{
  "query": "Player 的碰撞检测方式",
  "filter": {
    "module": "Player",
    "type": "technical_decision",
    "tags": ["collision"]
  }
}

// 返回
[
  {
    "entry_id": "ke-20260615-001",
    "summary": "Player 使用 Area2D，手动碰撞检测",
    "confidence": "high",
    "source": "Worker:Player:001"
  }
]
```

---

## 10. 信号系统（Signal System）

### 10.1 全局信号（跨模块）

**所有跨模块信号必须写入 `SignalBus.gd`（autoload）**。

文件位置：`res://scripts/signal_bus.gd`（或项目根目录下的 autoload）

```gdscript
# signal_bus.gd
extends Node

# === Gameplay ===
signal GameStart()
signal GameOver(score: int)
signal PlayerDied(lives_remaining: int)
signal EnemyKilled(score_value: int, position: Vector2)
signal WaveCompleted(wave_number: int)

# === UI ===
signal ScoreUpdated(new_score: int)
signal HealthChanged(current_hp: int, max_hp: int)
signal ShieldActivated(duration: float)

# === Audio ===
signal MusicRequested(track_name: String)
signal SFXRequested(event_name: String, volume: float)
```

**连接/断开/发送**：
```gdscript
# 连接
SignalBus.GameOver.connect(_on_game_over)
SignalBus.EnemyKilled.connect(_on_enemy_killed)

# 断开
SignalBus.GameOver.disconnect(_on_game_over)

# 发送
SignalBus.GameOver.emit(final_score)
SignalBus.EnemyKilled.emit(100, enemy.position)
```

**禁止**：在模块内部直接声明跨模块信号（如 `signal enemy_died` 在 `enemy.gd` 中）。

### 10.2 局部信号（模块内）

- 尽量避免使用局部信号
- 必须使用时遵循 snake_case：`signal game_start()` / `signal health_changed()`
- 局部信号只应在同一个 `.gd` 文件内连接和发射

### 10.3 接口契约阶段的全局信号定义

在骨架阶段（SKELETON_FIRST），Parent Branch 负责协调各 Worker 声明需要的全局信号，统一写入 `SignalBus.gd`。这是接口契约的一部分。

---

## 11. 分层工具协议（Layered Tool Protocol）

### 11.1 工具定义格式（.json）

每个层级定义独立的工具集，存储为 `.json` 文件：

**Root 层工具**（`root_tools.json`）：
```json
[
  {
    "name": "analyze_request",
    "description": "分析用户需求，输出结构化任务分解",
    "parameters": {"type": "object", "properties": {"user_input": {"type": "string"}}},
    "layer": "root"
  },
  {
    "name": "create_branch",
    "description": "创建子系统分支节点",
    "parameters": {"type": "object", "properties": {"name": {"type": "string"}, "scope": {"type": "string"}}},
    "layer": "root"
  },
  {
    "name": "assign_task",
    "description": "向分支分配任务工单",
    "parameters": {"type": "object", "properties": {"branch_id": {"type": "string"}, "ticket": {"type": "object"}}},
    "layer": "root"
  }
]
```

**Branch 层工具**（`branch_tools.json`）：
```json
[
  {
    "name": "create_module",
    "description": "创建模块 Worker",
    "parameters": {"type": "object", "properties": {"name": {"type": "string"}, "type": {"type": "string"}}},
    "layer": "branch"
  },
  {
    "name": "connect_modules",
    "description": "定义模块间接口契约",
    "parameters": {"type": "object", "properties": {"source": {"type": "string"}, "target": {"type": "string"}, "interface": {"type": "object"}}},
    "layer": "branch"
  }
]
```

**Worker 层工具**（`worker_tools.json`）：
```json
[
  {
    "name": "create_scene",
    "description": "创建新场景文件",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "root_type": {"type": "string"}}},
    "layer": "worker"
  },
  {
    "name": "update_script",
    "description": "更新脚本内容",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}},
    "layer": "worker"
  }
]
```

### 11.2 运行时加载

每个节点激活时，调度器只加载其对应层级的工具定义：
- Root 激活时 → 加载 `root_tools.json`（约 5-8 个工具）
- Branch 激活时 → 加载 `branch_tools.json`（约 6-10 个工具）
- Worker 激活时 → 加载 `worker_tools.json`（约 8-12 个工具）

**信息隔离**：Worker 永远看不到 Root 的 `create_branch` 或 Branch 的 `connect_modules`。

---

## 12. 遍历策略（Traversal Strategy）

### 12.1 Root 遍历决策 Skill（.md）

```markdown
# triggers: 遍历, 策略, skeleton, depth, 框架, 结构

## 遍历策略选择

作为 Root Coordinator，你需要根据用户请求的类型选择遍历策略：

### SKELETON_FIRST（骨架优先）
- **适用场景**：
  - 用户说"做一个新游戏"、"搭框架"、"先定义结构"
  - 创建新项目
  - 添加全新子系统（如"加一个装备系统"）
- **执行方式**：
  - 先创建所有 Branch 和 Worker 的空壳（空场景 + 空脚本 + 接口签名）
  - 所有模块编译通过但逻辑为空
  - 确认所有模块间接口契约一致
- **优势**：早期发现架构问题，模块间接口预先定义

### DEPTH_FIRST（深度优先）
- **适用场景**：
  - 用户说"完成 Player 模块"、"做详细实现"
  - 修改现有模块
  - 修复 bug
  - 添加单一功能（如"给 Player 加 Dash"）
- **执行方式**：
  - 选定一个 Worker，从头到尾完成其实现
  - 每完成一个子功能立即验证
- **优势**：快速产出可用模块，符合 Godot 模块化开发理念

### 默认规则
- 新项目 / 新系统 → SKELETON_FIRST
- 修改 / 补充 / 修复 → DEPTH_FIRST
- 模糊的"做一个游戏" → SKELETON_FIRST（安全优先）
```

### 12.2 执行流程

```
Root 收到用户请求
  → 加载遍历策略 skill
  → 分析请求关键词
  → 输出决策：SKELETON_FIRST 或 DEPTH_FIRST
  → 按决策执行 Phase 1 / Phase 2
```

---

## 13. 文件目录结构（File Directory Structure）

```
res://
├── addons/
│   ├── dotagent/                    # Legacy 模式（保留，不改动）
│   │   ├── plugin.cfg
│   │   ├── plugin.gd
│   │   └── ...
│   │
│   └── dotagent_cortex/             # 新架构（DotAgent Cortex）
│       ├── plugin.cfg               # 插件入口配置
│       ├── plugin.gd                # 插件入口（EditorPlugin）
│       │
│       ├── core/                    # 核心调度引擎
│       │   ├── node_scheduler.gd    # 节点调度器（串行/并行切换）
│       │   ├── worker_executor.gd   # Worker 执行器（生命周期管理）
│       │   └── traverser.gd         # 遍历策略执行器
│       │
│       ├── http/                    # HTTP 连接基础设施
│       │   ├── http_client_pool.gd  # HTTPClient 连接池
│       │   ├── request_slot.gd      # 请求槽（状态机 + SSE 解析）
│       │   └── stream_parser.gd     # SSE 流式解析器
│       │
│       ├── nodes/                   # 节点实现（运行时 .gd 仅此处）
│       │   ├── root_coordinator.gd  # Root 协调器
│       │   ├── branch_node.gd       # Branch 分支节点
│       │   └── worker_node.gd       # Worker 工作节点
│       │
│       ├── context/                 # 上下文管理
│       │   ├── context_manager.gd   # Context 加载/保存/恢复
│       │   └── message_builder.gd   # 消息构建与压缩
│       │
│       ├── knowledge/               # 知识库系统
│       │   ├── knowledge_base.gd    # 知识库管理器
│       │   ├── knowledge_entry.gd   # 知识条目结构
│       │   └── conflict_resolver.gd # 冲突检测与仲裁
│       │
│       ├── signal/                  # 信号总线管理
│       │   └── signal_bus_manager.gd # SignalBus.gd 生成与维护
│       │
│       ├── tools/                   # 工具执行层（复用 Legacy 底层）
│       │   ├── tool_loader.gd       # 工具定义加载器（.json）
│       │   ├── tool_executor.gd     # 工具执行代理（桥接 Legacy）
│       │   └── definitions/         # 工具定义（.json）
│       │       ├── root_tools.json
│       │       ├── branch_tools.json
│       │       └── worker_tools.json
│       │
│       ├── prompts/                 # System Prompt（.md）
│       │   ├── root_prompt.md       # Root 协调器系统提示
│       │   ├── branch_prompt.md     # Branch 分支节点系统提示
│       │   ├── worker_prompt.md     # Worker 执行节点系统提示
│       │   └── skills/              # Skill 文件（动态加载）
│       │       ├── traversal_strategy.md
│       │       ├── 2d_game.md
│       │       ├── 3d_game.md
│       │       ├── ui_scene.md
│       │       └── signal_patterns.md
│       │
│       ├── ui/                      # UI 层（前端）
│       │   ├── dock.gd              # 主 Dock
│       │   ├── dock.tscn
│       │   ├── activity_panel.gd    # Activity 面板
│       │   └── activity_panel.tscn
│       │
│       ├── config/                  # 配置管理
│       │   └── config_manager.gd    # 配置单例（复用 Legacy）
│       │
│       └── persistence/             # 持久化存储
│           ├── node_contexts/       # Worker 休眠 Context（.json）
│           ├── task_tickets/        # 任务工单（.json）
│           └── worker_reports/      # 工作汇报（.json）
│
├── dotagent_cortex/                 # 用户项目级数据（非插件）
│   ├── knowledge/                   # 知识库（按模块分 .json）
│   │   ├── Player.json
│   │   ├── Enemy.json
│   │   └── UI.json
│   └── sessions/                    # 会话历史（可选）
│
└── scripts/                         # 项目脚本（由 Cortex 生成）
    └── signal_bus.gd                # 全局信号总线（autoload）
```

---

## 14. 迁移策略（Migration Strategy）

### 14.1 保留 Legacy DotAgent

- `addons/dotagent/` 目录完全保留，继续可用
- `project.godot` 的 `editor_plugins` 同时保留两者（但同一时刻只能激活一个）
- Legacy 的日志、备份、会话数据不受影响

### 14.2 桥接层设计

DotAgent Cortex 的 Worker 层需要实际操作 Godot 编辑器。底层能力（创建场景、写脚本、设置属性、运行验证、截图）已经由 Legacy DotAgent 的 58 个工具实现。

**不重写底层工具，而是设计桥接层**：

```
Worker Node → tool_executor.gd → 调用 Legacy 工具模块
                                      │
                                      ▼
                              addons/dotagent/tools/*.gd
```

`tool_executor.gd` 的职责：
1. 加载 `.json` 中定义的 Worker 层工具子集（只暴露 8-12 个给 LLM）
2. 收到 tool_call 时，调用 Legacy 对应工具模块的 `call_method()`
3. 将 Legacy 的返回结果包装为 Cortex 格式的 WorkerReport

**好处**：
- 不重复造轮子（SSE 流式、文件备份、截图、语法检查都复用）
- 如果 Legacy 工具有 bug，修复一处两处受益
- 未来 Legacy 升级（如新增工具），Cortex 自动受益

### 14.3 切换机制

用户在 Godot 编辑器 → Project → Project Settings → Plugins：
- 勾选 **DotAgent** → 使用 Legacy 模式
- 勾选 **DotAgent Cortex** → 使用新架构
- 两者不可同时启用（避免冲突）

---

## 15. 附录（Appendices）

### 附录 A：Worker Context 存档 Schema

```json
{
  "$schema": "worker_context",
  "version": "1.0",
  "worker_id": "string",
  "ticket_id": "string",
  "state": "ACTIVATED | BLOCKED | EXPAND | FAILED",
  "block_reason": {
    "type": "dependency_missing | resource_exhausted | error_threshold",
    "detail": "string"
  },
  "messages": [
    {"role": "system | user | assistant | tool", "content": "string"}
  ],
  "execution_state": {
    "phase": "string",
    "completed_steps": ["string"],
    "pending_steps": ["string"],
    "current_tool": "string | null"
  },
  "knowledge_accumulated": ["entry_id"],
  "files_created": ["res://path"],
  "slot_snapshot": {
    "request_id": "string",
    "sse_buffer": "string",
    "accumulated_content": "string"
  }
}
```

### 附录 B：接口契约 Schema

```json
{
  "$schema": "interface_contract",
  "version": "1.0",
  "module_a": "Player",
  "module_b": "Enemy",
  "signals": [
    {
      "name": "enemy_died",
      "emitter": "Enemy",
      "listeners": ["Player", "GameplayManager"],
      "params": [
        {"name": "score_value", "type": "int"},
        {"name": "position", "type": "Vector2"}
      ]
    }
  ],
  "methods": [
    {
      "name": "take_damage",
      "owner": "Player",
      "params": [{"name": "amount", "type": "int"}],
      "returns": "void",
      "visibility": "public"
    }
  ],
  "status": "draft | locked | deprecated"
}
```

### 附录 C：典型工作流示例

**工作流：从 0 开始创建一个 Metroidvania 游戏**

```
Round 1: Root 收到 "做一个银河恶魔城，类似 Hollow Knight"
  → Root 分析 → 决策：SKELETON_FIRST
  → Root 创建 Gameplay Branch、UI Branch、Audio Branch、Level Branch

Round 2-5: 骨架阶段（广度优先）
  → Gameplay Branch 创建 Player Worker（空壳）
  → Gameplay Branch 创建 Enemy Worker（空壳）
  → Gameplay Branch 创建 Weapon Worker（空壳）
  → UI Branch 创建 HUD Worker（空壳）
  → ...
  → 所有 Branch 收集接口 → 确认 → 锁定契约
  → SignalBusManager 生成 signal_bus.gd

Round 6-20: 填充阶段（深度优先）
  → Gameplay Branch 唤醒 Player Worker → 填充 Movement → 测试 → 返回
  → Gameplay Branch 唤醒 Player Worker → 填充 Combat → 测试 → 返回
  → Player Worker 发现 Trail 系统过于复杂 → 申请 EXPAND
  → Gameplay Branch 创建 PlayerTrail Worker（子 Worker）
  → PlayerTrail Worker 完成 → 返回 → Player Worker 继续
  → Gameplay Branch 唤醒 Enemy Worker → 填充 Scout AI → 测试 → 返回
  → ...

Round 21: 集成验证
  → Root 唤醒 Integration Worker → 运行完整场景 → 验证信号流 → 返回

Round 22: Root 向用户汇报
  → "已完成：Player 系统（Movement + Combat + Dash + Trail），Enemy 系统（Scout + Boss），
       UI 系统（HUD + Menu）。待完成：Save 系统、Dialogue 系统。"
```

---

**文档结束**

*本架构设计文档为 DotAgent Cortex 开发的唯一真相来源。任何实现偏离必须在此文档中先更新。*
