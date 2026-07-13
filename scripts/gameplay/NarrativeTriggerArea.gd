class_name NarrativeTriggerArea
extends Area3D
## 叙事触发区：玩家进入后播放一段 NarrativeSequence。
## 只负责把“玩家到达某处”转换为叙事播放请求，不承载剧情流程判断。

@export var sequence: Resource
@export var trigger_once: bool = true
@export var cutscene_manager_path: NodePath

var _has_triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	call_deferred("_trigger_overlapping_player")


func _on_body_entered(body: Node3D) -> void:
	_try_trigger(body)


func _trigger_overlapping_player() -> void:
	for body in get_overlapping_bodies():
		_try_trigger(body)


func _try_trigger(body: Node3D) -> void:
	if trigger_once and _has_triggered:
		return
	if not sequence:
		return
	if not body.is_in_group("player"):
		return

	var cutscene_manager := _resolve_cutscene_manager()
	if not cutscene_manager:
		if GameConfig.DEBUG:
			print("[DEBUG][NarrativeTriggerArea] missing CutsceneManager at %s" % get_path())
		return

	if cutscene_manager.play_sequence(sequence):
		_has_triggered = true


func _resolve_cutscene_manager() -> CutsceneManager:
	if not cutscene_manager_path.is_empty():
		var configured := get_node_or_null(cutscene_manager_path) as CutsceneManager
		if configured:
			return configured

	for node in get_tree().get_nodes_in_group("cutscene_manager"):
		var manager := node as CutsceneManager
		if manager:
			return manager

	return get_tree().root.find_child("CutsceneManager", true, false) as CutsceneManager
