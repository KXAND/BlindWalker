# Issue #5: CaneSystem 盲杖探测系统

> **状态**: 已完成  
> **参考**: PRD §2.3, CONTEXT.md §盲杖, ADR-0006

**依赖**: Issue #1 (EventBus)

---

## 实现说明

`scripts/perception/CaneSystem.gd` 已落地，采用 ADR-0006 方案。

### 核心机制

- **`apply_sweep(delta)`**：仅写 `_target_angle / _target_pitch`，不立即应用旋转
- **`_physics_process`**：每物理帧执行两阶段防穿检测，然后应用 `rotation`
  - `_advance_to_safe_pose`：分步推进（≤3°/步），防扫动跳过薄墙
  - `_find_recovery_pose`：玩家位移穿模时网格搜索最近安全姿态
  - `_blocked_visible_length`：极端无解时临时缩短可视杆（最后防线）
- **`_shape_overlaps(angle, pitch)`**：`intersect_shape + BoxShape3D` 全体积查询，替代射线
- **`_detect_contact`**：`intersect_shape` 感知接触 + 射线精确定位 `hit_point`，触发音效

### 节点结构（运行时动态创建）

| 节点 | 类型 | 用途 |
|------|------|------|
| `CaneRod` | `MeshInstance3D` | 白色杆身可视化，`emission = 0.3`，不投影 |
| `CaneBodyArea` | `Area3D + BoxShape3D` | 全杖碰撞体（仅 NPC 触发器用，不参与防穿检测） |
| `CaneTipArea` | `Area3D + SphereShape3D` | 尖端触发器，NPC 躲避检测，加入 `cane_tip` group |

### 关键常量

| 常量 | 值 | 说明 |
|------|----|------|
| `MAX_SWEEP_STEP` | `3°` | 分步推进每步最大角度 |
| `RECOVERY_STEP` | `6°` | 位移恢复网格步长 |
| `HIT_RETRACT` | `0.04 m` | 应急缩短时距碰撞点的安全余量 |
| `MIN_VISIBLE_LENGTH` | `0.2 m` | 可视杆最小长度 |

## 文件

| 操作 | 文件 |
|------|------|
| 已创建 | `scripts/perception/CaneSystem.gd` |
