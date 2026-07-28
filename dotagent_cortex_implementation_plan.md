# DotAgent Cortex 实现计划书

**版本**: 2.0
**日期**: 2026-07-23
**关联文档**: `dotagent_cortex_architecture.md`（架构设计文档 v1.0，设计冻结）

---

## 一、核心问题与设计哲学

### 1.1 要解决的根本问题：模型注意力退化

当前主流 LLM 已支持 1M token 上下文窗口，但容量不等于能力。Transformer 的自注意力机制存在固有的效率瓶颈：当 context 填充率达到约 70% 时，注意力分布变得过于平坦，模型对每个 token 的关注度显著下降，表现为推理质量下滑、工具选择错误率上升、幻觉频率增加。与此同时，自注意力的 O(n²) 复杂度导致每增加一个 token 的计算成本和 API 费用都在急剧攀升。

这意味着即使把 context window 从 128K 扩大到 1M，如果不改变架构，模型在 700K tokens 处同样会遇到注意力退化。问题不在于"放不放得下"，而在于"看没看得清"。

### 1.2 双刀策略

Cortex 通过两个相互配合的策略将每个 LLM 节点的 context 填充率始终控制在远低于退化阈值的水平：

**第一刀：模型节点化**

将一个塞满的大 context 拆分为 N 个聚焦的小 context。Legacy 架构中单个 LLM 持有全项目知识 + 61 个工具定义，context 轻松达到 20K-80K tokens。Cortex 将其分解为树状拓扑（Root → Branch → Worker），每个 Worker 的 context 仅包含其职责范围内的模块知识和 8-12 个工具，典型填充量为 2-3K tokens。模型在每个节点上都保持"高度聚焦"的状态。

**第二刀：结构化感知工具**

节点化解决了 context 大小的问题，但如果 Worker 仍然需要用"阅读理解"的方式从大段文本中提取信息，context 会在工具返回阶段迅速膨胀。例如，为了确认 Player 节点的 `collision_layer` 属性，文本感知方式需要读取整个 .tscn 文件（可能 100+ 行，含大量无关节点和资源引用），而结构化感知工具直接返回精确的 JSON 数据（几十个 tokens，零噪声）。

两刀合在一起的效果：每个节点的 context 既小（节点化）又密（结构化工具），模型的注意力 100% 用在决策上，而不是浪费在从文本中提取信息的中间步骤上。

### 1.3 封装原则：能封装的绝不交给 AI

Cortex 的架构哲学可以用一句话概括：**工具代替思考和行动，AI 只进行决策。**

每一层封装都在缩小 AI 的职责范围：

```
Legacy：AI 读文本 → AI 理解 → AI 决策 → AI 生成文本 → 写入文件
Cortex：工具读 → 工具提取结构 → AI 决策 → 工具写
GNM：  工具读 → 工具提取结构 → 小模型决策 → 工具写
```

自由度越小，犯错空间越小。一个拥有 61 个工具的 LLM 理论上能做任何事情——包括删掉项目文件、写出不存在的 API 调用、搞乱场景树结构。但如果 Worker 只有 `build_scene`、`patch_scene`、`update_script`、`check_script_syntax` 这几个工具，它能犯的错就被物理限制了。`build_scene` 不会产生语法错误的 .tscn，因为它是通过 Godot API 构建的。`check_script_syntax` 会在写入前拦截编译错误。工具就是护栏。

这也解释了为什么未来可以用更小的模型（GNM）替代 Worker 层的 LLM——当 AI 只需要做决策时，它不需要理解 .tscn 的文件格式（工具会处理），不需要知道 `ResourceSaver.save()` 的 API（工具会调用）。它只需要输出结构化意图，工具负责翻译成 Godot 的文件格式。

### 1.4 Legacy DotAgent 的六大瓶颈

基于 Star Hunter 项目（21 脚本 / 2371 行代码 / 18 场景）的实测数据：

**瓶颈一：上下文爆炸。** 每轮 ReAct 循环发送全部 61 个工具定义（~6K tokens）+ 动态场景上下文 + 完整对话历史。`message_builder.gd` 的 `build()` 方法不压缩对话内消息，对话超过 20 轮后 context 轻松突破 50K，30 轮后频繁触发 76% 压缩阈值，LLM 丢失具体实现细节。

**瓶颈二：工具选择瘫痪。** 61 个工具全部暴露给 LLM，每轮从 61 个选项中做选择。Transformer 的 softmax 分布在 61 个候选上比 8 个候选更平坦，错误选择概率显著升高。

**瓶颈三：单一上下文无法分离知识域。** `player.gd` 和 `enemy.gd` 有大量相似结构（都有 `_draw()`、`signal died`、`_gm()` 方法），在混合上下文中 LLM 极易混淆两者的具体细节。

**瓶颈四：错误传播无边界。** 单个 LLM 操作整个项目，一次幻觉可能级联破坏所有文件。备份机制（`backup_manager.gd`）只是事后补救，无法阻止错误在 LLM 后续推理中级联传播。

**瓶颈五：无法并行处理多模块。** 串行执行下，开发到第四个模块时，第一个模块的具体细节已被压缩或遗忘。

**瓶颈六：缺乏架构级感知。** 所有工具都是文件级或节点级操作，LLM 需要用文本理解能力去模拟架构理解能力，极其低效。

### 1.5 Legacy 与 Cortex 的量化对比

单模块开发（为 Player 添加 Dash 功能）：

| 维度 | Legacy | Cortex (Player Worker) |
|------|--------|----------------------|
| Context 起始大小 | ~20K tokens | ~3K tokens |
| 工具选择空间 | 61 选 1 | 8-12 选 1 |
| 无关上下文 | Enemy/UI/Audio 历史 | 无（隔离） |
| 错误影响范围 | 全项目 | 仅 Player 模块 |
| 可用 context 余量 | ~108K（已用 15%） | ~125K（已用 2%） |

多模块开发（从零开始做 2D 银河恶魔城，Player + Enemy + Level + UI + Audio）：

| 维度 | Legacy | Cortex |
|------|--------|--------|
| 第 5 个模块的 context | ~80K（前 4 个模块历史） | ~3K（干净 Worker） |
| 接口一致性维护 | LLM 靠记忆 | Branch 显式锁定契约 |
| 错误恢复成本 | 高（可能级联） | 低（隔离到 Worker） |

项目规模天花板：

| 规模 | Legacy | Cortex |
|------|--------|--------|
| 小游戏（5-10 脚本） | 流畅 | 流畅 |
| 中等（20-30 脚本） | 后半段 context 压力大 | 稳定 |
| 大型（50-100 脚本） | 频繁压缩，丢失细节 | 每个 Worker 独立处理 |
| 超大型（100+ 脚本） | 无法维护全局一致性 | 需要更多 Branch 节点 |

---

## 二、架构总览

架构设计详见 `dotagent_cortex_architecture.md`，此处仅列出实现相关的关键约束。

### 2.1 树状拓扑

```
[User Input]
    │
    ▼
┌──────────────────────────────────────┐
│  Root Coordinator（唯一，常驻）       │
│  最强模型 / 项目级感知 / 不操作文件   │
└──────────────────────────────────────┘
    │
    ├─────────────┬─────────────┬─────────────┐
    ▼             ▼             ▼             ▼
┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
│Gameplay│  │   UI   │  │ Audio  │  │ Level  │
│ Branch │  │ Branch │  │ Branch │  │ Branch │
│中等模型│  │中等模型│  │中等模型│  │中等模型│
└────────┘  └────────┘  └────────┘  └────────┘
    │
    ├──┬──┐
    ▼  ▼  ▼
┌──────┐ ┌──────┐ ┌──────┐
│Player│ │Enemy │ │Weapon│
│Worker│ │Worker│ │Worker│
│快模型│ │快模型│ │快模型│
└──────┘ └──────┘ └──────┘
```

### 2.2 信息隔离三原则

1. 每个节点只对自己和直属上下节点负责
2. 每个节点只能获取：自己的信息 + 上级下达的任务 + 下级反馈的汇报
3. 同级节点不可直接通信，跨模块需求通过 Parent 中转

### 2.3 父节点决策机制

父节点决定是否创建子节点，并为其生成 TaskTicket（动态任务上下文）。子节点的完整指令由两部分组成：

1. **预定义 System Prompt**（`.md` 文件）：静态的，定义节点角色、可用工具、工作方式
2. **TaskTicket**（父节点动态生成）：包含需求、约束、预期接口——父节点对子节点说的"我要你做什么、怎么做、做到什么程度"

Worker 完成后通过 `WorkerReport` 向上汇报。如果 Worker 在执行过程中发现某个子任务过于复杂，可向父节点申请 `EXPAND`，父节点再决定是否创建孙子节点。

### 2.4 分层模型策略

不同层级的节点承担不同类型的推理任务，应匹配不同规格的模型：

| 层级 | 推理类型 | 推荐模型规格 | Context 预算 |
|------|---------|------------|-------------|
| Root Coordinator | 需求分析、任务分解、架构决策、冲突仲裁 | 旗舰级（最强推理） | 8-15K tokens |
| Branch Node | 接口协调、Worker 审查、子系统架构 | 中高级（平衡推理与速度） | 5-10K tokens |
| Worker Node | 代码生成、场景操作、属性设置 | 轻量级（快速执行） | 2-5K tokens |

模型选择由 `config_manager.gd` 统一管理，每个层级可独立配置 `base_url` 和 `model`。Worker 层使用轻量模型不仅降低成本，还因为 Worker 的 context 本身就小，配合轻量模型可获得更低的响应延迟。

### 2.5 通信协议

下行使用 TaskTicket（结构化任务工单），上行使用 WorkerReport（结构化交付汇报）。Schema 定义见架构文档第六章。

---

## 三、文件访问策略

### 3.1 核心决策：封禁非脚本文件的文本读写

Cortex 封禁 `.tscn`、`.tres`、`project.godot` 等文件的直接文本读写权限，全部通过结构化工具操作。唯一保留文本读写的是 `.gd` 脚本文件（逻辑代码天然就是文本）和 `.gdshader`（着色器代码等同脚本）。

最终的文件访问模式：

```
场景/资源/项目配置  →  100% 结构化工具（读写都是 JSON）
脚本接口/依赖/信号  →  100% 结构化工具
脚本实现逻辑 (.gd)  →  文本读取（仅在需要修改或调试时）
着色器代码 (.gdshader) → 文本读写（等同脚本）
```

### 3.2 覆盖完整性要求

封禁文本读写的前提是：**工具必须 100% 覆盖所有配置需求。** 否则会留下永远无法到达的死角——Worker 知道该做什么，但没有工具能做。

### 3.3 完整覆盖图

| 文件类型 | 读工具 | 写工具 | 状态 |
|---------|--------|--------|------|
| `.tscn` | `inspect_scene_structured` | `build_scene` / `patch_scene` | ✅ 已覆盖 |
| `.tres`（所有 Resource 类型，含自定义） | `inspect_resource_interface` + `configure_resource` (load) | `configure_resource` (save) | ✅ 已覆盖 |
| `project.godot` | `get_project_architecture` | `configure_project` | ✅ 已覆盖 |
| `.gd` 脚本 | `extract_script_interface`（接口）/ `read_script`（全文） | `build_script` / `update_script` | ✅ 已覆盖 |
| `.gdshader` | 文本读取 | `update_script`（扩展支持） | ✅ 视为代码 |
| Animation 资源 | `configure_resource` (通用) | `configure_resource` (通用) | ⚠️ 需验证 Animation API |
| Theme 资源 | `configure_resource` (通用) | `configure_resource` (通用) | ⚠️ 需验证 Theme API |
| TileSet 配置 | `configure_resource` (通用) | `configure_resource` (通用) | ⚠️ 复杂，可能需专用工具 |
| `export_presets.cfg` | 低优先级 | `configure_project` 扩展 | ⚠️ 低优先级 |
| `.import` 文件 | 通常不需修改 | 不覆盖 | — 排除 |
| `.csv` / `.po` (i18n) | 文本读取 | `write_file` | ✅ 文本文件 |

**关键约束**：`configure_resource` 必须是**通用的**——Godot 中用户可以通过 `extends Resource` + `class_name` 定义任意自定义资源类型（如 `WaveData`、`WeaponLevelData`）。工具实现通过 `ClassDB.instantiate(type)` + `set()` + `ResourceSaver.save()` 天然支持所有 Resource 类型，包括用户自定义的。不需要为每种资源类型写特殊逻辑。

---

## 四、感知工具层设计

感知工具是 Cortex 的基础设施，不是辅助。它们替代了 Legacy 中"用阅读理解分析文本"的低效模式，将编辑器状态转化为 Worker 可直接消费的结构化数据。

### 4.1 设计原则

**原则一：输出必须是结构化 JSON，不是文本字符串。** LLM 不需要"阅读"输出，直接解析 JSON 即可提取所需信息。

**原则二：信息密度优先于信息完整性。** 一个 200 tokens 的精确 JSON 优于一个 2000 tokens 的文本 dump。感知工具的核心职责是过滤噪声，只保留有价值的信息。

**原则三：支持聚焦查询。** 不强制返回完整数据，支持通过参数指定查询范围（特定节点、特定属性、特定深度），实现"手术刀模式"。

**原则四：主动标注异常。** 工具不仅返回数据，还在 `observations` 字段中标注发现的问题（缺失引用、越界属性、空形状等），将部分验证推理从 LLM 端转移到工具端。检查规则应支持**可扩展机制**——从项目级配置文件（如 `.dotagent_rules.json`）加载自定义规则，适应不同项目的需求。

**原则五：支持增量感知。** 首次查询返回完整结构，后续查询只返回变更部分（changed / added / removed），配合 Worker 的心理模型（上次完整结构 + 后续增量）维护当前状态认知。

### 4.2 感知工具清单（8 个）

#### 工具 1：`inspect_scene_structured`（核心感知）

替代 Legacy 的 `get_scene_tree`（文本树）+ `get_node_properties`（扁平属性列表）+ `get_signal_connections`（编辑器绑定）。

**输入参数**：

```json
{
  "scene_path": "res://scenes/player.tscn",
  "focus_path": "Player",
  "properties": ["collision_layer", "collision_mask", "position"],
  "include_signals": true,
  "include_script_interface": true,
  "max_depth": 0
}
```

`focus_path` 和 `properties` 实现聚焦查询——当指定时只返回目标节点的指定属性，不返回整棵树。

**输出结构**：

```json
{
  "ok": true,
  "content": {
    "type": "scene_struct",
    "path": "res://scenes/player.tscn",
    "scene_type": "2d",
    "root": {
      "name": "Player",
      "type": "Area2D",
      "properties": {
        "collision_layer": {"type": "int", "value": 1},
        "collision_mask": {"type": "int", "value": 2},
        "position": {"type": "Vector2", "value": [640, 360]}
      },
      "script": {
        "path": "res://scripts/player.gd",
        "class_name": "Player",
        "extends": "Area2D",
        "signals": [{"name": "died", "params": []}],
        "exports": [{"name": "speed", "type": "float", "default": 420.0}],
        "public_methods": [{"name": "take_damage", "params": ["amount: int"], "returns": "void"}]
      },
      "children": [
        {"name": "Sprite2D", "type": "Sprite2D", "child_count": 0},
        {"name": "CollisionShape2D", "type": "CollisionShape2D", "child_count": 0}
      ],
      "signal_connections": [
        {"signal": "area_entered", "target": ".", "method": "_on_area_entered"}
      ]
    },
    "observations": [
      "CollisionShape2D.shape 为 null，碰撞检测不会生效"
    ],
    "stats": {"total_nodes": 3, "total_scripts": 1, "total_resources": 2}
  }
}
```

**实现策略**：优先从编辑器实时场景树读取（`EditorInterface.get_edited_scene_root()`），如果指定了 `scene_path` 且非当前编辑场景则从磁盘加载 `PackedScene`。节点属性过滤默认值和 `_` 前缀内部属性。脚本接口通过正则解析 `.gd` 文件提取。

---

#### 工具 2：`extract_script_interface`（接口提取）

提取脚本的接口摘要，不读实现细节。用于 Cortex 的接口契约阶段和 Branch 层的模块接口审查。

**输入**：`{"path": "res://scripts/player.gd", "include_private_methods": false, "include_body_preview": false}`

**输出**：结构化 JSON 包含 class_name、extends、signals、exports、constants、enums、public_methods、dependencies（preload/load）、node_refs（@onready）、observations（如"signal shoot_spread 已声明但从未被发射"）。

**实现策略**：纯正则解析 `.gd` 文件。匹配规则：`signal`、`func`（过滤 `_` 前缀私有方法）、`@export`、`class_name`、`extends`、`enum`、`const`、`@onready`、`preload()`、`load()`。

---

#### 工具 3：`get_project_architecture`（架构概览）

替代 Legacy 的 `get_project_info` + `list_files`。Root Coordinator 的核心感知工具。

**输出**：结构化 JSON 包含 project_name、main_scene、viewport、autoloads（含接口摘要）、scene_tree（实例化层级）、signal_bus（跨模块信号流）、scripts_summary（统计）、resource_types（分类统计）、observations（如"game.gd 528 行，可能需要拆分为多个 Worker"）。

**实现策略**：遍历项目文件（复用 `_walk_dir`），对每个 `.tscn` 文件用正则提取 `ext_resource` 中的场景引用，对每个 `.gd` 文件提取 `signal` 声明和 `.connect()` 调用，从 `project.godot` 提取 autoload 列表。

---

#### 工具 4：`inspect_live_scene`（编辑器实时状态 + 增量感知）

获取编辑器中当前正在编辑的场景的实时状态，包括未保存的修改。支持增量模式（`baseline_hash` 对比，只返回 changed/added/removed）。

Worker 首次调用获取完整结构和 hash，后续调用只获取变更。Worker 在自己的 context 中维护"心理模型"（上次完整结构 + 后续增量），始终知道当前状态但 token 消耗极低。

---

#### 工具 5：`get_scene_dependencies`（依赖图）

递归获取场景的所有依赖。支持反向依赖（`reverse: true`）用于影响分析——"如果我修改 player.tscn，哪些场景会受影响？"

---

#### 工具 6：`analyze_signal_flow`（信号流分析）

分析项目中信号的完整流向（声明 → 发射 → 连接 → 跨模块）。Branch 层协调接口契约的关键工具。支持按模块过滤。

---

#### 工具 7：`compare_scenes`（场景对比）

对比两个场景文件的差异（节点增删改、属性变更、脚本变更）。包含自动生成的 `summary` 一句话摘要。

---

#### 工具 8：`inspect_resource_interface`（资源接口提取）

提取任意 Resource 类型（包括用户自定义 `extends Resource`）的属性接口。配合 `configure_resource` 使用——先了解有哪些属性，再精确填写。

**输入**：`{"path": "res://scripts/wave_data.gd"}` 或 `{"path": "res://data/wave_3.tres"}`

**输出**：

```json
{
  "ok": true,
  "content": {
    "type": "resource_interface",
    "class_name": "WaveData",
    "extends": "Resource",
    "exports": [
      {"name": "wave_number", "type": "int", "default": 1},
      {"name": "enemy_count", "type": "int", "default": 5},
      {"name": "enemy_types", "type": "Array[String]", "default": ["scout"]},
      {"name": "spawn_interval", "type": "float", "default": 1.4}
    ],
    "observations": []
  }
}
```

**实现策略**：对 `.gd` 文件用正则提取 `@export` 属性。对已存在的 `.tres` 文件用 Godot 运行时反射 `res.get_property_list()` 获取完整属性列表（包括类型和当前值）。

与 `configure_resource` 构成**读写对称**对——感知工具读出结构，配置工具写入结构。

---

### 4.3 配置工具清单（4 个）

配置工具是感知工具的**反向操作**——感知工具把编辑器状态"读"成结构化 JSON，配置工具把结构化 JSON"写"成编辑器状态。读写对称。

LLM 全程不需要知道 .tscn / .tres / project.godot 的文本格式是什么样的——它只输出结构化意图，工具负责翻译成 Godot 的文件格式。

#### 工具 9：`build_scene`（场景创建）

接受完整的结构化场景描述，一轮完成所有创建操作。支持 sub_resource 定义和引用。

**输入参数**：

```json
{
  "path": "res://scenes/player.tscn",
  "scripts": [
    {"path": "res://scripts/player.gd", "content": "extends Area2D\n..."}
  ],
  "sub_resources": [
    {"id": "shape1", "type": "RectangleShape2D", "properties": {"size": [40, 50]}}
  ],
  "root": {
    "type": "Area2D", "name": "Player",
    "script_path": "res://scripts/player.gd",
    "properties": {"collision_layer": 1}
  },
  "children": [
    {"name": "CollisionShape2D", "type": "CollisionShape2D",
     "properties": {"shape": {"sub_resource": "shape1"}}},
    {"name": "WaveAnnounce", "type": "Label",
     "properties": {
       "theme_override_font_sizes/font_size": 56,
       "theme_override_colors/font_color": [1, 1, 0.4, 1]
     }}
  ],
  "unique_names": ["CollisionShape2D"],
  "open_in_editor": true
}
```

`scripts` 字段可选——如果提供了脚本内容，工具会先创建 .gd 文件再创建 .tscn，保证引用顺序正确。

**输出**：`{"type": "build_result", "nodes_created": 5, "properties_set": 4, "scripts_created": 1, "errors": [], "warnings": [...]}`

**实现**：`ClassDB.instantiate()` → `node.set()` → `node.owner = root`（关键！）→ `PackedScene.pack()` → `ResourceSaver.save()`。

---

#### 工具 10：`patch_scene`（场景批量修改）

对已有场景执行批量修改操作。这是最关键的配置工具——`build_scene` 解决"从零创建"，`patch_scene` 解决"修改已有"。

**输入参数**：

```json
{
  "path": "res://scenes/game.tscn",
  "operations": [
    {"op": "set", "node_path": "SpawnTimer",
     "properties": {"wait_time": 0.8, "autostart": true}},
    {"op": "add", "parent_path": "UI_Layer",
     "type": "Control", "name": "NewOverlay",
     "properties": {"anchors_preset": 15}},
    {"op": "add_sub_resource", "id": "new_shape",
     "type": "CircleShape2D", "properties": {"radius": 25}},
    {"op": "set", "node_path": "Boss/CollisionShape2D",
     "properties": {"shape": {"sub_resource": "new_shape"}}},
    {"op": "remove", "node_path": "OldDebugNode"},
    {"op": "connect_signal", "node_path": "SpawnTimer",
     "signal": "timeout", "target_path": ".",
     "method": "_on_spawn_timer_timeout"}
  ]
}
```

**输出**：逐条标注每个 operation 的成功/失败状态，支持 LLM 自我纠正：

```json
{
  "ok": true,
  "content": {
    "type": "patch_result",
    "operations_applied": 6,
    "results": [
      {"op": 0, "status": "ok", "detail": "SpawnTimer.wait_time = 0.8"},
      {"op": 5, "status": "ok", "detail": "SpawnTimer.timeout → ._on_spawn_timer_timeout"}
    ],
    "observations": ["_on_spawn_timer_timeout 方法在 game.gd 中不存在，需要创建"]
  }
}
```

**事务策略**：采用部分提交模式（非全量回滚）。操作前做一次备份（BackupManager），最坏情况下可整体回退。失败时返回有用的错误信息帮助 LLM 修正后重试。

---

#### 工具 11：`configure_resource`（通用资源读写）

创建或修改任意 `.tres` 资源文件。通用实现，不区分内置类型还是用户自定义 `extends Resource` 类型。

**输入参数**：

```json
{
  "action": "create_or_update",
  "path": "res://data/wave_3.tres",
  "type": "WaveData",
  "properties": {
    "wave_number": 3,
    "enemy_count": 12,
    "enemy_types": ["scout", "fighter", "tank"],
    "spawn_interval": 0.8
  }
}
```

**实现**：`ClassDB.instantiate(type)` 创建任意 Resource 类型 → `set()` 设属性 → `ResourceSaver.save()`。对已存在的文件：`ResourceLoader.load()` → 修改属性 → 重新保存。

**缓存注意**：修改共享资源时使用 `ResourceLoader.CACHE_MODE_IGNORE` 获取独立副本，避免影响其他引用者。

---

#### 工具 12：`configure_project`（项目配置）

读写 `project.godot` 中的项目设置、autoload、输入映射、主场景等。

**输入参数**：

```json
{
  "settings": {
    "display/window/size/viewport_width": 1920,
    "display/window/size/viewport_height": 1080
  },
  "autoloads": {
    "add": [{"name": "SignalBus", "path": "res://scripts/signal_bus.gd"}],
    "remove": []
  },
  "input_actions": {
    "add": [{"name": "dash", "events": [{"type": "key", "keycode": "KEY_L"}]}]
  },
  "main_scene": "res://scenes/main.tscn"
}
```

---

### 4.4 复合脚本工具（2 个）

#### 工具 13：`build_script`（脚本骨架构建）

接受结构化接口定义，一次性生成脚本骨架文件：

```json
{
  "path": "res://scripts/player.gd",
  "class_name": "Player",
  "extends": "Area2D",
  "signals": [{"name": "died", "params": []}],
  "exports": [{"name": "speed", "type": "float", "default": 420.0}],
  "methods": [
    {"name": "take_damage", "params": [{"name": "amount", "type": "int"}], "body": "pass # TODO"}
  ]
}
```

#### 工具 14：`update_script`（脚本更新，Legacy 桥接）

用于修改 .gd 文件的实现逻辑。这是唯一需要 LLM 生成完整代码文本的工具。

---

## 五、分层工具分配

### 5.1 Root Coordinator 工具（5-8 个）

| 工具 | 来源 | 用途 |
|------|------|------|
| `analyze_request` | Cortex 原生 | 分析用户需求，输出结构化任务分解和遍历策略决策 |
| `get_project_architecture` | 感知工具 | 获取项目架构概览 |
| `create_branch` | Cortex 原生 | 创建子系统分支节点 |
| `assign_task` | Cortex 原生 | 向分支分配任务工单 |
| `review_progress` | Cortex 原生 | 审查所有 Branch 的进度和交付物 |
| `get_module_interfaces` | 感知工具封装 | 批量获取多个模块的接口摘要 |

Root **不持有**任何文件操作、场景操作、脚本编辑工具。Root 不写代码，不操作编辑器。

### 5.2 Branch Node 工具（6-10 个）

| 工具 | 来源 | 用途 |
|------|------|------|
| `create_worker` | Cortex 原生 | 创建模块 Worker 节点 |
| `assign_worker_task` | Cortex 原生 | 向 Worker 分配具体任务 |
| `review_worker_output` | Cortex 原生 | 审查 Worker 交付物 |
| `define_contract` | Cortex 原生 | 定义模块间接口契约 |
| `validate_contracts` | Cortex 原生 | 验证所有接口契约一致性 |
| `inspect_scene_structured` | 感知工具 | 只读，用于审查 Worker 创建的场景 |
| `get_scene_dependencies` | 感知工具 | 分析模块依赖，评估修改影响范围 |
| `analyze_signal_flow` | 感知工具 | 验证信号一致性 |
| `extract_script_interface` | 感知工具 | 审查 Worker 生成的脚本接口 |
| `inspect_resource_interface` | 感知工具 | 审查自定义资源类型 |

Branch 持有感知工具的**只读子集**，用于审查 Worker 交付物和协调接口契约，但不持有写入工具。

### 5.3 Worker Node 工具（12-16 个）

| 工具 | 来源 | 用途 |
|------|------|------|
| `inspect_scene_structured` | 感知工具 | 结构化场景感知 |
| `inspect_live_scene` | 感知工具 | 编辑器实时状态 + 增量感知 |
| `inspect_resource_interface` | 感知工具 | 了解资源类型属性接口 |
| `extract_script_interface` | 感知工具 | 提取已有脚本的接口 |
| `build_scene` | 配置工具 | 结构化 JSON → 场景文件（批量创建） |
| `patch_scene` | 配置工具 | 结构化 JSON → 场景批量修改 |
| `configure_resource` | 配置工具 | 通用资源创建/修改 |
| `configure_project` | 配置工具 | 项目设置读写 |
| `build_script` | 复合工具 | 结构化接口定义 → 脚本骨架 |
| `update_script` | Legacy 桥接 | 编写/更新脚本逻辑 |
| `check_script_syntax` | Legacy 桥接 | 语法验证 |
| `screenshot_editor` | Legacy 桥接 | 视觉验证 |
| `run_scene_capture` | Legacy 桥接 | 运行验证 |

Worker 是唯一持有写入工具的层级。感知 + 配置工具提供完整的读写闭环。

---

## 六、Legacy 桥接策略

### 6.1 桥接层设计

Cortex 的 Worker 层通过桥接层复用 Legacy 的工具实现，不重写底层能力：

```
Worker Node → tool_executor.gd → 调用 Legacy 工具模块
                                      │
                                      ▼
                              addons/dotagent/tools/*.gd
```

### 6.2 新增工具与 Legacy 的关系

| 类别 | 处理方式 |
|------|---------|
| 感知工具（8 个） | 新增 `perception_tools.gd`，继承 `tool_base.gd` |
| 配置工具（4 个） | 新增 `configuration_tools.gd`，继承 `tool_base.gd` |
| 复合工具（2 个） | 新增 `composite_tools.gd`，内部调用 Legacy 的 scene_tools + script_tools |
| Cortex 原生工具 | 在 `addons/dotagent_cortex/` 内独立实现 |
| Legacy 工具（复用） | 通过 `tool_executor.gd` 桥接调用 |

新增工具模块同时注册到 Legacy 的 `tool_registry.gd`，在 Legacy 模式下也可使用。

### 6.3 对 `_ok()` 的扩展

```gdscript
# tool_base.gd 新增
func _ok_json(data: Dictionary) -> Dictionary:
    return {"ok": true, "content": JSON.stringify(data, "\t")}

func _err_json(error: String, data: Dictionary = {}) -> Dictionary:
    data["error"] = error
    return {"ok": false, "content": JSON.stringify(data, "\t")}
```

---

## 七、实现陷阱与应对

以下是基于 Legacy 源码分析和 Godot 4.x 特性识别的关键实现陷阱，必须在开发第一天就处理好。

### 7.1 `EditorFileSystem.scan()` 杀死协程（致命）

**问题**：`tool_base.gd` 第 134-136 行明确记录：`EditorFileSystem.scan()` 会触发全局脚本重载，杀死所有 GDScript 协程。

**影响**：`build_scene` 创建文件后如果立即 scan，会中断正在执行的 Worker 工具链。

**应对**：批量工具内部不做 scan。整个 Worker 工具链执行完毕后，由 `worker_executor.gd` 统一调一次 scan。

### 7.2 节点所有权（致命）

**问题**：Godot 的 `PackedScene.pack()` 只保存 `owner` 为场景根节点（或其子节点）的节点。如果 `build_scene` 创建节点但忘记设置 owner，保存的 .tscn 会是空的。

**应对**：每个 `add_child()` 之后必须设置 `node.owner = root`。递归子节点同样需要设置。Legacy 的 `_reown()` 辅助函数已有实现。

### 7.3 资源缓存污染（致命）

**问题**：`ResourceLoader.load()` 走缓存。修改一个被多场景共享的资源会影响所有引用者。

**应对**：对要修改的资源使用 `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)` 获取独立副本，或修改前检查引用计数，共享资源先 `.duplicate()` 再修改。

### 7.4 文件创建顺序依赖（致命）

**问题**：如果先创建 .tscn 引用一个还不存在的 .gd，Godot 报错。反过来先创建 .gd 但没 scan，.tscn 的 ext_resource 找不到 UID。

**应对**：`build_scene` 的 `scripts` 字段支持同时创建脚本。执行顺序：先创建 .gd → 再创建 .tres → 最后创建 .tscn → 最后统一 scan。

### 7.5 LLM 输出 JSON 验证（重要）

**问题**：LLM 可能输出不存在的类型名、不存在的属性名、类型错误、格式错误。

**应对**：每个工具执行前必须有验证层：`ClassDB.class_exists(type)` 检查类型 → `node.get_property_list()` 检查属性 → 类型匹配检查。验证失败时返回**有帮助的错误信息**："Unknown property 'speed' on Area2D. Available properties: position, rotation, scale, ..."

### 7.6 批量操作事务性（重要）

**问题**：`patch_scene` 有 N 个 operation，如果第 K 个失败了怎么办？

**应对**：采用部分提交模式。操作前做一次备份（BackupManager），逐条执行并记录结果。失败的 operation 返回详细错误信息，LLM 可修正后重试。最坏情况通过备份整体回退。

### 7.7 `_parse_property_value` 类型覆盖不足（重要）

**问题**：Legacy 的 `_parse_property_value` 只处理 Color、Vector2、Vector3、Rect2。缺少 Transform2D/3D、NodePath、Array、Dictionary、PackedXxxArray、enum 值。

**应对**：扩展 `_parse_property_value`，增加以下类型支持：
- `Array`：JSON array → Godot Array
- `Dictionary`：JSON object → Godot Dictionary（非 Color/Vector 判定）
- `NodePath`：string → NodePath()
- `PackedStringArray`：string[] → PackedStringArray
- `PackedInt32Array` / `PackedFloat32Array`：number[] → 对应类型
- enum 值：int → 直接使用（Godot 内部以 int 存储 enum）

### 7.8 编辑器状态与磁盘状态不一致（边界）

**问题**：用户在编辑器里修改了场景但没保存。写入工具操作的是磁盘旧版本。

**应对**：写入类工具执行前检查 `EditorInterface.get_edited_scene_root()` 是否有未保存修改。有则先自动保存（`_emit_change()`），或在 observations 中标注提醒。

### 7.9 脚本重编译连锁反应（边界）

**问题**：写入有 `class_name` 的 .gd 文件会触发全局脚本重编译，可能中断 @tool 脚本。

**应对**：与 scan 策略相同——`build_script` / `update_script` 写入后不立即触发重编译，由 Worker 执行器在所有工具调用完成后统一处理文件刷新。

### 7.10 observations 检查规则可扩展（设计）

**问题**：感知工具的 observations 检查规则会随项目增多而增长，不应硬编码。

**应对**：设计规则注册机制，从项目级配置文件 `.dotagent_rules.json` 加载自定义检查规则。内置规则（引用资源不存在、属性为 null、碰撞层为 0 等）作为默认集，用户可追加项目特定规则。

---

## 八、GNM 演进路线（Godot Node Model）

### 8.1 Worker 工作分类

Worker 节点的完整工作可拆分为四类任务，并非全部需要 LLM：

| 任务类型 | 是否需要 LLM | 说明 |
|---------|-------------|------|
| 场景/资源配置生成 | 不需要 | 结构化输入 → 结构化输出，规则引擎就够 |
| GDScript 代码生成 | 需要 | 逻辑创造，LLM 的核心价值 |
| 接口一致性验证 | 不需要 | 比对两个 JSON schema，确定性代码 |
| 需求理解与设计决策 | 需要 | "Dash 冷却 0.8s 够不够"需要推理 |

当工具封装足够完善时，AI 只做决策，工具做行动和验证。这为未来用更小的专用模型替代 Worker 层的通用 LLM 提供了可能。

### 8.2 混合架构愿景

```
TaskTicket
    │
    ▼
┌─────────────────────┐
│ 规划器（轻量 LLM）   │  "需要哪些节点？什么信号？什么接口？"
│ 7B 代码模型          │  输入：TaskTicket + 接口摘要
│                     │  输出：结构化配置方案
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 配置引擎（规则）     │  结构化方案 → .tscn / .tres / project.godot
│ 纯代码，零 LLM      │  确定性，100% 正确
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 代码生成器（轻量 LLM）│ 生成每个节点的 GDScript
│ 7B 代码模型          │ 基于模板 + TaskTicket 具体要求
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ 验证器（规则）       │ 语法检查 + 接口一致性 + 运行验证
│ 纯代码，零 LLM      │ 确定性
└─────────────────────┘
```

### 8.3 演进阶段

**短期（当前）**：用 LLM 做全部 Worker 工作，通过 Cortex 架构控制 context 大小。最可行的方案。

**中期（积累足够数据后）**：把配置引擎和验证器抽出来做成纯规则系统，Worker 的 LLM 从旗舰级降级到 7B 代码模型。

**长期（GDScript 训练数据充足后）**：微调一个专用的 GNM（Godot Node Model），替代 Worker 层的所有 LLM 调用。训练数据来源：Legacy DotAgent 的 `sessions/` 目录中的对话历史（输入是 TaskTicket + 场景状态，输出是代码 + 配置）。

**核心瓶颈**：GDScript 训练数据不足。GDScript 不像 Python/JavaScript 有海量开源数据。需要通过 Legacy DotAgent 的持续使用逐步积累。

---

## 九、实现路线

### Phase 0：基础设施（第 1 周）

**目标**：搭建 Cortex 的核心调度框架和 HTTP 连接池。

| 组件 | 文件 | 工作量 |
|------|------|--------|
| HTTP 连接池 | `http/http_client_pool.gd` | ~200 行 |
| 请求槽状态机 | `http/request_slot.gd` | ~300 行 |
| SSE 流式解析器 | `http/stream_parser.gd` | ~200 行 |
| 节点调度器 | `core/node_scheduler.gd` | ~300 行 |
| Worker 执行器 | `core/worker_executor.gd` | ~400 行 |
| 上下文管理器 | `context/context_manager.gd` | ~200 行 |
| 消息构建器 | `context/message_builder.gd` | ~150 行 |

**里程碑**：能够创建一个 Worker 节点，发送一条 LLM 请求，接收 SSE 流式响应，执行一个 Legacy 工具，返回结果。

### Phase 1：感知工具层 + 配置工具层（第 2-3 周）

**目标**：实现 8 个感知工具 + 4 个配置工具 + 2 个复合工具。这是 Cortex 的基础设施。

| 组件 | 文件 | 工作量 | 优先级 |
|------|------|--------|--------|
| 脚本接口提取 | `perception_tools.gd` → `extract_script_interface` | ~250 行 | P0 |
| 结构化场景感知 | `perception_tools.gd` → `inspect_scene_structured` | ~350 行 | P0 |
| 项目架构概览 | `perception_tools.gd` → `get_project_architecture` | ~350 行 | P0 |
| 编辑器实时状态 | `perception_tools.gd` → `inspect_live_scene` | ~200 行 | P0 |
| 资源接口提取 | `perception_tools.gd` → `inspect_resource_interface` | ~150 行 | P0 |
| 场景依赖图 | `perception_tools.gd` → `get_scene_dependencies` | ~150 行 | P1 |
| 信号流分析 | `perception_tools.gd` → `analyze_signal_flow` | ~250 行 | P1 |
| 场景对比 | `perception_tools.gd` → `compare_scenes` | ~200 行 | P2 |
| 场景批量创建 | `configuration_tools.gd` → `build_scene` | ~400 行 | P0 |
| 场景批量修改 | `configuration_tools.gd` → `patch_scene` | ~350 行 | P0 |
| 通用资源读写 | `configuration_tools.gd` → `configure_resource` | ~200 行 | P0 |
| 项目配置 | `configuration_tools.gd` → `configure_project` | ~250 行 | P0 |
| 脚本骨架构建 | `composite_tools.gd` → `build_script` | ~200 行 | P0 |
| `_parse_property_value` 扩展 | `tool_base.gd` 修改 | ~100 行 | P0 |
| observations 规则注册 | `.dotagent_rules.json` 机制 | ~100 行 | P1 |

**里程碑**：所有工具在 Legacy 模式下可独立使用，验证输出质量和覆盖完整性。

### Phase 2：节点实现（第 4 周）

**目标**：实现 Root / Branch / Worker 三层节点逻辑。

| 组件 | 文件 | 工作量 |
|------|------|--------|
| Root 协调器 | `nodes/root_coordinator.gd` | ~400 行 |
| Branch 节点 | `nodes/branch_node.gd` | ~350 行 |
| Worker 节点 | `nodes/worker_node.gd` | ~300 行 |
| 工具定义加载器 | `tools/tool_loader.gd` | ~100 行 |
| 工具执行代理 | `tools/tool_executor.gd` | ~200 行 |
| 工具定义文件 | `tools/definitions/*.json` | 3 个 JSON |

**里程碑**：用一个简单指令走通 Root → Branch → Worker 全流程。

### Phase 3：知识库与接口契约（第 5 周）

| 组件 | 文件 | 工作量 |
|------|------|--------|
| 知识库管理器 | `knowledge/knowledge_base.gd` | ~300 行 |
| 知识条目结构 | `knowledge/knowledge_entry.gd` | ~100 行 |
| 冲突检测器 | `knowledge/conflict_resolver.gd` | ~150 行 |
| 信号总线管理器 | `signal/signal_bus_manager.gd` | ~200 行 |

**里程碑**：SKELETON_FIRST 遍历策略可执行。

### Phase 4：System Prompts 与 UI（第 6 周）

| 组件 | 文件 | 工作量 |
|------|------|--------|
| Root / Branch / Worker Prompt | `prompts/*.md` | 3 × ~200 行 |
| Skills（遍历策略、2D/3D/UI 游戏） | `prompts/skills/*.md` | 4 × ~100 行 |
| 主 Dock + Activity 面板 | `ui/*.{gd,tscn}` | ~700 行 |

**里程碑**：用户可在 Godot 编辑器中通过 Cortex Dock 发送请求。

### Phase 5：集成测试与优化（第 7 周）

1. 使用 Cortex 重新创建 Star Hunter 的 Player 模块，对比 Legacy 的 context 消耗和轮次数
2. 使用 SKELETON_FIRST 策略创建一个新的 3 模块小游戏骨架
3. 验证感知工具的输出质量和 token 效率
4. 验证配置工具的覆盖完整性（无死角）
5. 压力测试：模拟 50+ 脚本项目规模的 context 表现

---

## 十、文件目录结构

```
res://
├── addons/
│   ├── dotagent/                          # Legacy（保留，不改动）
│   │   ├── tools/
│   │   │   ├── perception_tools.gd        # ★ 新增：感知工具（8 个）
│   │   │   ├── configuration_tools.gd     # ★ 新增：配置工具（4 个）
│   │   │   ├── composite_tools.gd         # ★ 新增：复合工具（2 个）
│   │   │   └── ... (现有工具不变)
│   │   └── ...
│   │
│   └── dotagent_cortex/                   # Cortex 新架构
│       ├── plugin.cfg
│       ├── plugin.gd
│       ├── core/
│       │   ├── node_scheduler.gd
│       │   ├── worker_executor.gd
│       │   └── traverser.gd
│       ├── http/
│       │   ├── http_client_pool.gd
│       │   ├── request_slot.gd
│       │   └── stream_parser.gd
│       ├── nodes/
│       │   ├── root_coordinator.gd
│       │   ├── branch_node.gd
│       │   └── worker_node.gd
│       ├── context/
│       │   ├── context_manager.gd
│       │   └── message_builder.gd
│       ├── knowledge/
│       │   ├── knowledge_base.gd
│       │   ├── knowledge_entry.gd
│       │   └── conflict_resolver.gd
│       ├── signal/
│       │   └── signal_bus_manager.gd
│       ├── tools/
│       │   ├── tool_loader.gd
│       │   ├── tool_executor.gd
│       │   └── definitions/
│       │       ├── root_tools.json
│       │       ├── branch_tools.json
│       │       └── worker_tools.json
│       ├── prompts/
│       │   ├── root_prompt.md
│       │   ├── branch_prompt.md
│       │   ├── worker_prompt.md
│       │   └── skills/
│       ├── ui/
│       │   ├── dock.gd + dock.tscn
│       │   └── activity_panel.gd + activity_panel.tscn
│       ├── config/
│       │   └── config_manager.gd          # 扩展：支持分层模型配置
│       └── persistence/
│
├── dotagent_cortex/                       # 项目级数据
│   ├── knowledge/
│   └── sessions/
│
└── .dotagent_rules.json                   # ★ 新增：自定义 observations 检查规则
```

---

## 十一、验证标准

### 11.1 感知工具验证

1. **输出可解析**：返回标准 JSON，LLM 可直接提取信息
2. **信息密度**：同等信息量下，token 消耗不超过文本方式的 20%
3. **聚焦查询**：支持参数指定查询范围，避免全量返回
4. **主动标注**：`observations` 字段标注异常，降低 LLM 验证负担
5. **增量模式**：支持只返回变更部分（`inspect_live_scene`）

### 11.2 配置工具验证

1. **覆盖完整性**：所有 Godot 文件类型（.tscn/.tres/project.godot）均可通过工具配置，无死角
2. **自定义资源**：`configure_resource` 能正确处理任意 `extends Resource` 自定义类型
3. **批量效率**：`build_scene` / `patch_scene` 将场景操作的 LLM 调用轮次从 10-16 降低到 1-2
4. **事务安全**：`patch_scene` 部分提交 + 备份回退，不丢数据

### 11.3 端到端验证

1. **context 效率**：Worker 执行单模块任务的 context 峰值不超过 5K tokens
2. **错误隔离**：故意在 Player Worker 中引入错误，验证不影响 Enemy Worker
3. **接口一致性**：SKELETON_FIRST 阶段结束后，所有模块接口无冲突
4. **模型分层**：Root 使用旗舰模型，Worker 使用轻量模型，全流程无异常
5. **无文本读取**：全流程中 Worker 不调用 `read_resource_as_text` 或 `read_file` 读取非 .gd 文件

---

## 十二、风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 多 LLM 请求延迟累积 | 用户等待时间变长 | 串行模式下 RequestSlot 复用；Worker 用轻量模型降低单次延迟 |
| 感知工具输出质量不稳定 | Worker 基于错误数据做决策 | 严格单元测试 + 已知场景的 golden file 对比 |
| 配置工具覆盖不完整 | Worker 遇到死角无法完成任务 | Phase 1 结束时做覆盖审计，遗漏类型补专用工具 |
| 接口契约过于复杂 | 小项目开发效率反降 | 从简单项目开始；DEPTH_FIRST 模式不走契约阶段 |
| Worker 知识不足 | 需要跨模块信息时无法获取 | KnowledgeBase 查询；Worker 向 Parent 申请 |
| Legacy 工具副作用 | 桥接调用触发意外编辑器操作 | 危险工具（`execute_gdscript`）不暴露给 Worker |
| scan() / 脚本重编译杀协程 | Worker 工具链中断 | 所有文件刷新延迟到工具链完成后统一执行 |
| 资源缓存污染 | 修改共享资源影响其他场景 | CACHE_MODE_IGNORE + .duplicate() |
