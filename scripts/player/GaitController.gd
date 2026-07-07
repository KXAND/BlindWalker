class_name GaitController
extends CharacterBody3D

enum GaitState { BOTH_EVEN, LEFT_AHEAD, RIGHT_AHEAD }

## 离散步态控制器。它不读取键鼠，只接受 InputManager 翻译后的步态意图。
@export var flat_step_length: float = GameConfig.STEP_LENGTH_FLAT
@export var stair_step_length: float = GameConfig.STEP_LENGTH_STAIR
@export var step_height: float = GameConfig.MAX_HIGH_STEP_HEIGHT
@export var stagger_duration: float = 0.3
@export var gravity: float = 9.8

var locked_key: StringName = &""
var input_enabled: bool = true

@onready var _attributes: PlayerAttributes = get_node_or_null("PlayerAttributes") as PlayerAttributes

var _state: GaitState = GaitState.BOTH_EVEN
var _high_step_charge: float = 0.0
var _cautious_active: bool = false
var _stagger_time: float = 0.0


func _ready() -> void:
	# GaitController 只管理步态、地形和摔倒规则；输入由 InputManager 统一翻译成请求。
	add_to_group("player")


func request_step(foot: StringName) -> void:
	if not input_enabled:
		return
	_handle_step(foot)


func set_cautious_active(active: bool) -> void:
	_cautious_active = active


func update_high_step(active: bool, delta: float) -> void:
	if active:
		_high_step_charge = minf(_high_step_charge + GameConfig.HIGH_STEP_CHARGE_RATE * delta, step_height)
	else:
		_high_step_charge = 0.0


func _physics_process(delta: float) -> void:
	if _stagger_time > 0.0:
		_stagger_time -= delta

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	move_and_slide()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func _handle_step(foot: StringName) -> void:
	if _stagger_time > 0.0:
		return
	if locked_key == foot:
		return

	var old_state := _state
	var should_move := false

	if foot == &"left":
		if _state == GaitState.LEFT_AHEAD:
			_state = GaitState.BOTH_EVEN
			locked_key = &"left"
		else:
			_state = GaitState.LEFT_AHEAD if _state == GaitState.BOTH_EVEN else GaitState.BOTH_EVEN
			locked_key = &""
			should_move = true
	elif foot == &"right":
		if _state == GaitState.RIGHT_AHEAD:
			_state = GaitState.BOTH_EVEN
			locked_key = &"right"
		else:
			_state = GaitState.RIGHT_AHEAD if _state == GaitState.BOTH_EVEN else GaitState.BOTH_EVEN
			locked_key = &""
			should_move = true

	if old_state != _state:
		EventBus.gait_state_changed.emit(_state_name(old_state), _state_name(_state))

	if should_move:
		_apply_step()


func _apply_step() -> void:
	var forward := -global_transform.basis.z.normalized()
	var terrain_delta := _probe_terrain_delta(forward)
	var is_stair := absf(terrain_delta) > 0.06
	var step_length := stair_step_length if is_stair else flat_step_length

	if _hits_wall(forward, step_length):
		_do_stagger(forward)
		return

	if terrain_delta > 0.06 and _high_step_charge < minf(terrain_delta, step_height):
		_do_fall(absf(terrain_delta))
		return

	if terrain_delta < -0.15 and not _cautious_active:
		_do_fall(absf(terrain_delta))
		return

	global_position += forward * step_length
	if is_stair:
		global_position.y += terrain_delta
	EventBus.audio_requested.emit("step", global_position, 0.0)


func _hits_wall(direction: Vector3, distance: float) -> bool:
	var from := global_position + Vector3.UP * 0.7
	var to := from + direction * distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var normal: Vector3 = result["normal"]
	return normal.y < 0.45


func _probe_terrain_delta(direction: Vector3) -> float:
	var current_floor := _floor_height_at(global_position)
	var target_floor := _floor_height_at(global_position + direction * stair_step_length)
	if is_nan(current_floor) or is_nan(target_floor):
		return 0.0
	return target_floor - current_floor


func _floor_height_at(sample_position: Vector3) -> float:
	var from := sample_position + Vector3.UP * 0.8
	var to := sample_position + Vector3.DOWN * 1.4
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return NAN
	var hit_position: Vector3 = result["position"]
	return hit_position.y


func _do_stagger(forward: Vector3) -> void:
	_stagger_time = stagger_duration
	global_position -= forward * GameConfig.STAGGER_PUSH_BACK
	print("GaitController: stagger push_back=%.2f duration=%.2f" % [GameConfig.STAGGER_PUSH_BACK, stagger_duration])
	EventBus.audio_requested.emit("wall_hit", global_position, 0.0)


func _do_fall(fall_distance: float) -> void:
	print("GaitController: fall distance=%.2f damage=%d" % [fall_distance, GameConfig.FALL_DAMAGE])
	EventBus.audio_requested.emit("fall", global_position, 0.0)
	EventBus.player_fell.emit(fall_distance)
	if _attributes:
		_attributes.take_damage(GameConfig.FALL_DAMAGE)


func _state_name(state: GaitState) -> StringName:
	match state:
		GaitState.BOTH_EVEN:
			return &"BothEven"
		GaitState.LEFT_AHEAD:
			return &"LeftAhead"
		GaitState.RIGHT_AHEAD:
			return &"RightAhead"
	return &"Unknown"
