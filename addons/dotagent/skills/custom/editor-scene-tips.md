# triggers: editor, select, click, scene tree, order, background, block, z_index, layering, pickup, cursor, 2d editor, canvas item

# Editor Scene Interaction Tips

## Scene Tree Order vs Click Detection

**Godot 编辑器的 2D/3D 视口中，点击检测顺序和场景树列表顺序相反：**

```
场景树列表（从上到下）       实际点击命中顺序（从先到后）
─────────────────────       ─────────────────────────────
  SkyBG     ← index=0       4️⃣ 最后检测到（兜底）
  Player    ← index=1       1️⃣ 最先检测到 ✅
  Ground    ← index=2       2️⃣ 
  Stars     ← index=3       3️⃣
```

**规则**：场景树中 index 越大的节点（列表越下面的），在编辑器视口中**越先被点击命中**。

## 全屏背景的正确放置

ColorRect 全屏背景必须在场景树中放在**最上面（index=0）**：

```gdscript
# ✅ 正确
root.move_child(bg_node, 0)  # 移到最上面
bg_node.z_index = -10         # 渲染在最后面
```

这样：
- 编辑器里点击 → 先命中 Player/Ground/Stars ✅
- 运行时渲染 → `z_index = -10` 排在最后面 ✅

**渲染和点击是两套系统**，互不干扰。

## 常见错误

- ❌ 全屏 ColorRect 放场景树最末尾 → 编辑器里点不到任何节点
- ❌ 用 `z_index` 控制点击顺序 → z_index 只影响渲染，不影响点击
- ❌ 把背景放 CanvasLayer 里 → 不仅渲染盖住一切，编辑器里也选不到游戏物体
