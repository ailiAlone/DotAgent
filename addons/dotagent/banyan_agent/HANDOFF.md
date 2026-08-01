# Banyan Agent 交接文档（2026-08-01 晚）

> 写给接手的 agent：这里记录当前状态、操作手册和坑。先读这个，再读
> `COMMERCIAL_GAP_ANALYSIS.md`（差距清单与优化日志）、`AGENT_WORKFLOW.md`、`ARCHITECTURE.md`。

## 当前状态一句话

❶运行时闭环、❸成功率基准、❹长任务韧性 **三项已完成并全量回归绿灯**；
基准首轮 **15/15 = 100%**。下一步候选：❷多模型适配（owner 已暂缓，说"模型不用管"）、❺规划层（观察中）。

## 本轮（2026-08-01 下午）交付清单

| 交付 | 位置 | 验证 |
|---|---|---|
| `run_game_check` 工具（运行时冒烟闭环） | `addons/dotagent/tools/exec_tools.gd` + `tools/runtime_smoke.gd` + `banyan_agent/tools/definitions/node_tools.json`（32 工具）+ `prompts/node_prompt.md` 引导 | `tests/_test_run_game_check.gd` 端到端通过 |
| 长任务韧性 | `tree/agent_node.gd`（wind_down/abort 终态保护/from_dict 残留态归一化）+ `tests/run_banyan_headless.gd`（优雅收束看门狗、30s 定期存树、心跳活动去重） | `tests/_test_r18_resilience.gd` 13/13 |
| HTTP 传输错误快速失败 | `banyan_agent/http/request_slot.gd` 的 `_poll_waiting`/`_poll_reading` | `tests/_test_r19_slot_errors.gd` 6/6 |
| API key strip 加固 | `config/config_manager.gd` `get_api_key()` | 实战验证（A1 通过） |
| 同参数连败守卫 | `tree/agent_node.gd` `_execute_tool_round`（`_fail_sig_counts`） | X3 复测 148.6k/204s → 10.6k/31s |
| 成功率基准 | `tests/benchmark/tasks.json`（15 任务）+ `tests/_benchmark.py` + `tests/benchmark/report.md` | 首轮 15/15 |

## 操作手册

### 跑一次真实无头 Banyan 任务
```bash
KEY=$(reg query "HKCU\\Environment" //v DOTAGENT_API_KEY | awk '/DOTAGENT_API_KEY/ {print $3}' | tr -d '\r\n')
DOTAGENT_API_KEY="$KEY" BANYAN_TASK="任务文本" \
  "E:\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe" \
  --headless --path "E:\Projects\DotAgent" --script res://tests/run_banyan_headless.gd
```
**密钥提取必须用上面这行**（`awk '/DOTAGENT_API_KEY/ {print $3}' | tr -d '\r\n'`）——
旧的 `awk '{print $3}'` 会把空行的空字段拼成前导换行，产生 `Bearer \n\nsk-...` 被服务器 400。

### 跑基准
```bash
python tests/_benchmark.py --only A1,M1   # 部分任务（bash 前台 300s 上限，建议每次 ≤2 个）
python tests/_benchmark.py                # 全部（会逐任务跑，注意分批）
python tests/_benchmark.py --report       # 由 results.jsonl 重新生成 report.md
python tests/_benchmark.py --restore      # 恢复快照 + 清理 bench_* 产物
python tests/_benchmark.py --snapshot     # 强制重拍基线快照
```
- 快照只在首次建立（`_snapshot/` 不存在时），防止中间态污染基线；换基线用 `--snapshot`。
- 评分 = 运行 COMPLETED + 全部 checks 通过；预算超支单列 `budget_ok` 不影响 pass。
- 任务效果是**累积的**（后面的任务看得到前面的产出），顺序执行。

### 诊断与分析
- `python tests/_trace_analyze.py` — 吃最新 `sessions/*/run_*.json`，输出成本/失败/复读/空转四类浪费。
- `tests/_count_tools.gd` — 工具模块加载计数（exec_tools 现 13 个，全模块 76）。
- `tests/_check_scene_load.gd` — 20 场景 script 挂接回归。
- 回归套件（改动后必跑全部）：`_test_r10_fixes`(58) `_test_r18_resilience`(13) `_test_r19_slot_errors`(6)
  `test_banyan_fixes`(5) `test_round_budget`(5) `_test_new_fixes`(7) `_test_fuzzy_replace`(8)
  `test_ui_compile` `_check_scene_load`(20)。
- 新增 GDScript 文件后 Godot 会生成同名 `.uid`；**删 .gd 要连 .uid 一起删**（孤儿 .uid 会报警）。

## 关键坑（都踩过，别再踩）

1. **Windows 嵌套 Godot 子进程**：`OS.execute` 管道捕获会死锁。必须 `OS.create_process("cmd.exe", ["/c", inner])`
   + 输出重定向到 `user://` 临时文件 + `OS.is_process_running(pid)` 轮询。
   cmd `/c` 的命令串**不要整体再包一层引号**（触发 cmd 引号规则解析失败、日志不落盘）。
2. **HTTP 状态机**：`HTTPClient` 的 CONNECTION_ERROR/TLS_HANDSHAKE_ERROR/CANT_* 都是终态错误，
   任何"重试下一帧"写法都会永久挂起。Pool 看门狗 90s（`SLOT_WATCHDOG_TIMEOUT`）兜底。
3. **看门狗活动判定**：LLM 等待循环每 0.5s 发同状态心跳（流式展示用），不能算作活动；
   真活动 = 状态变化 / progress_chunk / 工具开始结束。
4. **测试脚本**：SceneTree 测试必须注册进 `_init`；`_init` 里报错会表现为"挂死"（主循环永不退出）。
5. **工具改动三处同步**：`tools/*.gd` 实现 + `banyan_agent/tools/definitions/node_tools.json` 定义
   + `prompts/node_prompt.md` 引导。执行路由是通用的（非管理工具直转 ToolRegistry），不用改 executor。
6. **游戏文件是 Banyan 的产出**：我只做修复性/清理性改动，功能留给 agent 写。
   跑基准/实验后**必须恢复或清理**（bench_*、BENCH_* 这类脚手架不许留在游戏文件里——曾清过一轮）。
7. **不主动 git commit**；改动只动 `addons/dotagent/` 和 `tests/`。
8. `run_game_check`/`runtime_smoke` 从**磁盘**读场景——验证前先确认改动已保存（set_node_property 会自动存）。

## 当前性能基线（首轮基准，2026-08-01）

| 类型 | 成功率 | 平均 in_tokens | 平均耗时 |
|---|---|---|---|
| 分析 ×4 | 4/4 | 29.9k | 55s |
| 微改 ×4 | 4/4 | 15.9k | 28s |
| 新域 ×3 | 3/3 | 14.2k | 53s |
| 跨域 ×4 | 4/4 | 20.6k | 57s |

优化参照点：跨节点曾 163s/62k、微改动曾 77s/57k、X3 同类任务曾 148.6k/204s（连败守卫后 10.6k/31s）。

## 下一步候选（按 owner 意图排序）

1. **每轮优化后重跑基准防回退**——成功率是当前唯一硬指标，掉下 100% 要查原因。
2. ❷ 多模型适配：owner 说"模型不用管"，但若要量化，用基准集换模型跑一遍即可，基础设施已就绪。
3. ❺ 规划层：基准数据显示当前任务规模下不需要；更大任务出现"漂移"时再评估。
4. hud.gd 引用 9 个缺失 `%UniqueName` 节点（ResumeButton/RestartButton/QuitButton/WeatherIconLabel/
   ComboLabel/SprintLabel/BossWarningLabel/SlowMoLabel/MagnetLabel）——真实运行时错误，
   run_game_check 每次都会报。适合作为给 Banyan 的下一个修复任务（让它自己闭环修）。

## 环境与数据

- Godot 4.5.1：`E:\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe`
- 模型 MiniMax-M2.7-highspeed（`https://api.minimaxi.com/anthropic/v1`），key 在注册表 `HKCU\Environment\DOTAGENT_API_KEY`
- 运行证据：`addons/dotagent/banyan_agent/sessions/`（56 次运行）、`tests/benchmark/results.jsonl` + `logs/` + `report.md`
- 持久化树：`addons/dotagent/banyan_agent/persistence/agent_tree.json`（Root + Enemy/Game/Ui 等子节点，跨会话知识复利的关键，别删）
