# ADR 0005: InputManager 吞并视角控制 + input_enabled 归 GameState

**日期**: 2026-07-09  
**状态**: Accepted  
**取代**: PRD §2.4 ViewController, Issue #0004

---

## 上下文

### 视角控制独立模块的问题

PRD §2.4 原设计要求独立的 `ViewController.gd` 挂载在 Player 下。在原型开发中发现：

1. **过度解耦**：玩家实体上的视角、属性、步态、感知全部拆为独立模块，模块间通信开销大于职责分离收益
2. **输入分散**：鼠标输入既驱动盲杖扫动（CaneSystem），又驱动视角旋转（ViewController），还需要 InputManager 做溢出转发——三个模块共同处理一组鼠标事件
3. **InputManager 已是输入聚合层**：`ref/prototype` 中 InputManager 已经统一处理键鼠输入并转发给各组件。视角控制本质上是"鼠标输入的一种解释方式"，归入 InputManager 是自然延伸

### input_enabled 重复问题

三个组件（InputManager、GaitController、CaneSystem）各自维护 `input_enabled: bool` + `set_input_enabled()` 方法。CutsceneManager 通过 `has_method` 鸭子类型遍历调用每个组件。问题：

1. **Duplicated Code**：三处相同的 flag + setter
2. **真相分散**：三个独立布尔值可能不同步
3. **鸭子类型耦合**：CutsceneManager 依赖组件方法名约定，非类型安全
4. **语义错位**：`input_enabled` 的触发原因只有"游戏流程状态"（加载中/演出中/已结束），不是组件的私有状态

## 决策

### 1. 视角控制归入 InputManager

- **不创建** 独立的 `ViewController.gd`
- InputManager 负责鼠标输入的两种解释模式：
  - **R 键按住**：鼠标直接控制摄像机 Yaw/Pitch（标准 FPS 视角）
  - **默认模式**：鼠标先驱动盲杖扫动，溢出量转发为玩家 Yaw 旋转
- Pitch 限制 -80° ~ +80°，由 InputManager 内部管理
- 身体朝向 = 摄像机朝向，通过旋转 Player 根节点的 Yaw 实现

### 2. input_enabled 由 GameState 拥有

- GameState 新增 `_cutscene_active: bool` 和以下方法：

```gdscript
func set_cutscene_active(active: bool) -> void:
    _cutscene_active = active

func is_input_enabled() -> bool:
    return current_state == State.PLAYING and not _cutscene_active
```

- 组件**不再持有** `input_enabled` flag，在输入处理入口点直接查询 `GameState.is_input_enabled()`
- CutsceneManager 调用 `GameState.set_cutscene_active(true/false)`，不再遍历组件

### 3. 删除内容

| 删除 | 替代 |
|------|------|
| `InputManager.input_enabled` + `set_input_enabled()` | 查询 `GameState.is_input_enabled()` |
| `GaitController.input_enabled` + `set_input_enabled()` | 同上 |
| `CaneSystem.input_enabled` + `set_input_enabled()` | 同上 |
| `CutsceneManager._set_player_input()` 遍历逻辑 | `GameState.set_cutscene_active()` |
| `ViewController.gd`（不创建） | InputManager 内部视角控制逻辑 |

## 理由

### 为什么视角控制归 InputManager 而非独立模块

1. **输入是单一入口**：鼠标移动既可能驱动盲杖也可能驱动视角，这个"解释"决策应该在输入层完成，而非分散到两个模块再协调
2. **减少模块数量**：玩家实体下已有 GaitController、PlayerAttributes、CaneSystem、TouchMemorySystem，再加 ViewController 过于碎片化
3. **prototype 验证可行**：`ref/prototype` 的 InputManager 已成功整合视角控制，效果符合预期

### 为什么 input_enabled 归 GameState 而非 InputManager 或 GameConfig

1. **语义正确**：`input_enabled` 的触发原因全是游戏流程状态（LOADING/CUTSCENE/SUCCESS/FAILURE），是 GameState 的自然职责
2. **单一真相源**：一个属性一个持有者，消除三处重复
3. **无新单例**：GameState 已是 autoload，不违反 AGENTS.md §5
4. **无双向依赖**：组件只读 GameState（已有全局依赖），不像"组件读 InputManager"会产生双向耦合
5. **GameConfig 不合适**：GameConfig 是 `const` 常量容器，不放可变运行时状态

## 替代方案

| 方案 | 否决理由 |
|------|---------|
| 组件读 InputManager 的 input_enabled | InputManager → GaitController（调用 request_step）+ GaitController → InputManager（读 flag）= 双向依赖 |
| 放 GameConfig | GameConfig 是 const 容器，不放可变状态 |
| 新建 InputGate 单例 | 不必要的新单例，违反 AGENTS.md §5 |
| EventBus 信号广播 input_enabled_changed | 组件在输入入口点查询即可，不需要 push 通知；信号增加复杂度 |

## 影响

- PRD §2.4 标记为被本 ADR 取代
- PRD 新增 InputManager 条目（§2.13）
- Issue #0004 标记为 Superseded
- GameState 新增 `set_cutscene_active()` / `is_input_enabled()`
- 三个组件删除 `input_enabled` flag + setter
- CutsceneManager 简化：一行 `GameState.set_cutscene_active()` 替代遍历
