class_name GaitController
extends CharacterBody3D
## 连续移动控制器。按住 W 前进，SHIFT 谨慎减速，SPACE 高抬腿模式。
## 不读取键鼠输入——所有输入意图由 InputManager 转发。

@export var gravity: float = 9.8
@export var stagger_duration: float = 0.3
@export var fall_recover_time: float = 1.5
@export var terrain_check_interval: float = 0.05

const TERRAIN_PROBE_DISTANCE := 0.5
const STAIR_UP_THRESHOLD := 0.06
const STAIR_DOWN_THRESHOLD := -0.15
const WALL_NORMAL_THRESHOLD := 0.45
const WALL_HIT_COOLDOWN := 0.3
const FALL_Y_THRESHOLD := -10.0
const _RaycastUtil = preload("res://scripts/core/RaycastUtil.gd")

var _is_moving: bool = false
var _cautious_active: bool = false
var _high_step_active: bool = false

var _stagger_timer: float = 0.0
var _fall_recover_timer: float = 0.0
var _terrain_check_timer: float = 0.0
var _wall_hit_cooldown: float = 0.0
var _fall_start_y: float = 0.0
var _was_falling: bool = false
var _was_on_floor: bool = false

var _distance_since_last_step: float = 0.0
var _last_foot_left: bool = false
var _stair_up_handled: bool = false  # 本帧 stair_up 已处理，跳过 wall_hit 检测
# 平滑上台阶：探测到目标高度后，Player.y 按速度逐步逼近，避免相机瞬时跳跃
var _stair_up_target_y: float = NAN  # NAN 表示当前没有正在抬升的目标
const STAIR_UP_LIFT_SPEED := 3.0    # m/s，足够快不卡顿，也足够慢不跳变

@onready var _attributes: PlayerAttributes = get_node_or_null("PlayerAttributes") as PlayerAttributes


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		if _was_on_floor and not _was_falling:
			_fall_start_y = global_position.y
			_was_falling = true
		velocity.y -= gravity * delta
		if global_position.y < FALL_Y_THRESHOLD:
			_do_fall(absf(_fall_start_y - global_position.y))
			_was_falling = false
	else:
		if _was_falling:
			var fall_dist := absf(_fall_start_y - global_position.y)
			# 谨慎模式下主动走下台阶，物理自然落地不受惩罚
			if fall_dist > 0.5 and not _cautious_active:
				_do_fall(fall_dist)
			_was_falling = false
		_was_on_floor = true
		# 正在平滑上台阶时不要把 velocity.y 强制成 -0.1，否则会和抬升目标值拉扯
		if is_nan(_stair_up_target_y):
			velocity.y = -0.1

	# Timers
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
	if _fall_recover_timer > 0.0:
		_fall_recover_timer -= delta
	if _wall_hit_cooldown > 0.0:
		_wall_hit_cooldown -= delta
	if _terrain_check_timer > 0.0:
		_terrain_check_timer -= delta

	# Horizontal movement
	var can_move := GameState.is_input_enabled() and _fall_recover_timer <= 0.0 and _stagger_timer <= 0.0
	_stair_up_handled = false
	if can_move and _is_moving:
		var speed := _current_speed()
		var forward := -global_transform.basis.z.normalized()
		velocity.x = forward.x * speed
		velocity.z = forward.z * speed

		# Throttled terrain check
		if _terrain_check_timer <= 0.0:
			_check_terrain(forward)
			_terrain_check_timer = terrain_check_interval
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	var pos_before := global_position
	move_and_slide()

	# 平滑抬升上台阶：move_and_slide 之后再插值逼近目标高度
	# 抬升期间不会与物理碰撞冲突（player 在地面上，y 只往上走）
	if not is_nan(_stair_up_target_y):
		var dy := _stair_up_target_y - global_position.y
		if absf(dy) <= 0.001:
			global_position.y = _stair_up_target_y
			_stair_up_target_y = NAN
		else:
			global_position.y += clampf(dy, -STAIR_UP_LIFT_SPEED * delta, STAIR_UP_LIFT_SPEED * delta)
			# 抬升过程需要保持"在地面上"的速度行为；不要把 velocity.y 改回 -0.1
			velocity.y = 0.0

	# Wall hit detection — skip if stair_up was already handled this frame.
	# 同时在以下条件中跳过：跌落恢复期、玩家正在下落、stagger 已激活、正在平滑抬升。
	# 避免"摔倒"瞬间被错判为撞墙而叠加 stagger，也避免抬升途中被误判成撞墙。
	if _is_moving and can_move and not _stair_up_handled \
			and _fall_recover_timer <= 0.0 \
			and is_on_floor() \
			and velocity.y >= -0.1 \
			and _stagger_timer <= 0.0 \
			and is_nan(_stair_up_target_y):
		_detect_wall_hit(pos_before)

	# Step audio
	if _is_moving and can_move and is_on_floor():
		_update_step_audio(pos_before)
	else:
		_distance_since_last_step = 0.0


# ---- Input interface (called by InputManager) ----

func set_moving(active: bool) -> void:
	_is_moving = active


func set_cautious(active: bool) -> void:
	_cautious_active = active


func set_high_step(active: bool) -> void:
	_high_step_active = active


func teleport_to(pos: Vector3) -> void:
	## 传送玩家并重置所有跌落追踪状态，避免传送后落地被误判为摔落。
	## 先用射线探地，将玩家精确放置在地面正上方，避免传送后悬空。
	var surface_y := _floor_height_at(pos)
	if not is_nan(surface_y):
		# CollisionShape offset=0.95，胶囊底部 = 节点Y + 0.35，贴地余量 0.02m
		pos.y = surface_y - 0.35 + 0.02
	global_position = pos
	velocity = Vector3.ZERO
	_was_falling = false
	_was_on_floor = false
	_fall_start_y = pos.y
	_fall_recover_timer = 0.0
	_stagger_timer = 0.0
	_terrain_check_timer = 0.0
	_wall_hit_cooldown = 0.0
	_stair_up_target_y = NAN


# ---- Internal logic ----

func _current_speed() -> float:
	if _high_step_active:
		return GameConfig.HIGH_STEP_SPEED
	if _cautious_active:
		return GameConfig.CAUTIOUS_SPEED
	return GameConfig.WALK_SPEED


func _check_terrain(forward: Vector3) -> void:
	if GameState.is_gameplay_locked():
		return
	if not is_on_floor():
		return

	var current_floor := _floor_height_at(global_position)
	if is_nan(current_floor):
		return

	var probe_pos := global_position + forward * TERRAIN_PROBE_DISTANCE
	var target_floor := _floor_height_at(probe_pos)
	if is_nan(target_floor):
		return

	var terrain_delta := target_floor - current_floor

	# Stair up
	if terrain_delta > STAIR_UP_THRESHOLD:
		_stair_up_handled = true
		if _high_step_active and terrain_delta <= GameConfig.MAX_HIGH_STEP_HEIGHT:
			# SPACE held + step within height limit: 设定抬升目标高度，Player.y 在 _physics_process 中平滑逼近
			# 这样相机不会在每帧 0.05s 节流触发时被瞬时跳变
			_stair_up_target_y = target_floor
		else:
			# No SPACE, or step too high: stagger + damage
			# 注意：stagger 路径不要碰 y，否则会和已经存在的抬升目标打架
			_stair_up_target_y = NAN
			velocity.x = 0.0
			velocity.z = 0.0
			_do_stagger(forward)
			if _attributes:
				if GameConfig.DEBUG:
					print("[DEBUG][GaitController] stair_up blocked delta=%.2f damage=%d" % [terrain_delta, GameConfig.STAIR_UP_DAMAGE])
				_attributes.take_damage(GameConfig.STAIR_UP_DAMAGE)

	# Stair down
	elif terrain_delta < STAIR_DOWN_THRESHOLD:
		if _cautious_active:
			# SHIFT held: let physics handle the drop naturally, no penalty
			if GameConfig.DEBUG:
				print("[DEBUG][GaitController] stair_down safe (cautious) delta=%.2f" % terrain_delta)
		else:
			_do_fall(absf(terrain_delta))


func _detect_wall_hit(pos_before: Vector3) -> void:
	if GameState.is_gameplay_locked():
		return
	if _wall_hit_cooldown > 0.0 or _stagger_timer > 0.0:
		return
	# 跌落恢复期内：刚摔过，stagger 不该再叠加；这种"水平没动"是正常的恢复表现
	if _fall_recover_timer > 0.0:
		return
	var actual_move := global_position - pos_before
	var horizontal_move := Vector2(actual_move.x, actual_move.z).length()
	var expected_move := _current_speed() * get_physics_process_delta_time()
	if expected_move > 0.01 and horizontal_move < expected_move * 0.3:
		_do_stagger(-global_transform.basis.z.normalized())
		_wall_hit_cooldown = WALL_HIT_COOLDOWN


func _update_step_audio(pos_before: Vector3) -> void:
	var actual_move := global_position - pos_before
	var horizontal_move := Vector2(actual_move.x, actual_move.z).length()
	_distance_since_last_step += horizontal_move
	if _distance_since_last_step >= GameConfig.STEP_AUDIO_DISTANCE:
		_distance_since_last_step = 0.0
		_last_foot_left = not _last_foot_left
		EventBus.audio_requested.emit("step", global_position, 0.0)


func _do_stagger(forward: Vector3) -> void:
	if GameState.is_gameplay_locked():
		return
	_stagger_timer = stagger_duration
	global_position -= forward * GameConfig.STAGGER_PUSH_BACK
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] stagger push_back=%.2f" % GameConfig.STAGGER_PUSH_BACK)
	EventBus.audio_requested.emit("wall_hit", global_position, 0.0)


func _do_fall(fall_distance: float) -> void:
	if GameState.is_gameplay_locked():
		return
	_fall_recover_timer = fall_recover_time
	# 摔倒时显式清掉 stagger：stagger 是"撞墙踉跄"，与"跌落"是两件事，不能同时出现
	_stagger_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] fall distance=%.2f damage=%d" % [fall_distance, GameConfig.FALL_DAMAGE])
	EventBus.audio_requested.emit("fall", global_position, 0.0)
	EventBus.player_fell.emit(fall_distance)
	if _attributes:
		_attributes.take_damage(GameConfig.FALL_DAMAGE)


func _floor_height_at(sample_position: Vector3) -> float:
	var from := sample_position + Vector3.UP * 0.8
	var to := sample_position + Vector3.DOWN * 1.4
	var space_state := get_world_3d().direct_space_state
	var result := _RaycastUtil.query_body(space_state, from, to, get_rid())
	if result.is_empty():
		return NAN
	var hit_position: Vector3 = result["position"]
	return hit_position.y
