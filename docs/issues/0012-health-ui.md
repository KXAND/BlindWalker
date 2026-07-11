# Issue #0012: HealthUI —— 血量数字显示

**依赖**: Issue #0001 (EventBus), Issue #0003 (PlayerAttributes)  
**参考**: PRD §2.14, CONTEXT.md §血量

---

## 背景

当前游戏无任何血量反馈 UI。由于音效优先于视觉，血量 UI **仅用于辅助开发测试**，不作为主要玩家反馈渠道（主反馈为心跳音效等）。

## 需求

创建 `scripts/ui/HealthUI.gd`，在屏幕左上角显示 `HP: X / 100` 格式的 Label。

## 范围

1. 新建 `scripts/ui/HealthUI.gd`，`class_name HealthUI extends CanvasLayer`
2. 运行时动态创建 `Label`，锚点固定在屏幕左上角（`offset_left=12, offset_top=8`）
3. `_ready()` 时主动读取 `PlayerAttributes.hp` 初始值（不依赖信号触发初始化，防止首帧显示空值）
4. 监听 `EventBus.player_damaged` 和 `EventBus.player_healed` 更新显示
5. `HealthUI` 节点挂在 `Main.tscn` 根节点下（`SubViewportContainer` 平级），`layer = 1`
6. 查找 `PlayerAttributes` 节点：通过 `get_tree().get_first_node_in_group("player_attributes")` 或 `@export` 绑定

## 关键约束

- **CanvasLayer 必须在 SubViewportContainer 外层**：挂在 SubViewport 内部会被渲染进 3D 纹理，导致 UI 被裁剪
- `current_hp` 显示需做 `max(0, current_hp)` 夹断，防止极端情况显示负数
- 不需要动画、颜色渐变或进度条，纯 Label 即可
- `GameConfig.DEBUG` 为 `false` 时可考虑隐藏（可选，MVP 阶段始终显示）

## 验收

- 游戏启动后左上角立即显示 `HP: 100 / 100`
- 玩家摔跤扣血后 Label 实时更新
- HP 归零时显示 `HP: 0 / 100`，不显示负数
- 场景 reload 后 UI 重新正确显示初始满血值

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/ui/HealthUI.gd` |
| 修改 | `scenes/main/Main.tscn`（挂载 HealthUI 节点，layer=1） |
