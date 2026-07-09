extends Node
## 全局音频入口：监听玩法事件并播放 2D/3D 音效。
## 3D 播放器必须挂到 GameRoot，否则 SubViewport 内的 AudioListener3D 听不到。

@export var master_volume_db: float = 0.0

const POOL_SIZE: int = 4

var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_player_index: int = 0
var _player_2d: AudioStreamPlayer
var _silent_stream: AudioStreamWAV
var _player_parent_3d: Node

var _sound_paths: Dictionary = {
	"step": "res://assets/audio/step.ogg",
	"cane_hit": "res://assets/audio/cane_hit.ogg",
	"wall_hit": "res://assets/audio/wall_hit.ogg",
	"fall": "res://assets/audio/fall.ogg",
	"spray": "res://assets/audio/spray.ogg",
	"touch": "res://assets/audio/touch.ogg",
	"npc_approach": "res://assets/audio/npc_approach.ogg",
	"victory": "res://assets/audio/victory.ogg",
	"failure": "res://assets/audio/failure.ogg",
	"ui_click": "res://assets/audio/ui_click.ogg",
	"danger_warning": "res://assets/audio/danger_warning.ogg",
}


func _ready() -> void:
	_silent_stream = _create_silent_stream()
	call_deferred("_create_player_pool")
	EventBus.audio_requested.connect(_on_audio_requested)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.cane_entered_npc_zone.connect(_on_cane_entered_npc_zone)


func play_3d(sound_id: String, position: Vector3, volume_db: float = 0.0) -> void:
	if _players_3d.is_empty():
		play_2d(sound_id, volume_db)
		return

	var player := _players_3d[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players_3d.size()
	player.global_position = position
	player.volume_db = master_volume_db + volume_db
	player.stream = _resolve_stream(sound_id)
	player.play()


func play_2d(sound_id: String, volume_db: float = 0.0) -> void:
	_player_2d.volume_db = master_volume_db + volume_db
	_player_2d.stream = _resolve_stream(sound_id)
	_player_2d.play()


func _on_audio_requested(sound_id: String, position: Vector3, volume_db: float) -> void:
	play_3d(sound_id, position, volume_db)


func _on_game_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if new_state == &"SUCCESS":
		play_2d("victory")
	elif new_state == &"FAILURE":
		play_2d("failure")


func _on_cane_entered_npc_zone(_npc_name: String) -> void:
	play_2d("npc_approach")


func _create_player_pool() -> void:
	_player_parent_3d = _find_game_world_parent()
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		player.name = "AudioStreamPlayer3D_%d" % i
		_player_parent_3d.add_child(player)
		_players_3d.append(player)

	_player_2d = AudioStreamPlayer.new()
	_player_2d.name = "AudioStreamPlayer2D"
	add_child(_player_2d)


func _find_game_world_parent() -> Node:
	var game_root := get_tree().root.find_child("GameRoot", true, false)
	if game_root:
		return game_root
	return self


func _resolve_stream(sound_id: String) -> AudioStream:
	var path: String = _sound_paths.get(sound_id, "")
	if not path.is_empty():
		var stream := load(path) as AudioStream
		if stream:
			return stream
	return _silent_stream


func _create_silent_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.stereo = false
	stream.data = PackedByteArray()
	return stream
