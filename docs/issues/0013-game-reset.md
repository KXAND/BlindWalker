# Issue #0013: GameReset —— 胜利/失败后按键确认重置

**依赖**: Issue #0001 (EventBus), Issue #0002 (GameState), Issue #0007 (AudioManager)  
**参考**: PRD §2.15

---

## 背景

当前游戏在 SUCCESS 或 FAILURE 后直接定住，没有任何重置路径。需要在结局后显示提示 UI，由玩家主动按键触发场景重载，回到游戏开头。

## 需求

创建 `scripts/ui/GameOverUI.gd`，结局时显示全屏提示（"按 [空格] 重玩"），玩家确认后执行重置。同时为 `GameState` 新增 `reset_to_loading()` 方法。

## 范围

### GameState 修改

在 `scripts/core/GameState.gd` 中新增：

```gdscript
## 重置状态机回 LOADING，供场景 reload 前调用。
## 不做其他副作用（不移动玩家、不清空音效）。
func reset_to_loading() -> void:
    current_state = State.LOADING
```

> **必须在 `reload_current_scene()` 之前调用**，否则新场景的 `set_playing()` 守卫会因状态仍为 FAILURE/SUCCESS 而直接返回，导致游戏卡在 LOADING。

### GameOverUI 新建

新建 `scripts/ui/GameOverUI.gd`，`class_name GameOverUI extends CanvasLayer`：

1. `layer = 10`（高于 HealthUI 的 layer=1，确保覆盖在最上层）
2. 运行时动态创建全屏半透明背景 Panel + 居中 Label
3. 默认隐藏（`visible = false`）
4. 监听 `EventBus.game_state_changed`：
   - `new_state == &"SUCCESS"` → 显示 "你到达了目的地\n按 [空格] 重玩"
   - `new_state == &"FAILURE"` → 显示 "血量耗尽\n按 [空格] 重玩"
5. 显示后开始监听 `SPACE` 键输入（仅在 UI 可见时响应，不干扰游戏中的输入）
6. 玩家按下空格后执行重置序列：

```gdscript
func _do_reset() -> void:
    AudioManager.stop_all()                        # 显式停止所有音效（Web 平台必要）
    await get_tree().create_timer(0.08).timeout    # 给 Web Audio 一帧缓冲
    GameState.reset_to_loading()                   # autoload 状态回 LOADING
    get_tree().reload_current_scene()              # 重载场景
```

7. 挂在 `Main.tscn` 根节点下（`SubViewportContainer` 平级）

### AudioManager 修改（若尚未实现 stop_all）

在 `scripts/core/AudioManager.gd` 中确认或新增：

```gdscript
## 停止所有正在播放的音频流，供场景 reload 前调用。
func stop_all() -> void:
    for player in _players:  # _players 为内部维护的 AudioStreamPlayer 列表
        if player.playing:
            player.stop()
```

## 关键约束

- **不使用延迟自动 reload**：时长魔法数字难以确定，剥夺玩家控制权
- **GameOverUI 输入处理独立于游戏逻辑**：在 `_input()` 中检查 `visible` 后再响应，不经过 `GameState.is_input_enabled()`（该函数在 SUCCESS/FAILURE 下返回 false）
- **reload 前必须先 reset_to_loading()**：顺序不能反，否则新场景无法进入 PLAYING
- **Web 平台音效截断**：0.08s 缓冲是 Web Audio API 的必要延迟，桌面端无害
- **不使用手动重置各子系统的方案**：每次新增子系统都需要在 reset 路径注册，MVP 阶段维护成本过高，`reload_current_scene()` 是正确的一次性重置

## 层级规划

| 节点 | layer | 说明 |
|------|-------|------|
| HealthUI | 1 | 左上角血量，始终可见 |
| CutsceneManager CanvasLayer | 5 | 字幕（动态创建） |
| GameOverUI | 10 | 结局全屏覆盖，优先级最高 |

## 验收

- 胜利/失败后立即显示全屏提示，游戏画面冻结在原处
- 按空格后所有音效停止，场景重载，游戏回到起点满血状态
- 重载后 HealthUI 正确显示 `HP: 100 / 100`
- 重载后 GameState 处于 PLAYING 状态，玩家输入正常响应
- 游戏进行中按空格不触发重置

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/ui/GameOverUI.gd` |
| 修改 | `scripts/core/GameState.gd`（新增 `reset_to_loading()`） |
| 修改（确认） | `scripts/core/AudioManager.gd`（确认或新增 `stop_all()`） |
| 修改 | `scenes/main/Main.tscn`（挂载 GameOverUI 节点，layer=10） |
