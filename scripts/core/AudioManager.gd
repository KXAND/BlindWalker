extends Node
## 全局音频入口：监听玩法事件并播放 2D/3D 音效。
## 3D 播放器必须挂到 GameRoot，否则 SubViewport 内的 AudioListener3D 听不到。

@export var master_volume_db: float = 0.0

signal audio_settings_changed

const POOL_SIZE: int = 4
const DEFAULT_CANE_TAP_SOUND_ID := "cane_tap_default"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "audio"
const SETTINGS_VERSION := 3
const DEFAULT_MUSIC_VOLUME := 0.35
const DEFAULT_SFX_VOLUME := 1.0
const MUTE_DB := -80.0

var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_player_index: int = 0
var _player_2d: AudioStreamPlayer
var _silent_stream: AudioStreamWAV
var _player_parent_3d: Node
var _warned_missing_sounds: Dictionary = {}
var _music_volume: float = DEFAULT_MUSIC_VOLUME
var _sfx_volume: float = DEFAULT_SFX_VOLUME

var _sound_paths: Dictionary = {
	# 脚步声 —— 按地面材质分类
	"step": "res://assets/audio/sfx/step.wav",
	"step_asphalt": "res://assets/audio/sfx/step_asphalt.wav",
	"step_concrete": "res://assets/audio/sfx/step_concrete.wav",
	"step_pavement": "res://assets/audio/sfx/step_pavement.wav",
	"step_tiles": "res://assets/audio/sfx/step_tiles.wav",
	"step_wood": "res://assets/audio/sfx/step_wood.wav",
	"step_metal": "res://assets/audio/sfx/step_metal.wav",
	# 盲杖敲击
	"cane_hit": "res://assets/audio/sfx/cane_tap_default.wav",
	"cane_tap_asphalt": "res://assets/audio/sfx/cane_tap_asphalt.ogg",
	"cane_tap_pavement": "res://assets/audio/sfx/cane_tap_pavement.wav",
	"cane_tap_concrete": "res://assets/audio/sfx/cane_tap_concrete.wav",
	"cane_tap_tiles": "res://assets/audio/sfx/cane_tap_tiles.wav",
	"cane_tap_metal_pole": "res://assets/audio/sfx/cane_tap_metal_pole.wav",
	"cane_tap_plastic": "res://assets/audio/sfx/cane_tap_plastic.ogg",
	"cane_tap_wood_or_shelf": "res://assets/audio/sfx/cane_tap_wood.wav",
	"cane_tap_default": "res://assets/audio/sfx/cane_tap_default.wav",
	"cane_tap_glass": "res://assets/audio/sfx/cane_tap_glass.wav",
	"traffic_light_beep": "res://assets/audio/sfx/traffic_green.wav",
	"traffic_green": "res://assets/audio/sfx/traffic_green.wav",
	"traffic_red": "res://assets/audio/sfx/traffic_red.wav",
	"traffic_yellow": "res://assets/audio/sfx/traffic_yellow.wav",
	"ambient_noise": "res://assets/audio/sfx/ambient_noise.ogg",
	"wall_hit": "res://assets/audio/sfx/wall_hit.ogg",
	"fall": "res://assets/audio/sfx/fall.wav",
	"spray": "res://assets/audio/sfx/spray.ogg",
	"touch": "res://assets/audio/sfx/touch.ogg",
	"npc_approach": "res://assets/audio/sfx/npc_approach.ogg",
	"victory": "res://assets/audio/sfx/victory.ogg",
	"failure": "res://assets/audio/sfx/failure.ogg",
	"ui_click": "res://assets/audio/sfx/ui_click.ogg",
	"danger_warning": "res://assets/audio/sfx/danger_warning.ogg",
	"handrail_grab": "res://assets/audio/sfx/touch.ogg",
	"handrail_release": "res://assets/audio/sfx/ui_click.ogg",
	"door_open": "res://assets/audio/sfx/ui_click.ogg",
	"door_close": "res://assets/audio/sfx/ui_click.ogg",
}


func _ready() -> void:
	_load_audio_settings()
	_silent_stream = _create_silent_stream()
	_player_2d = AudioStreamPlayer.new()
	_player_2d.name = "AudioStreamPlayer2D"
	add_child(_player_2d)
	EventBus.audio_requested.connect(_on_audio_requested)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.cane_entered_npc_zone.connect(_on_cane_entered_npc_zone)
	await get_tree().process_frame
	_create_3d_player_pool()


func play_3d(sound_id: String, position: Vector3, volume_db: float = 0.0, source: StringName = &"unknown") -> void:
	if _players_3d.is_empty():
		play_2d(sound_id, volume_db, source)
		return

	var player := _players_3d[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players_3d.size()
	player.global_position = position
	player.volume_db = sfx_volume_db(volume_db)
	player.stream = _resolve_stream(sound_id, source)
	player.play()


func play_2d(sound_id: String, volume_db: float = 0.0, source: StringName = &"unknown") -> void:
	if not _player_2d:
		return
	_player_2d.volume_db = sfx_volume_db(volume_db)
	_player_2d.stream = _resolve_stream(sound_id, source)
	_player_2d.play()


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	_save_audio_settings()
	audio_settings_changed.emit()


func set_sfx_volume(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	_apply_current_sfx_volume()
	_save_audio_settings()
	audio_settings_changed.emit()


func music_volume_db(base_volume_db: float = 0.0) -> float:
	return base_volume_db + _linear_to_volume_db(_music_volume)


func sfx_volume_db(base_volume_db: float = 0.0) -> float:
	return master_volume_db + base_volume_db + _linear_to_volume_db(_sfx_volume)


func stop_2d() -> void:
	if is_instance_valid(_player_2d) and _player_2d.playing:
		_player_2d.stop()


## 停止所有正在播放的音频流，供场景 reload 前调用。
## Web 平台必要：显式停止可防止 Web Audio 在页面生命周期中产生鬼影音效。
## 调用后清空 3D 播放器池引用（节点在 reload 后会被销毁）。
func stop_all() -> void:
	if is_instance_valid(_player_2d) and _player_2d.playing:
		_player_2d.stop()
	for player in _players_3d:
		if is_instance_valid(player) and player.playing:
			player.stop()
	# reload_current_scene 会销毁 GameRoot 下的 3D 播放器，清空引用防止悬空
	_players_3d.clear()
	_next_player_index = 0


func _on_audio_requested(sound_id: String, position: Vector3, volume_db: float) -> void:
	play_3d(sound_id, position, volume_db, &"cane")


func _on_game_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if new_state == &"SUCCESS":
		play_2d("victory")
	elif new_state == &"FAILURE":
		play_2d("failure")


func _on_cane_entered_npc_zone(_npc_name: String) -> void:
	play_2d("npc_approach")


func _create_3d_player_pool() -> void:
	_player_parent_3d = _find_game_world_parent()
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer3D.new()
		player.name = "AudioStreamPlayer3D_%d" % i
		_player_parent_3d.add_child(player)
		_players_3d.append(player)


func _find_game_world_parent() -> Node:
	var game_root := get_tree().root.find_child("GameRoot", true, false)
	if game_root:
		return game_root
	return self


func _resolve_stream(sound_id: String, source: StringName = &"unknown") -> AudioStream:
	var path: String = _sound_paths.get(sound_id, "")
	var stream := _resolve_stream_at_path(path)
	if stream:
		return stream

	if _should_fallback_to_default_cane_tap(sound_id, source):
		var fallback_path: String = _sound_paths.get(DEFAULT_CANE_TAP_SOUND_ID, "")
		var fallback_stream := _resolve_stream_at_path(fallback_path)
		if fallback_stream:
			_warn_missing_sound_once(sound_id, source, path, DEFAULT_CANE_TAP_SOUND_ID)
			return fallback_stream

	if _should_fallback_to_default_step(sound_id, source):
		var fallback_path: String = _sound_paths.get("step", "")
		var fallback_stream := _resolve_stream_at_path(fallback_path)
		if fallback_stream:
			_warn_missing_sound_once(sound_id, source, path, "step")
			return fallback_stream

	_warn_missing_sound_once(sound_id, source, path, "silent")
	return _silent_stream


func _resolve_stream_at_path(path: String) -> AudioStream:
	if not path.is_empty():
		var raw_stream := _load_raw_ogg(path)
		if raw_stream:
			return raw_stream
	if not path.is_empty() and ResourceLoader.exists(path):
		var stream := ResourceLoader.load(path) as AudioStream
		if stream:
			return stream
	return null


func _should_fallback_to_default_cane_tap(sound_id: String, source: StringName) -> bool:
	return source == &"cane" and sound_id.begins_with("cane_tap_") and sound_id != DEFAULT_CANE_TAP_SOUND_ID


func _should_fallback_to_default_step(sound_id: String, source: StringName) -> bool:
	return source == &"gait" or (sound_id.begins_with("step_") and sound_id != "step")


func _warn_missing_sound_once(sound_id: String, source: StringName, path: String, fallback: String) -> void:
	if GameConfig.DEBUG and not _warned_missing_sounds.has(sound_id):
		_warned_missing_sounds[sound_id] = true
		print("[DEBUG][AudioManager] missing source=%s sound_id=%s path=%s fallback=%s" % [
			source,
			sound_id,
			path if not path.is_empty() else "<unregistered>",
			fallback,
		])


func _load_raw_ogg(path: String) -> AudioStream:
	if not path.ends_with(".ogg") or not FileAccess.file_exists(path):
		return null
	return AudioStreamOggVorbis.load_from_file(path)


func _create_silent_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.stereo = false
	stream.data = PackedByteArray()
	return stream


func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var version := int(config.get_value(SETTINGS_SECTION, "version", 0))
	_music_volume = DEFAULT_MUSIC_VOLUME if version < SETTINGS_VERSION else clampf(float(config.get_value(SETTINGS_SECTION, "music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
	_sfx_volume = clampf(float(config.get_value(SETTINGS_SECTION, "sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)
	if version < SETTINGS_VERSION:
		_save_audio_settings()


func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "version", SETTINGS_VERSION)
	config.set_value(SETTINGS_SECTION, "music_volume", _music_volume)
	config.set_value(SETTINGS_SECTION, "sfx_volume", _sfx_volume)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("AudioManager: failed to save audio settings err=%d" % err)


func _linear_to_volume_db(value: float) -> float:
	if value <= 0.0:
		return MUTE_DB
	return linear_to_db(value)


func _apply_current_sfx_volume() -> void:
	if is_instance_valid(_player_2d):
		_player_2d.volume_db = sfx_volume_db()
	for player in _players_3d:
		if is_instance_valid(player):
			player.volume_db = sfx_volume_db()
