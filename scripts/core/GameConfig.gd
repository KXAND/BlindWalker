class_name GameConfig
## 全局游戏配置 —— 所有常量集中管理

# ---- 按键映射 ----
const KEY_FORWARD := KEY_W
const KEY_CAUTIOUS := KEY_SHIFT
const KEY_HIGH_STEP := KEY_SPACE
const KEY_LOOK_DIRECT := KEY_R
const KEY_TOUCH := MOUSE_BUTTON_RIGHT
const KEY_INTERACT := KEY_E

# ---- 移动参数 ----
const WALK_SPEED := 1.0
const CAUTIOUS_SPEED := 0.3
const HIGH_STEP_SPEED := 0.3
const STEP_AUDIO_DISTANCE := 0.5

# ---- 步态参数 ----
const MAX_HIGH_STEP_HEIGHT := 0.4
const LIGHT_STUMBLE_RECOVER_TIME := 0.35
const UNSTABLE_STUMBLE_QTE_WINDOW := 0.75
const UNSTABLE_STUMBLE_QTE_HOLD_TIME := 1.0
const UNSTABLE_STUMBLE_MOVE_PENALTY := 1.5
const FALL_GET_UP_TIME := 1.2
const TUMBLE_SPEED := 1.2
const TUMBLE_MIN_TRAVEL_DISTANCE := 0.9
const TUMBLE_MAX_TIME := 4.0
const TUMBLE_DAMAGE_INTERVAL := 1.0
const TUMBLE_FINAL_DAMAGE_MIN_INTERVAL := 0.7
const TUMBLE_DAMAGE_CAP := 80
const TUMBLE_STABLE_SLOPE_DELTA := 0.08
const TUMBLE_STABLE_FORWARD_DELTA := 0.08

# ---- 盲杖参数 ----
const CANE_SWEEP_ANGLE := 60.0
const CANE_LENGTH := 1.5

# ---- 触摸参数 ----
const TOUCH_YAW_OFFSET_DEG: float = 45.0    ## 手触摸射线相对相机正前方的左前方偏转角（相机局部坐标系，正值=左偏）
const TOUCH_DISTANCE: float = 1.2            ## 手触摸最大探测距离（米）
const TOUCH_MEMORY_RADIUS: float = 0.5      ## 手触摸显影半径（米）
const TOUCH_AFTERGLOW_RADIUS: float = 0.5   ## 手触摸残影半径（米）

# ---- 杖触内存参数 ----
const CANE_TOUCH_MEMORY_RADIUS: float = 0.6  ## 盲杖触碰显影半径（米）
const CANE_TOUCH_AFTERGLOW_RADIUS: float = 0.6 ## 盲杖触碰残影半径（米）
const CANE_TOUCH_MEMORY_LIFETIME: float = 8.0 ## 杖触内存显影球寿命（秒）
const CANE_TOUCH_MEMORY_MIN_DISTANCE: float = 0.45 ## 杖触记忆点之间的最小空间间隔（米）
const CANE_TOUCH_MEMORY_COOLDOWN: float = 0.75 ## 同一接触段内生成新杖触记忆点的最小时间间隔（秒）
const CANE_TOUCH_CONTACT_BREAK_GRACE: float = 0.15 ## 接触断开超过该时长后，下次接触视为新接触段

# ---- 血量 / 摔跤 ----
const MAX_HP := 100
const TUMBLE_TICK_DAMAGE := 12
const STAIR_UP_DAMAGE := 5  # 未按 SPACE 强行上台阶时扣血；数值待 playtesting 调整
const STAGGER_PUSH_BACK := 0.15

# ---- 调试 ----
const DEBUG := true
