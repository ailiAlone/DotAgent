# DotAgent Banyan — 架构设计文档

## 一、核心理念

**自组织多智能体。树即本体。**

Agent Tree 不是一个可视化工具，它是 Agent 本身。树是持久的、活的、跨对话持续生长的结构。每次用户任务都是一次水流经这棵树 — 有的任务流经已有节点（修改已知模块），有的任务让树长出新枝（新增子系统）。

没有协调者、没有中层管理、没有叶子节点。每个节点都是**同构的** — 同一个类、同一套行为、同一个决策逻辑。

## 二、唯一行为

每个节点在 ReAct 循环中执行任务时，遵循唯一规则：

> **遇到"长"、"难"、"复杂"的子问题 → 生成子节点，下派任务。**
> **否则 → 自己继续做。**

这是微观判断，不是宏观规划。没有节点在开始前做"复杂度评估"来决定整体策略。每个节点只在**执行过程中**、**遇到具体问题时**，决定是否下派。

**任务分解 = 上下文管理。** 同一个行为解决了两个问题：复杂任务被拆分，同时上下文自然分流。不存在上下文溢出 — 每个节点只装自己那一层问题。因此不需要上下文压缩、token 计数、SessionMemory 等传统 agent 机制。

## 三、树的生长

```
第1天: "了解项目"
       Root
       └─ ProjectExplorer

第2天: "加护盾系统"
       Root
       ├─ ProjectExplorer
       ├─ Player_Shield
       ├─ UI_ShieldBar
       └─ Audio_Shield

第3天: "护盾冷却改成5秒"          ← 流经已有节点
       Root
       ├─ ProjectExplorer
       ├─ Player_Shield（更新知识）
       ├─ UI_ShieldBar
       └─ Audio_Shield

第4天: "加敌人AI系统"              ← 长出新枝
       Root
       ├─ ...（已有节点）
       ├─ Enemy_AI
       ├─ Enemy_Patrol
       └─ Enemy_Combat
```

树深度不固定，宽度不固定，结构不预设。完全由执行中的微观决策决定。

## 四、节点 = 上下文

节点不是一个"运行中的进程"。节点就是它持有的上下文本身。持久化到磁盘的是这个上下文，加载回来时节点就"醒"了。

### 节点上下文结构

```
节点上下文 = {
  // 身份
  node_id: "Player_Shield"
  parent_id: "Root"

  // 领域知识（节点的核心价值 — 蒸馏后的理解，不是原始日志）
  domain_knowledge: "护盾系统: 持续3秒, 冷却5秒,
                     player.gd的_shield_active逻辑,
                     依赖 signal shield_depleted"

  // 管辖范围
  managed_files: ["player.gd", "shield_effect.gd"]
  managed_nodes: ["Player", "ShieldEffect"]       // Godot 场景节点

  // 子节点摘要
  children: [
    { id: "Shield_VFX", status: "completed", summary: "护盾粒子效果" },
    { id: "Shield_SFX", status: "completed", summary: "护盾音效" }
  ]

  // 开发记录（精简版）
  history: [
    "Day1: 实现护盾基础逻辑 (3 files)",
    "Day3: 冷却时间从8秒改为5秒 (1 file)"
  ]
}
```

**不包含：**
- ❌ 原始 LLM 对话记录（知识摘要足够）
- ❌ 工具调用详细参数（一次性信息）
- ❌ 文件完整内容（只记路径，需要时现读）

原则：蒸馏后的知识，不是原始日志。就像工程师脑子里记的是"护盾怎么工作"，不是"敲的每一行代码"。

## 五、持久化

两样东西都需要持久化：

1. **对话历史** — 开发者的工作记录（"我说了什么、Agent 做了什么"）
2. **Agent Tree** — 树结构 + 每个节点的上下文（Agent 本体）

对话是流水，树是河床。水流过了但留下了痕迹（树长了新枝或节点更新了知识）。

## 六、根节点与 LLM

- **根节点是常驻的持久实体** — 编辑器启动时就存在，等待用户输入
- **LLM 是间歇性工具** — 节点进入 ReAct 循环时才调用，思考完就停止
- **用户直接跟根节点对话** — 不存在独立的"聊天机器人"层
- **根节点的 LLM 输出 = 用户在 Chat 里看到的 AI 回复**

```
根节点（持久实体）
  ├── 等待用户输入（不消耗 LLM）
  ├── 收到任务 → 进入 ReAct 循环
  │   ├── Round 1: LLM 调用 → 分析 → spawn 子节点
  │   ├── Round 2: LLM 调用 → 等待 → 收报告
  │   └── Round 3: LLM 调用 → 汇总 → 返回用户
  └── ReAct 结束 → 回到等待状态
```

## 七、一棵树，不是森林

- 树 = 项目。一个 Godot 项目就是一棵树
- 所有模块（Player、UI、Audio）天然在一棵树下
- 森林引入不必要的隔离和复杂度
- 项目切换不需要特殊处理 — addon 在 `res://addons/` 里，切项目就是切了一整套

## 八、整形修剪（Pruning）

树的自我重构，对标传统 agent 的 compact，但操作的是树结构而非文本历史。

### 触发机制

- **不做自动修剪** — 开发中自动执行太危险
- **提供 Prune 按钮** — 用户手动触发
- **定期自检** — 每 7-8 轮或距上次 Prune 过了一段时间，系统分析树结构
- **有可优化区域时提示用户** — "发现3个可合并节点，点击 Prune 执行"
- **用户点击 Prune 才真正执行**

### 修剪行为

- 发现多个节点有重复代码 → 提取公共工具节点，各节点放下包袱
- 发现子节点做的事很简单 → 父节点收回职责，子节点消失
- 发现节点职责重叠 → 合并为一个节点
- 目标：简化历史包袱，提高开发效率

## 九、反对的设计

| # | 拒绝的模式 | 原因 |
|---|-----------|------|
| 1 | 固定层级（Root→Branch→Worker） | 限制涌现 |
| 2 | 宏观复杂度评估（Step 0） | 应由微观决策涌现 |
| 3 | 异构节点（不同权限/工具） | 违反同构原则 |
| 4 | 叶子节点限制 | 任意节点可 spawn |
| 5 | 集中调度 | 违反自组织 |
| 6 | 模式切换（用户选模式） | Agent 自主决策 |
| 7 | 会话管理（列表/切换/搜索） | 只有一棵树 |
| 8 | 上下文压缩/summarization | spawn 即分流 |
| 9 | Token 计数/用量指示器 | 不会溢出 |
| 10 | 自动修剪 | 开发中危险 |

## 十、UI 架构

### 右侧 Dock — 纯对话流

```
┌──────────────────────────────┐
│ Banyan  Idle    [kimi] [⚙]  │
├──────────────────────────────┤
│                              │
│  You                         │
│  给 Player 加护盾系统         │
│                              │
│  AI                          │
│  已添加护盾系统：             │
│  - player.gd 新增护盾逻辑     │
│  - shield_bar.gd 新增HUD     │
│                              │
├──────────────────────────────┤
│ [输入任务描述...     ] [Send] │
└──────────────────────────────┘
```

只有消息流 + 输入框。没有标签页、没有模式选择、没有会话按钮。

### 编辑器底部面板 — Agent Tree + Inspector

```
┌──────────────────────────────────────────────────────────────┐
│  Agent Tree                          │  Node Inspector       │
│                                      │                       │
│        Root                          │  ID: Player_Shield    │
│       ╱    ╲                         │  State: COMPLETED     │
│      ╱      ╲                        │  Rounds: 4            │
│  Player    UI_ShieldBar              │  Files: 3             │
│  _Shield     │                       │  Tools: 8             │
│    │         └─ 3 children           │  Duration: 12.3s      │
│    └─ 2 children                     │                       │
│                                      │  [Prune]              │
│  (交互式树状图，点击节点→右侧显示)     │                       │
└──────────────────────────────────────────────────────────────┘
```

- **左侧**：Agent Tree 可视化 — 持久的、跨对话生长的树
- **右侧**：Node Inspector — 选中节点的详情
- **Prune 按钮** — 在 Inspector 中，用户手动触发修剪

## 十一、工具集

所有节点共享同一套工具（32 个，定义在 `tools/definitions/node_tools.json`）：
- **发现**（只读）：list_files, list_scenes, list_resources, get_project_architecture
- **感知**（只读）：read_script, read_multiple_files, inspect_scene_structured, analyze_signal_flow 等
- **执行**（写入）：update_script, build_scene, build_script, patch_scene, write_file 等
- **可视验证**：screenshot_editor, run_scene_capture, run_game_check
- **知识**：save_knowledge, query_knowledge, search_knowledge
- **文件归属**：claim_files
- **子节点**：spawn_child, route_to_child, wait_for_children, list_children

## 十二、信号与通信

```
父节点 → spawn_child(description)
  → 创建子 BanyanNode（同构，继承相同工具和 prompt）
  → 子节点独立运行 ReAct 循环
  → 子节点完成后返回 report 给父节点
  → 父节点收到 report，继续自己的 ReAct 循环
```

HTTP 连接池共享。活跃节点接近池上限时，新子节点排队等待 — 自然背压。

## 十三、实现结构

```
addons/dotagent/
├── plugin.gd                     ← 统一插件入口（模式切换 + 信号桥接）
├── config.cfg                    ← 共享配置
├── config/                       ← 共享: ConfigManager + Locale
├── llm/                          ← 共享: LLMClient + providers + ModelFetcher
├── tools/                        ← 共享: ToolRegistry + 12 工具模块
├── log/                          ← 共享: SessionLog + EditorLogBuffer + BanyanRunLog
├── ui/
│   ├── dotagent_dock.tscn/gd     ← 共享 Dock（纯对话流，两种模式共用）
│   └── dotagent_settings.tscn/gd ← 共享设置（含模式切换）
├── banyan_agent/
│   ├── tree/
│   │   ├── agent_node.gd         ← 唯一的节点类（同构，ReAct 循环 + spawn_child 能力）
│   │   └── agent_tree.gd         ← Agent Tree 持久化 + Prune 分析
│   ├── http/                     ← HTTP 连接池 + 流式解析
│   ├── context/                  ← 消息构建（滑动窗口）
│   ├── persistence/              ← 运行时产物: agent_tree.json + shared_knowledge.json
│   ├── sessions/                 ← 运行时产物: 会话消息 + run 日志
│   ├── tools/                    ← 工具加载 + 执行路由 + definitions/node_tools.json
│   ├── prompts/
│   │   ├── node_prompt.md        ← 统一的系统 prompt
│   │   ├── project_structure.md  ← 领域目录规范
│   │   └── skills/               ← 领域技能文件（# triggers 关键词触发注入）
│   └── ui/
│       ├── banyan_bottom_panel.tscn/gd ← 底部面板（Agent Tree + Inspector + Prune + Log）
│       ├── banyan_session_popup.tscn/gd
│       ├── connection_overlay.gd ← 连线绘制（贝塞尔 + slot 持久化）
│       └── CustomNode/           ← 图节点卡片 + 四方向 slot
├── legacy_agent/                  ← Legacy 单智能体独有代码
```

## 十四、项目文件架构

Agent Tree 天然映射项目的文件结构。每个节点对应一个领域目录，`managed_files` 就是该目录下所有文件。

### Godot 式结构（按领域组织）

```
res://
├── player/                    ← PlayerSystem 节点管辖
│   ├── player.gd
│   ├── player.tscn
│   ├── player_theme.tres
│   └── player_sprites.png
├── enemies/                   ← EnemySystem 节点管辖
│   ├── enemy_base.gd
│   ├── enemy_scout.tscn
│   └── enemy_config.tres
├── ui/                        ← UISystem 节点管辖
│   ├── hud/
│   │   ├── hud.gd
│   │   └── hud.tscn
│   └── settings/
│       ├── settings.gd
│       └── settings.tscn
├── core/                      ← CoreSystem 节点管辖
│   ├── game_manager.gd
│   └── audio_manager.gd
├── assets/                    ← AssetManager 节点管辖
│   ├── audio/
│   ├── fonts/
│   └── textures/
├── project.godot              ← ProjectConfig 节点管辖
└── export_presets.cfg
```

**一个领域的所有文件 — 脚本、场景、资源 — 在同一个目录下。**

### 反对的结构（Unity 式，按文件类型组织）

```
scripts/       ← 所有 .gd 混在一起
scenes/        ← 所有 .tscn 混在一起
resources/     ← 所有 .tres 混在一起
textures/      ← 所有图片混在一起
```

这种结构导致一个功能的文件散落在多个目录，无法与 Agent Tree 的领域节点对应。

### 原则

- **无游离文件** — 项目中的每个文件必须被某个节点的 `managed_files` 覆盖
- **文件创建即归属** — 节点创建文件时，文件自动进入该节点的 `managed_files`
- **资源有管家** — `.tres`、纹理、音频、字体等资源文件由专门的资源管理节点维护
- **配置有管家** — `project.godot`、`export_presets.cfg` 由项目配置节点维护
- **发现缺口即生长** — 如果发现文件不被任何节点覆盖，树应该长出对应的节点

---

*文档版本: 4.1*
*创建日期: 2026-07-25*
*最后更新: 2026-07-31 — 实现结构对齐实际代码（§13）+ 工具集更新为 31 个（§11）；代码侧已放开任意节点 spawn 推荐、恢复全深度树重载、接线 skills 关键词注入*

> **相关文档**: [banyan_agent/AGENT_WORKFLOW.md](banyan_agent/AGENT_WORKFLOW.md) — 外部 AI agent 如何无头驱动 Banyan、读取执行轨迹、评估输出并迭代修复插件的工作手册（含真实诊断案例）。
