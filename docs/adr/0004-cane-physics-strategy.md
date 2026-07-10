# ADR 0004: 盲杖物理碰撞策略

> ⚠️ **已废弃** — 本决策已被 [ADR-0006](./0006-cane-shape-overlap-detection.md) 取代。射线方案因漏检和 Area3D 事后回退抖动被全面替换为 `intersect_shape` + 分步推进。原文保留供历史参考。

**日期**: 2026-07-09  
**状态**: Superseded by ADR-0006

---

## 上下文

盲杖是 BlindWalker 的核心感知工具。当前原型（`ref/prototype`）中盲杖仅使用 RayCast3D 检测碰撞，视觉上是 CSGBox3D 杆身。问题：

1. **杖身穿模**：RayCast 只检测从根部到尖端的射线，当盲杖与墙壁呈角度时，杆身中段可能穿过墙壁几何体
2. **无物理存在感**：盲杖没有碰撞体积，无法体现"实体工具"的质感
3. **视觉不一致**：杆身穿过墙壁破坏沉浸感

需求明确要求：**整根杖身都有碰撞体积，不能穿模**。

## 决策

采用 **RayCast 为主 + Area3D 全杖防穿模补丁** 的双重检测方案。

### 1. RayCast3D — 主检测器

- 每帧从盲杖根部发射射线到尖端方向
- 决定视觉长度（碰撞时缩短到碰撞点）
- 发射 `cane_hit_object` 信号
- 触发 `cane_hit` 音效（上升沿）
- 行为与现有 prototype 一致

### 2. Area3D + BoxShape3D — 全杖碰撞体

- 沿杖身方向放置 `BoxShape3D`，覆盖从根部到当前视觉尖端的整根杖身
- 每帧根据 RayCast 结果同步更新 `BoxShape3D.size.z` 和位置
- 用 `get_overlapping_bodies()` 检测穿入
- 如果检测到穿入，将视觉长度回退到不穿入的位置
- **碰撞层**：只与墙壁/地形碰撞，不与 NPC 碰撞（NPC 交互由尖端 Area3D 触发器处理）

### 3. 尖端 Area3D — NPC 触发器

- 保留现有设计：尖端小球 Area3D 用于 NPC 躲避检测
- 加入 `cane_tip` group，供 NPCAvoidance 查找
- 碰撞层与全杖 Area3D 不同（仅 NPC 层）

### 4. "停杖不推人"原则

- 盲杖碰撞**不影响玩家移动**——盲杖是感知工具，不是物理屏障
- 玩家撞墙由 GaitController 的 `move_and_slide()` 碰撞响应独立处理
- 盲杖碰撞仅导致：视觉缩短 + 碰撞信号 + 音效

### 5. 视觉风格

- `MeshInstance3D + BoxMesh` 替代 `CSGBox3D`（CSG 有额外开销，不需要布尔运算）
- 白色 `StandardMaterial3D` + 低 `emission_energy_multiplier`（0.3），符合真实导盲杖颜色
- `cast_shadow = OFF`（细杆投影在低模风格中杂乱）
- 始终可见（非仅扫动时）

## 替代方案

| 方案 | 否决理由 |
|------|---------|
| RigidBody3D 物理刚体 | 会被物理引擎推动，产生不可控弹跳/滑动，"停杖不推人"无法实现 |
| AnimatableBody3D 同步碰撞体 | 让物理引擎自然阻挡，但会导致盲杖碰撞阻挡玩家移动，违反"停杖不推人" |
| 多条 RayCast 等分检测 | 5 条射线仍可能漏检薄墙边缘，且性能开销大于单个 Area3D |
| 仅尖端碰撞 | 不满足"整根杖身不穿模"的需求 |

## 影响

- CaneSystem 新增 Area3D + BoxShape3D 全杖碰撞体
- 视觉从 CSGBox3D 改为 MeshInstance3D + BoxMesh
- PRD §2.3 C5 补充实现说明
- 每帧 Area3D `get_overlapping_bodies()` 调用，但范围小、碰撞体少，性能可接受
