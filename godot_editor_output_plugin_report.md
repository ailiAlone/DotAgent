# Godot Editor Output 深度爬取报告 - 使用插件获取 Editor Output

## 核心发现摘要

在 Godot 4.x 中，**EditorInterface 没有提供 `get_editor_log()` 或类似的方法来直接访问编辑器的 Output 面板**。这是一个已知的 API 缺失，社区已通过多个 GitHub Issues 提出需求（#5297、#8879、#1628）。不过，仍有多种方式可以从插件与 Editor Output 系统交互。

---

## 一、Output 面板概述

### 1.1 文档位置
- **英文文档**: https://docs.godotengine.org/en/stable/tutorials/scripting/debug/output_panel.html
- **Logging 文档**: https://docs.godotengine.org/en/stable/tutorials/scripting/logging.html

### 1.2 Output 面板功能

Output 面板位于编辑器底部，提供以下功能：

**消息类别（4种）**:
| 类别 | 颜色 | 说明 |
|------|------|------|
| Log | 白色/黑色 | 标准消息，由项目打印 |
| Error | 红色 | 表示某种失败的消息 |
| Warning | 黄色 | 报告重要信息但不表示失败 |
| Editor | 灰色 | 编辑器打印的消息，通常是 undo/redo 操作跟踪 |

**过滤功能**:
- 通过右侧按钮隐藏特定消息类别
- 使用"Filter Messages"文本框按内容过滤

**自动清除**:
- 运行项目时默认自动清除已有消息
- 由编辑器设置 `Run > Output > Always Clear Output on Play` 控制
- 可手动点击"刷子"图标清除

---

## 二、向 Output 面板写入内容的方法

### 2.1 全局打印函数（GDScript）

这些函数可在插件代码中直接调用：

| 函数 | 说明 | 输出到 Output 面板 |
|------|------|-------------------|
| `print(...)` | 打印消息，多参数自动连接 | 是 |
| `printt(...)` | 参数间用制表符分隔 | 是 |
| `prints(...)` | 参数间用空格分隔 | 是 |
| `print_rich(...)` | 支持 BBCode 格式化 | 是 |
| `print_verbose(...)` | 仅详细模式时打印 | 是 |
| `printerr(...)` | 打印到 stderr | 是 |
| `printraw(...)` | 不换行，仅打印到 OS 终端 | **否** |
| `print_stack()` | 打印当前堆栈跟踪 | 是 |
| `print_tree()` | 打印场景树 | 是 |
| `push_error(...)` | 推送错误到调试器 | 是（Errors 标签页） |
| `push_warning(...)` | 推送警告到调试器 | 是（Errors 标签页） |

### 2.2 print_rich() - 富文本输出

`print_rich()` 支持 BBCode 标签，可以在 Output 面板中显示格式化文本：

**支持的 BBCode 标签**:
- `b` - 粗体
- `i` - 斜体
- `u` - 下划线
- `s` - 删除线
- `indent` - 缩进
- `code` - 代码
- `url` - 可点击链接（点击时调用 `OS.shell_open()`）
- `center` - 居中
- `right` - 右对齐
- `color` - 文本颜色
- `bgcolor` - 背景颜色
- `fgcolor` - 前景颜色

**示例代码**:
```gdscript
print_rich("[color=green][b]Hello world![/b][/color]")
print_rich("[url=https://godotengine.org]点击访问 Godot[/url]")
```

**注意**: 在 Godot 4.4+ 中，`[url]` 标签在编辑器 Output 中支持点击，通过 `OS.shell_open()` 处理。但无法直接在插件中拦截点击事件，因为无法访问 EditorLog 的 `meta_clicked` 信号。

### 2.3 EditorToaster - Toast 通知（替代方案）

如果需要在编辑器中显示通知，可以使用 `EditorToaster`:

```gdscript
var toaster = EditorInterface.get_editor_toaster()
toaster.push_toast("消息内容", EditorToaster.SEVERITY_INFO, "提示文本")
toaster.push_toast("警告内容", EditorToaster.SEVERITY_WARNING)
toaster.push_toast("错误内容", EditorToaster.SEVERITY_ERROR)
```

**Severity 枚举**:
- `SEVERITY_INFO` = 0
- `SEVERITY_WARNING` = 1
- `SEVERITY_ERROR` = 2

---

## 三、从插件读取/拦截 Output 消息

### 3.1 方法1：自定义 Logger（推荐，Godot 4.5+）

从 Godot 4.5 开始，可以创建自定义 Logger 类来拦截引擎的消息流：

```gdscript
extends Node

class CustomLogger extends Logger:
	func _log_message(message: String, error: bool) -> void:
		# message: 日志消息内容
		# error: 如果为 true，表示该消息是发送到 stderr 的
		# 
		# 注意：此方法可能从非主线程调用，需要线程安全处理
		print("[拦截] 消息: ", message, " 是否错误: ", error)
		
	func _log_error(
			function: String,
			file: String,
			line: int,
			code: String,
			rationale: String,
			editor_notify: bool,
			error_type: int,
			script_backtraces: Array[ScriptBacktrace]
	) -> void:
		# error_type: Logger.ErrorType 枚举
		#   ERROR_TYPE_ERROR = 0
		#   ERROR_TYPE_WARNING = 1
		#   ERROR_TYPE_SCRIPT = 2
		#   ERROR_TYPE_SHADER = 3
		print("[拦截] 错误: ", rationale, " 在 ", file, ":", line)

func _init() -> void:
	OS.add_logger(CustomLogger.new())
```

**注册方式**: 将脚本添加为 Autoload，在 `_init()` 中注册

**重要限制**:
- `_log_message()` **不会** 被 `push_error()` 和 `push_warning()` 调用（即使它们打印到 stderr）
- 方法可能从多个不同线程同时调用，需要 `Mutex` 等线程安全机制
- 引擎自身的初始化消息不可访问

### 3.2 方法2：通过节点树遍历获取 EditorLog（Hack）

由于 `EditorInterface` 没有提供 `get_editor_log()` 方法，可以通过遍历编辑器节点树来获取 `EditorLog`：

```gdscript
@tool
extends EditorPlugin

var editor_log: Node = null

func _enter_tree():
	editor_log = get_editor_log(EditorInterface.get_base_control())
	if editor_log:
		print("找到 EditorLog: ", editor_log)

func get_editor_log(base: Control) -> VBoxContainer:
	var class_path = [
		'VBoxContainer',      # 根容器
		'HSplitContainer',    # 水平分割1
		'HSplitContainer',    # 水平分割2
		'HSplitContainer',    # 水平分割3
		'VBoxContainer',      # 中间列
		'VSplitContainer',    # 垂直分割
		'PanelContainer',     # 底部面板容器
		'VBoxContainer',      # Output 容器
		'EditorLog'           # EditorLog 节点
	]
	return find_node_by_class_path(base, class_path)

func find_node_by_class_path(node: Node, class_path: Array) -> Node:
	var stack = []
	var depths = []
	
	var first = class_path[0]
	for c in node.get_children():
		if c.get_class() == first:
			stack.push_back(c)
			depths.push_back(0)
	
	if stack.is_empty():
		return null
	
	var max_depth = class_path.size() - 1
	
	while not stack.is_empty():
		var d = depths.pop_back()
		var n = stack.pop_back()
		
		if d > max_depth:
			continue
			
		if n.get_class() == class_path[d]:
			if d == max_depth:
				return n
			
			for c in n.get_children():
				stack.push_back(c)
				depths.push_back(d + 1)
	
	return null
```

**重要说明**:
- 这是社区提供的"丑陋但可用"的 Hack 方法（来源: godot-proposals#5297）
- 节点路径可能因 Godot 版本不同而变化
- EditorLog 节点名称是自动生成的，无法通过 `find_child("EditorLog")` 可靠获取
- 此方法可能在未来 Godot 版本中失效

### 3.3 方法3：读取日志文件

Godot 默认将日志写入文件，可以读取这些文件：

```gdscript
# 桌面平台默认日志路径
var log_path = "user://logs/godot.log"

# 读取日志文件
if FileAccess.file_exists(log_path):
    var file = FileAccess.open(log_path, FileAccess.READ)
    var content = file.get_as_text()
    file.close()
```

**日志文件配置**:
- 路径：`debug/file_logging/log_path` 项目设置
- 默认保留 5 个日志文件：`debug/file_logging/max_log_files`
- 可禁用：`debug/file_logging/enable_file_logging`
- 崩溃日志也写入同一文件

---

## 四、控制 Output 面板显示

### 4.1 显示底部面板

虽然无法直接访问 EditorLog，但可以显示/切换底部面板：

```gdscript
# 显示底部面板中的特定控件
make_bottom_panel_item_visible(control)
```

如果已通过节点树遍历获取了 EditorLog，可以这样显示它：

```gdscript
if editor_log:
	make_bottom_panel_item_visible(editor_log)
```

### 4.2 添加自定义面板到底部

可以向底部面板（与 Output、Debugger、Animation 同区域）添加自定义控件：

```gdscript
@tool
extends EditorPlugin

var my_panel: Control

func _enter_tree():
	my_panel = preload("res://addons/my_plugin/panel.tscn").instantiate()
	# 新版 Godot (4.x)
	var dock = EditorDock.new()
	dock.add_child(my_panel)
	dock.title = "My Panel"
	dock.default_slot = DOCK_SLOT_BOTTOM
	add_dock(dock)
	
	# 旧版方式（已废弃）
	# add_control_to_bottom_panel(my_panel, "My Panel")

func _exit_tree():
	remove_dock(dock)
	my_panel.queue_free()
```

### 4.3 编辑器设置相关

控制 Output 行为的编辑器设置：

| 设置路径 | 说明 |
|----------|------|
| `Run > Bottom Panel > Action on Play` | 运行项目时底部面板行为 |
| `Run > Output > Always Clear Output on Play` | 运行前是否清除输出 |

---

## 五、关键类参考

### 5.1 EditorPlugin 相关方法

| 方法 | 说明 |
|------|------|
| `get_editor_interface()` | 获取 EditorInterface |
| `make_bottom_panel_item_visible(item)` | 显示底部面板项 |
| `add_dock(dock)` | 添加停靠面板 |
| `add_control_to_bottom_panel(control, title)` | 添加底部面板控件（已废弃） |
| `remove_control_from_bottom_panel(control)` | 移除底部面板控件 |

### 5.2 EditorInterface 相关方法

| 方法 | 说明 | 返回类型 |
|------|------|----------|
| `get_base_control()` | 编辑器主容器 | Control |
| `get_editor_main_screen()` | 主屏幕区域 | VBoxContainer |
| `get_editor_theme()` | 编辑器主题 | Theme |
| `get_editor_toaster()` | Toast 通知管理器 | EditorToaster |
| `get_editor_settings()` | 编辑器设置 | EditorSettings |
| `get_editor_viewport_2d()` | 2D 编辑器视口 | SubViewport |
| `get_editor_viewport_3d(idx)` | 3D 编辑器视口 | SubViewport |
| `get_script_editor()` | 脚本编辑器 | ScriptEditor |
| `get_file_system_dock()` | 文件系统停靠面板 | FileSystemDock |
| `get_inspector()` | 属性检查器 | EditorInspector |
| `get_selection()` | 编辑器选择 | EditorSelection |

**注意**: EditorInterface **没有** `get_editor_log()` 方法！

### 5.3 Engine 相关属性

| 属性 | 说明 |
|------|------|
| `Engine.print_to_stdout` | 是否打印到 stdout |
| `Engine.print_error_messages` | 是否打印错误消息 |

---

## 六、已知限制与 GitHub Issues

### 6.1 已知 API 缺失

1. **EditorInterface.get_editor_log() 不存在**
   - Issue #8879: Make `print_rich` url tag support meta_click
   - Issue #5297: Add an easy way to get controls of the bottom panel
   - Issue #1628: Make script paths in Editor Output error messages clickable

2. **无法直接连接 EditorLog 的信号**
   - 无法访问 `meta_clicked` 信号来处理 `print_rich()` 的 `[url]` 点击
   - 无法监听消息添加事件

3. **EditorLog 节点名称不固定**
   - 节点名称是自动生成的
   - 只能通过类名 `EditorLog` 来识别

### 6.2 社区提出的解决方案

**提案 #5297 建议添加**:
```gdscript
# 建议的 API
EditorPlugin.get_bottom_panel_control(control_name: String) -> Control
EditorPlugin.get_bottom_panel_controls_names() -> Array[String]
```

---

## 七、完整插件示例

### 7.1 写入 Output 的插件

```gdscript
# plugin.gd
@tool
extends EditorPlugin

const AUTOLOAD_NAME = "OutputHelper"

func _enable_plugin():
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/my_plugin/output_helper.gd")
	print_rich("[color=green][b]Output Helper 插件已启用[/b][/color]")

func _disable_plugin():
	remove_autoload_singleton(AUTOLOAD_NAME)
	print("Output Helper 插件已禁用")
```

```gdscript
# output_helper.gd
extends Node

func _ready():
	push_warning("Output Helper 已就绪")

func log_info(message: String):
	print_rich("[color=blue][b][INFO][/b] " + message + "[/color]")

func log_success(message: String):
	print_rich("[color=green][b][OK][/b] " + message + "[/color]")

func log_error(message: String):
	push_error("[ERROR] " + message)
```

### 7.2 拦截消息的插件（使用 Logger）

```gdscript
# log_interceptor.gd
@tool
extends EditorPlugin

class InterceptLogger extends Logger:
	var plugin: EditorPlugin
	
	func _init(p_plugin: EditorPlugin):
		plugin = p_plugin
	
	func _log_message(message: String, error: bool) -> void:
		# 处理拦截到的消息
		if error:
			print_rich("[color=red][ intercepted stderr ][/color] ", message)
		else:
			print_rich("[color=gray][ intercepted ][/color] ", message)
	
	func _log_error(
			function: String,
			file: String,
			line: int,
			code: String,
			rationale: String,
			editor_notify: bool,
			error_type: int,
			script_backtraces: Array[ScriptBacktrace]
	) -> void:
		var type_name = "UNKNOWN"
		match error_type:
			ERROR_TYPE_ERROR: type_name = "ERROR"
			ERROR_TYPE_WARNING: type_name = "WARNING"
			ERROR_TYPE_SCRIPT: type_name = "SCRIPT"
			ERROR_TYPE_SHADER: type_name = "SHADER"
		
		print_rich("[color=yellow][ intercepted error ][/color] [%s] %s" % [type_name, rationale])

var logger: Logger

func _enter_tree():
	logger = InterceptLogger.new(self)
	OS.add_logger(logger)
	print("日志拦截器已启动")

func _exit_tree():
	if logger:
		OS.remove_logger(logger)
		logger = null
	print("日志拦截器已停止")
```

### 7.3 访问 EditorLog 面板的插件

```gdscript
# editor_log_accessor.gd
@tool
extends EditorPlugin

var editor_log: Node = null

func _enter_tree():
	editor_log = find_editor_log(EditorInterface.get_base_control())
	if editor_log:
		print("成功找到 EditorLog 面板")
		# 显示 Output 面板
		make_bottom_panel_item_visible(editor_log)
	else:
		push_error("无法找到 EditorLog 面板")

func find_editor_log(node: Node) -> Node:
	# 使用广度优先搜索查找 EditorLog
	var queue = [node]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		if current.get_class() == "EditorLog":
			return current
		for child in current.get_children():
			queue.push_back(child)
	
	return null

func show_output_panel():
	"""显示 Output 面板"""
	if editor_log:
		make_bottom_panel_item_visible(editor_log)

func _exit_tree():
	editor_log = null
```

---

## 八、版本兼容性说明

| 功能 | Godot 版本 | 说明 |
|------|-----------|------|
| `print()`, `push_error()` 等基础函数 | 所有版本 | 基础功能 |
| `print_rich()` | 4.x+ | BBCode 支持 |
| `Logger` 类和 `OS.add_logger()` | 4.5+ | 自定义日志记录 |
| `EditorToaster` | 4.x+ | Toast 通知 |
| `add_dock()` / `EditorDock` | 4.3+ | 新版 Dock API |
| `add_control_to_bottom_panel()` | 4.x | 已废弃，使用 `add_dock()` |

---

## 九、相关资源链接

### 官方文档
- Output Panel: https://docs.godotengine.org/en/stable/tutorials/scripting/debug/output_panel.html
- Logging: https://docs.godotengine.org/en/stable/tutorials/scripting/logging.html
- EditorPlugin: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html
- EditorInterface: https://docs.godotengine.org/en/stable/classes/class_editorinterface.html
- EditorToaster: https://docs.godotengine.org/en/stable/classes/class_editortoaster.html
- Logger: https://docs.godotengine.org/en/stable/classes/class_logger.html
- OS: https://docs.godotengine.org/en/stable/classes/class_os.html
- print_rich(): https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html

### GitHub Issues
- #5297: https://github.com/godotengine/godot-proposals/issues/5297
- #8879: https://github.com/godotengine/godot-proposals/issues/8879
- #1628: https://github.com/godotengine/godot-proposals/issues/1628

---

## 十、总结与建议

### 推荐方案

| 需求 | 推荐方法 | 可靠性 |
|------|----------|--------|
| 向 Output 写入内容 | 直接使用 `print()` / `print_rich()` | 高（官方 API） |
| 显示编辑器通知 | 使用 `EditorToaster.push_toast()` | 高（官方 API） |
| 拦截引擎消息 | 使用 `Logger` + `OS.add_logger()` | 高（Godot 4.5+） |
| 读取 Output 面板内容 | 使用 `Logger` 拦截或读取日志文件 | 中 |
| 显示/切换 Output 面板 | 使用节点树遍历 + `make_bottom_panel_item_visible()` | 中（Hack） |
| 处理 `[url]` 点击 | 目前**不可行**，需等待官方 API | 低 |

### 重要提示

1. **不要在 `@tool` 脚本中过度使用 `print()`** - 会影响编辑器性能
2. **Logger 的回调是线程不安全的** - 需要使用 `Mutex` 保护共享数据
3. **节点树遍历方法可能在新版本失效** - 需要测试目标 Godot 版本
4. **Logger 不拦截 `push_error()`/`push_warning()`** - 这些是独立的消息通道
