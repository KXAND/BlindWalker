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
const FLOOR_SNAP_LENGTH := 0.35
const FLOOR_HEIGHT_MISSING := -1000000.0
const _RaycastUtil = preload("res://scripts/core/RaycastUtil.gd")
const _ContactProfileProvider = preload("res://scripts/interaction/ContactProfileProvider.gd")
const DEFAULT_STEP_SOUND_ID := &"step"

enum BalanceState { STEADY, LIGHT_STUMBLE, UNSTABLE_STUMBLE, FALLING, GETTING_UP }

var _is_moving: bool = false
var _cautious_active: bool = false
var _high_step_active: bool = false
var _recovery_qte_pressed: bool = false
var _unstable_stumble_progress: float = 0.0

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
var _has_stair_up_target: bool = false
var _stair_up_target_y: float = 0.0
const STAIR_UP_LIFT_SPEED := 3.0    # m/s，足够快不卡顿，也足够慢不跳变

var _balance_state: int = BalanceState.STEADY
var _balance_timer: float = 0.0
var _tumble_direction: Vector3 = Vector3.ZERO
var _tumble_start_position: Vector3 = Vector3.ZERO
var _has_fall_lift_target: bool = false
var _fall_lift_target_y: float = 0.0
var _pending_stumble_lift_delta: float = 0.0
var _tumble_elapsed: float = 0.0
var _fall_damage_total: int = 0
var _fall_damage_elapsed: float = 0.0
var _time_since_fall_damage: float = 0.0
var _handrail_assist: Area3D

@onready var _attributes: PlayerAttributes = get_node_or_null("PlayerAttributes") as PlayerAttributes


func _ready() -> void:
	add_to_group("player")
	floor_snap_length = FLOOR_SNAP_LENGTH


func _physics_process(delta: float) -> void:
	if is_instance_valid(_handrail_assist) and not _handrail_assist.is_player_inside():
		_handrail_assist = null
	_update_balance_state(delta)

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
			if fall_dist > 0.5 and not _cautious_active and _balance_state != BalanceState.FALLING:
				_do_fall(fall_dist)
			_was_falling = false
		_was_on_floor = true
		# 正在平滑上台阶时不要把 velocity.y 强制成 -0.1，否则会和抬升目标值拉扯
		if not _has_stair_up_target:
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
	var can_move := GameState.is_input_enabled() \
			and _fall_recover_timer <= 0.0 \
			and _balance_state != BalanceState.FALLING \
			and _balance_state != BalanceState.GETTING_UP
	_stair_up_handled = false
	if _balance_state == BalanceState.FALLING:
		velocity.x = _tumble_direction.x * GameConfig.TUMBLE_SPEED
		velocity.z = _tumble_direction.z * GameConfig.TUMBLE_SPEED
	elif can_move and _is_moving:
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

	if _balance_state == BalanceState.FALLING and _has_fall_lift_target:
		var lift_dy := _fall_lift_target_y - global_position.y
		if absf(lift_dy) <= 0.001:
			global_position.y = _fall_lift_target_y
			_has_fall_lift_target = false
		else:
			# 低矮路牙磕绊后的摔倒会越到上方平面；这里复用高抬腿的抬升速度。
			global_position.y += clampf(lift_dy, -STAIR_UP_LIFT_SPEED * delta, STAIR_UP_LIFT_SPEED * delta)
			velocity.y = 0.0

	# 平滑抬升上台阶：move_and_slide 之后再插值逼近目标高度
	# 抬升期间不会与物理碰撞冲突（player 在地面上，y 只往上走）
	if _has_stair_up_target:
		var dy := _stair_up_target_y - global_position.y
		if absf(dy) <= 0.001:
			global_position.y = _stair_up_target_y
			_has_stair_up_target = false
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
			and not _has_stair_up_target:
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
	if not active and not is_handrail_assist_active():
		_has_stair_up_target = false


func set_recovery_qte_pressed(active: bool) -> void:
	_recovery_qte_pressed = active


func set_handrail_assist(handrail: Area3D) -> void:
	_handrail_assist = handrail


func clear_handrail_assist(handrail: Area3D = null) -> void:
	if handrail == null or handrail == _handrail_assist:
		_handrail_assist = null


func is_handrail_assisted_by(handrail: Area3D) -> bool:
	return is_instance_valid(_handrail_assist) and _handrail_assist == handrail


func is_handrail_assist_active() -> bool:
	return is_instance_valid(_handrail_assist) and _handrail_assist.is_player_inside()


func is_recovery_qte_active() -> bool:
	return _balance_state == BalanceState.UNSTABLE_STUMBLE


func is_balance_view_locked() -> bool:
	return _balance_state == BalanceState.FALLING or _balance_state == BalanceState.GETTING_UP


func debug_balance_state() -> StringName:
	match _balance_state:
		BalanceState.STEADY:
			return &"steady"
		BalanceState.LIGHT_STUMBLE:
			return &"light_stumble"
		BalanceState.UNSTABLE_STUMBLE:
			return &"unstable_stumble"
		BalanceState.FALLING:
			return &"falling"
		BalanceState.GETTING_UP:
			return &"getting_up"
	return &"unknown"


func has_move_intent() -> bool:
	return _is_moving


func teleport_to(pos: Vector3) -> void:
	## 传送玩家并重置所有跌落追踪状态，避免传送后落地被误判为摔落。
	## 先用射线探地，将玩家精确放置在地面正上方，避免传送后悬空。
	var surface_y := _floor_height_at(pos)
	if _has_floor_height(surface_y):
		# CollisionShape offset=0.95，胶囊底部 = 节点Y + 0.35，贴地余量 0.02m
		pos.y = surface_y - 0.35 + 0.02
	global_position = pos
	velocity = Vector3.ZERO
	_was_falling = false
	_was_on_floor = false
	_fall_start_y = pos.y
	_fall_recover_timer = 0.0
	_stagger_timer = 0.0
	_balance_state = BalanceState.STEADY
	_balance_timer = 0.0
	_handrail_assist = null
	_recovery_qte_pressed = false
	_unstable_stumble_progress = 0.0
	_has_fall_lift_target = false
	_pending_stumble_lift_delta = 0.0
	_terrain_check_timer = 0.0
	_wall_hit_cooldown = 0.0
	_has_stair_up_target = false


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
	# 失衡踉跄已经由当前地形触发；不要在 QTE 窗口内因同一个路牙/台阶重复判定而立刻升级为摔倒。
	if _balance_state == BalanceState.UNSTABLE_STUMBLE:
		return

	var current_floor := _floor_height_at(global_position)
	if not _has_floor_height(current_floor):
		return

	var probe_pos := global_position + forward * TERRAIN_PROBE_DISTANCE
	var target_floor := _floor_height_at(probe_pos)
	if not _has_floor_height(target_floor):
		return

	var terrain_delta := target_floor - current_floor

	# Stair up
	if terrain_delta > STAIR_UP_THRESHOLD:
		_stair_up_handled = true
		if _can_step_up_safely() and terrain_delta <= GameConfig.MAX_HIGH_STEP_HEIGHT:
			# SPACE held or handrail assisted + step within height limit: 设定抬升目标高度，Player.y 在 _physics_process 中平滑逼近
			# 这样相机不会在每帧 0.05s 节流触发时被瞬时跳变
			_stair_up_target_y = global_position.y + terrain_delta
			_has_stair_up_target = true
		else:
			# No SPACE, or step too high: stagger + damage
			# 注意：stagger 路径不要碰 y，否则会和已经存在的抬升目标打架
			_has_stair_up_target = false
			velocity.x = 0.0
			velocity.z = 0.0
			var lift_delta := terrain_delta if terrain_delta <= GameConfig.MAX_HIGH_STEP_HEIGHT else 0.0
			_enter_unstable_stumble(forward, lift_delta)

	# Stair down
	elif terrain_delta < STAIR_DOWN_THRESHOLD:
		_has_stair_up_target = false
		if _cautious_active or is_handrail_assist_active():
			# SHIFT held or handrail assisted: let physics handle the drop naturally, no penalty
			if GameConfig.DEBUG:
				print("[DEBUG][GaitController] stair_down safe (cautious_or_handrail) delta=%.2f" % terrain_delta)
		else:
			_start_fall(forward, absf(terrain_delta))


func _detect_wall_hit(pos_before: Vector3) -> void:
	if GameState.is_gameplay_locked():
		return
	if _balance_state == BalanceState.UNSTABLE_STUMBLE:
		return
	if _wall_hit_cooldown > 0.0:
		return
	# 跌落恢复期内：刚摔过，stagger 不该再叠加；这种"水平没动"是正常的恢复表现
	if _fall_recover_timer > 0.0:
		return
	var actual_move := global_position - pos_before
	var horizontal_move := Vector2(actual_move.x, actual_move.z).length()
	var expected_move := _current_speed() * get_physics_process_delta_time()
	if expected_move > 0.01 and horizontal_move < expected_move * 0.3:
		_enter_light_stumble(-global_transform.basis.z.normalized())
		_wall_hit_cooldown = WALL_HIT_COOLDOWN


func _update_step_audio(pos_before: Vector3) -> void:
	var actual_move := global_position - pos_before
	var horizontal_move := Vector2(actual_move.x, actual_move.z).length()
	_distance_since_last_step += horizontal_move
	if _distance_since_last_step >= GameConfig.STEP_AUDIO_DISTANCE:
		_distance_since_last_step = 0.0
		_last_foot_left = not _last_foot_left
		var sound_id: StringName = _resolve_step_sound_id()
		EventBus.audio_requested.emit(sound_id, global_position, 0.0)


## 向下投射射线，获取当前踩踏表面的 ContactProfile，返回对应的脚步声 ID。
## 未找到 profile 时返回 "step" 作为默认。
func _resolve_step_sound_id() -> StringName:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.3
	var to := global_position + Vector3.DOWN * 1.5
	var result := _RaycastUtil.query_body(space_state, from, to, get_rid())
	if result.is_empty():
		return DEFAULT_STEP_SOUND_ID
	var collider: Object = result["collider"]
	var profile := _ContactProfileProvider.resolve_profile(collider, &"gait")
	return _ContactProfileProvider.step_sound_id(profile)


func _enter_light_stumble(forward: Vector3) -> void:
	if GameState.is_gameplay_locked():
		return
	if _balance_state == BalanceState.UNSTABLE_STUMBLE:
		_start_fall(forward, 0.0)
		return
	if _balance_state != BalanceState.STEADY:
		return
	_balance_state = BalanceState.LIGHT_STUMBLE
	_balance_timer = GameConfig.LIGHT_STUMBLE_RECOVER_TIME
	global_position -= forward * GameConfig.STAGGER_PUSH_BACK
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] light_stumble push_back=%.2f" % GameConfig.STAGGER_PUSH_BACK)
	EventBus.audio_requested.emit("wall_hit", global_position, 0.0)
	EventBus.player_light_stumbled.emit()


func _enter_unstable_stumble(forward: Vector3, lift_delta: float = 0.0) -> void:
	if GameState.is_gameplay_locked():
		return
	_pending_stumble_lift_delta = maxf(lift_delta, 0.0)
	if _balance_state == BalanceState.LIGHT_STUMBLE:
		_balance_state = BalanceState.UNSTABLE_STUMBLE
	elif _balance_state == BalanceState.UNSTABLE_STUMBLE:
		_start_fall(forward, 0.0, _pending_stumble_lift_delta)
		return
	elif _balance_state != BalanceState.STEADY:
		return
	else:
		_balance_state = BalanceState.UNSTABLE_STUMBLE

	_balance_timer = GameConfig.UNSTABLE_STUMBLE_QTE_WINDOW
	_recovery_qte_pressed = false
	_unstable_stumble_progress = 0.0
	global_position -= forward * GameConfig.STAGGER_PUSH_BACK
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] unstable_stumble qte=%.2f" % GameConfig.UNSTABLE_STUMBLE_QTE_WINDOW)
	EventBus.audio_requested.emit("wall_hit", global_position, 0.0)
	EventBus.player_unstable_stumbled.emit(GameConfig.UNSTABLE_STUMBLE_QTE_WINDOW)


func _do_fall(fall_distance: float) -> void:
	_start_fall(-global_transform.basis.z.normalized(), fall_distance)


func _can_step_up_safely() -> bool:
	return _high_step_active or is_handrail_assist_active()


func _start_fall(direction: Vector3, fall_distance: float, lift_delta: float = 0.0) -> void:
	if GameState.is_gameplay_locked():
		return
	_start_fall_ignoring_gameplay_lock(direction, fall_distance, lift_delta)


func _start_fall_ignoring_gameplay_lock(direction: Vector3, fall_distance: float, lift_delta: float = 0.0) -> void:
	_balance_state = BalanceState.FALLING
	_handrail_assist = null
	_balance_timer = 0.0
	_tumble_elapsed = 0.0
	_tumble_start_position = global_position
	_has_fall_lift_target = lift_delta > 0.0
	if _has_fall_lift_target:
		_fall_lift_target_y = global_position.y + lift_delta
	_pending_stumble_lift_delta = 0.0
	_fall_damage_total = 0
	_fall_damage_elapsed = 0.0
	_time_since_fall_damage = 0.0
	_recovery_qte_pressed = false
	_unstable_stumble_progress = 0.0
	_tumble_direction = direction
	_tumble_direction.y = 0.0
	if _tumble_direction.length_squared() <= 0.001:
		_tumble_direction = -global_transform.basis.z
		_tumble_direction.y = 0.0
	_tumble_direction = _tumble_direction.normalized()
	_fall_recover_timer = fall_recover_time
	# 摔倒时显式清掉 stagger：stagger 是"撞墙踉跄"，与"跌落"是两件事，不能同时出现
	_stagger_timer = 0.0
	_has_stair_up_target = false
	_was_falling = true
	_fall_start_y = global_position.y
	# 摔倒不是原地动画：本帧就沿失衡方向开始滑/滚，避免在路肩边缘原地起身。
	velocity.x = _tumble_direction.x * GameConfig.TUMBLE_SPEED
	velocity.z = _tumble_direction.z * GameConfig.TUMBLE_SPEED
	velocity.y = minf(velocity.y, -1.0)
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] fall_started distance=%.2f cap=%d" % [fall_distance, GameConfig.TUMBLE_DAMAGE_CAP])
	EventBus.player_fall_started.emit()
	EventBus.player_tumble_started.emit()
	EventBus.player_fell.emit(fall_distance)


func _update_balance_state(delta: float) -> void:
	match _balance_state:
		BalanceState.LIGHT_STUMBLE:
			_balance_timer -= delta * (0.35 if _is_moving else 1.0)
			if _balance_timer <= 0.0:
				_recover_balance()
		BalanceState.UNSTABLE_STUMBLE:
			if _recovery_qte_pressed:
				var recovery_speed := 1.0 / GameConfig.UNSTABLE_STUMBLE_QTE_HOLD_TIME
				if _is_moving:
					recovery_speed /= GameConfig.UNSTABLE_STUMBLE_MOVE_PENALTY
				_unstable_stumble_progress = maxf(_unstable_stumble_progress - delta * recovery_speed, 0.0)
				EventBus.player_recovery_qte_progress.emit(_unstable_stumble_progress, _recovery_qte_pressed)
				if _unstable_stumble_progress <= 0.0:
					_recover_balance()
					return
			else:
				var stumble_speed := 1.0 / GameConfig.UNSTABLE_STUMBLE_QTE_WINDOW
				_unstable_stumble_progress = minf(_unstable_stumble_progress + delta * stumble_speed, 1.0)
				EventBus.player_recovery_qte_progress.emit(_unstable_stumble_progress, _recovery_qte_pressed)
			_balance_timer = (1.0 - _unstable_stumble_progress) * GameConfig.UNSTABLE_STUMBLE_QTE_WINDOW
			if _unstable_stumble_progress >= 1.0:
				_start_fall_ignoring_gameplay_lock(-global_transform.basis.z.normalized(), 0.0, _pending_stumble_lift_delta)
		BalanceState.FALLING:
			_tumble_elapsed += delta
			_fall_damage_elapsed += delta
			_time_since_fall_damage += delta
			if _fall_damage_elapsed >= GameConfig.TUMBLE_DAMAGE_INTERVAL:
				_fall_damage_elapsed = 0.0
				_apply_fall_damage(GameConfig.TUMBLE_TICK_DAMAGE)
			if _tumble_elapsed >= GameConfig.TUMBLE_MAX_TIME or _is_on_stable_surface():
				if _fall_damage_total <= 0 \
						or _time_since_fall_damage >= GameConfig.TUMBLE_FINAL_DAMAGE_MIN_INTERVAL:
					_apply_fall_damage(GameConfig.TUMBLE_TICK_DAMAGE)
				_start_get_up()
		BalanceState.GETTING_UP:
			_balance_timer -= delta
			if _balance_timer <= 0.0:
				_recover_balance()


func _start_get_up() -> void:
	_balance_state = BalanceState.GETTING_UP
	_balance_timer = GameConfig.FALL_GET_UP_TIME
	_tumble_direction = Vector3.ZERO
	_has_fall_lift_target = false
	velocity = Vector3.ZERO
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] get_up_started duration=%.2f damage_total=%d" % [
			GameConfig.FALL_GET_UP_TIME,
			_fall_damage_total,
		])
	EventBus.player_get_up_started.emit(GameConfig.FALL_GET_UP_TIME)


func _recover_balance() -> void:
	_balance_state = BalanceState.STEADY
	_balance_timer = 0.0
	_recovery_qte_pressed = false
	_unstable_stumble_progress = 0.0
	_pending_stumble_lift_delta = 0.0
	_fall_recover_timer = 0.0
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] balance_recovered")
	EventBus.player_balance_recovered.emit()


func _apply_fall_damage(amount: int) -> void:
	if not _attributes:
		return
	var remaining := GameConfig.TUMBLE_DAMAGE_CAP - _fall_damage_total
	if remaining <= 0:
		return
	var applied := mini(amount, remaining)
	_fall_damage_total += applied
	_time_since_fall_damage = 0.0
	_attributes.take_damage_ignoring_gameplay_lock(applied)
	EventBus.audio_requested.emit("fall", global_position, 0.0)


func _is_on_stable_surface() -> bool:
	if not is_on_floor() or _tumble_elapsed < 0.45:
		return false
	var horizontal_travel := Vector2(
		global_position.x - _tumble_start_position.x,
		global_position.z - _tumble_start_position.z
	).length()
	if horizontal_travel < GameConfig.TUMBLE_MIN_TRAVEL_DISTANCE:
		return false
	var current_floor := _floor_height_at(global_position)
	if not _has_floor_height(current_floor):
		return false
	var forward_floor := _floor_height_at(global_position + _tumble_direction * TERRAIN_PROBE_DISTANCE)
	if not _has_floor_height(forward_floor):
		return false
	var forward_delta := forward_floor - current_floor
	if forward_delta < -GameConfig.TUMBLE_STABLE_FORWARD_DELTA:
		return false
	var normal := get_floor_normal()
	return normal.dot(Vector3.UP) >= 1.0 - GameConfig.TUMBLE_STABLE_SLOPE_DELTA


func _floor_height_at(sample_position: Vector3) -> float:
	var from := sample_position + Vector3.UP * 0.8
	var to := sample_position + Vector3.DOWN * 1.4
	var space_state := get_world_3d().direct_space_state
	var result := _RaycastUtil.query_body(space_state, from, to, get_rid())
	if result.is_empty():
		return FLOOR_HEIGHT_MISSING
	var hit_position: Vector3 = result["position"]
	return hit_position.y


func _has_floor_height(height: float) -> bool:
	return height != FLOOR_HEIGHT_MISSING
