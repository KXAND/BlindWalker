# ADR 0006: 盲杖碰撞检测从射线迁移到 intersect_shape + 分步推进

**日期**: 2026-07-10  
**状态**: Accepted  
**取代**: ADR-0004

---

## 上下文

ADR-0004 确立了"RayCast 为主 + Area3D 全杖防穿补丁"的双重方案，但实际实现后暴露两个根本性问题：

1. **射线漏检**：多条平行射线只能模拟几个离散截面，盲杖以斜角切入薄墙时仍可能整根穿过
2. **Area3D 事后回退产生抖动**：`get_overlapping_bodies()` 结果延迟一帧，导致"穿入 → 回退 → 穿入"逐帧振荡，在无碰撞区域也出现明显抖动

问题的根源在于：射线是线检测，永远无法完整覆盖一个有宽度的三维物体；Area3D 事后回退是补丁而非预防。

## 决策

用 **`intersect_shape`（引擎形状重叠检测）+ 分步推进** 替代所有射线预测。

### 1. `_shape_overlaps(angle, pitch)` — 核心预测原语

使用 `PhysicsShapeQueryParameters3D` + `BoxShape3D`（与杖身同尺寸），在引擎物理层做完整的形状重叠查询。一次查询覆盖整根杖身体积，无任何盲区。

```
collision_mask = LAYER_ENVIRONMENT（仅环境层，不碰 NPC）
collide_with_bodies = true
collide_with_areas = false
exclude = [玩家 RID]
```

### 2. `apply_sweep` 解耦 — 只写目标，不立即应用

`apply_sweep` 只将鼠标增量写入 `_target_angle / _target_pitch`，不做任何物理查询。所有碰撞检测移到 `_physics_process`，与物理帧同步，消除时序问题。

### 3. `_advance_to_safe_pose` — 分步推进防大角度跳过薄墙

每帧将 `_current` → `_target` 的角度差切成 ≤ 3° 的小步，逐步推进，遇到第一个重叠立即停在上一步的安全姿态。保证鼠标快速甩动时不会跳过薄墙。

### 4. `_find_recovery_pose` — 玩家位移穿模时搜索最近安全姿态

当玩家向前走进障碍（杖角度未变但世界变了），以 6° 为网格步长枚举锥角范围内的所有离散姿态，选出**曼哈顿距离最近**的无重叠点。比线性归零更合理：障碍在左侧时，杖会向右找安全点。

### 5. `_blocked_visible_length` — 无解时临时缩短可视杆

极端情况（玩家完全陷入障碍，整个锥角范围都重叠）时，不强制跳变角度，而是用射线求实际碰撞距离，临时缩短可视杆长至碰撞点前 `HIT_RETRACT`（0.04m），至少保留 `MIN_VISIBLE_LENGTH`（0.2m）。这是**最后防线**，正常游玩几乎不触发。

### 6. `_detect_contact` — 接触检测与音效定位

接触检测同样改用 `intersect_shape`（用可视长度的 `_contact_shape`），感知到碰撞后再补发一条射线精确定位 `hit_point`。这解决了原方案射线起点未考虑 `ROD_Y_OFFSET` 导致音效位置偏差的问题。

## 替代方案

| 方案 | 否决理由 |
|------|---------|
| 多射线（3~5 条平行）覆盖杖身宽度 | 仍是线检测，斜角切入时漏检；射线数增加性能代价但无法彻底消除盲区 |
| Area3D `get_overlapping_bodies()` 事后回退 | 延迟一帧，产生振荡抖动；即使在无碰撞区也抖动 |
| `move_toward` 逐帧向零归零 | 方向错误：障碍在左时不应向左推；归零速度固定，快速扫动时体验差 |
| RigidBody3D 物理刚体 | 引擎接管旋转，产生弹跳；"停杖不推人"无法保证 |

## 影响

- 碰撞检测每帧最多调用 `intersect_shape` 两次（分步推进 + 位移恢复），比无上限的多射线循环更可预测
- `apply_sweep` 接口不变，对 InputManager 透明
- 废弃 ADR-0004 中"视觉长度随碰撞动态缩短"的表述；可视长度仅在极端穿模保护时缩短，正常碰撞下杖身全长显示、旋转被阻止
- PRD §2.3 C4/C5 需同步更新
