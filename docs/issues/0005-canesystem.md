# Issue #5: CaneSystem 盲杖探测系统

**依赖**: Issue #1 (EventBus)  
**参考**: PRD §2.3, CONTEXT.md §盲杖

---

## 需求

创建 `CaneSystem.gd`，挂载在 Player 下。鼠标 X 轴控制盲杖左右摆动，物理碰撞检测，尖端挂 Area3D 供 NPC 躲避检测。

## 范围

1. 创建 `scripts/perception/CaneSystem.gd`，`class_name CaneSystem extends Node3D`
2. 盲杖可视化：用 CSGBox3D 或 MeshInstance3D 表示（细长杆）
3. `@export var cone_angle: float = 60.0`（左右各 30°）
4. `@export var cane_length: float = 1.5`
5. `@export var sweep_sensitivity: float = 0.005`
6. 鼠标 X 轴 → 盲杖在锥角内旋转
7. 锥角溢出时：不再移盲杖，通过 `ViewController.rotate_view()` 旋转视角
8. 每帧物理射线从盲杖根部到尖端，碰撞时停止盲杖视觉位置
9. 碰撞时通过 EventBus 广播 `cane_hit_object`
10. 盲杖尖端挂 `Area3D`（小半径球体碰撞），供 NPC 检测

## 验收

- 鼠标左右移动 → 盲杖在锥角内扫动
- 盲杖到锥角极限 + 继续推鼠标 → 视角旋转
- 盲杖碰到物体 → 停在碰撞点，EventBus 广播碰撞事件
- Area3D 挂载在盲杖尖端

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/perception/CaneSystem.gd` |
