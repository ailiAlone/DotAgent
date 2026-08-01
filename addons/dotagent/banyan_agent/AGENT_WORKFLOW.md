# Agent 驱动 Banyan 的工作手册

> 本文档面向**操作本插件的 AI agent**（以及想了解这条工作流的人类开发者）。
> 记录一个外部 agent 如何绕过编辑器 UI、以无头方式给 Banyan 下达任务、读取它的执行轨迹、
> 评估输出质量、定位插件缺陷并验证修复的完整闭环。
> 本文由 Kimi 在 2026-07-28 的实际迭代过程中总结，所有案例均为真实运行。

---

## 1. 总览：闭环长什么样

```
下任务（无头运行） → 读轨迹（run log / messages / tree） → 评估（任务真的完成了吗？）
     ↑                                                        ↓
回归测试 ← 可视化验证（截图） ← 修复插件 ← 定位根因（数据层 or 渲染层？）
```

核心原则：**不要凭日志猜，要让系统自己拿出证据**——数据层问题打印内部状态，渲染层问题直接截图回读。

## 2. 给 Banyan 下达任务（无头驱动）

驱动器：`tests/run_banyan_headless.gd`。它绕过 EditorPlugin UI，复刻 `plugin.gd` 的运行时装配
（Pool / ToolRegistry / AgentTree / Root 节点），并挂接实时监控输出。

```bash
# 从 Windows 注册表读 API key（用户配置在环境变量 DOTAGENT_API_KEY）
KEY=$(reg query "HKCU\\Environment" //v DOTAGENT_API_KEY | tr -d '\r' | grep DOTAGENT_API_KEY | awk '{print $3}')

BANYAN_TASK="给项目添加一个设置菜单系统：创建 settings_menu.tscn…" \
DOTAGENT_API_KEY="$KEY" \
godot --headless --path "C:\path\to\project" --script res://tests/run_banyan_headless.gd \
  2>&1 | tee tests/_live_run.log
```

### Godot 路径解析

`C:\Users\aili\bin\godot` 是一个 **bash 包装脚本**（110 bytes），内容指向真正的 exe：

```bash
#!/bin/bash
"C:/Users/aili/Downloads/Compressed/Godot_v4.5-stable_win64.exe/Godot_v4.5-stable_win64.exe" "$@"
```

Git Bash / MSYS2 可以执行它，但 **PowerShell 和 CMD 无法执行 bash 脚本**。
在这些环境中必须使用真正的 exe 路径：

```
C:\Users\aili\Downloads\Compressed\Godot_v4.5-stable_win64.exe\Godot_v4.5-stable_win64.exe
```

桌面上可能还有 `Godot_v4.6.1` 等其他版本的 exe，注意区分——`godot --version` 确认是 `4.5.stable`。

### PowerShell 驱动方案（推荐，输出捕获更可靠）

```powershell
$env:DOTAGENT_API_KEY = [Environment]::GetEnvironmentVariable("DOTAGENT_API_KEY", "User")
$godot = "C:\Users\aili\Downloads\Compressed\Godot_v4.5-stable_win64.exe\Godot_v4.5-stable_win64.exe"
$project = "C:\Users\aili\Desktop\DotAgent"

# 用 System.Diagnostics.Process 捕获 stdout+stderr（Out-File / Tee-Object 会丢中文）
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $godot
$psi.Arguments = "--headless --path `"$project`" --script res://tests/run_banyan_headless.gd"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables["DOTAGENT_API_KEY"] = $env:DOTAGENT_API_KEY

$p = [System.Diagnostics.Process]::Start($psi)
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()

$stdout | Out-File "tests/_live_run.log" -Encoding utf8
```

要点：

- **BANYAN_TASK** 环境变量传任务文本；不传则跑默认的只读任务。
- **看门狗 260 秒**（`WATCHDOG_SEC`）超时强制 abort，仍写 trace、保存树。编辑器里无此限制，
  所以"被看门狗截停"≠ 插件失败。
- 实时监控（`[MON]` 行）逐节点打印：状态迁移、工具开始/结束、流式生成字符数。
  这是判断"节点是不是活的"的最快途径。
- 前台命令最长 300 秒；看门狗 260 秒 + 收尾正好放得下。
- **API Key 获取**：`reg query "HKCU\Environment"` 在某些环境不可靠，
  PowerShell 的 `[Environment]::GetEnvironmentVariable("DOTAGENT_API_KEY", "User")` 更稳定。
- **中文编码**：PowerShell 的 `Out-File` / `Tee-Object` 默认编码可能丢中文，
  用 `System.Diagnostics.Process` 的 `StandardOutput.ReadToEnd()` + `-Encoding utf8` 写入更可靠。

## 3. 读取输出：三个信息源，各有分工

| 来源 | 路径 | 回答什么问题 |
|------|------|-------------|
| 运行轨迹 | `addons/dotagent/banyan_agent/sessions/<会话>/run_*.md` / `.json` | 每一轮想了什么、调了什么工具、成功还是失败、最终状态 |
| 会话消息 | `sessions/<会话>/messages.json` | 用户看到的对话（蒸馏后），含实际下发的 system prompt 和任务原文 |
| 持久化树 | `persistence/agent_tree.json` | 节点集合、状态、父子关系、managed_files、domain_knowledge |

读轨迹时的检查清单：

1. **轮次序列**：每轮的 `llm_preview`（思考）+ `tools`（工具调用）。空轮（无思考无工具）
   通常是 Nudge 拦截轮——模型发了无推理的工具调用被丢弃。
2. **执行类工具是否为 0**：`build_scene/build_script/update_script/write_file/patch_scene/…`
   一次都没出现 = 只分析没干活（见 §6 案例 A）。
3. **失败工具的 result_preview**：工具失败原因往往直接写在里面（语法校验、参数格式、文件已存在）。
4. **最终 summary 的形状**：如果是 "Project Overview / System Modules / Issues Found" 模板腔，
   那是收束模板生成的，**不代表任务成果**——必须对照磁盘上的真实产物（`ls`、grep 文件内容）。

## 4. 渲染层问题：截图取证，不要无头猜

无头模式不渲染 GUI，连线/颜色/布局问题必须**真实渲染 + 截图 + 回读图片**：

```bash
# 注意：截图验证不能加 --headless（会短暂弹出窗口，属正常）
godot --path "C:\path\to\project" --script res://tests/_repro_graph_render.gd
```

`tests/_repro_graph_render.gd` 的模式值得复用：把嫌疑场景拆成独立的**场景用例**，
每个用例操作完后等待若干帧再截图。本次连线迭代覆盖了 5 个场景：

1. 面板隐藏时收到 `update_tree` 再显示（模拟编辑器重载）；
2. 平移 `scroll_offset` + 缩放 `zoom`；
3. 内容更新撑大节点卡片（scroll/zoom 不变）；
4. 手动拖动节点（不经过 `update_tree`）；
5. 缩放状态下拖动节点（用户反馈的精确操作）。

数据层的图问题用 `tests/_repro_graph_reload.gd`：打印 `_tree_data`、每个 GraphElement 的
`position_offset/global_position/size`、每条连线的 `_from_dir/_to_dir`。`<none>` 就是没设上。

**教训**：渲染 bug 的根因经常在"坐标在什么时候有效"。GraphEdit 的 `position_offset` 是同步赋值
（随时可信），`global_position` 要等下一帧（加载时不可信），新建 slot 控件的坐标要等容器排版
（重建后一帧内不可信）。采样之前先想清楚你读的值处于哪个时序阶段。

## 5. 回归测试

| 套件 | 覆盖 |
|------|------|
| `tests/test_banyan_fixes.gd` | 脚本编译、工具清单、prompt 内容 |
| `tests/test_ui_compile.gd` | UI 编译 + 面板增量更新行为 + 节点状态颜色 |
| `tests/test_round_budget.gd` | 轮数预算制（Root 无限、子节点申请、断链拒绝） |

注意：`test_all_tools.gd` 会留 `test_skill.md` 残留，导致下次 create_skill 误报，删掉即可。

## 6. 真实案例：失败诊断记录

### 案例 A：Root 只分析不干活（假完成）

- **现象**：任务"添加设置菜单系统"跑了 11 轮 COMPLETED，但磁盘上没有任何新文件。
- **轨迹证据**：9 次工具调用全是只读（list/read/inspect），执行类 0 次；R3/R5/R9 空轮
  （Nudge 拦截）；R11 直接输出文字收工。
- **关键发现**：最终 summary 是收束模板（`_request_convergence_summary`）无条件生成的
  架构分析，并把节点洗成 COMPLETED——漂亮的报告掩盖了零产出。
- **修复**：FINISH 前做成果校验（零执行/零文件/零委派 → 挑战一次，要求继续或明确声明
  纯分析）；收束不再无条件转 COMPLETED；prompt 补 Completion Criteria。
- **验证**：同一任务无头重跑，执行类工具 5 次，`settings_menu.tscn` / `settings_manager.gd`
  真实落盘。

### 案例 B：重载后连线消失 / 偏差（一串时序 bug）

- **现象**：重启编辑器后连线全没；修好后又出现"缩放正确、移动节点有固定偏差"。
- **取证**：无头脚本打印出 `_from_dir=<none>`（slot 根本没建）；截图发现连线冻在滚动前坐标。
- **根因链**：① `_setup_slots` 用 `global_position`（加载时未生效，方向为 0 跳过建 slot）；
  ② 连线层只在 refresh 时重绘，平移/缩放/节点尺寸变化后冻结；③ 几何监听只重绘不重选槽位；
  ④ `_draw` 采样新建 slot 的 `global_position`（容器排版前是旧值）。
- **修复链**：方向改用 `position_offset` → 几何签名（scroll/zoom/节点位置/尺寸/slot 中心）
  驱动重绘 → 位置变化时重选槽位 → **slot 持久化**（只增减排尾差额，不整体重建）后恢复
  采样槽点中心，连线精确落在各自槽点上。

### 案例 C：CTX 重载归零

- **根因**：messages 不持久化（P0-2 设计），`get_ctx_size()` 现算必然得 0。
- **修复**：`ctx_size` 随树持久化，messages 为空时展示持久值，开跑后自动切回实时值。

### 案例 D：无头模式静默无输出（路径解析陷阱）
- **现象**：通过 PowerShell / CMD 执行 `C:\Users\aili\bin\godot --headless …`，进程瞬间退出，
  无 stdout/stderr，退出码为空，日志文件仅有 `EXIT_CODE=`。
- **根因**：`C:\Users\aili\bin\godot` 是 bash 包装脚本（110 bytes，`#!/bin/bash` 开头），
  Git Bash 可以执行，但 PowerShell / CMD 把它当作普通文件，不识别 shebang。
- **排查**：`Get-Item` 发现文件只有 110 bytes → 读内容确认是 bash 脚本 →
  找到真正的 exe 路径 `C:\Users\aili\Downloads\Compressed\Godot_v4.5-stable_win64.exe\…`。
- **修复**：直接用完整 exe 路径调用，不再依赖 `C:\Users\aili\bin\godot`。
- **附加坑**：`reg query "HKCU\Environment" /v DOTAGENT_API_KEY` 在某些 shell 环境下
  也取不到值，改用 PowerShell `[Environment]::GetEnvironmentVariable("DOTAGENT_API_KEY", "User")`
  更可靠。
- **教训**：无头驱动失败时，**先验证 Godot 是否真的启动了**（`tasklist | grep Godot`），
  再看输出。进程瞬间退出 + 零输出 = 路径问题，不是插件问题。

### 案例 E：工具全灭——模型用 `[TOOL_CALL]` 伪文本代替真实工具调用（2026-07-31）

- **现象**：任务 9.2s "完成"，轨迹里 0 次真实工具调用，最终 summary 是模型用
  `[TOOL_CALL] {tool => "list_files", args => {...}} [/TOOL_CALL]` 伪格式写的文本。
  比案例 A 更底层——连挑战机制都无从触发，因为根本没有工具可供调用。
- **根因链**：① `AnthropicProvider._adapt_tools()` 没拆 OpenAI `{"type":"function","function":{...}}`
  封装，`t.get("name")` 取空 → **31 个工具全部静默丢弃**，模型只能凭训练记忆写伪调用；
  ② 修复后暴露第二层——Anthropic content block 索引全局递增（thinking/text 也占位），
  按索引补槽产生 name/id 全空的幻影 tool_call，回发时 API 报 `duplicate tool_call id: ""`。
- **排查**：`curl` 直接打端点验证工具调用能力（端点正常返回 tool_use 块）→ 锁定问题在
  我方序列化层。**端点能力与我方代码要分开验证，不要一起猜。**
- **修复**：`_adapt_tools` 先拆 `function` 封装；`get_accumulated_tool_calls()` 过滤空名槽位。
- **教训**：工具适配层改动后，第一轮真实运行就要检查 `[MON] 工具 →` 行的工具名是否非空——
  空工具名 = 幻影槽位特征。

### 案例 F：LLM 参数双重编码与缩进漂移（2026-07-31）

- **现象 A**：`patch_scene` 报 "No operations provided"，但 args_preview 里明明有 operations——
  模型把数组**双重编码成 JSON 字符串**（`"operations": "[{...}]"`），`is Array else []` 吞掉。
- **现象 B**：`replace_in_file` 高频报 "old_text not found"，但文件内容其实匹配——
  模型把 tab 缩进写成 4 空格（或层级漂移），精确匹配失败。Ui 节点曾因此 6 连败。
- **修复**：① `tool_base._as_array()` 统一兜底字符串化数组（patch_scene/build_scene 全应用）；
  ② `replace_in_file` 增加模糊匹配自愈——按行去空白归一化匹配，唯一命中时探测双方
  缩进单位（`\t` vs 空格）按层级翻译后自动应用；多义/未命中时把最相似区域的真实文本
  （含行号）塞进错误消息，下轮即可精确命中，省一次 read。
- **配套**：连续 2 次 Parse Error 注入定向 typing 提醒（user 消息才有效，system 被当背景噪音）。
- **验证**：模糊替换单测 8/8（`tests/_test_fuzzy_replace.gd`）；验证轮 Ui 节点失败 6→0。
- **教训**：**工具的失败消息就是模型下一轮的输入**——把"修复所需的全部信息"塞进错误消息，
  比指望模型自己重读文件更省轮次。

### 案例 G：Root 包办与委派的经济学（2026-07-31 ~ 08-01）

- **现象**：胜利面板任务中 Root 有 3 个专家子节点仍自己实现全部 4 个文件，
  35 轮 / 210k input tokens；route_to_child 只用来事后"同步知识"。
- **对比**：路由机制生效后的同类小改任务——Root 7 轮 / 19k in 纯协调，
  Game 子节点 4 轮搞定（它已持有 game_manager 知识，零重复探索）。
  **Root 成本降 91%，这就是"知识复利"——树架构的核心收益。**
- **机制**：路由推荐（读了子节点管辖文件 + ≥6 轮未路由 → 提醒一次）；
  token 用量全链路采集（parser → slot → execution trace `usage` 字段）让成本可见。
- **坑**：Root 收工但路由出去的子节点还在跑时直接保存，会截断子节点的知识与用量数据
  （trace 出现 rounds>0 但 duration=0/tokens=0 的假象）——驱动器要等整棵树收尾。
- **教训**：评估"更省"要看**委派任务的全树成本**而非只看 Root；子节点读自己管辖的文件
  是复利，Root 读同样的文件是浪费。

### 案例 H：全项目场景 script 集体挂空（2026-08-01，最严重缺陷）

- **现象**：`tests/_check_scene_load.gd` 加载普查发现——**全部 17 个场景的 script
  属性都是 String/Dictionary 而非 Script 资源**。游戏在引擎里从未真正运行过任何脚本；
  此前所有"完成"都只是文件落盘。enemy.tscn 甚至是 `script = {"path": ..., "type": ...}`
  字典字面量，victory_panel.tscn 是 `script = {"__uuid__": ...}` 幻觉 UUID。
- **根因**：① 场景文件由 LLM 以文本手写（`write_file`），`script = "res://x.gd"`
  字符串不会被 tscn 解析器还原为资源；② `patch_scene` 的 `set script` 把字典
  原样 set 进 script 槽并被序列化器落盘；③ 最致命的是 `inspect_scene_structured`
  对非 Resource 的 script **静默省略**——每次"验证"都报 OK，验证形同虚设。
- **修复**：`tests/_repair_scene_scripts.py` 批量改为 `ExtResource` 引用；
  `_apply_node_property`（_op_set/_op_add 共用）对 script 特判——只接受可加载的
  脚本路径并 `set_script()`，否则拒绝；`_serialize_node` 显式输出
  `script: {broken: true, raw_type: ...}` 且 observations 升级为最高优先级告警。
- **教训**：**"语法检查通过"≠"能运行"**。验证工具自身要对"看起来有输出"保持怀疑——
  缺数据时应该报缺，而不是跳过。加载级回归（`_check_scene_load.gd`）现在属于
  每次场景改动后的必跑套件。

## 7. 工作约定（本仓库实测有效的规则）

- 任务只改插件（`addons/dotagent/`）和 `tests/`，游戏文件交给 Banyan 自己动。
- 跑会写树的测试前**先备份 `persistence/agent_tree.json`**，测完恢复。
- 不主动 `git commit`——提交需要用户明确指令。
- 编辑器里 running 的插件实例不会热加载脚本改动，验证修复必须请用户重启编辑器
  （或重新加载项目）。
- "显示是否正确"这类问题，优先写可重复的可视化复现脚本，而不是让用户反复描述现象。
