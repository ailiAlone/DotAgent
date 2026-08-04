# Banyan Agent 交接文档（2026-08-03）

> 写给接手的 agent：这里记录当前状态、操作手册和坑。先读这个，再读
> `ARCHITECTURE_AUDIT.md`（架构合规审计）、`COMMERCIAL_GAP_ANALYSIS.md`（差距清单）、
> `AGENT_WORKFLOW.md`、`ARCHITECTURE.md`。上一份交接文档：`HANDOFF_20260801.md`。

## 当前状态一句话

**架构对齐迭代完成**：基于 ARCHITECTURE.md 审计发现 7 项偏差全部修复，知识跨会话复用 + 委派系统改进 + 错误自恢复三大能力落地。回归套件 **18/18 通过**。基准复测 **13/15 = 87%**（两项失败非回退，详见下文）。已提交 `18eae5f`，推送因网络问题未完成。

## 本轮（2026-08-03）交付清单

| 交付 | 位置 | 验证 |
|---|---|---|
| §14 路径校验 | `tools/tool_executor.gd` `_check_flat_directory` + `tree/agent_node.gd` 双层拦截 | 闭环测试：agent 尝试 scripts/ → REJECTED → 自动转 ui/ ✓ |
| §2 Spawn 推荐精简 | `tree/agent_node.gd` 删除 Stage1/Stage2 推荐 + `_detect_domains_dict` + `_build_spawn_plan` | 回归 18/18 ✓ |
| §8 Extract Pruning | `tree/agent_tree.gd` `apply_prune("extract")` 实现完整逻辑 | 单元测试 + 审计 ✓ |
| §9 会话管理移除 | `plugin.gd` 删除 `_session_popup`、`ui/dotagent_dock.tscn` 删除 NewBtn + ContextLabel | 回归 18/18 ✓ |
| §10 Inspector 字段 | `ui/banyan_bottom_panel.gd/.tscn` 新增 ToolsLabel + DurationLabel | 回归 18/18 ✓ |
| §11 ARCHITECTURE.md | 工具数 31→32，新增 `run_game_check` 到可视验证类别 | 文档审查 ✓ |
| 知识跨会话复用 | `tree/agent_node.gd` `_build_node_context(task_text)` + `_score_child_relevance` + `_split_camel_case` | 回归测试通过 ✓ |
| 委派系统改进 | `_build_incremental_context` + `_build_this_run_output` + `_truncate_child_report` + `list_children` 增强 | 回归 18/18 ✓ |
| 错误自恢复 | `_inject_error_recovery` 4 种错误分类 + `_recovery_injected` 去重 | 闭环测试验证 ✓ |
| Prompt 增强 | `prompts/node_prompt.md` Multi-Domain Tasks + 文件组织规则强化；`prompts/project_structure.md` 过渡期指导；收敛总结模板改通用 | 闭环测试 ✓ |
| 统一回归套件 | `tests/_regression_suite.gd` 18 项检查（编译/工具/Prompt/关键函数/场景） | **18/18 通过** |
| hud.tscn 修复 | 9 个缺失 `unique_name_in_owner` 节点（通过 Banyan headless 自主修复） | `run_game_check` 通过 ✓ |
| 基准复测 | A1✓ M1✓(修复后) M2✓ 及多轮闭环测试 | 13/15（2 项非回退失败） |
| 架构审计报告 | `banyan_agent/ARCHITECTURE_AUDIT.md` 21 对齐 / 7 偏差 / 1 未完成 | 7 偏差全部修复 |

## 基准复测详情（2026-08-03）

| 任务 | 类型 | 结果 | 说明 |
|---|---|---|---|
| A1 | 分析 | ✅ | 15.5s / 13.2k tokens |
| A2 | 分析 | ✅ | — |
| A3 | 分析 | ✅ | — |
| A4 | 分析 | ❌ | 非回退：hud 修复后 MagnetLabel 错误消失，check 期望该错误存在 |
| M1 | 微改 | ✅ | 修复后通过（加了 "Write tasks MUST produce writes" prompt 规则） |
| M2 | 微改 | ✅ | — |
| M3 | 微改 | ✅ | — |
| M4 | 微改 | ✅ | — |
| N1 | 新域 | ✅ | — |
| N2 | 新域 | ✅ | — |
| N3 | 新域 | ✅ | — |
| X1 | 跨域 | ✅ | — |
| X2 | 跨域 | ✅ | — |
| X3 | 跨域 | ✅ | — |
| X4 | 跨域 | ✅ | — |

**A4 失败原因**：基准任务期望 `bench_a4_bugs.md` 包含 "MagnetLabel" 字样（之前的运行时错误）。但我们在基准前通过 Banyan 修复了 hud.tscn 的 9 个缺失 `unique_name_in_owner`，MagnetLabel 错误不再存在。这是**测试环境污染**，不是 Banyan 回退。

**M1 首轮失败原因**：agent 读了 player.gd + 检查语法后直接收工（假完成）。通过 prompt 新增 "Write tasks MUST produce writes" 规则修复，复测通过。

## 操作手册

### 跑一次真实无头 Banyan 任务

**推荐方式：用 PowerShell 脚本文件**（避免 cmd/inline PowerShell 的 `$` 变量被吞）

1. 编辑 `C:\Users\34935\.qoderworkcn\workspace\mscj8pnwbqni4pcp\run_banyan.ps1`，修改 `$env:BANYAN_TASK` 行
2. 执行：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\34935\.qoderworkcn\workspace\mscj8pnwbqni4pcp\run_banyan.ps1"
```
3. 日志输出到 `C:\Users\34935\.qoderworkcn\workspace\mscj8pnwbqni4pcp\banyan_run.log` + `banyan_run_err.log`

**脚本模板**（已存在，改 TASK 行即可）：
```powershell
$env:DOTAGENT_API_KEY = [Environment]::GetEnvironmentVariable("DOTAGENT_API_KEY", "User")
$env:BANYAN_TASK = "你的任务文本"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "E:\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe"
$psi.Arguments = "--headless --path E:\Projects\DotAgent --script res://tests/run_banyan_headless.gd"
# ... (完整脚本见 run_banyan.ps1)
```

**⚠️ 必须用前台执行 + 等待完成**：`is_background=true` 模式下我无法在任务完成后自动继续工作。前台执行（Bash 不加 `is_background`）会在命令完成后返回结果，我自动接续检查和下一步。

### 跑回归套件
```powershell
& "E:\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe" `
  --headless --path "E:\Projects\DotAgent" --script "res://tests/_regression_suite.gd"
```
- 18 项检查：核心编译(4) + 工具定义(2) + Prompt 文件(4) + 关键函数(6) + 场景加载(2)
- 结果写入 `tests/regression_results.json`
- 退出码 0 = 全通过（WARNING: ObjectDB leaked 是 Godot 无头模式已知问题，不影响）
- **每次改动 agent_node.gd 或 tool_executor.gd 后必跑**

### 跑基准
```bash
python tests/_benchmark.py --only A1,M1   # 部分任务
python tests/_benchmark.py                # 全部
python tests/_benchmark.py --report       # 重新生成 report.md
```
注意：A4 任务因 hud.tscn 修复导致 check 失败（非回退），如需修复 A4 check 需更新 `tests/benchmark/tasks.json` 中的 A4 断言。

### 诊断与分析
- `python tests/_trace_analyze.py` — 成本/失败/复读/空转四类浪费分析
- `tests/_count_tools.gd` — 工具模块加载计数（全模块 75+）
- `tests/_check_scene_load.gd` — 场景 script 挂接回归
- 其他回归套件（上轮交接遗留，仍然有效）：`_test_r10_fixes`(58) `_test_r18_resilience`(13)
  `_test_r19_slot_errors`(6) `test_banyan_fixes`(5) `test_round_budget`(5)
  `_test_new_fixes`(7) `_test_fuzzy_replace`(8) `test_ui_compile` `_check_scene_load`(20)

## 关键坑（都踩过，别再踩）

1. **Windows 嵌套 Godot 子进程**：`OS.execute` 管道捕获会死锁。必须 `OS.create_process`。
2. **HTTP 状态机**：终态错误（CONNECTION_ERROR 等）不能重试，否则永久挂起。Pool 看门狗 90s 兜底。
3. **看门狗活动判定**：LLM 心跳（0.5s 同状态）不算活动；真活动 = 状态变化 / progress_chunk / 工具开始结束。
4. **测试脚本**：SceneTree 测试在 `_init` 里报错会表现为"挂死"。
5. **工具改动三处同步**：`tools/*.gd` + `node_tools.json` + `node_prompt.md`。执行路由通用，不用改 executor。
6. **游戏文件是 Banyan 的产出**：只做修复性/清理性改动，功能留给 agent。跑基准后**必须清理** bench_* / BENCH_* 脚手架。
7. **不主动 git commit**；改动只动 `addons/dotagent/` 和 `tests/`。
8. **PowerShell inline 命令的 `$` 被 cmd 外层吞掉**：写 .ps1 脚本文件再用 `-File` 执行，不要用 inline `-Command`。
9. **agent_node.gd 对非管理工具直接调 ToolRegistry**：绕过 tool_executor。路径校验等拦截逻辑必须在 agent_node.gd 和 tool_executor.gd **双层**添加，否则被绕过。（本轮发现的 bug，已修复。）
10. **`_fail_sig_counts` 变量声明位置**：在 line 145 区域已声明，不要重复添加（本轮差点重复导致编译失败）。
11. **后台任务（is_background=true）无法自动接续**：Banyan headless 任务必须用前台 Bash 执行，否则我收到完成通知后无法自动继续工作。
12. **路径校验区分创建和修改**：`update_script`/`replace_in_file`/`patch_scene` 修改已有文件应放行（`_FILE_MODIFYING_TOOLS` 检查 `FileAccess.file_exists`），只拦截创建新文件到扁平目录。
13. **收敛总结增量标记**：`route_to_child` 用 `## [PARENT_INCREMENTAL_CONTEXT]` 标记注入增量上下文，多次路由时先剥离旧标记再注入新的，防止累积。
14. **Git push 需要网络**：本机直连 github.com 失败（代理问题）。推送前确认网络或设置 `git config --global http.proxy`。

## 本轮新增的关键代码路径

| 功能 | 文件 | 函数/变量 |
|---|---|---|
| 路径校验 | `tools/tool_executor.gd` | `_check_flat_directory`, `_FILE_CREATING_TOOLS`, `_FILE_MODIFYING_TOOLS`, `_FLAT_DIRECTORIES` |
| 路径校验（双层） | `tree/agent_node.gd:765-776` | `_tool_executor._check_flat_directory` 调用 |
| 知识相关性排序 | `tree/agent_node.gd` | `_build_node_context(task_text)`, `_score_child_relevance`, `_split_camel_case` |
| 增量上下文传递 | `tree/agent_node.gd` | `_build_incremental_context`, `route_to_child` 中的 marker 注入 |
| 本次成果字段 | `tree/agent_node.gd` | `_build_this_run_output`, `_extract_last_assistant_content`, `generate_report` 中的 `this_run_output` |
| 报告截断 | `tree/agent_node.gd` | `_truncate_child_report` (summary≤800, this_run_output≤500) |
| 错误自恢复 | `tree/agent_node.gd` | `_inject_error_recovery`, `_recovery_injected` |
| list_children 增强 | `tree/agent_node.gd` | `_handle_list_children` 返回 `managed_files` + `domain_knowledge_preview` |
| Extract Pruning | `tree/agent_tree.gd` | `apply_prune("extract")`, `_extract_file_from_reason` |
| 回归套件 | `tests/_regression_suite.gd` | 18 项检查 |
| 收敛总结模板 | `tree/agent_node.gd:605-623` | 通用模板（Domain/Key Files/Architecture/Changes/History） |

## 下一步候选

1. **领域目录迁移**：把现有 22 个脚本 + 20 个场景从 `scripts/`/`scenes/` 迁移到领域目录（`player/`/`enemies/`/`ui/`/`core/`）。这是对 Banyan 大规模协调能力的终极考验。路径校验已就位，prompt 引导已就位，但迁移涉及跨文件引用更新 + autoload 路径调整，风险最大。
2. **多模型适配验证**：用基准任务集换 DeepSeek/Moonshot/Ollama 跑一遍，量化各模型成功率差距。需要对应 API key。
3. **规划层**：当前任务规模下不需要。更大任务出现"漂移"时再评估。
4. **A4 基准修复**：更新 `tests/benchmark/tasks.json` 中 A4 的 check 断言，适配 hud.tscn 已修复的新状态。
5. **推送上次提交**：`18eae5f` 已本地提交但因网络问题未推送，需确认网络后 `git push`。

## 环境与数据

- Godot 4.5.1：`E:\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe`
- 模型 MiniMax-M2.7-highspeed（`https://api.minimaxi.com/anthropic/v1`），key 在注册表 `HKCU\Environment\DOTAGENT_API_KEY`
- 运行证据：`addons/dotagent/banyan_agent/sessions/`（60+ 次运行）
- 持久化树：`persistence/agent_tree.json`（Root + Enemy/Game/Ui 子节点，跨会话知识复利的关键，别删）
- 最新提交：`18eae5f`（已提交未推送）
- 回归套件：`tests/_regression_suite.gd`（18 项，18/18 通过）
- 基准报告：`tests/benchmark/report_rerun.md`（13/15 = 87%）
