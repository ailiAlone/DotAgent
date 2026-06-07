# AI Panel

Godot 编辑器 AI 对话面板。OpenAI 兼容协议(DeepSeek / Moonshot / Ollama 等),带完整工具调用权限,能直接动手改你的项目。

## 截图占位

```
┌─ AI Panel ────────────────── [Activity] [Clear] [Settings] ─┐
│                                                             │
│  system                                                      │
│  你是 Godot 编辑器 AI 助手...                                │
│                                                             │
│  [当前上下文]                                                │
│  - 当前场景: res://scenes/main.tscn                          │
│  - 选中节点: Player (CharacterBody2D)                        │
│                                                             │
│  AI                                                          │
│  我看了下你的 Player 节点,速度字段在 line 23,改成 300 吧?  │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Ask AI to do something... (Enter to send)  [Send] [Stop]    │
└─────────────────────────────────────────────────────────────┘
```

## 安装

1. 整个 `addons/dotagent/` 目录拷到你的 Godot 项目 `addons/` 下
2. Godot 编辑器 → Project → Project Settings → Plugins
3. 启用 "AI Panel"
4. 编辑器右下角出现 "AI Panel" 面板
5. 编辑器底部出现 "AI Activity" 面板(显示工具调用过程)

## 配置

点 AI Panel 右上角 **Settings**:

- **Base URL** — OpenAI 兼容 API 地址,例如:
  - `https://api.openai.com/v1`
  - `https://api.deepseek.com/v1`
  - `http://localhost:11434/v1` (Ollama)
- **API Key** — 你的 key(只存在本地 `addons/dotagent/config.cfg`,不进 git)
- **Model** — 模型名,例如 `gpt-4o` / `deepseek-chat` / `qwen2.5-coder:7b`
- **Max Tokens** / **Temperature** — 采样参数

点 **Test Connection** 验证能联通。

## 使用

直接在输入框打字,Enter 发送,Shift+Enter 换行。AI 收到后会:

1. 自动看到当前场景结构、选中节点、Godot 版本(每次请求前注入)
2. 决定要不要调工具
3. 调工具时结果会显示在底部 "AI Activity" 面板
4. 危险操作(覆盖脚本、删除节点、执行 GDScript)会弹一次确认

底部 "AI Activity" 面板展示:
```
14:23:01  🔧 get_node("Player")           [running]
14:23:01  ✓ get_node → {name: "Player", type: "CharacterBody2D", ...}
14:23:02  🔧 set_node_property(path="Player", name="speed", value=300)
14:23:02  ✓ set_node_property → Set Player.speed = 300
```

## 工具列表

**📖 读取(无副作用)**
| 工具 | 干啥 |
|------|------|
| `get_scene_tree` | 拿当前编辑场景的树形结构 |
| `get_node` | 拿单个节点详情 |
| `get_node_properties` | 列节点所有属性 |
| `get_editor_selection` | 拿当前选中的节点 |
| `read_script` | 读 .gd / .cs 脚本内容 |
| `list_scripts` | 列所有脚本 |
| `list_scenes` | 列所有场景 |
| `list_resources` | 列所有资源 |
| `list_files` | 列目录下文件 |
| `get_project_info` | 拿项目名、版本、autoloads |
| `get_project_setting` | 读 project.godot 设置 |
| `get_node_type_info` | 拿类(属性/方法/信号)信息 |
| `search_in_scripts` | 跨脚本搜字符串 |

**✏️ 写入(改项目状态)**
| 工具 | 干啥 |
|------|------|
| `set_node_property` | 改节点属性 |
| `add_node` | 加新节点 |
| `reparent_node` | 移动节点 |
| `create_script` | 创建新脚本 |
| `set_project_setting` | 改项目设置 ⚠️ |

**⚡ 执行(影响运行环境)**
| 工具 | 干啥 |
|------|------|
| `execute_gdscript` | eval 模式跑 GDScript 片段 ⚠️ |
| `call_node_method` | 在节点上调方法 ⚠️ |
| `run_current_scene` | F5 跑当前场景 ⚠️ |
| `stop_running_scene` | F8 停止 |
| `reload_project` | 重新扫文件系统 ⚠️ |
| `remove_node` | 删节点 ⚠️ |
| `delete_file` | (在 update_script overwrite 等工具里隐含) ⚠️ |
| `update_script` | 覆盖已有脚本 ⚠️ |

⚠️ 标记的会弹一次确认对话框。

## 安全 / 备份

- API key 存 `addons/dotagent/config.cfg`,已在 `.gitignore` 中
- 危险操作弹确认对话框
- 写脚本操作前自动备份到 `res://.dotagent_backups/<时间戳>/<原路径>`,最多保留 50 个时间戳目录
- 整个 `.dotagent_backups/` 已在 `.gitignore` 中

要恢复备份:从 `.dotagent_backups/<时间戳>/<路径>` 复制回原位。

## 架构

```
addons/dotagent/
├── plugin.cfg                    插件元数据
├── plugin.gd                     EditorPlugin 入口
├── dock.tscn + dock.gd           主 Dock(消息流 + ReAct 循环)
├── config_dialog.tscn + .gd       设置弹窗
├── activity_panel.tscn + .gd      底部活动面板
├── config_manager.gd              配置持久化
├── llm_client.gd                  OpenAI 兼容客户端 + SSE 流式
├── tool_registry.gd               工具注册中心 + 危险确认
├── backup_manager.gd              自动备份
└── tools/
	├── scene_tools.gd             场景/节点操作
	├── script_tools.gd            脚本读写
	├── project_tools.gd           文件/项目设置
	└── exec_tools.gd              执行类
```

## 已知限制 / TODO

- SSE 流式解析在 Godot 4.4 上是"整段响应后逐 event 推"而非真正逐 token 流(LSP `get_chunked_body` API 待跟进)
- `execute_gdscript` 编译动态代码是高级功能,部分 GDScript 写法可能不兼容
- `get_console_output` 暂未实现完整 console buffer 捕获
- 消息历史不持久化,重启插件会清空
- 没有 markdown 完整渲染(目前只显示纯文本 + BBCode 加粗/颜色)

## 许可

MIT
