# Star Hunter — 星海猎手

> **v1.2** — 完整可玩的 2D 太空射击游戏，零外部资源依赖。

## 🎮 玩法

| 操作 | 按键 |
|------|------|
| 移动 | `WASD` / 方向键 |
| 射击 | `Space`（按住连射） |
| 副武器 | `Shift`（5 发散射） |
| 暂停 | `ESC` |

**目标**：击退无限 STAGE 的敌机潮，每 5 波（Boss）通关一关。

## ✨ v1.2 特性

### 视觉（零贴图）
- 全部 `_draw()` 程序化绘制
- 3 层视差星空 + 屏幕震动 + 命中顿帧
- 玩家拖尾粒子 + 火花粒子
- 屏幕红闪（受击反馈）
- 玩家复活光环（8 方向扩张）
- NewRecord 金色脉动动画

### 关卡系统
- **STAGE 概念**：每 5 波 = 1 STAGE
- WaveAnnounce 显示 `STAGE N · WAVE M`（如 `STAGE 2 · WAVE 1`）
- Boss 波次显示 `⚠ BOSS  STAGE N ⚠`
- 通关 Boss 显示 `★ STAGE N CLEARED ★`（金色脉动）

### 敌人（6 种）
- **Scout** — 快速杂兵
- **Fighter** — 会射弹的轻型
- **Tank** — 重型慢速
- **Bomber** — 左右摆动 + 抛物攻击
- **Sweeper** — 屏幕左右横扫
- **Carrier** — 周期性吐 Scout 小弟

### Boss（每 5 波）
3 阶段变形：单发 → 三连扇形 → 16 向环形弹幕

### 道具（5 种）
- 💚 **Heal** — 回血
- 💛 **Rapid Fire** — 8 秒高速
- 💙 **Shield** — 6 秒护盾
- ❤️ **Bomb** — 清屏
- 💜 **Score x2** — 10 秒双倍

### 系统
- 连击倍率（每 10 连 +1）
- 最高分本地存档（`user://high_score.save`）
- 完整 4 状态：菜单 → 游戏 → 暂停 → 结算
- 程序化音乐（menu / game 各 1 首）
- 8+1 种程序化音效

## 🏗️ 架构

```
res://
├── scenes/    15 个场景
│   ├── main.tscn / menu.tscn / game.tscn
│   ├── player.tscn / enemy.tscn / boss.tscn
│   ├── bullet.tscn / enemy_bullet.tscn / powerup.tscn
│   ├── explosion.tscn / hit_spark.tscn / screen_flash.tscn / player_trail.tscn
│   ├── hud.tscn / pause_menu.tscn / game_over.tscn
│   └── star_field.tscn
├── scripts/   19 个 GDScript
├── shapes/    5 个碰撞体资源
└── addons/dotagent/  AI 开发助手
```

**关键技术模式**：
- **CanvasLayer 装 Control**：HUD / PauseMenu / ScreenFlash 都用这个模式（避免 Control 挂在 Node2D 下 anchor 失效）
- **静态 helper**：`_gm()` / `_am()` 全局访问 autoload
- **运行时兜底**：`alt_shoot` 输入在 player.gd._ready 兜底注册（独立运行时也能工作）
- **process_mode 谨慎**：`AudioManager` / `Boss UI` 等用 ALWAYS，game.gd 保持 INHERIT（避免 queue_free 后脏数据）

## 🚀 运行

```bash
godot --main-scene res://scenes/main.tscn
```

或编辑器内 F5。

## 📊 质量保证

- ✅ 19 个 `.gd` 脚本：全部 Syntax OK
- ✅ 15 个 `.tscn` 场景：全部 600 帧（10 秒）headless 运行无错
- ✅ 3 个核心场景（main/menu/game）: 120 帧/600 帧测试无错
- ✅ 修复 3 个潜在 bug：boss.gd 单独跑 / player 单独跑 / game.gd anchor 失效

## 📝 版本历史

- **v1.0.0** — 初始完整可玩版本
- **v1.1.0** — 清理 + 火花 + 红闪 + 顿帧 + 副武器 + Boss + 拖尾 + 6 敌机 + 5 道具
- **v1.1.1** — PauseMenu anchor 修复（reparent 到 root）
- **v1.1.2** — PauseMenu CanvasLayer 包装（更优雅方案）
- **v1.2.0** — 关卡系统（STAGE 概念）+ NewRecord 动效 + 菜单脉动 + 复活光环 + 长测稳定性

Made with **Godot 4.5** + **GDScript**。
