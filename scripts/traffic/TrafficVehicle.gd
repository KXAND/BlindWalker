class_name TrafficVehicle
extends PathFollow3D
## 沿固定车道推进的交通车辆。运动状态和信号许可分离，车辆不会因等待超时主动撞向玩家。

signal horn_requested

enum MotionState { STOPPED, STARTING, RUNNING, BRAKING }

@export var crossing_path: NodePath
@export var traffic_system_path: NodePath
@export var forward_detection_path: NodePath = ^"ForwardDetection"
@export var impact_area_path: NodePath = ^"ImpactArea"
@export var physical_body_path: NodePath = ^"PhysicalBody"
@export var base_speed: float = 8.0
@export var clearance_speed: float = 6.0
@export var acceleration: float = 3.5
@export var signal_deceleration: float = 3.0
@export var emergency_deceleration: float = 5.0
@export var stop_progress: float = 10.0
@export var clearance_end_progress: float = 16.0
@export var clear_before_start_duration: float = 0.5
@export var horn_repeat_interval: float = 2.5
@export var audio_enabled: bool = true
@export var engine_base_volume_db: float = -10.0
@export var horn_base_volume_db: float = -2.0
@export var vehicle_audio_max_distance: float = 30.0

var crossing: TrafficCrossing
var traffic_system: TrafficSystem
var current_speed: float = 0.0

var _motion_state: int = MotionState.STOPPED
var _forward_players: Dictionary = {}
var _clear_before_start_elapsed: float = 0.0
var _waiting_for_player: bool = false
var _horn_elapsed: float = 0.0
var _committed_to_crossing: bool = false
var _signal_stop_active: bool = false
var _stopping_for_signal: bool = false
var _forward_detection: Area3D
var _impact_area: Area3D
var _physical_body: AnimatableBody3D
var _engine_player: AudioStreamPlayer3D
var _horn_player: AudioStreamPlayer3D
var _impact_players: Dictionary = {}
var _impact_blocked_elapsed: Dictionary = {}
var _impact_bodies: Dictionary = {}
var _emergency_stop_after_impact: bool = false

const AUDIO_MIX_RATE := 22050
const ENGINE_LOOP_SECONDS := 1.0
const HORN_SECONDS := 0.45
const IMPACT_REARM_SEPARATION := 0.3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	loop = true
	rotation_mode = PathFollow3D.ROTATION_ORIENTED
	_resolve_dependencies()
	_connect_detection_areas()
	_sync_physical_body()
	if audio_enabled:
		_create_audio_players()
		AudioManager.audio_settings_changed.connect(update_audio_feedback)


func _exit_tree() -> void:
	if AudioManager.audio_settings_changed.is_connected(update_audio_feedback):
		AudioManager.audio_settings_changed.disconnect(update_audio_feedback)


func _physics_process(delta: float) -> void:
	advance_vehicle(delta)
	_sync_physical_body()
	update_audio_feedback()


func advance_vehicle(delta: float) -> void:
	if delta <= 0.0:
		return
	_prune_forward_players()
	_prune_impact_players()
	_advance_impact_rearm(delta)
	var player_ahead := not _forward_players.is_empty() or not _impact_players.is_empty()
	if _emergency_stop_after_impact and current_speed > 0.001:
		_brake_without_horn(delta)
		return
	_emergency_stop_after_impact = false
	var signal_requires_stop := is_instance_valid(crossing) and crossing.should_vehicles_stop()

	if signal_requires_stop:
		if not _signal_stop_active:
			_signal_stop_active = true
			_choose_signal_stop_response()
		_advance_during_signal_stop(delta, player_ahead)
		return
	_signal_stop_active = false
	_stopping_for_signal = false
	_committed_to_crossing = false

	if player_ahead and current_speed > 0.001:
		_brake_for_player(delta)
		return

	if current_speed <= 0.001:
		current_speed = 0.0
		_motion_state = MotionState.STOPPED
		if player_ahead:
			_wait_for_player(delta)
			return
		_waiting_for_player = false
		_horn_elapsed = 0.0
		_clear_before_start_elapsed += delta
		if _clear_before_start_elapsed < clear_before_start_duration:
			return
		_motion_state = MotionState.STARTING
	else:
		_clear_before_start_elapsed = clear_before_start_duration

	current_speed = move_toward(current_speed, base_speed, acceleration * delta)
	progress += current_speed * delta
	if is_equal_approx(current_speed, base_speed):
		_motion_state = MotionState.RUNNING


func register_forward_player(player: Node) -> void:
	if is_instance_valid(player) and player.is_in_group("player"):
		_forward_players[player.get_instance_id()] = player


func unregister_forward_player(player: Node) -> void:
	if is_instance_valid(player):
		_forward_players.erase(player.get_instance_id())


func register_impact_player(player: Node3D) -> void:
	if not is_instance_valid(player) or not player.is_in_group("player"):
		return
	var instance_id := player.get_instance_id()
	if _impact_players.has(instance_id):
		return
	_impact_players[instance_id] = player
	_impact_bodies[instance_id] = player
	if _impact_blocked_elapsed.has(instance_id) or not is_instance_valid(traffic_system):
		return

	var vehicle_velocity := -global_transform.basis.z.normalized() * current_speed
	var player_velocity := Vector3.ZERO
	if player is CharacterBody3D:
		player_velocity = (player as CharacterBody3D).velocity
	var relative_velocity := vehicle_velocity - player_velocity
	relative_velocity.y = 0.0
	var impact_speed := relative_velocity.length()
	if impact_speed <= 0.001:
		return
	if traffic_system.report_vehicle_impact(
			player,
			player.global_position,
			impact_speed,
			relative_velocity.normalized()
	):
		_impact_blocked_elapsed[instance_id] = 0.0
		_emergency_stop_after_impact = true


func unregister_impact_player(player: Node3D) -> void:
	if not is_instance_valid(player):
		return
	var instance_id := player.get_instance_id()
	_impact_players.erase(instance_id)
	if _impact_blocked_elapsed.has(instance_id):
		# 重新进入会中断连续分离，因此每次离开都从零开始计时。
		_impact_blocked_elapsed[instance_id] = 0.0
	else:
		_impact_bodies.erase(instance_id)


func get_motion_state() -> int:
	return _motion_state


func get_current_speed() -> float:
	return current_speed


func is_engine_audio_playing() -> bool:
	return is_instance_valid(_engine_player) and _engine_player.playing


func is_horn_audio_playing() -> bool:
	return is_instance_valid(_horn_player) and _horn_player.playing


func get_engine_pitch_scale() -> float:
	if is_instance_valid(_engine_player):
		return _engine_player.pitch_scale
	return 0.0


func update_audio_feedback() -> void:
	if not is_instance_valid(_engine_player):
		return
	var speed_ratio := clampf(current_speed / maxf(base_speed, 0.01), 0.0, 1.0)
	_engine_player.pitch_scale = lerpf(0.75, 1.15, speed_ratio)
	_engine_player.volume_db = AudioManager.sfx_volume_db(engine_base_volume_db + lerpf(-8.0, 0.0, speed_ratio))
	if is_instance_valid(_horn_player):
		_horn_player.volume_db = AudioManager.sfx_volume_db(horn_base_volume_db)


func is_waiting_at_stop_line() -> bool:
	return _motion_state == MotionState.STOPPED and is_instance_valid(crossing) and crossing.should_vehicles_stop()


func is_committed_to_crossing() -> bool:
	return _committed_to_crossing


func _advance_during_signal_stop(delta: float, player_ahead: bool) -> void:
	if _committed_to_crossing:
		_advance_committed_vehicle(delta, player_ahead)
		return
	if _stopping_for_signal:
		if player_ahead:
			_brake_without_horn(delta)
		else:
			_approach_stop_line(delta)
		return
	if progress >= clearance_end_progress:
		var previous_progress := progress
		_advance_toward_speed(base_speed, delta)
		if progress < previous_progress:
			_choose_signal_stop_response()
		return
	_choose_signal_stop_response()
	_advance_during_signal_stop(delta, player_ahead)


func _choose_signal_stop_response() -> void:
	_stopping_for_signal = false
	_committed_to_crossing = false
	if progress > stop_progress and progress < clearance_end_progress:
		_committed_to_crossing = true
		return
	if progress >= clearance_end_progress:
		return

	var distance_to_stop := maxf(stop_progress - progress, 0.0)
	var braking_distance := current_speed * current_speed / (2.0 * maxf(signal_deceleration, 0.01))
	if current_speed > 0.001 and braking_distance > distance_to_stop + 0.001:
		_committed_to_crossing = true
		return
	_stopping_for_signal = true


func _approach_stop_line(delta: float) -> void:
	var distance_to_stop := maxf(stop_progress - progress, 0.0)
	_waiting_for_player = false
	_clear_before_start_elapsed = 0.0
	var safe_speed := sqrt(maxf(2.0 * signal_deceleration * distance_to_stop, 0.0))
	var target_speed := minf(base_speed, safe_speed)
	var rate := acceleration if target_speed > current_speed else signal_deceleration
	var previous_speed := current_speed
	current_speed = move_toward(current_speed, target_speed, rate * delta)
	var travel := (previous_speed + current_speed) * 0.5 * delta
	progress = minf(progress + travel, stop_progress)
	if distance_to_stop <= 0.001 or progress >= stop_progress - 0.001:
		progress = stop_progress
		current_speed = 0.0
		_motion_state = MotionState.STOPPED
	elif current_speed < previous_speed:
		_motion_state = MotionState.BRAKING
	else:
		_motion_state = MotionState.STARTING


func _brake_without_horn(delta: float) -> void:
	_waiting_for_player = false
	_clear_before_start_elapsed = 0.0
	var previous_speed := current_speed
	current_speed = move_toward(current_speed, 0.0, emergency_deceleration * delta)
	progress = minf(progress + (previous_speed + current_speed) * 0.5 * delta, stop_progress)
	if current_speed <= 0.001:
		current_speed = 0.0
		_motion_state = MotionState.STOPPED
	else:
		_motion_state = MotionState.BRAKING


func _advance_committed_vehicle(delta: float, player_ahead: bool) -> void:
	if player_ahead:
		if current_speed > 0.001:
			_brake_for_player(delta)
		else:
			_wait_for_player(delta)
		return
	if current_speed <= 0.001 and _waiting_for_player:
		_clear_before_start_elapsed += delta
		if _clear_before_start_elapsed < clear_before_start_duration:
			return
	_waiting_for_player = false
	_horn_elapsed = 0.0
	_advance_toward_speed(clearance_speed, delta)
	if progress >= clearance_end_progress:
		_committed_to_crossing = false


func _advance_toward_speed(target_speed: float, delta: float) -> void:
	var rate := acceleration if target_speed > current_speed else signal_deceleration
	current_speed = move_toward(current_speed, target_speed, rate * delta)
	progress += current_speed * delta
	if current_speed <= 0.001:
		current_speed = 0.0
		_motion_state = MotionState.STOPPED
	elif current_speed < target_speed:
		_motion_state = MotionState.STARTING
	elif current_speed > target_speed:
		_motion_state = MotionState.BRAKING
	else:
		_motion_state = MotionState.RUNNING


func _brake_for_player(delta: float) -> void:
	_clear_before_start_elapsed = 0.0
	if not _waiting_for_player:
		_waiting_for_player = true
		_horn_elapsed = 0.0
		_request_horn()
	else:
		_horn_elapsed += delta
		if _horn_elapsed >= horn_repeat_interval:
			_horn_elapsed = 0.0
			_request_horn()
	current_speed = move_toward(current_speed, 0.0, emergency_deceleration * delta)
	if current_speed <= 0.001:
		current_speed = 0.0
		_motion_state = MotionState.STOPPED
		return
	_motion_state = MotionState.BRAKING
	progress += current_speed * delta


func _wait_for_player(delta: float) -> void:
	_clear_before_start_elapsed = 0.0
	if not _waiting_for_player:
		_waiting_for_player = true
		_horn_elapsed = 0.0
		_request_horn()
		return
	_horn_elapsed += delta
	if _horn_elapsed >= horn_repeat_interval:
		_horn_elapsed = 0.0
		_request_horn()


func _request_horn() -> void:
	horn_requested.emit()
	if is_instance_valid(_horn_player):
		_horn_player.play()


func _prune_forward_players() -> void:
	for instance_id in _forward_players.keys():
		if not is_instance_valid(_forward_players[instance_id]):
			_forward_players.erase(instance_id)


func _prune_impact_players() -> void:
	for instance_id in _impact_players.keys():
		if is_instance_valid(_impact_players[instance_id]):
			continue
		_impact_players.erase(instance_id)
		if not _impact_blocked_elapsed.has(instance_id):
			_impact_bodies.erase(instance_id)


func _resolve_dependencies() -> void:
	if not crossing and not crossing_path.is_empty():
		crossing = get_node_or_null(crossing_path) as TrafficCrossing
	if not traffic_system and not traffic_system_path.is_empty():
		traffic_system = get_node_or_null(traffic_system_path) as TrafficSystem
	if not forward_detection_path.is_empty():
		_forward_detection = get_node_or_null(forward_detection_path) as Area3D
	if not impact_area_path.is_empty():
		_impact_area = get_node_or_null(impact_area_path) as Area3D
	if not physical_body_path.is_empty():
		_physical_body = get_node_or_null(physical_body_path) as AnimatableBody3D


func _connect_detection_areas() -> void:
	if _forward_detection:
		_forward_detection.body_entered.connect(register_forward_player)
		_forward_detection.body_exited.connect(unregister_forward_player)
	if _impact_area:
		_impact_area.body_entered.connect(register_impact_player)
		_impact_area.body_exited.connect(unregister_impact_player)


func _sync_physical_body() -> void:
	if is_instance_valid(_physical_body):
		# PhysicsBody 作为移动父节点的普通子节点时，PhysicsServer 不会可靠跟随父变换。
		_physical_body.global_transform = global_transform


func _create_audio_players() -> void:
	_engine_player = AudioStreamPlayer3D.new()
	_engine_player.name = "EngineAudio"
	_engine_player.max_distance = vehicle_audio_max_distance
	_engine_player.unit_size = 3.0
	_engine_player.stream = _create_engine_stream()
	add_child(_engine_player)
	_engine_player.play()

	_horn_player = AudioStreamPlayer3D.new()
	_horn_player.name = "HornAudio"
	_horn_player.max_distance = vehicle_audio_max_distance
	_horn_player.unit_size = 3.0
	_horn_player.stream = _create_horn_stream()
	add_child(_horn_player)
	update_audio_feedback()


func _create_engine_stream() -> AudioStreamWAV:
	var sample_count := int(AUDIO_MIX_RATE * ENGINE_LOOP_SECONDS)
	var stream := _create_wave_stream(sample_count, true)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index in sample_count:
		var time := float(sample_index) / float(AUDIO_MIX_RATE)
		var sample := sin(TAU * 70.0 * time) * 0.65 + sin(TAU * 105.0 * time) * 0.35
		data.encode_s16(sample_index * 2, int(clampf(sample * 0.16, -1.0, 1.0) * 32767.0))
	stream.data = data
	return stream


func _create_horn_stream() -> AudioStreamWAV:
	var sample_count := int(AUDIO_MIX_RATE * HORN_SECONDS)
	var stream := _create_wave_stream(sample_count, false)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index in sample_count:
		var time := float(sample_index) / float(AUDIO_MIX_RATE)
		var remaining := HORN_SECONDS - time
		var envelope := minf(minf(time / 0.03, remaining / 0.08), 1.0)
		var sample := sin(TAU * 320.0 * time) * 0.7 + sin(TAU * 480.0 * time) * 0.3
		data.encode_s16(sample_index * 2, int(clampf(sample * envelope * 0.35, -1.0, 1.0) * 32767.0))
	stream.data = data
	return stream


func _create_wave_stream(sample_count: int, should_loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AUDIO_MIX_RATE
	stream.stereo = false
	if should_loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream


func _advance_impact_rearm(delta: float) -> void:
	for instance_id in _impact_blocked_elapsed.keys():
		if _impact_players.has(instance_id):
			continue
		var body: Node = _impact_bodies.get(instance_id)
		if not is_instance_valid(body):
			_impact_blocked_elapsed.erase(instance_id)
			_impact_bodies.erase(instance_id)
			continue
		var separated_time: float = _impact_blocked_elapsed[instance_id] + delta
		if separated_time >= IMPACT_REARM_SEPARATION:
			_impact_blocked_elapsed.erase(instance_id)
			_impact_bodies.erase(instance_id)
		else:
			_impact_blocked_elapsed[instance_id] = separated_time
