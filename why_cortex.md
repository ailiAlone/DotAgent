# 为什么需要升级到 DotAgent Cortex

**日期**: 2026-07-23
**基于**: Legacy DotAgent v0.1.1 源码分析 + Star Hunter 项目实测数据

---

## 一、Legacy DotAgent 的现状

### 1.1 架构概览

```
用户输入
    │
    ▼
┌─────────────────────────────────────────────┐
│  单个 LLM（MiniMax-M3, 128K context）        │
│  ├── System Prompt（~2K tokens）             │
│  ├── 61 个工具定义（~6K tokens）              │
│  ├── 动态上下文（当前场景树 + 选中节点）        │
│  ├── 完整对话历史（无压缩）                    │
│  └── ReAct 循环（每轮发送全部 messages）       │
└─────────────────────────────────────────────┘
    │
    ▼
  61 个工具（8 个模块）
  file / node_query / scene / script / script_file
  exec / screenshot / project
```

这是一个**星型架构**：单个 LLM 作为中心，辐射 61 个工具。所有请求、所有上下文、所有工具定义都在同一个 128K 窗口中处理。

### 1.2 Star Hunter 项目规模

| 指标 | 数值 |
|------|------|
| 脚本文件 | 21 个 |
| 代码总行数 | 2,371 行 |
| 场景文件 | 18 个 |
| 最大单文件 | game.gd (528 行) |
| 敌人类型 | 6 种 + Boss 3 阶段 |
| 信号声明 | ~15 个跨脚本 |
| Autoload | 2 个 (GameManager, AudioManager) |

这是一个相对简单的 2D 太空射击游戏。但即便如此，Legacy DotAgent 在开发过程中已经遇到了多个瓶颈。

---

## 二、六大架构瓶颈

### 2.1 上下文爆炸（Context Window Exhaustion）

**问题**：每一轮 ReAct 循环，LLM 都要重新处理**全部历史消息 + 全部工具定义 + 动态上下文**。

**实测数据**（基于 `context_builder.gd` 的估算逻辑）：

```
每轮 LLM 请求的 context 消耗：

System Prompt         ~2K tokens（静态提示 + 动态上下文 + 技能）
工具定义（61个）       ~6K tokens（JSON Schema，description + parameters）
当前场景树摘要         ~0.5K tokens（_summarize_scene, max_depth=1）
对话历史              ~5-80K tokens（随对话增长，无压缩）
  └── tool 结果截断至 1000 chars/条
  └── 但 assistant 消息全量保留（含思考链）
─────────────────────────────
总计                  ~13K-90K+ tokens（取决于对话长度）
```

**关键发现**：`message_builder.gd` 的 `build()` 方法**不压缩对话内消息**，只截断大 tool 结果到 1000 chars。一旦对话超过 20 轮（包含多次工具调用），context 轻松突破 50K。

**对 128K 窗口的影响**：
- 短对话（< 10 轮）：~20K tokens，充裕
- 中对话（10-30 轮）：~40-60K tokens，开始紧张
- 长对话（30+ 轮）：~80-100K tokens，频繁触发 76% 压缩阈值
- 一旦触发压缩，旧对话被替换为摘要，**LLM 丢失具体实现细节**

**这意味着**：开发一个 Hollow Knight 级别的游戏（50+ 脚本，30+ 场景，复杂状态机），Legacy 架构会在早期就耗尽 context。

---

### 2.2 工具选择瘫痪（Tool Selection Paralysis）

**问题**：61 个工具全部暴露给 LLM，每轮都要从 61 个选项中做选择。

**实测表现**：

当 LLM 需要"读取 player.gd 的接口"时，它面对的工具列表包括：
```
read_script           — 读取脚本文件（纯文本）
read_resource_as_text — 读取资源文件（纯文本）
read_multiple_files   — 批量读取
read_file_tail        — 读取文件尾部
get_node_properties   — 获取节点属性
get_node              — 获取节点信息
peek_scene            — 场景预览
describe_scene        — 场景描述（SCD 格式）
get_script_references — 脚本引用
...还有 52 个工具
```

**LLM 的典型行为**：
1. 选择 `read_script`（正确），但输出是纯文本，需要后续处理
2. 或者选择 `get_node_properties`（错误，应该用 `read_script`）
3. 或者同时调用多个工具"探索"，浪费 3-5 轮

**根本原因**：工具越多，LLM 的选择空间越大，错误选择的概率越高。这是 Transformer 注意力机制的固有限制——61 个候选的 softmax 分布比 8 个候选的分布更"平坦"，更难收敛到正确选项。

**Cortex 的解决方式**：Worker 层只暴露 8-12 个相关工具，从 61 选 1 降低到 10 选 1。

---

### 2.3 单一上下文无法分离知识域

**问题**：Legacy 只有一个 LLM 实例，所有模块的知识都在同一个对话历史中。

**实际场景**：当你在开发 Player 模块时，对话历史中可能混入了：
- 之前 Enemy 模块的实现讨论
- UI 系统的修改记录
- 音频系统的调试输出

当 LLM 需要为 Player 添加新逻辑时，它的注意力被这些**无关上下文**分散。更糟糕的是，如果 Player 和 Enemy 有相似但不同的实现（比如都用 `_draw()` 绘制，但绘制内容完全不同），LLM 容易**混淆两者的具体细节**。

**Star Hunter 中的具体例子**：
- `player.gd` 和 `enemy.gd` 都有 `_draw()` 方法
- 都有 `signal died` / `signal killed`
- 都有 `hp` / `max_hp` / `score_value` 变量
- 都通过 `_gm()` 和 `_am()` 访问 GameManager/AudioManager

在单一上下文中，LLM 很容易把 Player 的 `died` 信号和 Enemy 的 `killed` 信号搞混，或者把 Enemy 的 `setup_by_type()` 逻辑误用到 Player 上。

**Cortex 的解决方式**：信息隔离三原则——每个 Worker 只持有自己模块的知识，同级节点不可直接通信。

---

### 2.4 错误传播无边界（Error Propagation Without Isolation）

**问题**：Legacy 的单个 LLM 操作整个项目，一次错误可能影响所有文件。

**实际场景**：假设 LLM 在修改 `game.gd` 时产生幻觉，错误地删除了 `spawn_timer` 的引用。这个错误会：
1. 导致 `game.gd` 编译失败
2. 所有依赖 `game.gd` 的场景（game.tscn, main.tscn）都无法正常运行
3. 如果 LLM 继续在此基础上修改其他文件，错误会**级联传播**

**Legacy 的保护机制**：
- `backup_manager.gd` 在每次写操作前备份文件
- `undo_last` 工具可以撤销最后一次操作
- `check_script_syntax` 验证语法

**但这些只是事后补救**。在 Legacy 架构中，LLM 在犯错的那一刻，整个项目的状态已经被破坏了。对于大型项目（50+ 文件），恢复成本极高。

**Cortex 的解决方式**：错误只影响当前 Worker 的模块。Player Worker 犯错不会破坏 Enemy Worker 的文件。父节点审查交付物后才合并。

---

### 2.5 无法并行处理多模块

**问题**：Legacy 是串行执行——一个任务完成后才能开始下一个。

**实际场景**：开发一个 2D 平台游戏，需要同时实现：
- Player（移动、跳跃、攻击）
- Enemy（AI、巡逻、攻击模式）
- Level（地形、机关、道具）
- UI（HUD、菜单、对话框）

在 Legacy 中，这些模块必须**逐个开发**。即使它们之间相对独立，LLM 也只能一个接一个地处理。每完成一个模块，对话历史就增长一大截，等到开发第四个模块时，第一个模块的具体细节已经被压缩或遗忘。

**Cortex 的解决方式**：
- 4 个 Branch 节点并行管理 4 个子系统
- 每个 Branch 下的 Worker 节点独立工作
- 父节点协调接口契约，确保模块间一致性
- 即使串行执行 Worker，每个 Worker 的 context 也是**干净的**（只有自己的模块知识）

---

### 2.6 缺乏架构级感知（No Architectural Awareness）

**问题**：Legacy 的工具都是"文件级"或"节点级"操作，没有"项目级"感知。

**实际场景**：当用户说"做一个 2D 银河恶魔城"，Legacy 的 LLM 需要：
1. 先理解"银河恶魔城"是什么（依赖 system prompt 中的知识）
2. 手动遍历文件列表，推断项目结构
3. 从脚本内容中反推信号流向和依赖关系
4. 在脑中维护整个项目的"架构图"

这个过程极其低效且容易出错。LLM 本质上是在用**文本理解能力**去模拟**架构理解能力**。

**Cortex 的解决方式**：
- Root Coordinator 持有项目高层架构摘要（模块列表 + 依赖关系）
- Branch 节点持有子系统级知识（模块接口 + 契约）
- Worker 节点持有模块级知识（具体实现细节）
- 新增结构化工具（`get_project_architecture` / `extract_script_interface` / `inspect_scene_structured`）提供架构级感知

---

## 三、量化对比：Legacy vs Cortex

### 3.1 单模块开发效率

**场景**：为 Player 添加 Dash 功能

| 维度 | Legacy | Cortex (Player Worker) |
|------|--------|----------------------|
| Context 起始大小 | ~20K（全项目 + 61 工具） | ~3K（Player 知识 + 8 工具） |
| 工具选择空间 | 61 选 1 | 8 选 1 |
| 无关上下文 | Enemy/UI/Audio 历史 | 无（隔离） |
| 错误影响范围 | 全项目 | 仅 Player 模块 |
| 可用 context 余量 | ~108K（已用 15%） | ~125K（已用 2%） |

### 3.2 多模块开发效率

**场景**：从零开始做一个 2D 银河恶魔城（Player + Enemy + Level + UI + Audio）

| 维度 | Legacy | Cortex |
|------|--------|--------|
| 开发模式 | 串行（逐个模块） | 并行/分层（Branch + Worker） |
| 第 5 个模块的 context | ~80K（前 4 个模块历史） | ~3K（干净 Worker） |
| 接口一致性 | LLM 靠记忆维护 | Branch 显式锁定契约 |
| 总 LLM 请求数 | ~200+（串行，每轮 1 个） | ~60-80（分层，可并行） |
| 错误恢复成本 | 高（可能级联） | 低（隔离到 Worker） |

### 3.3 项目规模天花板

| 项目规模 | Legacy 表现 | Cortex 预期 |
|----------|------------|------------|
| 小游戏（5-10 脚本） | ✅ 流畅 | ✅ 流畅（无必要） |
| 中等（20-30 脚本） | ⚠️ 后半段 context 压力大 | ✅ 稳定 |
| 大型（50-100 脚本） | ❌ 频繁压缩，丢失细节 | ✅ 每个 Worker 独立处理 |
| 超大型（100+ 脚本） | ❌ 无法维护全局一致性 | ⚠️ 需要更多 Branch 节点 |

---

## 四、Cortex 架构的核心优势

### 4.1 从"全能大脑"到"分工皮层"

Legacy 试图用一个 LLM 做所有事情：理解需求、分解任务、实现逻辑、验证结果。这就像让一个人同时当项目经理、架构师、程序员、测试员。

Cortex 将这些职责分配到不同层级：

```
Root Coordinator（项目经理）
  → 理解需求，分解任务，决定遍历策略
  → 不写代码，不操作文件

Branch Node（子系统架构师）
  → 协调模块间接口，审查 Worker 交付物
  → 不写代码，但理解架构

Worker Node（模块程序员）
  → 实现具体逻辑，操作场景/脚本/节点
  → 只关注自己的模块
```

### 4.2 信息隔离三原则

1. **每个节点只对自己和直属上下节点负责**
2. **每个节点只能获取：自己的信息 + 上级下达的任务 + 下级反馈的汇报**
3. **同级节点不可直接通信**，跨模块需求通过 Parent 中转

这三条规则确保了：
- Player Worker 不会被 Enemy Worker 的实现细节干扰
- UI Branch 不需要知道 Audio Branch 的内部工具
- Root 不需要知道每个 Worker 的具体代码（只看接口契约）

### 4.3 动态按需生长

Worker 在开发过程中如果发现子任务过于复杂（比如 Player 的移动和射击系统都很庞大），可以向 Parent 申请创建子 Worker。这种"生长"是按需的，不是预先分配的。

### 4.4 接口契约驱动开发

Cortex 的 SKELETON_FIRST 遍历策略：
1. 先创建所有模块的空壳（空场景 + 空脚本 + 接口签名）
2. Branch 收集所有接口定义，确认一致性
3. 锁定契约（信号声明 + public 方法签名）
4. 然后逐个 Worker 填充实现

这确保了：即使模块间有依赖，它们的接口在开发早期就已经对齐。不会出现"Player 发射了一个 Enemy 没定义的信号"这种低级错误。

---

## 五、迁移成本与收益

### 5.1 开发成本

| 组件 | 工作量 | 优先级 |
|------|--------|--------|
| 感知工具层（7 个新工具） | ~1500 行 GDScript | P0（Cortex 依赖） |
| HTTP 连接池 + 请求槽 | ~800 行 GDScript | P0 |
| 节点调度器 | ~500 行 GDScript | P0 |
| Worker 执行器 | ~600 行 GDScript | P0 |
| Root/Branch/Worker 节点实现 | ~1200 行 GDScript | P1 |
| 知识库系统 | ~400 行 GDScript | P1 |
| 信号总线管理器 | ~300 行 GDScript | P2 |
| UI（Dock + Activity Panel） | ~800 行 GDScript + .tscn | P2 |
| System Prompts + Skills | ~5 个 .md 文件 | P1 |

**总计**：~6100 行 GDScript，预计 2-3 周（假设每天 4-6 小时开发时间）。

### 5.2 收益预期

1. **Context 效率提升 10 倍+**：Worker 层从 20K context 降低到 2-3K
2. **工具选择准确率提升**：从 61 选 1 降低到 8-12 选 1
3. **支持大型项目**：50-100 脚本的银河恶魔城级别游戏
4. **错误隔离**：单模块错误不影响全局
5. **接口一致性**：显式契约机制，不依赖 LLM 记忆
6. **知识积累**：每个 Worker 的知识沉淀到知识库，跨会话复用

### 5.3 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 多 LLM 请求的延迟累积 | 串行模式下 RequestSlot 复用，不增加并发连接 |
| 接口契约过于复杂 | 从简单项目开始，逐步增加模块数 |
| Worker 知识不足 | 通过 KnowledgeBase 查询跨模块知识 |
| 调试困难 | Activity Panel 实时显示所有节点状态 |

---

## 六、结论

Legacy DotAgent 是一个**优秀的原型验证工具**，适合快速开发小游戏（5-20 脚本）。但它的单中心架构在面对中等规模以上项目时，会遇到三个根本性瓶颈：

1. **Context 爆炸**：对话历史 + 工具定义 + 动态上下文消耗 128K 窗口
2. **注意力分散**：61 个工具 + 多模块混合上下文导致选择错误
3. **错误无边界**：一次幻觉可能破坏整个项目

DotAgent Cortex 通过**树状多智能体架构**解决这些问题：
- 信息隔离确保每个 Worker 只关注自己的模块
- 分层工具减少选择空间
- 接口契约机制确保模块间一致性
- 知识库积累跨会话知识

**升级不是"锦上添花"，而是"规模化的必要条件"**。如果目标是支持 Hollow Knight / Celeste 级别的游戏开发，Legacy 架构在技术上无法支撑。Cortex 是唯一可行的路径。
