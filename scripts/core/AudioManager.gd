extends Node

@export var master_volume_db: float = 0.0

const POOL_SIZE: int = 4

var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_player_index: int = 0
var _player_2d: AudioStreamPlayer
var _silent_stream: AudioStreamWAV
var _sound_paths: Dictionary = {
	"step": "",
	"stagger": "",
	"fall": "",
	"cane_hit": "",
	"npc": "",
	"ui": ""
}


func _ready() -> void:
	_silent_stream = _create_silent_stream()
	_create_player_pool()
	EventBus.audio_requested.connect(_on_audio_requested)


func play_3d(sound_id: String, position: Vector3, volume_db: float = 0.0) -> void:
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


func _create_player_pool() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		player.name = "AudioStreamPlayer3D_%d" % i
		add_child(player)
		_players_3d.append(player)

	_player_2d = AudioStreamPlayer.new()
	_player_2d.name = "AudioStreamPlayer2D"
	add_child(_player_2d)


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
