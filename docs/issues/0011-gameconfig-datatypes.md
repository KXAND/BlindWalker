# Issue #0011: GameConfig + 自定义数据结构

## 依赖

无（最先做）

## 参考

- PRD §2.0
- ADR 0002
- CONTEXT.md §配置

## 任务

### 1. GameConfig.gd

在 `scripts/core/GameConfig.gd` 创建 `class_name GameConfig`，定义以下 `const`：

**按键映射**：
- `KEY_LEFT_FOOT = KEY_W`
- `KEY_RIGHT_FOOT = KEY_E`
- `KEY_CAUTIOUS = KEY_SHIFT`
- `KEY_HIGH_STEP = KEY_SPACE`
- `KEY_LOOK_DIRECT = KEY_R`
- `KEY_TOUCH = MOUSE_BUTTON_LEFT`

**步态参数**：
- `STEP_LENGTH_FLAT = 0.5`
- `STEP_LENGTH_STAIR = 0.35`
- `MAX_HIGH_STEP_HEIGHT = 0.3`
- `HIGH_STEP_CHARGE_RATE = 0.2`

**盲杖参数**：
- `CANE_SWEEP_ANGLE = 60.0`
- `CANE_LENGTH = 1.5`

**血量/摔跤**：
- `MAX_HP = 100`
- `FALL_DAMAGE = 20`
- `STAGGER_PUSH_BACK = 0.15`

### 2. 自定义数据结构

在 `scripts/core/` 下创建：

**StepResult.gd**：
```gdscript
class_name StepResult
enum StepResultType { SUCCESS, STAGGER, FALL }
var type: StepResultType
var displacement: Vector3
```

**CaneHitInfo.gd**：
```gdscript
class_name CaneHitInfo
var collider: Object
var point: Vector3
var normal: Vector3
```

**NpcDialogue.gd**：
```gdscript
class_name NpcDialogue
var lines: Array[String]
var voice_paths: Array[String]
```

## 验收标准

- [ ] `GameConfig.gd` 存在且包含所有常量
- [ ] `StepResult.gd`、`CaneHitInfo.gd`、`NpcDialogue.gd` 存在
- [ ] 无运行时错误（可在 Godot 编辑器中打开项目验证 `class_name` 注册成功）
- [ ] 不产生 autoload 注册
