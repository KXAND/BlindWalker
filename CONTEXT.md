# BlindWalker 领域术语表

> 最后更新：2026-07-10

---

## 步态 (Gait)

玩家移动通过交替迈步实现，不是连续移动。

| 术语 | 定义 |
|------|------|
| **迈步 (Step)** | 一次按键产生一段固定位移。W = 左脚迈步，E = 右脚迈步。平地与楼梯步长不同。 |
| **收脚 (Retract)** | 同脚连续按第二次：后脚收回到前脚侧，双脚平齐，无位移，不摔跤。 |
| **锁脚 (Lock)** | 收脚后该键被锁定，必须切换另一只脚才能继续前进。 |
| **步态状态** | `BothEven`（双脚平齐）\| `LeftAhead`（左脚在前）\| `RightAhead`（右脚在前）。从 BothEven 起，W 或 E 皆可起步。 |
| **步态周期** | 正常：BothEven → W(位移) → E(位移) → BothEven。一个周期 = 步长 × 2。 |
| **谨慎模式 (Cautious)** | 按住 SHIFT + 迈步。下楼梯必须使用，否则摔跤。 |
| **抬腿模式 (Lift)** | 按住 SPACE + 迈步。按住时长 = 抬腿高度。上楼梯抬腿高度不足 → 摔跤。 |
| **摔跤 (Fall)** | 上楼梯抬腿不够 或 下楼梯未按 SHIFT → 扣血。 |
| **踉跄 (Stagger)** | 迈步撞墙 → 短暂趔趄反馈，不扣血。 |

## 盲杖 (Cane)

| 术语 | 定义 |
|------|------|
| **扫动 (Sweep)** | 玩家鼠标 X/Y 轴控制盲杖左右/上下摆动，限制在一个锥形夹角内。每物理帧做形状重叠检测。 |
| **锥角 (Cone)** | 盲杖扫动的角度范围。锥角内 → 只移盲杖。 |
| **锥角溢出 (Cone Overflow)** | 盲杖到达锥角极限 + 继续推鼠标 → 旋转玩家视角。 |
| **碰撞停杖 (Collision Stop)** | 盲杖碰到障碍物时旋转被阻止，杖身全长不变，鼠标继续推则溢出转视角。杖身不缩短。 |
| **目标姿态 (Target Pose)** | 玩家鼠标输入写入的期望角度（`_target_angle / _target_pitch`）。不直接应用，由每帧分步推进检测后才落地为当前姿态。 |
| **当前姿态 (Current Pose)** | 物理帧确认无重叠后实际应用到 `rotation` 的角度（`_current_angle / _current_pitch`）。任何时刻均无穿模。 |
| **分步推进 (Stepped Advance)** | 每帧将当前姿态向目标姿态推进时，将角度差切成 ≤ 3° 的小步逐步测试，遇到重叠立即停在上一步的安全姿态。防止快速扫动跳过薄墙。 |
| **位移穿模恢复 (Displacement Recovery)** | 玩家前进把整根杖带入障碍时，在锥角范围内以 6° 为步长网格搜索距当前姿态最近的无重叠姿态并跳转。 |
| **可视长度应急缩短 (Emergency Retract)** | 位移穿模无法恢复（整个锥角都重叠）时的最后防线：用射线求实际碰撞距，临时缩短可视杆至该距离，保证画面不穿墙。正常游玩几乎不触发。 |
| **宏观探路 (Macro Probe)** | 盲杖扫动的用途：大范围感知前方地形与障碍。 |
| **微观确认 (Micro Confirm)** | 左键触摸的用途：近距离精细确认材质/连续性等。 |

## 视角 (View)

| 术语 | 定义 |
|------|------|
| **身体朝向** | 玩家身体前方 = 摄像机朝向，两者永远一致。 |
| **视角旋转** | 只有两种触发：R 键直接控制 + 盲杖锥角溢出。 |

## NPC

| 术语 | 定义 |
|------|------|
| **连续移动 (Continuous Movement)** | NPC 沿路径点自动行走，非离散迈步。 |
| **躲避盲杖 (Cane Avoidance)** | 盲杖尖端 Area3D 进入 NPC 触发器范围 → NPC 横向避让一步。一次性行为。 |
| **NPC 碰撞** | NPC 有碰撞体。盲杖碰到 NPC 身体时有物理反馈。NPC 不受地形惩罚，不摔跤。 |

## 配置 (Config)

| 术语 | 定义 |
|------|------|
| **GameConfig** | `class_name` 全局配置类，`scripts/core/GameConfig.gd`。非 autoload，通过 `class_name` 全局引用，类似 Python import。包含所有可调常量：按键映射、步态参数、盲杖参数、摔跤参数。 |
| **按键映射** | `KEY_LEFT_FOOT`(W)、`KEY_RIGHT_FOOT`(E)、`KEY_CAUTIOUS`(SHIFT)、`KEY_HIGH_STEP`(SPACE)、`KEY_LOOK_DIRECT`(R)、`KEY_TOUCH`(MOUSE_LEFT)。运行时不可变。 |
| **数据类 (Data Class)** | 自定义数据结构，独立 `.gd` 文件 + `class_name`，放 `scripts/core/`。如 `StepResult`、`CaneHitInfo`、`NpcDialogue`。GDScript 约定：一个 `.gd` 文件 = 一个 class。 |

## 交互 (Interaction)

| 术语 | 定义 |
|------|------|
| **对话交互 (Dialogue Interaction)** | 玩家靠近 NPC → 提示 → 按键对话。由 InteractionSystem 管理。 |

## 感知可视化 (Perception Visualization)

| 术语 | 定义 |
|------|------|
| **声音方向指示 (Sound Direction Indicator)** | MVP 唯一可视化：声源位置的方向提示，集成在 TouchMemorySystem 着色器管线中。 |

## 游戏流程 (Game Flow)

| 术语 | 定义 |
|------|------|
| **线性流程** | 无检查点，从头走到底。HP 归零 = 失败，到达目标 = 成功。 |
| **演出 (Cutscene)** | MVP 只做两段：开场（黑屏→街角）和结尾（到达→胜利播报）。摄像机动画 + 字幕。 |
