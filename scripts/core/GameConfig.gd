class_name GameConfig
## 全局游戏配置 —— 所有常量集中管理

# ---- 按键映射 ----
const KEY_FORWARD := KEY_W
const KEY_CAUTIOUS := KEY_SHIFT
const KEY_HIGH_STEP := KEY_SPACE
const KEY_LOOK_DIRECT := KEY_R
const KEY_TOUCH := MOUSE_BUTTON_RIGHT

# ---- 移动参数 ----
const WALK_SPEED := 0.8
const CAUTIOUS_SPEED := 0.3
const HIGH_STEP_SPEED := 0.3
const STEP_AUDIO_DISTANCE := 0.5

# ---- 步态参数 ----
const MAX_HIGH_STEP_HEIGHT := 0.3

# ---- 盲杖参数 ----
const CANE_SWEEP_ANGLE := 60.0
const CANE_LENGTH := 1.5

# ---- 触摸参数 ----
const TOUCH_YAW_OFFSET_DEG: float = 45.0    ## 手触摸射线相对相机正前方的左前方偏转角（相机局部坐标系，正值=左偏）
const TOUCH_DISTANCE: float = 3.0            ## 手触摸最大探测距离（米）

# ---- 杖触内存参数 ----
const CANE_TOUCH_MEMORY_SCALE: float = 0.4   ## 杖触内存球半径相对手触摸的缩放比例
const CANE_TOUCH_MEMORY_LIFETIME: float = 8.0 ## 杖触内存显影球寿命（秒）
const CANE_TOUCH_MEMORY_MIN_DISTANCE: float = 0.45 ## 杖触记忆点之间的最小空间间隔（米）
const CANE_TOUCH_MEMORY_COOLDOWN: float = 0.75 ## 持续接触时生成新杖触记忆点的最小时间间隔（秒）

# ---- 血量 / 摔跤 ----
const MAX_HP := 100
const FALL_DAMAGE := 20
const STAIR_UP_DAMAGE := 5  # 未按 SPACE 强行上台阶时扣血；数值待 playtesting 调整
const STAGGER_PUSH_BACK := 0.15

# ---- 调试 ----
const DEBUG := true
