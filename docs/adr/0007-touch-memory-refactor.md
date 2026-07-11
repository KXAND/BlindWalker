# ADR 0007: TouchMemorySystem 重构 — 左前方手触、右键触发、杖触记忆共享显影

**日期**: 2026-07-10  
**状态**: Accepted

---

玩家伸手触摸的方向定为**相机局部坐标系左前方约 45 度**，随摄像机俯仰角联动：即无论相机抬头还是低头，探测方向始终在相机视角内保持左前方，而非世界坐标系水平偏移。实现上由 `GameConfig.TOUCH_YAW_OFFSET_DEG` 表达具体角度：

```gdscript
var forward := -camera.global_transform.basis.z
var direction := forward.rotated(camera.global_transform.basis.y, deg_to_rad(GameConfig.TOUCH_YAW_OFFSET_DEG))
```

触发绑定由鼠标左键改为**右键**，为单次触发（非持续）。在 Web 平台需通过 `JavaScriptBridge.eval()` 阻止浏览器默认右键菜单；否则 `MOUSE_BUTTON_RIGHT` 在浏览器中会被拦截，触摸功能完全失效。

`TouchMemorySystem.try_touch()` 中"射线投射 + 生成内存球"的逻辑拆分为独立的 `spawn_touch_memory(position, active_radius, active_life, afterglow_radius, afterglow_life)` 公共方法，使外部系统（如 `CaneSystem`）可以在自行获得接触点后直接生成视觉反馈，而无需重复射线检测。

`CaneSystem` 在盲杖接触环境时调用 `spawn_touch_memory()` 生成杖触记忆。杖触记忆使用比手触记忆更小的半径和更短的寿命，但不是“同一物体只触发一次”：大建筑、长墙、路沿等大物体需要能留下多个局部触觉记忆点。

杖触记忆采用**接触节流**：只有当接触点相对上一个杖触记忆点发生显著空间变化，或持续接触超过节流时间时，才生成新的触觉记忆点。MVP 起始参数为 `CANE_TOUCH_MEMORY_MIN_DISTANCE = 0.45` 和 `CANE_TOUCH_MEMORY_COOLDOWN = 0.75`。`cane_hit` 声音与杖触记忆绑定：只有成功生成杖触记忆时才播放对应碰撞声音，避免持续贴墙时声音刷屏。

手触记忆和杖触记忆都会随时间逐渐消失。显影球在玩家靠近时暂停衰减，远离时继续缩小；残影球按自身寿命衰减。不同来源的触觉记忆点必须保留自己的初始半径，不能在生命周期更新时统一恢复成手触记忆大小。触觉记忆数量达到 `MAX_SPHERES` 时，淘汰最旧点，保留最新感知反馈。

`touch_max_distance` 的 `@export` 变量从 `TouchMemorySystem` 中删除，统一由 `GameConfig.TOUCH_DISTANCE` 管理，消除两处并存的距离常量（原 `@export` 默认 5.0 与 `GameConfig` 中 3.0 不一致）。

视觉表达采用“轮廓显影 + 面显影”组合。原先只依赖深度/法线边缘时，圆柱、墙面等平滑表面在非调试模式下只有特定视角才明显；因此 shader 在记忆球覆盖范围内保留弱透明面显影（`feedback_surface_alpha`），同时继续用边缘检测强调轮廓。这样杖触到灯柱、墙面等物体时，玩家能稳定看到被触局部，而不是只看到调试模式或轮廓角度恰好明显时的反馈。

## 考虑的替代方案

| 方案 | 否决理由 |
|------|---------|
| 触摸方向偏移使用世界坐标系 Y 轴旋转 | 相机低头时"水平左偏"会变成"斜向左下"，不符合"伸手方向与视线一致"的体感 |
| 同一物体只生成一次杖触记忆 | 大建筑或长墙会只留下一个点，不能表达玩家沿物体连续探索的路径 |
| 杖触摸按固定冷却时间重复生成 | 停在同一点贴墙时仍会生成过多视觉噪音；仅按时间无法表达接触点空间变化 |
| 杖触摸经由 EventBus 信号转发给 TouchMemorySystem | Cane → TouchMemory 是直接因果，不需要广播；直接方法调用更简单、依赖关系更清晰 |
| 保留 `touch_max_distance` 的 `@export`，仅在编辑器中与 GameConfig 保持同步 | 两处配置必然漂移；`@export` 覆盖 `GameConfig` 值时会产生静默 bug |
| 只保留轮廓显影 | 平滑物体正面缺少明显深度/法线边缘，正常模式下反馈不稳定；面显影是 MVP 阶段更可靠的可见性兜底 |
