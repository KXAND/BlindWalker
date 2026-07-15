extends Node3D
## 场景入口引导：主场景加载完成后进入 PLAYING 状态。

@export var failure_sequence: Resource

const LOADING_SCENE := "res://scenes/main/LoadingScreen.tscn"
const GAME_MUSIC_PATH := "res://assets/audio/music/Sun on Keys_2.mp3"
const GAME_MUSIC_BASE_VOLUME_DB := -8.0

var _failure_started := false
var _reviving := false
var _music_player: AudioStreamPlayer


func _ready() -> void:
	EventBus.game_state_changed.connect(_on_game_state_changed)
	if GameState.current_state == GameState.State.LOADING:
		GameState.set_playing()
	_start_game_music()


func _exit_tree() -> void:
	stop_game_music()
	if AudioManager.audio_settings_changed.is_connected(_sync_game_music_volume):
		AudioManager.audio_settings_changed.disconnect(_sync_game_music_volume)


func _on_game_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if new_state != &"FAILURE" or _failure_started:
		return
	_failure_started = true
	# 延后一帧，确保 player_died 的其他监听者先完成，避免中断失败演出。
	call_deferred("_play_failure_sequence")


func _play_failure_sequence() -> void:
	var manager := get_tree().root.find_child("CutsceneManager", true, false) as CutsceneManager
	if not manager or not failure_sequence or not manager.play_sequence(failure_sequence):
		return
	if not manager.final_line_secondary_requested.is_connected(_on_failure_secondary_requested):
		manager.final_line_secondary_requested.connect(_on_failure_secondary_requested)
	EventBus.cutscene_ended.connect(_on_failure_cutscene_ended)


func _on_failure_secondary_requested(cutscene_id: String) -> void:
	if cutscene_id != String(failure_sequence.sequence_id) or GameState.current_state != GameState.State.FAILURE:
		return
	var manager := get_tree().root.find_child("CutsceneManager", true, false) as CutsceneManager
	if not manager:
		return
	_reviving = true
	if EventBus.cutscene_ended.is_connected(_on_failure_cutscene_ended):
		EventBus.cutscene_ended.disconnect(_on_failure_cutscene_ended)
	manager.finish_sequence()
	var attributes := get_tree().get_first_node_in_group("player_attributes") as PlayerAttributes
	if attributes:
		attributes.revive()
	GameState.revive()
	_failure_started = false
	_reviving = false


func _on_failure_cutscene_ended(cutscene_id: String) -> void:
	if _reviving or cutscene_id != String(failure_sequence.sequence_id):
		return
	if EventBus.cutscene_ended.is_connected(_on_failure_cutscene_ended):
		EventBus.cutscene_ended.disconnect(_on_failure_cutscene_ended)
	stop_game_music()
	AudioManager.stop_all()
	GameState.reset_to_loading()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _start_game_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "GameMusicPlayer"
	add_child(_music_player)

	var stream := ResourceLoader.load(GAME_MUSIC_PATH) as AudioStream
	if not stream:
		push_warning("MainBootstrap: game music load FAILED path=%s" % GAME_MUSIC_PATH)
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	_music_player.stream = stream
	_sync_game_music_volume()
	if not AudioManager.audio_settings_changed.is_connected(_sync_game_music_volume):
		AudioManager.audio_settings_changed.connect(_sync_game_music_volume)
	_music_player.play()


func _sync_game_music_volume() -> void:
	if _music_player:
		_music_player.volume_db = AudioManager.music_volume_db(GAME_MUSIC_BASE_VOLUME_DB)


func stop_game_music() -> void:
	if is_instance_valid(_music_player) and _music_player.playing:
		_music_player.stop()
