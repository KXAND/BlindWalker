# Issue #4: ViewController 视角控制

**依赖**: Issue #1 (EventBus)  
**参考**: PRD §2.4, CONTEXT.md §视角

---

## 需求

创建 `ViewController.gd`，挂载在 Player 下，管理摄像机旋转。摄像机只能通过两种方式旋转：R 键直接控制 + 盲杖锥角溢出（暂不需要连接 CaneSystem，留接口）。

## 范围

1. 创建 `scripts/player/ViewController.gd`，`class_name ViewController extends Node`
2. `@export var mouse_sensitivity: float = 0.002`
3. R 键按住时：鼠标 X/Y → 摄像机 Yaw/Pitch
4. Pitch 限制 `-80° ~ +80°`
5. 暴露 `rotate_view(h_angle: float, v_angle: float)` 方法，供 CaneSystem 溢出调用
6. 身体朝向始终跟随摄像机 Yaw（旋转 Player 根节点）
7. 从现有 `PlayerController.gd` 中提取视角逻辑（之后不删，等 GaitController issue 整体替换）

## 验收

- 按 R + 移动鼠标 → 视角正常旋转
- 松开 R → 鼠标不再影响视角
- Pitch 不会越界

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/player/ViewController.gd` |
