class_name GaitController
extends CharacterBody3D
## 连续移动控制器。按住 W 前进，SHIFT 谨慎减速，SPACE 高抬腿模式。
## 不读取键鼠输入——所有输入意图由 InputManager 转发。

@export var gravity: float = 9.8
@export var stagger_duration: float = 0.3
@export var fall_recover_time: float = 1.5
@export var terrain_check_interval: float = 0.05

const TERRAIN_PROBE_DISTANCE := 0.3
const STAIR_UP_THRESHOLD := 0.06
const STAIR_DOWN_THRESHOLD := -0.15
const WALL_NORMAL_THRESHOLD := 0.45
const WALL_HIT_COOLDOWN := 0.3
const FALL_Y_THRESHOLD := -10.0

var _is_moving: bool = false
var _cautious_active: bool = false
var _high_step_active: bool = false

var _stagger_timer: float = 0.0
var _fall_recover_timer: float = 0.0
var _terrain_check_timer: float = 0.0
var _wall_hit_cooldown: float = 0.0
var _fall_start_y: float = 0.0
var _was_falling: bool = false

var _distance_since_last_step: float = 0.0
var _last_foot_left: bool = false

@onready var _attributes: PlayerAttributes = get_node_or_null("PlayerAttributes") as PlayerAttributes


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		if not _was_falling:
			_fall_start_y = global_position.y
			_was_falling = true
		velocity.y -= gravity * delta
		# Fell off the world
		if global_position.y < FALL_Y_THRESHOLD:
			_do_fall(absf(_fall_start_y - global_position.y))
			_was_falling = false
	else:
		if _was_falling:
			var fall_dist := absf(_fall_start_y - global_position.y)
			if fall_dist > 0.5:
				_do_fall(fall_dist)
			_was_falling = false
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

	# Wall hit detection
	if _is_moving and can_move:
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


# ---- Internal logic ----

func _current_speed() -> float:
	if _high_step_active:
		return GameConfig.HIGH_STEP_SPEED
	if _cautious_active:
		return GameConfig.CAUTIOUS_SPEED
	return GameConfig.WALK_SPEED


func _check_terrain(forward: Vector3) -> void:
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
		if not _high_step_active or terrain_delta > GameConfig.MAX_HIGH_STEP_HEIGHT:
			# Blocked: can't step up without SPACE or step too high
			velocity.x = 0.0
			velocity.z = 0.0
			_do_stagger(forward)
		else:
			# Smooth lift onto step
			global_position.y = target_floor

	# Stair down
	elif terrain_delta < STAIR_DOWN_THRESHOLD:
		if not _cautious_active:
			_do_fall(absf(terrain_delta))


func _detect_wall_hit(pos_before: Vector3) -> void:
	if _wall_hit_cooldown > 0.0 or _stagger_timer > 0.0:
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
	_stagger_timer = stagger_duration
	global_position -= forward * GameConfig.STAGGER_PUSH_BACK
	if GameConfig.DEBUG:
		print("[DEBUG][GaitController] stagger push_back=%.2f" % GameConfig.STAGGER_PUSH_BACK)
	EventBus.audio_requested.emit("wall_hit", global_position, 0.0)


func _do_fall(fall_distance: float) -> void:
	_fall_recover_timer = fall_recover_time
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
	var result := RaycastUtil.query_body(space_state, from, to, get_rid())
	if result.is_empty():
		return NAN
	var hit_position: Vector3 = result["position"]
	return hit_position.y
