# ADR 0002: GameConfig 使用 class_name 而非 autoload

## 日期

2026-07-04

## 状态

已接受

## 上下文

游戏存在大量可调参数（按键映射、步长、盲杖锥角等），不应硬编码在逻辑文件中。
需要一个全局可访问的配置来源。

## 决策

- 使用 `class_name GameConfig`（`scripts/core/GameConfig.gd`），而非 autoload 单例
- 所有常量为 `const`，运行时不可变
- 各模块通过 `GameConfig.KEY_LEFT_FOOT` 直接引用，无 preload

## 理由

1. `class_name` 更接近 Python `import` 的体验——按名字引用，显式可见
2. 不占用 autoload 运行时资源（autoload 列表保持精简：EventBus、GameState、AudioManager）
3. `const` 编译时常量，零运行时开销
4. 改值需修改文件后重新导出——MVP 阶段可接受

## 替代方案

| 方案 | 否决理由 |
|------|---------|
| autoload | 运行时实例化无必要，增加 autoload 数量 |
| 自定义 Resource + .tres | 依赖编辑器、.tres 二进制不 VCS 友好 |
| static func 返回 dict | 失去类型安全，无 IDE 补全 |

## 影响

- 所有模块引用按键和参数时使用 `GameConfig.CONST_NAME`
- 数据结构（StepResult、CaneHitInfo 等）同样使用 `class_name`，放在 `scripts/core/`
