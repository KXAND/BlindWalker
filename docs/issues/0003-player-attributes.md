# Issue #3: PlayerAttributes 玩家属性

**依赖**: Issue #1 (EventBus)  
**参考**: PRD §2.5

---

## 需求

创建 `PlayerAttributes.gd`，挂载在 Player 节点下，管理血量。

## 范围

1. 创建 `scripts/player/PlayerAttributes.gd`，`class_name PlayerAttributes extends Node`
2. `@export var max_hp: int = 100`
3. `var hp: int = max_hp`（初始满血）
4. `take_damage(amount: int)` → 扣血 → 广播 `player_damaged` / `player_died`
5. `heal(amount: int)` → 回血 → 广播 `player_healed`（上限 max_hp）
6. 挂在现有 Player 场景节点下

## 验收

- `take_damage(30)` → hp 减 30，EventBus 广播 `player_damaged(30, 70)`
- `take_damage(100)` → hp 归零，EventBus 广播 `player_died`
- `heal(20)` → hp 恢复但不超过 max_hp

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/player/PlayerAttributes.gd` |
