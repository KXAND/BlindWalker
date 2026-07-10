# BlindWalker MVP 产品需求文档

> 来源：`/grill-with-docs` 会话产出  
> 参考：`CONTEXT.md`（领域术语表）、`docs/adr/0003-continuous-movement.md`  
> 最后更新：2026-07-09

---

## 1. 概述

BlindWalker 是一款模拟视障体验的第一人称公益游戏。玩家扮演视障者，通过**盲杖探测**、**连续行走**和**触摸确认**，从街角安全走到目的地。核心挑战来自持续注意力分配（边走边探）+ 台阶/墙壁物理判定的组合。

> **设计变更说明**：原设计采用离散步态（ADR-0001），经原型验证后改为连续移动（ADR-0003）。视角控制从独立模块改为 InputManager 统一管理（ADR-0005）。盲杖碰撞检测从射线方案迁移至 `intersect_shape` + 分步推进（ADR-0006，取代 ADR-0004）。

---

## 2. 模块需求

### 2.0 GameConfig（基础设施 · class_name）

`class_name GameConfig`，`scripts/core/GameConfig.gd`。非 autoload，全局可访问。定义所有可调常量，消除硬编码。

**常量清单**：

| 类别 | 常量 | 默认值 | 说明 |
|------|------|--------|------|
| 按键 | `KEY_FORWARD` | `KEY_W` | 前进行走 |
| 按键 | `KEY_CAUTIOUS` | `KEY_SHIFT` | 谨慎模式（减速） |
| 按键 | `KEY_HIGH_STEP` | `KEY_SPACE` | 高抬腿模式（减速+可上台阶） |
| 按键 | `KEY_LOOK_DIRECT` | `KEY_R` | 视角直控 |
| 按键 | `KEY_TOUCH` | `MOUSE_BUTTON_LEFT` | 触摸确认 |
| 移动 | `WALK_SPEED` | `0.8` | 正常行走速度 (m/s) |
| 移动 | `CAUTIOUS_SPEED` | `0.3` | 谨慎模式速度 (m/s) |
| 移动 | `HIGH_STEP_SPEED` | `0.3` | 高抬腿模式速度 (m/s) |
| 移动 | `STEP_AUDIO_DISTANCE` | `0.5` | 脚步声间隔距离 (m) |
| 步态 | `MAX_HIGH_STEP_HEIGHT` | `0.3` | 最大抬腿高度 (m) |
| 盲杖 | `CANE_SWEEP_ANGLE` | `60.0` | 扫动锥角 (±°) |
| 盲杖 | `CANE_LENGTH` | `1.5` | 盲杖长度 (m) |
| 血量 | `MAX_HP` | `100` | 最大血量 |
| 血量 | `FALL_DAMAGE` | `20` | 摔跤扣血 |
| 摔跤 | `STAGGER_PUSH_BACK` | `0.15` | 踉跄回退距离 (m) |
| 调试 | `DEBUG` | `true` | 调试输出开关（print/debug_mode） |

**自定义数据结构**（均为 `class_name`，`scripts/core/`）：

| 类 | 文件 | 字段 |
|-----|------|------|
| `StepResult` | `StepResult.gd` | `success: bool`, `type: int` (SUCCESS/STAGGER/FALL), `displacement: Vector3` |
| `CaneHitInfo` | `CaneHitInfo.gd` | `collider: Object`, `point: Vector3`, `normal: Vector3` |
| `NpcDialogue` | `NpcDialogue.gd` | `lines: Array[String]`, `voice_paths: Array[String]` |

---

### 2.1 EventBus（基础设施 · autoload）

全局信号总线，模块间解耦通信的唯一通道。

**信号清单**：

| 信号 | 参数 | 用途 |
|------|------|------|
| `player_damaged` | `amount: int, current_hp: int` | 玩家受伤 |
| `player_healed` | `amount: int, current_hp: int` | 玩家回血 |
| `player_died` | — | 玩家死亡 |
| `player_fell` | `fall_distance: float` | 玩家摔跤 |
| `cane_hit_object` | `object_name: String, hit_point: Vector3, hit_normal: Vector3` | 盲杖碰撞 |
| `cane_entered_npc_zone` | `npc_name: String` | 盲杖进入 NPC 躲避范围 |
| `cane_exited_npc_zone` | `npc_name: String` | 盲杖离开 NPC 躲避范围 |
| `touch_detected` | `hit_point: Vector3` | 触摸确认命中 |
| `npc_interaction_available` | `npc_name: String, prompt: String` | 可对话 NPC |
| `npc_interaction_unavailable` | — | 离开对话范围 |
| `npc_interaction_triggered` | `npc_name: String` | 对话触发 |
| `game_state_changed` | `old_state: StringName, new_state: StringName` | 游戏状态变化 |
| `cutscene_started` | `cutscene_id: String` | 演出开始 |
| `cutscene_ended` | `cutscene_id: String` | 演出结束 |
| `audio_requested` | `sound_id: String, position: Vector3, volume_db: float` | 音频播放请求 |

---

### 2.2 GaitController（玩家 · 移动控制）

替代原 `PlayerController.gd`。挂载在 `CharacterBody3D` 上。采用连续移动模式（ADR-0003）。

**需求**：

| ID | 需求 |
|----|------|
| G1 | 按住 W = 沿视角前方持续行走（`WALK_SPEED`），松开 = 停止 |
| G2 | 按住 SHIFT + W = 谨慎模式减速行走（`CAUTIOUS_SPEED`），下楼梯不摔 |
| G3 | 按住 SPACE + W = 高抬腿模式减速行走（`HIGH_STEP_SPEED`），固定高度 `MAX_HIGH_STEP_HEIGHT`（0.3m），允许跨过 ≤ 该高度的台阶 |
| G4 | 撞墙 → `move_and_slide()` 碰撞响应 + 短暂减速 + `wall_hit` 音效，**不扣血** |
| G5 | 每帧（节流）射线检测前方地形高差：上坡高差 ≤ 0.3m + SPACE 按住 → 平滑抬升；SPACE 未按住 → 撞墙 |
| G6 | 每帧射线检测前方地形高差：下坡高差 < -0.15m + SHIFT 未按住 → 摔倒扣血 |
| G7 | 摔倒 → 扣 `FALL_DAMAGE` + `fall` 音效 + `player_fell` 信号 + 1-2s 移动禁用 |
| G8 | 脚步音频：距离累加器每移动 `STEP_AUDIO_DISTANCE` 播放一次，交替左右声道 |
| G9 | 输入处理入口查询 `GameState.is_input_enabled()`，非 PLAYING 状态或演出中不响应输入 |

---

### 2.3 CaneSystem（玩家 · 盲杖探测）

挂载在 Player 下。管理盲杖的扫动、碰撞和 NPC 触发器。碰撞检测采用 `intersect_shape` 全体积查询（ADR-0006）。

**需求**：

| ID | 需求 |
|----|------|
| C1 | 鼠标 X/Y 轴控制盲杖左右/上下扫动 |
| C2 | 盲杖扫动限制在锥形夹角内（可配置角度） |
| C3 | 锥角内移动鼠标 → 只移盲杖，不转视角（溢出量返回给 InputManager） |
| C4 | 每物理帧用 `intersect_shape`（BoxShape3D 全体积）预测新姿态是否与环境重叠，替代 RayCast 射线检测 |
| C5 | 碰撞停杖：新姿态重叠时旋转被阻止，杖身全长不缩短；分步推进确保快速扫动不跳过薄墙（ADR-0006） |
| C6 | 碰撞时通过 EventBus 发送 `cane_hit_object` 信号（`intersect_shape` 感知 + 射线精确定位接触点） |
| C7 | 盲杖尖端挂 Area3D，用于 NPC 躲避检测 |
| C8 | Area3D 进入/离开 NPC 范围时通过 EventBus 发信号 |
| C9 | 玩家位移穿模时，在锥角范围内搜索最近安全姿态恢复；极端情况下临时缩短可视杆防止画面穿墙（最后防线） |
| C10 | 盲杖视觉用白色 MeshInstance3D + 低 emission，始终可见，不投影 |
| C11 | 输入处理入口查询 `GameState.is_input_enabled()` |

---

### 2.4 ~~ViewController~~ → InputManager（玩家 · 输入与视角控制）

> ⚠️ **本节已被 [ADR-0005](./adr/0005-input-manager-merges-view.md) 取代。** 视角控制归入 InputManager，不再独立成模块。

挂载在 Player 下。统一管理键鼠输入分发和视角旋转。

**需求**：

| ID | 需求 |
|----|------|
| V1 | R 键按住时，鼠标直接控制摄像机 Yaw/Pitch（标准 FPS 视角） |
| V2 | 默认模式下，鼠标先驱动盲杖扫动，锥角溢出量转为玩家 Yaw 旋转（视角 + 身体朝向同步） |
| V3 | 身体朝向 = 摄像机朝向，永远一致 |
| V4 | Pitch 限制在 -80° 到 +80° 之间 |
| V5 | W 键持续检测：按住 = 通知 GaitController 前进，松开 = 停止 |
| V6 | SHIFT / SPACE 持续状态检测，转发给 GaitController |
| V7 | 鼠标左键触发 TouchMemorySystem.try_touch() |
| V8 | ESC 切换鼠标捕获/释放 |
| V9 | 输入处理入口查询 `GameState.is_input_enabled()` |

---

### 2.5 PlayerAttributes（玩家 · 属性）

挂载在 Player 下。血量管理。

**需求**：

| ID | 需求 |
|----|------|
| A1 | 管理 HP（当前值 + 最大值），初始满血 |
| A2 | 摔跤时扣血，血量变更通过 EventBus 广播 |
| A3 | HP ≤ 0 时通过 EventBus 广播 `player_died` |
| A4 | 提供 `take_damage(amount)` 和 `heal(amount)` 接口 |

---

### 2.6 TouchMemorySystem（感知 · 触摸确认）

**已有模块**，保持不变。左键触发 `try_touch()`，通过着色器后处理显示触觉记忆球。

需求变更：无。具体触摸交互按键后续确定。

---

### 2.7 NPCBase（NPC · 基础行走）

NPC 基类，`CharacterBody3D`。

**需求**：

| ID | 需求 |
|----|------|
| N1 | 连续移动（非离散迈步），沿预设路径点循环行走 |
| N2 | 有碰撞体，盲杖碰到 NPC 时有物理反馈 |
| N3 | 不参与地形惩罚（不摔跤，不被台阶阻挡） |

---

### 2.8 NPCAvoidance（NPC · 躲避盲杖）

挂载在 NPC 下。

**需求**：

| ID | 需求 |
|----|------|
| NA1 | 监听盲杖尖端 Area3D 的进入信号 |
| NA2 | 盲杖进入范围 → NPC 横向避让一步（一次性行为） |
| NA3 | 避让期间暂停正常路径行走，避让完成后恢复 |

---

### 2.9 InteractionSystem（交互层）

挂载在玩家或场景根节点下。管理 NPC 对话触发。

**需求**：

| ID | 需求 |
|----|------|
| I1 | 检测玩家与 NPC 的距离 |
| I2 | 距离 < 阈值 → 通过 EventBus 发 `npc_interaction_available`（含提示文本） |
| I3 | 距离 > 阈值 → 发 `npc_interaction_unavailable` |
| I4 | 对话交互的具体按键搁置（MVP 后用） |

---

### 2.10 AudioManager（流程控制 · autoload）

**需求**：

| ID | 需求 |
|----|------|
| AM1 | 监听 EventBus `audio_requested` 信号 |
| AM2 | 在指定 3D 位置播放音效（支持 2D 和 3D 音频） |
| AM3 | 三层音频：环境音（循环）、反馈音（单次）、提示音/语音（单次） |
| AM4 | 音量可全局调节 |

---

### 2.11 CutsceneManager（流程控制 · 演出）

**需求**：

| ID | 需求 |
|----|------|
| CM1 | 开场演出：短暂黑屏 → 摄像机动画（推进到街角起始位）→ 字幕/任务提示 |
| CM2 | 结尾演出：到达目标区域 → 摄像机动画 → 胜利播报 |
| CM3 | 演出期间通过 `GameState.set_cutscene_active(true)` 暂停玩家输入（ADR-0005） |
| CM4 | 演出开始/结束通过 EventBus 广播 |

---

### 2.12 GameState（流程控制 · autoload）

**需求**：

| ID | 需求 |
|----|------|
| GS1 | 状态机：LOADING → PLAYING → (SUCCESS \| FAILURE) |
| GS2 | 监听 `player_died` → 切换到 FAILURE |
| GS3 | 监听目标到达 → 切换到 SUCCESS |
| GS4 | 无检查点，线性从头到尾 |
| GS5 | 拥有 `is_input_enabled()`：返回 `current_state == PLAYING && !_cutscene_active`（ADR-0005） |
| GS6 | 拥有 `set_cutscene_active(active: bool)`：供 CutsceneManager 调用 |

---

### 2.13 MainBootstrap（流程控制 · 场景入口）

挂载在 Main 场景根节点下。

**需求**：

| ID | 需求 |
|----|------|
| MB1 | 场景 `_ready()` 时检查 GameState，若为 LOADING 则调用 `set_playing()` |
| MB2 | 避免终点触发时仍停留在 LOADING 状态 |

---

## 3. 模块依赖图

```
GameConfig  ← 所有模块（class_name 全局引用）
EventBus    ← 所有模块（autoload 信号总线）
GameState   ← 所有模块（autoload，拥有 is_input_enabled()）
    ↑
GameState ────→ PlayerAttributes (监听 player_died)
AudioManager ← EventBus.audio_requested / game_state_changed / cane_entered_npc_zone
CutsceneManager → GameState.set_cutscene_active()
MainBootstrap → GameState.set_playing()

InputManager ────→ GaitController (request_step / set_cautious_active / update_high_step)
               → CaneSystem (apply_sweep)
               → TouchMemorySystem (try_touch)
               → 玩家 Yaw 旋转 + Head Pitch 旋转（视角控制，ADR-0005）

GaitController ────→ EventBus (player_fell)
                  → PlayerAttributes (扣血)
                  → GameState.is_input_enabled()

CaneSystem ────→ EventBus (cane_hit_object, cane_entered/exited_npc_zone)
              → GameState.is_input_enabled()

TouchMemorySystem ─→ EventBus (audio_requested)

NPCBase ← NPCAvoidance (避让行为)
NPCAvoidance ← 监听 cane_tip group 的 Area3D 信号

InteractionSystem → EventBus (npc_interaction_available/unavailable)

StepResult / CaneHitInfo / NpcDialogue / TouchSphere  ← 各系统使用的数据结构
RaycastUtil  ← GaitController, CaneSystem, TouchMemorySystem (共享射线查询)
```

---

## 4. 非功能需求

- 所有代码使用 GDScript
- 系统间通信优先使用 EventBus 信号
- 节点引用优先 `@export`，避免深层硬编码路径
- MVP 不引入 C#、不做多人联机
- 目标帧率：桌面浏览器 30 FPS 以上
