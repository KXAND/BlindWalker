class_name GameConfig
extends RefCounted

## MVP 共享常量。这里不做 autoload，脚本通过 class_name 直接读取。
const KEY_LEFT_FOOT: Key = KEY_W
const KEY_RIGHT_FOOT: Key = KEY_E
const KEY_CAUTIOUS: Key = KEY_SHIFT
const KEY_HIGH_STEP: Key = KEY_SPACE
const KEY_LOOK_DIRECT: Key = KEY_R
const KEY_TOUCH: MouseButton = MOUSE_BUTTON_LEFT

const STEP_LENGTH_FLAT: float = 0.5
const STEP_LENGTH_STAIR: float = 0.35
const MAX_HIGH_STEP_HEIGHT: float = 0.3
const HIGH_STEP_CHARGE_RATE: float = 0.2

const CANE_SWEEP_ANGLE: float = 60.0
const CANE_LENGTH: float = 1.5

const MAX_HP: int = 100
const FALL_DAMAGE: int = 20
const STAGGER_PUSH_BACK: float = 0.15
