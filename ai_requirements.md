# DotAgent AI Assistant — 功能需求文档

> 本文档面向 DotAgent 插件开发者，列出为了让 AI 助手（我）更流畅、更可靠地工作，插件需要新增或改进的功能。
> 按优先级从高到低排列。

---

## 🔴 P0 — 阻断级（没有就会频繁出错/卡死）

### 0.1 FileTailReader（读取大文件末尾）
**痛点：** conversation.md 通常 80k+ 字符，`read_resource_as_text` 只能读前 N 字符，无法读末尾。我不得不写复杂的 GDScript 提取最后几行。

**需求：** 新增工具 `read_file_tail(path, max_chars, max_lines)`，从文件末尾往回读取。
- 默认返回末尾 3000 字符
- 可选按行数截断（如末尾 50 行）
- 解决：读历史对话末尾、读日志末尾

### 0.2 execute_gdscript 输出可靠捕获
**痛点：** `push_error()` / `print()` 输出经常无法通过工具 result 返回来。目前返回值为空字符串 `"(no return value)"`。我在测试中写了 FileAccess 写入临时文件来绕过。

**需求：** 改进 `_tool_execute_gdscript` 的 stdout/stderr 捕获机制：
- 用 `OS.execute` 或重定向 Godot 的 stdout 到字符串缓冲区
- 确保 `print()` 和 `push_error()` 的输出都能被捕获
- 对长输出做截断（5KB 上限）

### 0.3 ReAct 循环最大轮次保护
**痛点：** LLM 可能陷入无限工具调用循环（比如不断调 `get_scene_tree` 或反复修复一个永远不会好的 bug）。目前无任何保护。

**需求：** 在 `dock_controller.gd` 的 `_run_react_loop()` 中增加：
- `MAX_REACT_ROUNDS = 15`，达到后自动终止循环
- 在 completion 消息中附加 `"⚠️ Max tool rounds reached"`
- UI 上显示 "Round 12/15" 计数器

### 0.4 空场景自动保存保护
**痛点：** `scene_tools.gd` 的 `_emit_change()` 在场景无文件路径时只 log warning 不保存。但我用 `create_scene` + `add_node` 构建场景后，修改不会被存盘。切场景或运行项目时数据丢失。

**需求：** `create_scene` 成功后，自动标记场景为"已修改"状态，让 Godot 在适当时提示保存。或 `add_node` 检测到场景无路径时，用原 `create_scene` 的 path 自动保存一次（第一笔写操作主动保存）。

---

## 🟠 P1 — 高优先级（日常使用频繁受阻）

### 1.1 多文件批量读取
**痛点：** 要理解一个功能，我经常需要同时读 3-5 个相关文件（如 .gd + .tscn + 引用的 autoload）。逐个调 `read_script` 来回 5 轮太浪费。

**需求：** 新增工具 `read_multiple_files(paths: string[])`，同时读取多个文件，返回 `{path: content}` 的 JSON 对象。每个文件限制 2000 字符（可配置 max_chars_per_file）。

### 1.2 搜索带上下文行
**痛点：** `search_in_scripts` 只返回匹配行+行号，没有上下文。比如找到 `change_scene_to_file` 出现 5 次，但不知道每次是在什么函数里调用的。

**需求：** 在 `search_in_scripts` 返回值中增加 `context_lines`（匹配行前后各 2 行），或者新增一个 `grep_with_context(query, context_lines=3)` 工具。

### 1.3 Token 使用量可见性
**痛点：** 我（LLM）不知道自己当前用了多少 token。`context_label` 只在 UI 上显示给用户看，但我无法读取它。经常写到 context 炸了被截断。

**需求：**
- 自动注入当前 token 使用量到 system prompt 的动态上下文中（由 `_build_dynamic_context()` 添加一行 `"- 当前 context: %dK / %dK"`）
- 当使用量超过 60% 时，在 system prompt 附加警告 `"⚠️ Context is at %d%%，建议 compact"`

### 1.4 自动上下文压缩（Auto Compact）
**痛点：** 会话变长后，LLM 响应变慢变差。手动点 Compact 不现实（AI 不知道什么时候该压）。

**需求：** 在每轮 tool round 完成后，检测 `_messages` 总 token 估算值。如果超过 context_limit 的 70%，**自动触发 `compact_context(keep_exchanges=3)`**，并在下一轮的消息中注入压缩通知。

### 1.5 备份恢复预览
**痛点：** `undo_last` 直接覆盖文件，我不知道备份里是什么内容。有时恢复后场景炸得更厉害。

**需求：** 新增工具 `preview_backup(target_path)`，列出该文件最近的 3 个备份及时间戳，可预览差异（simple diff）。`undo_last` 可接受可选参数 `backup_index` 指定恢复到哪个版本。

### 1.6 执行 GDscript 的异步超时
**痛点：** 某些 GDscript snippet 包含 `await` 或死循环，会永久挂起 ReAct 循环。目前没有超时保护。

**需求：** `_tool_execute_gdscript` 执行时加 watchdog：
- 最大执行时间 15 秒
- 超时后强制终止（用 `OS.kill` 或通过 SceneTree 强制退出）
- 返回 `"⚠️ Snippet timed out after 15s"`

---

## 🟡 P2 — 中优先级（显著提升体验）

### 2.1 编辑器输出面板读取
**痛点：** `open_scene` 失败时，错误信息只出现在 Godot Output 面板，我无法读取。只能用 `run_scene_capture` 间接验证。

**需求：** 新增工具 `read_editor_output(max_lines=50)`，读取 Godot 编辑器的 Output 面板最近 N 行文本。这样 `open_scene` 失败时我能直接看到原因。

### 2.2 场景结构摘要（不是完整树）
**痛点：** `get_scene_tree` 返回完整 JSON 树，深度 3 时已有 100+ 行。我很多时候只需要知道"有哪些节点及它们的类型"。

**需求：** 新增 `get_scene_tree_summary()` 返回扁平列表 `[{name, type, path, child_count}]`，每个节点一行。适用于快速定位节点。

### 2.3 工具流式进度反馈
**痛点：** 当 LLM 同时调多个工具（如 add_node 重复调用 5 次建 UI），中间没有进度反馈。如果第 3 个失败了，用户看到的是 5 个结果一起出来。

**需求：**
- `tool_started/tool_finished` 信号已经存在，但 `activity_panel` 的日志写入是即时的
- 在 ToolRegistry 层增加 `_current_tool_index` 和 `total_tool_count`，通过信号 `tool_progress(current, total)` 发送
- 这样 UI 可以显示 "Tool 3/5: add_node"

### 2.4 跨 session 记忆查询
**痛点：** `remember` / `recall` 只读写 `.dotagent_memory.md`，但那是单层文本，无法按 session 查询。我忘了之前改过什么。

**需求：**
- `.dotagent_memory.md` 支持按 session_id 分组标记
- 新增 `recall_session(session_id)` 读取指定 session 的 conversation.md 摘要
- 新增 `search_memory(query)` 在记忆文件中搜索

### 2.5 文件修改后自动 reload 但不 kill coroutine
**痛点：** `script_tools.gd` 的 `_tool_create_script` 不调 `_refresh_filesystem()` 因为会触发 Godot 全局脚本重载，杀掉挂起的协程。但这样新建的 .gd 文件不会立即出现在编辑器文件系统中。

**需求：** 实现一个安全的 `_safe_refresh()`：
- 只扫描新增文件，不触发全局重载
- 或者在 ReAct 循环外（request_completed 后）才调 `_refresh_filesystem()`

### 2.6 新增 run_scene_capture 的轻量模式
**痛点：** `run_scene_capture` 每次 spawn 一个新 Godot 进程（200MB+），频繁调用吃内存。

**需求：** 增加轻量模式：
- `lightweight=true` 使用 `EditorInterface.play_custom_scene()` + `stop_playing_scene()` + 临时 stdout hook
- 或使用 `OS.create_process` 异步启动 + polling stdout 而非阻塞执行
- 默认保持当前实现，但加参数 `lightweight` 切换

---

## 🟢 P3 — 低优先级（锦上添花）

### 3.1 Scene 节点路径模糊匹配
**痛点：** 用户说"改那个按钮"或"列表里的第三项"，我不知道是哪个节点。`resolve_node` 只支持精确路径。

**需求：** `get_node` 和 `set_node_property` 支持模糊匹配：
- `path="*Button"` 匹配所有以 Button 结尾的节点
- `path="%Inventory"` 匹配 unique_name 为 Inventory 的节点（不管路径）
- 返回匹配列表，让 LLM 选择

### 3.2 当前编辑场景自动保存
**痛点：** 我改了场景但忘记调 `save_scene`，下次 `run_scene_capture` 跑的其实是旧版本。`_emit_change()` 已经在每个写操作后自动保存了，但万一异常中断（script reload）就可能丢失。

**需求：** 在 `_emit_change()` 中增加异常保护：
```gdscript
func _emit_change() -> void:
    # ... 现有代码 ...
    var err := ei.save_scene()
    if err != OK:
        # 尝试重新打开再保存
        var path = root.scene_file_path
        ei.open_scene_from_path(path)
        ei.save_scene()
```

### 3.3 项目文件变更事件通知
**痛点：** 用户手动改了 .tscn / .gd 文件（在外部编辑器），我不知道。下次我读文件时读到旧版本。

**需求：** 在 `_build_dynamic_context()` 中注入文件变更通知：
```gdscript
var last_scan = ei.get_resource_filesystem().get_filesystem().get_last_modified()
var last_check = _last_context_check
if last_scan > last_check:
    dynamic += "\n- ⚠️ 文件系统有变更（上次检查后有文件被修改）"
```

### 3.4 工具调用参数校验
**痛点：** 我给 `set_node_property` 传了错误的参数类型（比如 string 当成 number），工具直接崩但返回 ok=true。

**需求：** 在每个工具实现中增加参数类型校验：
- `add_node` 的 `type` 参数：检查 `ClassDB.class_exists(type)`
- `set_node_property` 的 `value`：尝试类型转换，失败则返回 err
- `path` 参数：统一校验非空

### 3.5 Session 全量导出 & 导入
**痛点：** 用户想备份当前工作会话（包含所有工具调用记录和错误修复过程），目前只有 `export_session` 导出单次 log。

**需求：** 新增 `export_session_full(session_id)`，导出：
- messages.json（完整）
- session.json
- 所有相关的备份文件（可选）
- 打包成单个 JSON 或 Markdown

### 3.6 指令级 Undo（不只是场景级）
**痛点：** `undo_last` 只恢复场景文件。如果我做了 `update_script` + `set_node_property` + `set_project_setting`，只能恢复最后一个场景操作，脚本和项目设置无法回退。

**需求：** 实现操作历史栈：
- 每次写操作（场景/脚本/项目设置）自动记录到 `.dotagent_backups/operations.json`
- `undo_last` 可指定 `target="scene"` / `"script"` / `"project"` / `"all"`
- 支持 `undo_n(2)` 回退两步

---

## 📊 总结优先级矩阵

| 优先级 | 数量 | 核心价值 |
|--------|------|----------|
| P0 (阻断) | 4 | 不死循环、不丢数据、能读到信息 |
| P1 (高频) | 6 | 每天省 30+ 轮工具调用 |
| P2 (体验) | 6 | 流畅感、透明度提升 |
| P3 (增强) | 6 | 容错、可回溯、灵活匹配 |

**如果只能选 5 个做：** 0.1 → 1.3 → 0.3 → 1.1 → 2.1

---

## 💡 附：自检清单

以下功能我已经有了，**不需要重复造轮子**：

- ✅ 场景 CRUD（create / get / set / add / remove / reparent）
- ✅ 脚本 CRUD（read / create / update / list / search / replace）
- ✅ 项目信息读取 & 设置修改
- ✅ 文件读写（write_file / read_resource_as_text）
- ✅ 记忆持久化（remember / recall）
- ✅ Session 管理（create / switch / rename / fork / delete）
- ✅ 备份 & 恢复（undo_last 场景级）
- ✅ 流式 LLM 响应 + watchdog 超时保护
- ✅ 脏数据检测（switch_session 时清理不配对的 tool_calls）
- ✅ 上下文动态注入（当前场景/选中节点/Godot版本）
