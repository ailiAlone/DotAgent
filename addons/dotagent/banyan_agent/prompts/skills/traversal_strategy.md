# triggers: 遍历, 策略, skeleton, depth, 框架, 骨架, 结构, traversal, strategy

# Root 遍历决策 Skill

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

## 执行流程

```
Root 收到用户请求
  → 分析请求关键词（匹配 triggers）
  → 输出决策：SKELETON_FIRST 或 DEPTH_FIRST
  → 按决策创建 Branch 和分配 TaskTicket
```

## Branch 划分参考

根据请求类型划分 Branch：
- **Gameplay**：玩家控制、敌人 AI、物理交互
- **UI**：HUD、菜单、对话框
- **Audio**：音效、背景音乐
- **Level**：关卡设计、地形、道具
- **Save**：存档、读档、持久化

每个 Branch 内部再按模块拆分为 Worker 任务。
