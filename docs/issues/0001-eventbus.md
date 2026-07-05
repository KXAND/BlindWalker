# Issue #1: EventBus 信号总线 + Autoload 注册

**依赖**: 无  
**参考**: PRD §2.1, CONTEXT.md

---

## 需求

创建全局信号总线 `EventBus.gd`，作为 autoload 单例加载。所有模块通过 EventBus 进行解耦通信。

## 范围

1. 创建 `scripts/core/EventBus.gd`，定义 PRD §2.1 列出的全部信号
2. 在 `project.godot` 中注册 `EventBus` 为 autoload
3. 验证：场景启动后 `EventBus` 可被任何脚本通过全局名访问

## 验收

- `EventBus` 在游戏启动后存在
- 任意脚本可 `EventBus.player_damaged.connect(...)` 订阅信号
- 任意脚本可 `EventBus.player_damaged.emit(10, 90)` 发射信号

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/core/EventBus.gd` |
| 修改 | `project.godot`（添加 autoload 条目） |
