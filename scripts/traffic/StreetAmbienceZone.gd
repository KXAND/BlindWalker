class_name StreetAmbienceZone
extends Node3D
## 以一个可旋转矩形区域表达街区底噪覆盖范围，并计算边界外衰减。

@export var half_extents: Vector3 = Vector3(6.0, 2.0, 30.0)
@export var fade_distance: float = 16.0
@export var audio_enabled: bool = true
@export var listener: Node3D
@export_file("*.ogg") var ambience_path: String = "res://assets/audio/sfx/street_ambience.ogg"
@export var base_volume_db: float = -3.0

const MUTE_DB := -80.0

var _ambience_player: AudioStreamPlayer
var _current_volume_linear: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not listener:
		listener = get_tree().get_first_node_in_group("player") as Node3D
	if audio_enabled:
		_create_ambience_player()
		AudioManager.audio_settings_changed.connect(update_ambience_volume)
	update_ambience_volume()


func _exit_tree() -> void:
	if AudioManager.audio_settings_changed.is_connected(update_ambience_volume):
		AudioManager.audio_settings_changed.disconnect(update_ambience_volume)


func _process(_delta: float) -> void:
	if not is_instance_valid(listener):
		listener = get_tree().get_first_node_in_group("player") as Node3D
	update_ambience_volume()


func volume_linear_for_position(world_position: Vector3) -> float:
	var local_position := to_local(world_position)
	var outside_x := maxf(absf(local_position.x) - half_extents.x, 0.0)
	var outside_z := maxf(absf(local_position.z) - half_extents.z, 0.0)
	var distance_from_zone := Vector2(outside_x, outside_z).length()
	if distance_from_zone <= 0.0:
		return 1.0
	if fade_distance <= 0.0:
		return 0.0
	var fade_ratio := clampf(distance_from_zone / fade_distance, 0.0, 1.0)
	return 1.0 - smoothstep(0.0, 1.0, fade_ratio)


func update_ambience_volume() -> void:
	_current_volume_linear = volume_linear_for_position(listener.global_position) if is_instance_valid(listener) else 0.0
	if not is_instance_valid(_ambience_player):
		return
	var distance_volume_db := linear_to_db(_current_volume_linear) if _current_volume_linear > 0.0 else MUTE_DB
	_ambience_player.volume_db = AudioManager.sfx_volume_db(base_volume_db + distance_volume_db)


func get_current_volume_linear() -> float:
	return _current_volume_linear


func is_ambience_playing() -> bool:
	return is_instance_valid(_ambience_player) and _ambience_player.playing


func _create_ambience_player() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "StreetAmbiencePlayer"
	add_child(_ambience_player)
	var imported_stream := ResourceLoader.load(ambience_path) as AudioStreamOggVorbis
	if not imported_stream:
		push_warning("StreetAmbienceZone: failed to load ambience path=%s" % ambience_path)
		return
	var loop_stream := imported_stream.duplicate(true) as AudioStreamOggVorbis
	loop_stream.loop = true
	loop_stream.loop_offset = 0.0
	_ambience_player.stream = loop_stream
	_ambience_player.play()
