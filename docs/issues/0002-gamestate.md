# Issue #2: GameState 游戏状态管理

**依赖**: Issue #1 (EventBus)  
**参考**: PRD §2.12

---

## 需求

创建 autoload 单例 `GameState.gd`，管理游戏流程状态机和玩家 HP 追踪。

## 范围

1. 创建 `scripts/core/GameState.gd`
2. 状态枚举：`LOADING → PLAYING → (SUCCESS | FAILURE)`
3. 监听 `player_died` 信号 → 切换 FAILURE
4. 提供 `set_victory()` 方法 → 切换 SUCCESS
5. 在 `project.godot` 中注册为 autoload
6. **暂不做检查点**，线性从头走到底

## 验收

- `GameState.current_state` 初始为 `LOADING`
- 游戏开始后调用 → 切换到 `PLAYING` 并广播 `game_state_changed`
- `player_died` 信号触发 → 切换到 `FAILURE`

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/core/GameState.gd` |
| 修改 | `project.godot`（添加 autoload） |
