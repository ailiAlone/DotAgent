# triggers: ui, control, panel, button, label, menu, settings, hud, interface, widget, dialog, form, toolbar, inventory, 菜单, 界面, 设置, 按钮, 标签

# UI 场景领域知识（Control-based）

## 场景结构
- 根节点：`Control`（或 `Panel`、`MarginContainer`、`VBoxContainer`）
- 所有子节点继承 Control — UI 场景中不出现 Node2D/Node3D
- 布局：使用锚点（`layout_mode = 1`），不用 position/size 像素值
- 容器：`VBoxContainer`、`HBoxContainer`、`MarginContainer`、`GridContainer`

## 常用控件
| 用途 | 节点 | 关键属性 |
|------|------|----------|
| 文本 | `Label` | `text` |
| 按钮 | `Button` | `text`, `pressed` 信号 |
| 输入框 | `LineEdit` | `text`, `placeholder_text` |
| 复选框 | `CheckBox` | `button_pressed`, `toggled` 信号 |
| 滑块 | `HSlider` / `VSlider` | `value`, `min_value`, `max_value` |
| 图片 | `TextureRect` | `texture`, `expand_mode` |
| 背景 | `ColorRect` | `color`, anchors 全屏 |
| 滚动 | `ScrollContainer` | 内部子节点可滚动 |
| 下拉 | `OptionButton` | `add_item()`, `selected` |
| 进度条 | `ProgressBar` | `value`, `min_value`, `max_value` |
| 标签页 | `TabContainer` | 子 Control 自动成为标签页 |

## 样式与颜色
- 背景：`ColorRect` + anchors (0,0,1,1) + `color`
- 文字颜色：`add_theme_color_override("font_color", Color(...))` 
- 字号：`add_theme_font_size_override("font_size", 24)`
- 圆角面板：`StyleBoxFlat` + `corner_radius` → `add_theme_stylebox_override("panel", style)`
- **禁止**：`theme_override_colors["font_color"] = Color(...)` （只读属性）

## 信号连接（代码方式）
```gdscript
func _ready():
    %Button.pressed.connect(_on_click)
    %Slider.value_changed.connect(_on_value_changed)
    %CheckBox.toggled.connect(_on_toggled)
    %LineEdit.text_changed.connect(_on_text_changed)
```

## OptionButton 陷阱
`size_flags_horizontal = 10`（EXPAND|SHRINK_CENTER）会导致按钮缩到最小宽度，长文本被视觉裁剪。改为 `3`（FILL|EXPAND）让按钮填满可用空间。170+ 项的下拉框尤其注意。

## 静态组合优先
UI 场景也应静态组合：
```
# main.tscn
[ext_resource type="PackedScene" path="res://ui/hud.tscn" id="1_hud"]
[node name="HUD" parent="." instance=ExtResource("1_hud")]
```

## Worker 工具要点
- 创建 UI 场景：`build_scene`（根节点 Control）
- 添加控件：`patch_scene`（add 操作）
- 设属性：`patch_scene`（set 操作，如 text、color）
- 创建脚本：`build_script`
- 验证：`inspect_scene_structured` + `check_script_syntax`
- **禁止**直接编辑 .tscn 文本

## 常见错误
- 设 `position`/`size` 而非 `anchors_preset` — UI 不用像素定位
- 用 `Node2D` 做 UI 根节点 — 应用 `Control`
- `theme_override_colors["key"] = val` — 用 `add_theme_color_override`
- OptionButton size_flags_horizontal=10 — 改为 3
- 在 `_process()` 中连接信号 — 每帧重复连接
- 忘记创建回调方法就 connect — `check_script_syntax` 可捕获
