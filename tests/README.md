# Banyan Tool Tests

## 使用方法

1. 在 Godot 编辑器中，打开 `tests/run_tests.gd`
2. 确保至少打开了一个场景（如 Star Hunter 的任意场景）
3. 按 **Ctrl+Shift+X** 运行 EditorScript
4. 结果输出到：
   - `tests/results.json` — 结构化数据（供 QoderWork 分析）
   - `tests/results_summary.txt` — 人类可读摘要

## 测试内容

| 测试 | 验证内容 |
|------|---------|
| EditorInterface 可用性 | Godot 编辑器 API 是否可用 |
| 脚本接口提取 | 正则提取 signal/func/export/class_name/extends/enum |
| 场景树结构化读取 | 遍历场景树，收集节点类型/属性/信号/组 |
| ClassDB 工具验证 | 13 种常用节点/资源类型能否被 ClassDB 实例化 |
| 资源接口提取 | get_property_list() 反射能力 |

## 迭代流程

```
QoderWork 写/改工具代码
    ↓
用户在 Godot 中运行 run_tests.gd (Ctrl+Shift+X)
    ↓
结果写入 tests/results.json
    ↓
QoderWork 读取结果，分析问题
    ↓
修复代码 → 重新测试 → 循环
```
