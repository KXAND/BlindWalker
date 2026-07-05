# Issue #9: InteractionSystem + CutsceneManager

**依赖**: Issue #1, #2 (GameState)  
**参考**: PRD §2.9, §2.11

---

## 需求

创建 InteractionSystem（NPC 对话触发检测）和 CutsceneManager（简单演出系统）。

## 范围

### InteractionSystem

1. 创建 `scripts/interaction/InteractionSystem.gd`，`class_name InteractionSystem extends Node`
2. 挂载在 Player 下
3. `@export var interaction_range: float = 2.0`
4. 每帧检测范围内是否有 NPC
5. 有 → 通过 EventBus 广播 `npc_interaction_available(npc_name, prompt)`
6. 无 → 广播 `npc_interaction_unavailable`
7. 具体对话按键搁置（MVP 后确定）

### CutsceneManager

1. 创建 `scripts/ui/CutsceneManager.gd`，挂载在场景根节点
2. 两段演出：`intro`（开场）和 `outro`（结尾）
3. `play(cutscene_id: String)` → 禁用玩家输入 → 播放摄像机动画 → 显示字幕 → 恢复输入
4. 演出开始/结束通过 EventBus 广播
5. 摄像机动画用 `Tween` 实现（MVP 阶段简单移动过渡）
6. 字幕用 `Label` 居中显示

## 验收

- 玩家靠近 NPC 2m 内 → EventBus 收到 `npc_interaction_available`
- 触发 `CutsceneManager.play("intro")` → 玩家输入被屏蔽 → 动画播放 → 字幕出现 → 恢复
- 触发 `CutsceneManager.play("outro")` → 同理

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/interaction/InteractionSystem.gd` |
| 新建 | `scripts/ui/CutsceneManager.gd` |
