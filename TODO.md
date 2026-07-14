# TODO

> 记录当前 MVP 后续工作。这里不是需求入口，只放已经识别但暂不处理的事项。

## 合并 / 发布前

- 将 `scripts/core/GameConfig.gd` 中的 `DEBUG := true` 改为 `false`，并确认关闭后不会影响必要的玩家反馈。
- 确认当前文档与 PR 描述一致，避免把本 PR 表述为完整产品 MVP；更准确的范围是 playable navigation MVP。

## 代码整理

- Review `scripts/perception/CaneSystem.gd`，判断是否需要拆解。当前文件在 MVP 阶段同时承担盲杖姿态、碰撞检测、接触点定位、显影触发、音效触发和视觉节点创建，后续可考虑拆出接触定位与反馈触发模块。
- 明确 `scripts/core/EventBus.gd` 中 `touch_detected(hit_point)` 的用途。如果没有消费者，删除该信号或在文档中标记为预留；如果需要 UI/音频/记录消费，则在 `scripts/interaction/TouchMemorySystem.gd` 命中手触时发出该信号。

## 功能接线

- 检查 `scripts/ui/CutsceneManager.gd` 是否需要接入开场和结尾流程。当前已有 `play(cutscene_id)`，但尚未看到实际调用方。

## 已知问题

- 调查扶手/细杆与盲杖接触时的偶发输入死区。现象是玩家仍可移动，但短时间内鼠标无法明显驱动盲杖扫动或视角旋转；临时脚本未复现持续锁死，只观察到极短 dead-zone。后续若再出现，应优先用真实楼梯扶手位置复现，并检查 `scripts/perception/CaneSystem.gd` 中目标姿态被碰撞阻挡时是否吞掉输入溢出。
