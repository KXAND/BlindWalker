class_name Interactable
extends Area3D
## 通用可互动对象。自身就是互动触发区，具体对象可继承并覆写互动效果。

enum RepeatPolicy { REPEATABLE, ONCE }

@export var prompt_text: String = "按 E 互动"
@export var prompt_anchor_path: NodePath
@export var reveal_target_path: NodePath
@export var interaction_priority: int = 0
@export_range(1.0, 90.0, 1.0) var focus_angle_degrees: float = 28.0
@export var requires_line_of_sight: bool = true
@export var show_prompt: bool = true
@export var repeat_policy: RepeatPolicy = RepeatPolicy.REPEATABLE
@export var interaction_sound_id: StringName = &""
@export var narrative_sequence: Resource

var _player_inside: bool = false
var _has_interacted: bool = false
var _warned_missing_anchor: bool = false
var _warned_missing_reveal_target: bool = false


func _ready() -> void:
	add_to_group("interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_sync_initial_overlaps")


func is_player_inside() -> bool:
	return _player_inside


func can_interact(_player: Node3D) -> bool:
	return repeat_policy != RepeatPolicy.ONCE or not _has_interacted


func get_interaction_prompt(_player: Node3D) -> String:
	return prompt_text


func get_prompt_anchor() -> Node3D:
	if not prompt_anchor_path.is_empty():
		var configured := get_node_or_null(prompt_anchor_path) as Node3D
		if configured:
			return configured
	if not _warned_missing_anchor:
		_warned_missing_anchor = true
		push_warning("%s: prompt_anchor_path missing or invalid, fallback to self" % get_path())
	return self


func get_reveal_target() -> Node3D:
	if not reveal_target_path.is_empty():
		var configured := get_node_or_null(reveal_target_path) as Node3D
		if configured:
			return configured
	var anchor := get_prompt_anchor()
	if anchor:
		if not _warned_missing_reveal_target:
			_warned_missing_reveal_target = true
			push_warning("%s: reveal_target_path missing or invalid, fallback to prompt anchor" % get_path())
		return anchor
	return self


func get_reveal_points() -> Array[Vector3]:
	var target := get_reveal_target()
	if target:
		return [target.global_position]
	return [global_position]


func interact(player: Node3D) -> bool:
	if not can_interact(player):
		return false
	_play_interaction_sound()
	_play_narrative_sequence()
	_mark_interacted()
	if GameConfig.DEBUG:
		print("[DEBUG][Interactable] interacted path=%s prompt=%s" % [get_path(), prompt_text])
	return true


func debug_reset_interaction() -> void:
	_has_interacted = false


func _mark_interacted() -> void:
	_has_interacted = true


func _play_interaction_sound(sound_id: StringName = &"") -> void:
	if sound_id == &"":
		sound_id = interaction_sound_id
	if sound_id == &"":
		return
	EventBus.audio_requested.emit(String(sound_id), global_position, 0.0)


func _play_narrative_sequence(sequence: Resource = narrative_sequence) -> bool:
	if not sequence:
		return false
	var manager := _resolve_cutscene_manager()
	if not manager:
		if GameConfig.DEBUG:
			print("[DEBUG][Interactable] missing CutsceneManager path=%s" % get_path())
		return false
	return manager.play_sequence(sequence)


func _resolve_cutscene_manager() -> CutsceneManager:
	for node in get_tree().get_nodes_in_group("cutscene_manager"):
		var manager := node as CutsceneManager
		if manager:
			return manager
	return get_tree().root.find_child("CutsceneManager", true, false) as CutsceneManager


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _sync_initial_overlaps() -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_player_inside = true
			return
