class_name TargetArea
extends Area3D
## 线性 MVP 的终点区域；玩家进入后请求 GameState 切到 SUCCESS。

@export var outro_sequence: Resource

const LOADING_SCENE := "res://scenes/main/LoadingScreen.tscn"

var _outro_started: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if GameState.is_gameplay_locked():
		return
	if not body.is_in_group("player"):
		return
	if _outro_started:
		return
	if outro_sequence and _play_outro_sequence():
		return
	GameState.set_victory()


func _play_outro_sequence() -> bool:
	var manager := _resolve_cutscene_manager()
	if not manager:
		return false
	_outro_started = true
	EventBus.cutscene_ended.connect(_on_cutscene_ended)
	if manager.play_sequence(outro_sequence):
		return true
	EventBus.cutscene_ended.disconnect(_on_cutscene_ended)
	_outro_started = false
	return false


func _on_cutscene_ended(cutscene_id: String) -> void:
	if cutscene_id != String(outro_sequence.sequence_id):
		return
	if EventBus.cutscene_ended.is_connected(_on_cutscene_ended):
		EventBus.cutscene_ended.disconnect(_on_cutscene_ended)
	AudioManager.stop_all()
	GameState.reset_to_loading()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _resolve_cutscene_manager() -> CutsceneManager:
	for node in get_tree().get_nodes_in_group("cutscene_manager"):
		var manager := node as CutsceneManager
		if manager:
			return manager
	return get_tree().root.find_child("CutsceneManager", true, false) as CutsceneManager
