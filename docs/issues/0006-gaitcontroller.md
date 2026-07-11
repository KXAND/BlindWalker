# Issue #6: GaitController 步态控制器

**依赖**: Issue #1, #3, #4, #5  
**参考**: PRD §2.2, CONTEXT.md §步态, ADR-0001

---

## 需求

创建 `GaitController.gd` 替代 `PlayerController.gd`。实现离散 W/E 交替迈步系统，包括步态状态机、抬腿/谨慎模式、摔跤/踉跄判定。

## 范围

1. 创建 `scripts/player/GaitController.gd`，挂载在 Player 的 `CharacterBody3D` 上
2. **移除原有 `PlayerController.gd` 并替换**（备份原文件为 `PlayerController.gd.bak`）
3. 步态状态机：`BothEven | LeftAhead | RightAhead` + `locked_key: String = ""`
4. `@export var flat_step_length: float = 0.5`
5. `@export var stair_step_length: float = 0.35`
6. `@export var step_height: float = 0.3`
7. `@export var stagger_duration: float = 0.3`
8. W 键逻辑：BothEven→LeftAhead(位移)，RightAhead→BothEven(位移)，LeftAhead+不锁→收脚+锁W
9. E 键逻辑：对称
10. 迈步时 RayCast 前方检测：撞墙→踉跄，台阶判定→摔跤或抬腿
11. 引用 `PlayerAttributes` 调用 `take_damage()` 处理摔跤扣血
12. 步态状态变化通过 EventBus 广播
13. 保留左键调用 `TouchMemorySystem.try_touch()` 

## 验收

- W-E-W-E 交替 → 正常前进，每周期移动 1m（平地）
- W-W → 收脚锁 W，不动 → 再按 W 无效 → 按 E 解除继续走
- 盲杖扫动不受步态影响（并行操作）
- 撞墙迈步 → 踉跄反馈
- 台阶判定正常

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/player/GaitController.gd` |
| 删除 | `scripts/player/PlayerController.gd`（移为 .bak 备份） |

## 场景更新

Main.tscn 中 Player 节点的脚本改为 `GaitController.gd`，并添加 `PlayerAttributes`、`ViewController`、`CaneSystem` 子节点。
