class_name TrafficCrossing
extends Node3D
## 独立运行的交通过街点。快速提示音只会在车辆清空区确认无车后开始。

signal phase_changed(phase: int)

enum TrafficPhase { VEHICLE_FLOW, VEHICLE_CLEARING, PEDESTRIAN_GREEN }

@export var red_duration: float = 16.0
@export var green_duration: float = 16.0
@export_enum("Vehicle Flow", "Vehicle Clearing", "Pedestrian Green") var start_phase: int = TrafficPhase.VEHICLE_FLOW
@export var clearance_area_path: NodePath
@export var audio_enabled: bool = true
@export var beep_base_volume_db: float = -4.0
@export var beep_max_distance: float = 24.0

var _traffic_phase: int = TrafficPhase.VEHICLE_FLOW
var _phase_elapsed: float = 0.0
var _clearance_vehicles: Dictionary = {}
var _clearance_area: Area3D
var _beep_player: AudioStreamPlayer3D

const RED_BEEP_SOUND_ID := &"traffic_red"
const GREEN_BEEP_SOUND_ID := &"traffic_green"
const RED_BEEP_PATH := "res://assets/audio/sfx/traffic_red.wav"
const GREEN_BEEP_PATH := "res://assets/audio/sfx/traffic_green.wav"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_traffic_phase = start_phase
	_connect_clearance_area()
	if audio_enabled:
		_create_beep_player()
		_sync_beep_audio()
		AudioManager.audio_settings_changed.connect(_sync_beep_volume)


func _exit_tree() -> void:
	if AudioManager.audio_settings_changed.is_connected(_sync_beep_volume):
		AudioManager.audio_settings_changed.disconnect(_sync_beep_volume)


func _process(delta: float) -> void:
	advance_cycle(delta)


func advance_cycle(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	while remaining > 0.0:
		match _traffic_phase:
			TrafficPhase.VEHICLE_FLOW:
				var flow_remaining := maxf(red_duration, 0.01) - _phase_elapsed
				if remaining < flow_remaining:
					_phase_elapsed += remaining
					return
				remaining -= flow_remaining
				_phase_elapsed = 0.0
				_set_traffic_phase(TrafficPhase.VEHICLE_CLEARING)
				_try_finish_vehicle_clearance()
				if _traffic_phase == TrafficPhase.VEHICLE_CLEARING:
					return
			TrafficPhase.VEHICLE_CLEARING:
				_try_finish_vehicle_clearance()
				return
			TrafficPhase.PEDESTRIAN_GREEN:
				var green_remaining := maxf(green_duration, 0.01) - _phase_elapsed
				if remaining < green_remaining:
					_phase_elapsed += remaining
					return
				remaining -= green_remaining
				_phase_elapsed = 0.0
				_set_traffic_phase(TrafficPhase.VEHICLE_FLOW)


func register_clearance_vehicle(vehicle: Node) -> void:
	if is_instance_valid(vehicle):
		_clearance_vehicles[vehicle.get_instance_id()] = vehicle


func unregister_clearance_vehicle(vehicle: Node) -> void:
	if not is_instance_valid(vehicle):
		return
	_clearance_vehicles.erase(vehicle.get_instance_id())
	_try_finish_vehicle_clearance()


func get_traffic_phase() -> int:
	return _traffic_phase


func is_pedestrian_green() -> bool:
	return _traffic_phase == TrafficPhase.PEDESTRIAN_GREEN


func is_vehicle_clearing() -> bool:
	return _traffic_phase == TrafficPhase.VEHICLE_CLEARING


func should_vehicles_stop() -> bool:
	return _traffic_phase != TrafficPhase.VEHICLE_FLOW


func can_vehicles_enter_crosswalk() -> bool:
	return _traffic_phase == TrafficPhase.VEHICLE_FLOW


func get_active_beep_sound_id() -> StringName:
	return GREEN_BEEP_SOUND_ID if is_pedestrian_green() else RED_BEEP_SOUND_ID


func is_beep_playing() -> bool:
	return is_instance_valid(_beep_player) and _beep_player.playing


func _try_finish_vehicle_clearance() -> void:
	_prune_clearance_vehicles()
	if _traffic_phase == TrafficPhase.VEHICLE_CLEARING and _clearance_vehicles.is_empty():
		_phase_elapsed = 0.0
		_set_traffic_phase(TrafficPhase.PEDESTRIAN_GREEN)


func _prune_clearance_vehicles() -> void:
	for instance_id in _clearance_vehicles.keys():
		if not is_instance_valid(_clearance_vehicles[instance_id]):
			_clearance_vehicles.erase(instance_id)


func _set_traffic_phase(phase: int) -> void:
	if phase == _traffic_phase:
		return
	_traffic_phase = phase
	_sync_beep_audio()
	phase_changed.emit(_traffic_phase)


func _connect_clearance_area() -> void:
	if clearance_area_path.is_empty():
		return
	_clearance_area = get_node_or_null(clearance_area_path) as Area3D
	if not _clearance_area:
		push_warning("TrafficCrossing: clearance area not found path=%s" % clearance_area_path)
		return
	_clearance_area.body_entered.connect(register_clearance_vehicle)
	_clearance_area.body_exited.connect(unregister_clearance_vehicle)


func _create_beep_player() -> void:
	_beep_player = AudioStreamPlayer3D.new()
	_beep_player.name = "PedestrianBeepPlayer"
	_beep_player.max_distance = beep_max_distance
	_beep_player.unit_size = 3.0
	add_child(_beep_player)
	_sync_beep_volume()


func _sync_beep_audio() -> void:
	if not is_instance_valid(_beep_player):
		return
	var path := GREEN_BEEP_PATH if is_pedestrian_green() else RED_BEEP_PATH
	var imported_stream := ResourceLoader.load(path) as AudioStreamWAV
	if not imported_stream:
		push_warning("TrafficCrossing: failed to load pedestrian beep path=%s" % path)
		return
	var loop_stream := imported_stream.duplicate(true) as AudioStreamWAV
	loop_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop_stream.loop_begin = 0
	loop_stream.loop_end = maxi(int(loop_stream.get_length() * loop_stream.mix_rate), 1)
	_beep_player.stream = loop_stream
	_beep_player.play()


func _sync_beep_volume() -> void:
	if is_instance_valid(_beep_player):
		_beep_player.volume_db = AudioManager.sfx_volume_db(beep_base_volume_db)
