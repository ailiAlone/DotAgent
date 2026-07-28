# DotAgent Cortex 工具层分析报告

**日期**: 2026-07-23
**目标**: 为 Cortex 多智能体架构设计结构化工具层，解决"游戏项目不可文本读取"的核心问题

---

## 一、现状盘点：Legacy 工具清单

Legacy DotAgent 当前拥有 8 个工具模块、61+ 工具，全部继承自 `tool_base.gd`。

| 模块 | 工具数 | 核心能力 | 关键问题 |
|------|--------|----------|----------|
| `file_tools.gd` | 12 | 文件读写、SCD 场景描述、资源创建 | `describe_scene` 仅读磁盘文件，不感知编辑器实时状态 |
| `node_query_tools.gd` | 5 | 场景树查询、节点属性、信号连接 | `get_scene_tree` 返回**纯文本树**，非结构化数据 |
| `scene_tools.gd` | 6 | 场景/节点增删改、撤销 | 写操作完备，但无批量操作、无场景模板 |
| `script_tools.gd` | 5 | 脚本读写、语法检查 | `read_script` 是纯文本读取，无接口提取能力 |
| `script_file_tools.gd` | 7 | 文件管理、搜索替换、引用分析 | `get_script_references` 基于文本搜索，非 AST 级别 |
| `exec_tools.gd` | 12 | GDScript 执行、方法调用、场景运行 | `execute_gdscript` 是万能后门但不可控 |
| `screenshot_tools.gd` | 4 | 编辑器截图、运行时截图、视觉分析 | 仅视觉反馈，无结构化运行时状态提取 |
| `project_tools.gd` | 10 | 项目设置、记忆、技能、输入映射 | `get_project_info` 过于简略，无架构级感知 |

---

## 二、核心问题：为什么"文本读取"不可接受

### 2.1 场景不是文本，是树状结构

一个 `.tscn` 文件在磁盘上是 INI 格式文本，但它表达的是**嵌套节点树 + 资源引用 + 属性绑定**。Legacy 的两种读取方式都有严重缺陷：

**方式 A：`read_resource_as_text`** — 直接读文本
```
[gd_scene load_steps=12 format=3 uid="uid://abc"]
[ext_resource type="Script" path="res://scripts/player.gd" id="1"]
[sub_resource type="RectangleShape2D" id="sub_1"]
size = Vector2(32, 48)
[node name="Player" type="Area2D"]
script = ExtResource("1")
...
```
LLM 需要自行脑补节点层级、资源归属、属性含义。对大型场景（100+ 节点），token 消耗爆炸且理解准确率极低。

**方式 B：`get_scene_tree`** — 文本树
```
Player (Area2D) [player.gd]
  Sprite2D (Sprite2D)
  CollisionShape2D (CollisionShape2D)
  HitBox (CollisionShape2D)
```
只有名字和类型，没有属性值、没有信号连接、没有脚本接口。对 LLM 来说信息严重不足。

**方式 C：`get_node_properties`** — 扁平属性列表
```json
[{"name": "position", "type": "Vector2", "value": "(640, 360)"}, ...]
```
返回所有属性（包括内部属性），无层级关系，无重点标注，token 浪费严重。

### 2.2 脚本不是文本，是接口契约

一个 `.gd` 文件的文本内容对 LLM 来说是一堆代码行。但 Cortex 真正需要的是：
- 这个脚本**声明了什么信号**（其他模块要连接）
- 这个脚本**暴露了什么 public 方法**（其他模块要调用）
- 这个脚本**导出了什么 @export 属性**（编辑器可配置）
- 这个脚本**依赖什么外部资源**（preload / load 路径）
- 这个脚本**继承自什么基类**（extends）

### 2.3 项目不是文件列表，是依赖图

`list_files` 返回一个扁平路径数组。但 Cortex 需要理解：
- 哪些场景**实例化**了哪些场景（场景依赖链）
- 哪些脚本**引用**了哪些资源（代码依赖链）
- 哪些模块通过**信号**互相通信（信号流图）
- 项目的**autoload 单例**有哪些（全局状态）
- 项目的**入口场景**和**启动流程**

---

## 三、已有的结构化能力：SCD（Scene Compact Description）

Legacy 的 `file_tools.gd` 中已实现 `describe_scene` 工具，它将 `.tscn` 转换为 SCD 格式：

**SCD 的优势**：
- 语义化节点树（缩进表示层级）
- 枚举值翻译（`layout_mode: 1` → `anchors`）
- 颜色命名（`Color(1,0,0)` → `red`）
- 资源路径解引用（`ExtResource("1")` → `res://scripts/player.gd`）
- 按场景类型自适应（UI 显示布局/主题，2D 显示位置/碰撞，3D 显示变换/材质）
- 子资源扁平化（`RectangleShape2D` 直接显示 `size`）

**SCD 的局限**：
1. **仅读磁盘文件**：编辑器中未保存的修改不可见
2. **输出仍是文本**：虽然有语义，但仍是字符串，非 JSON 结构化数据
3. **无信号连接信息**：不知道节点间如何通信
4. **无脚本接口信息**：不知道节点挂载的脚本暴露了什么
5. **无运行时状态**：不知道场景运行时的节点状态

**结论**：SCD 是一个好的起点，但远远不够。Cortex 需要在此基础上构建完整的结构化感知层。

---

## 四、缺失能力清单与工具设计

### 4.1 感知层工具（Perception Tools）— 最高优先级

这是用户强调的核心痛点。所有输出必须是**结构化 JSON**，不是文本字符串。

#### 工具 1：`inspect_scene_structured`

**用途**：获取场景的完整结构化描述，替代文本式的 `get_scene_tree` + `get_node_properties`。

**输入**：
```json
{
  "scene_path": "res://scenes/player.tscn",
  "include_properties": true,
  "include_signals": true,
  "include_scripts_interface": true,
  "max_depth": 0
}
```

**输出**（结构化 JSON，非文本）：
```json
{
  "ok": true,
  "content": {
    "type": "scene_struct",
    "path": "res://scenes/player.tscn",
    "root": {
      "name": "Player",
      "type": "Area2D",
      "script": {
        "path": "res://scripts/player.gd",
        "class_name": "Player",
        "extends": "Area2D",
        "signals": [
          {"name": "died", "params": []},
          {"name": "health_changed", "params": [{"name": "new_hp", "type": "int"}]}
        ],
        "methods": [
          {"name": "take_damage", "params": ["amount: int"], "returns": "void", "access": "public"},
          {"name": "heal", "params": ["amount: int"], "returns": "void", "access": "public"}
        ],
        "exports": [
          {"name": "max_health", "type": "int", "default": 100},
          {"name": "move_speed", "type": "float", "default": 420.0}
        ]
      },
      "properties": {
        "position": {"type": "Vector2", "value": [640, 360]},
        "visible": {"type": "bool", "value": true}
      },
      "children": [
        {
          "name": "Sprite2D",
          "type": "Sprite2D",
          "properties": {
            "texture": {"type": "Texture2D", "ref": "res://textures/player.png"},
            "modulate": {"type": "Color", "value": "#ffffff"}
          },
          "children": []
        },
        {
          "name": "CollisionShape2D",
          "type": "CollisionShape2D",
          "properties": {
            "shape": {"type": "RectangleShape2D", "size": [32, 48]}
          },
          "children": []
        }
      ],
      "signals_connections": [
        {"signal": "area_entered", "target": "Player", "method": "_on_area_entered", "source": "self"}
      ]
    },
    "external_resources": [
      {"id": "1", "type": "Script", "path": "res://scripts/player.gd"},
      {"id": "2", "type": "Texture2D", "path": "res://textures/player.png"}
    ],
    "sub_resources": [
      {"id": "sub_1", "type": "RectangleShape2D", "properties": {"size": [32, 48]}}
    ],
    "stats": {
      "total_nodes": 5,
      "total_scripts": 2,
      "total_resources": 4,
      "scene_type": "2d"
    }
  }
}
```

**实现策略**：
- 优先从编辑器实时场景树读取（`EditorInterface.get_edited_scene_root()`），获取运行时状态
- 如果指定了 `scene_path` 且非当前编辑场景，从磁盘加载 `PackedScene`
- 节点属性只输出**有意义的属性**（过滤默认值、过滤内部 `_` 前缀属性）
- 脚本接口通过解析 `.gd` 文件提取（正则匹配 `signal`、`func`、`@export`、`class_name`、`extends`）
- 信号连接通过 `node.get_signal_connection_list()` 获取编辑器绑定

**桥接**：组合 `node_query_tools.gd`（场景树）+ `script_tools.gd`（脚本读取）+ 新增脚本接口解析器

---

#### 工具 2：`extract_script_interface`

**用途**：提取脚本的接口摘要，不读实现细节。用于 Cortex 的接口契约阶段。

**输入**：
```json
{
  "path": "res://scripts/player.gd"
}
```

**输出**：
```json
{
  "ok": true,
  "content": {
    "type": "script_interface",
    "path": "res://scripts/player.gd",
    "class_name": "Player",
    "extends": "Area2D",
    "signals": [
      {"name": "died", "params": [], "line": 5},
      {"name": "health_changed", "params": [{"name": "new_hp", "type": "int"}], "line": 6}
    ],
    "exports": [
      {"name": "max_health", "type": "int", "default": 100, "line": 8},
      {"name": "move_speed", "type": "float", "default": 420.0, "line": 9}
    ],
    "constants": [
      {"name": "DASH_DURATION", "value": 0.15, "line": 12}
    ],
    "public_methods": [
      {"name": "take_damage", "params": [{"name": "amount", "type": "int"}], "returns": "void", "is_static": false, "line": 45},
      {"name": "heal", "params": [{"name": "amount", "type": "int"}], "returns": "void", "is_static": false, "line": 58}
    ],
    "dependencies": {
      "preload": ["res://scripts/bullet.gd"],
      "load": [],
      "scene_refs": []
    },
    "enums": [
      {"name": "State", "values": ["IDLE", "MOVING", "DASHING", "HURT"]}
    ],
    "node_refs": [
      {"name": "sprite", "type": "Sprite2D", "binding": "onready"},
      {"name": "anim_player", "type": "AnimationPlayer", "binding": "onready"}
    ]
  }
}
```

**实现策略**：
- 纯正则解析 `.gd` 文件（不需要 AST，GDScript 的接口声明是行级别的）
- 匹配规则：`signal xxx`、`func xxx`（过滤 `_` 前缀的私有方法）、`@export`、`class_name`、`extends`、`enum`、`const`、`@onready`、`preload()`、`load()`
- 输出行号方便定位

**桥接**：新增，不依赖现有工具。核心逻辑在 `script_tools.gd` 的 `read_script` 基础上增加接口提取。

---

#### 工具 3：`get_project_architecture`

**用途**：获取项目整体架构概览，替代扁平的 `list_files` + 简陋的 `get_project_info`。

**输入**：
```json
{
  "include_dependencies": true,
  "include_signal_map": true
}
```

**输出**：
```json
{
  "ok": true,
  "content": {
    "type": "project_architecture",
    "project_name": "Star Hunter",
    "main_scene": "res://scenes/main.tscn",
    "viewport": {"width": 1280, "height": 720},
    "autoloads": [
      {"name": "GameManager", "path": "res://scripts/game_manager.gd"},
      {"name": "AudioManager", "path": "res://scripts/audio_manager.gd"}
    ],
    "scenes": [
      {
        "path": "res://scenes/main.tscn",
        "root_type": "Node2D",
        "script": "res://scripts/main.gd",
        "instances": ["res://scenes/game.tscn", "res://scenes/ui/hud.tscn"],
        "depth": 0
      },
      {
        "path": "res://scenes/game.tscn",
        "root_type": "Node2D",
        "script": "res://scripts/game.gd",
        "instances": ["res://scenes/player.tscn", "res://scenes/enemies/scout.tscn"],
        "depth": 1
      }
    ],
    "scene_tree": {
      "res://scenes/main.tscn": {
        "children": ["res://scenes/game.tscn", "res://scenes/ui/hud.tscn"]
      }
    },
    "signal_bus": {
      "signals": [
        {"name": "GameStart", "params": [], "emitters": ["game.gd"], "listeners": ["audio_manager.gd"]},
        {"name": "GameOver", "params": ["score: int"], "emitters": ["game.gd"], "listeners": ["game_manager.gd", "hud.gd"]}
      ]
    },
    "scripts_summary": {
      "total": 12,
      "with_class_name": 3,
      "with_signals": 5,
      "with_exports": 4
    },
    "resource_types": {
      "scenes": 8,
      "scripts": 12,
      "textures": 0,
      "audio": 0,
      "resources": 2
    }
  }
}
```

**实现策略**：
- 遍历项目文件（复用 `_walk_dir`）
- 对每个 `.tscn` 文件，用正则提取 `ext_resource` 中的场景引用（`type="PackedScene"` 或路径以 `.tscn` 结尾）
- 对每个 `.gd` 文件，提取 `signal` 声明和 `SignalBus.xxx.connect()` 调用
- 从 `project.godot` 提取 autoload 列表和主场景
- 构建场景实例化树（哪个场景实例化了哪个场景）

**桥接**：组合 `project_tools.gd`（项目信息）+ `file_tools.gd`（文件遍历）+ 新增场景依赖解析 + 新增信号流分析

---

#### 工具 4：`get_scene_dependencies`

**用途**：递归获取一个场景的所有依赖（实例化的子场景 + 引用的资源 + 挂载的脚本）。

**输入**：
```json
{
  "path": "res://scenes/game.tscn",
  "recursive": true
}
```

**输出**：
```json
{
  "ok": true,
  "content": {
    "type": "dependency_graph",
    "root": "res://scenes/game.tscn",
    "direct": {
      "scenes": ["res://scenes/player.tscn", "res://scenes/enemies/scout.tscn"],
      "scripts": ["res://scripts/game.gd"],
      "resources": ["res://resources/wave_config.tres"]
    },
    "recursive": [
      {"path": "res://scenes/game.tscn", "depth": 0},
      {"path": "res://scenes/player.tscn", "depth": 1},
      {"path": "res://scenes/enemies/scout.tscn", "depth": 1},
      {"path": "res://scripts/player.gd", "depth": 2, "via": "res://scenes/player.tscn"}
    ],
    "stats": {"total_scenes": 5, "total_scripts": 8, "total_resources": 3}
  }
}
```

**桥接**：新增。解析 `.tscn` 的 `[ext_resource]` 段，递归展开。

---

#### 工具 5：`inspect_live_scene`

**用途**：获取编辑器中**当前正在编辑的场景**的实时状态（包括未保存的修改）。

**输入**：
```json
{
  "include_property_values": false,
  "include_groups": true
}
```

**输出**：
```json
{
  "ok": true,
  "content": {
    "type": "live_scene",
    "path": "res://scenes/player.tscn",
    "unsaved_changes": true,
    "root": {
      "name": "Player",
      "type": "Area2D",
      "instance_id": 12345,
      "script": "res://scripts/player.gd",
      "properties": {"position": [640, 360]},
      "children": [...],
      "groups": ["enemies", "damageable"],
      "signal_connections": [
        {"signal": "area_entered", "target_path": ".", "method": "_on_area_entered"}
      ]
    }
  }
}
```

**与 `inspect_scene_structured` 的区别**：
- `inspect_scene_structured` 可以从磁盘或编辑器读取，侧重完整结构
- `inspect_live_scene` 只能从编辑器读取，侧重实时状态（未保存修改、运行时属性、组信息）

**桥接**：基于 `node_query_tools.gd` 的 `get_scene_tree`，但输出结构化 JSON 而非文本。

---

### 4.2 分析层工具（Analysis Tools）— 高优先级

#### 工具 6：`analyze_signal_flow`

**用途**：分析项目中信号的完整流向（谁发射、谁监听、跨哪些模块）。

**输入**：
```json
{
  "scope": "project",
  "signal_name": ""
}
```

**输出**：
```json
{
  "ok": true,
  "content": {
    "type": "signal_flow",
    "signals": [
      {
        "name": "died",
        "declared_in": "res://scripts/player.gd",
        "emitted_in": ["res://scripts/player.gd"],
        "connected_in": [
          {"file": "res://scripts/game.gd", "method": "_on_player_died", "via": "editor"}
        ],
        "cross_module": true
      }
    ]
  }
}
```

**桥接**：新增。扫描所有 `.gd` 文件的 `signal` 声明 + `.emit()` 调用 + `.connect()` 调用 + 编辑器信号绑定。

---

#### 工具 7：`compare_scenes`

**用途**：对比两个场景文件的差异（用于 Cortex 验证修改是否正确）。

**输入**：
```json
{
  "path_a": "res://scenes/player.tscn",
  "path_b": "res://scenes/player.tscn.bak"
}
```

**输出**：
```json
{
  "ok": true,
  "content": {
    "type": "scene_diff",
    "added_nodes": ["Shield"],
    "removed_nodes": ["OldTimer"],
    "modified_nodes": [
      {
        "path": "Player",
        "changed_properties": [
          {"name": "position", "old": [0, 0], "new": [640, 360]}
        ]
      }
    ],
    "added_resources": ["res://textures/shield.png"],
    "removed_resources": []
  }
}
```

**桥接**：新增。解析两个 `.tscn` 文件的节点树并对比。

---

### 4.3 协调层工具（Coordination Tools）— Cortex 专属

这些工具是 Cortex 架构独有的，不存在于 Legacy 中。

#### Root 层工具

| 工具名 | 用途 | 输入 | 输出 |
|--------|------|------|------|
| `analyze_request` | 分析用户需求，输出结构化任务分解 | `user_input: string` | `{intents: [], modules_affected: [], strategy: "SKELETON_FIRST\|DEPTH_FIRST"}` |
| `get_architecture_overview` | 获取项目架构概览（调用 `get_project_architecture` 的封装） | 无 | 同 `get_project_architecture` 输出 |
| `create_branch` | 创建子系统分支节点 | `name, scope, modules[]` | `{branch_id, status}` |
| `assign_task` | 向分支分配任务工单 | `branch_id, ticket{}` | `{ticket_id, status}` |
| `review_progress` | 审查所有 Branch 的进度 | 无 | `{branches: [{id, status, completed_tasks, blocked}]}` |

#### Branch 层工具

| 工具名 | 用途 | 输入 | 输出 |
|--------|------|------|------|
| `create_worker` | 创建模块 Worker 节点 | `name, type, scope` | `{worker_id, status}` |
| `define_contract` | 定义模块间接口契约 | `source_module, target_module, signals[], methods[]` | `{contract_id, consistent: bool}` |
| `validate_contracts` | 验证所有接口契约一致性 | 无 | `{consistent: bool, conflicts: []}` |
| `assign_worker_task` | 向 Worker 分配具体任务 | `worker_id, task_type, requirements[]` | `{task_id, status}` |
| `review_worker_output` | 审查 Worker 交付物 | `worker_id` | `{files: [], interfaces: [], quality: "pass\|fail"}` |
| `get_module_interfaces` | 获取子系统内所有模块的接口摘要 | `scope` | `{modules: [{name, signals[], methods[], exports[]}]}` |

#### Worker 层工具

Worker 层工具由 Legacy 工具子集 + 新增感知工具组成：

| 工具名 | 来源 | 用途 |
|--------|------|------|
| `inspect_scene_structured` | 新增 | 结构化读取场景 |
| `extract_script_interface` | 新增 | 提取脚本接口 |
| `inspect_live_scene` | 新增 | 读取编辑器实时场景状态 |
| `create_scene` | Legacy `scene_tools` | 创建场景 |
| `add_node` | Legacy `scene_tools` | 添加节点 |
| `set_node_property` | Legacy `scene_tools` | 设置节点属性 |
| `update_script` | Legacy `script_tools` | 编写/更新脚本 |
| `check_script_syntax` | Legacy `script_file_tools` | 语法检查 |
| `screenshot_editor` | Legacy `screenshot_tools` | 截图验证 |
| `run_scene_capture` | Legacy `exec_tools` | 运行场景验证 |

---

## 五、工具分层映射总图

```
┌──────────────────────────────────────────────────────────────┐
│  Root Coordinator（5-8 工具）                                 │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ analyze_request                                         │ │
│  │ get_architecture_overview ← get_project_architecture    │ │
│  │ create_branch / assign_task / review_progress           │ │
│  │ get_module_interfaces ← extract_script_interface (批量) │ │
│  └─────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────┤
│  Branch Node（6-10 工具）                                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ create_worker / assign_worker_task / review_worker_output│ │
│  │ define_contract / validate_contracts                    │ │
│  │ inspect_scene_structured（只读，用于审查）                │ │
│  │ get_scene_dependencies（分析模块依赖）                    │ │
│  │ analyze_signal_flow（验证信号一致性）                     │ │
│  └─────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────┤
│  Worker Node（8-12 工具）                                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ ★ inspect_scene_structured  — 结构化场景感知             │ │
│  │ ★ extract_script_interface  — 脚本接口提取               │ │
│  │ ★ inspect_live_scene        — 编辑器实时状态             │ │
│  │   create_scene              — 创建场景 (Legacy bridge)   │ │
│  │   add_node / set_node_property — 构建场景 (Legacy bridge)│ │
│  │   update_script             — 编写脚本 (Legacy bridge)   │ │
│  │   check_script_syntax       — 语法验证 (Legacy bridge)   │ │
│  │   screenshot_editor         — 视觉验证 (Legacy bridge)   │ │
│  │   run_scene_capture         — 运行验证 (Legacy bridge)   │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

★ = 新增工具（需开发）
其余 = 桥接 Legacy 已有工具
```

---

## 六、开发优先级与实现路线

### Phase 1：感知核心（最高优先级）

这三个工具解决用户的核心痛点——"不能文本读取"：

1. **`extract_script_interface`** — 纯文本解析，实现最简单，价值最高
   - 正则提取 `signal` / `func` / `@export` / `class_name` / `extends` / `enum` / `const`
   - 输出结构化 JSON
   - 预估工作量：~200 行 GDScript
   - 文件：新增 `addons/dotagent/tools/interface_tools.gd`

2. **`inspect_scene_structured`** — 组合现有能力 + 结构化输出
   - 基于 `node_query_tools.gd` 的场景树遍历，但输出嵌套 JSON 而非文本
   - 集成 `extract_script_interface` 获取节点挂载脚本的接口
   - 集成信号连接信息
   - 预估工作量：~300 行 GDScript
   - 文件：扩展 `node_query_tools.gd` 或新增 `scene_perception_tools.gd`

3. **`get_project_architecture`** — 项目级全局感知
   - 组合 `_walk_dir` + `.tscn` 依赖解析 + autoload 解析 + 信号扫描
   - 预估工作量：~350 行 GDScript
   - 文件：扩展 `project_tools.gd` 或新增 `architecture_tools.gd`

### Phase 2：分析能力

4. **`analyze_signal_flow`** — 信号流分析
5. **`get_scene_dependencies`** — 场景依赖图
6. **`inspect_live_scene`** — 编辑器实时状态

### Phase 3：Cortex 协调工具

7. Root / Branch / Worker 层协调工具（这些在 Cortex 架构实现时开发）

---

## 七、技术实现细节

### 7.1 脚本接口解析器（`extract_script_interface` 核心逻辑）

```gdscript
# 正则模式
const RE_SIGNAL := RegEx.create_from_string("^signal\\s+(\\w+)(?:\\((.*)?\\))?")
const RE_FUNC := RegEx.create_from_string("^(?:static\\s+)?func\\s+(\\w+)\\s*\\((.*)?\\)(?:\\s*->\\s*(\\w+))?")
const RE_EXPORT := RegEx.create_from_string("^@export(?:\\((.*)?\\))?\\s+(?:var\\s+)?(\\w+)\\s*:\\s*(\\w+)(?:\\s*=\\s*(.*))?")
const RE_CLASS_NAME := RegEx.create_from_string("^class_name\\s+(\\w+)")
const RE_EXTENDS := RegEx.create_from_string("^extends\\s+(\\w+)")
const RE_ENUM := RegEx.create_from_string("^enum\\s+(\\w+)\\s*\\{")
const RE_CONST := RegEx.create_from_string("^const\\s+(\\w+)\\s*=\\s*(.*)")
const RE_ONREADY := RegEx.create_from_string("^@onready\\s+var\\s+(\\w+)\\s*:\\s*(\\w+)")
const RE_PRELOAD := RegEx.create_from_string("preload\\(\"([^\"]+)\"\\)")
```

**关键规则**：
- `func _xxx` 开头的视为私有方法，不纳入接口
- `signal` 声明全部纳入（信号天然是公开的）
- `@export` 全部纳入（编辑器可见属性）
- `static func` 单独标记

### 7.2 场景依赖解析器（`get_scene_dependencies` 核心逻辑）

```gdscript
# 从 .tscn 文本提取外部资源引用
func _extract_dependencies(tscn_text: String) -> Dictionary:
    var deps := {"scenes": [], "scripts": [], "resources": []}
    var re := RegEx.create_from_string('\\[ext_resource[^\\]]*path="([^"]+)"[^\\]]*type="([^"]+)"')
    for m in re.search_all(tscn_text):
        var path := m.get_string(1)
        var type := m.get_string(2)
        if path.ends_with(".tscn") or path.ends_with(".scn"):
            deps.scenes.append(path)
        elif path.ends_with(".gd"):
            deps.scripts.append(path)
        else:
            deps.resources.append(path)
    return deps
```

### 7.3 信号流分析器（`analyze_signal_flow` 核心逻辑）

```gdscript
# 扫描 .gd 文件中的信号声明和连接
func _scan_script_signals(path: String) -> Array:
    var f := FileAccess.open(path, FileAccess.READ)
    var text := f.get_as_text(); f.close()
    var signals := []
    var emits := []
    var connects := []

    for line in text.split("\n"):
        var s := line.strip_edges()
        # signal xxx
        if s.begins_with("signal "):
            signals.append(_parse_signal_decl(s))
        # .emit( 或 emit_signal(
        if ".emit(" in s or "emit_signal(" in s:
            emits.append(_parse_emit(s))
        # .connect(
        if ".connect(" in s:
            connects.append(_parse_connect(s))
        # SignalBus.xxx
        if "SignalBus." in s:
            connects.append(_parse_signal_bus_ref(s))

    return {"declared": signals, "emitted": emits, "connected": connects}
```

---

## 八、与 Legacy 工具的桥接策略

### 8.1 桥接原则

1. **新增感知工具**：不修改 Legacy 工具，新增独立工具模块
2. **复用底层能力**：新工具内部复用 `tool_base.gd` 的 `_walk_dir`、`_ei()`、`_ok()`/`_err()` 等
3. **Cortex 桥接层**：`tool_executor.gd` 同时支持 Legacy 工具名和新增工具名
4. **渐进式替换**：新增工具逐步替代 Legacy 的文本式工具，不一次性删除

### 8.2 工具模块规划

建议新增一个工具模块文件：

```
addons/dotagent/tools/perception_tools.gd
```

继承 `tool_base.gd`，包含以下工具：
- `inspect_scene_structured`
- `extract_script_interface`
- `inspect_live_scene`
- `get_project_architecture`
- `get_scene_dependencies`
- `analyze_signal_flow`
- `compare_scenes`

所有输出统一为结构化 JSON（`_ok()` 返回的 content 是 Dictionary，不是 String）。

### 8.3 对 `_ok()` 的扩展

当前 `_ok(content: String)` 只接受字符串。为了支持结构化输出，需要：

```gdscript
func _ok_structured(data: Dictionary) -> Dictionary:
    return {"ok": true, "content": JSON.stringify(data)}
    # 注意：对外仍是 JSON 字符串（LLM 消费）
    # 但内部结构是严格定义的，LLM 可以可靠解析
```

或者在 Cortex 的 `tool_executor.gd` 层面做转换：Legacy 工具返回字符串 → Cortex 层尝试 JSON 解析 → 如果成功则作为结构化数据传递给 Worker。

---

## 九、验证标准

每个新增工具需满足：

1. **输出可解析**：LLM 能直接从 JSON 中提取所需信息，无需"阅读理解"文本
2. **信息完备**：一个工具调用能替代多次 Legacy 工具调用（如 `inspect_scene_structured` 替代 `get_scene_tree` + `get_node_properties` + `get_signal_connections`）
3. **Token 高效**：过滤默认值和内部属性，只输出有意义的信息
4. **场景类型自适应**：UI/2D/3D 场景输出不同的重要属性子集
5. **兼容 Legacy**：所有新工具在 Legacy 模式下也可用（通过 `tool_registry.gd` 注册）

---

## 十、总结

DotAgent Cortex 的工具层需要在 Legacy 的 61+ 工具基础上，新增 **7 个结构化感知工具**，解决"游戏项目不可文本读取"的核心问题。这些工具的输出是严格定义的 JSON 结构，而非自由格式文本。

优先级排序：
1. `extract_script_interface` — 脚本接口提取（最基础，其他工具依赖）
2. `inspect_scene_structured` — 结构化场景感知（替代文本式场景树）
3. `get_project_architecture` — 项目架构概览（Root 层核心感知）
4. `get_scene_dependencies` — 场景依赖图
5. `analyze_signal_flow` — 信号流分析
6. `inspect_live_scene` — 编辑器实时状态
7. `compare_scenes` — 场景差异对比

建议统一放入 `perception_tools.gd` 新模块，继承 `tool_base.gd`，同时服务 Legacy 和 Cortex 两种模式。
