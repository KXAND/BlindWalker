class_name InteractionSystem
extends Node

@export var interaction_range: float = 2.0
@export var prompt_text: String = "按提示键与行人交流"

var _nearest_npc: NPCBase
var _was_available: bool = false


func _physics_process(_delta: float) -> void:
	var player := get_parent() as Node3D
	if not player:
		return

	var found_npc := _find_nearest_npc(player.global_position)
	var available := found_npc != null

	if available and not _was_available:
		_nearest_npc = found_npc
		EventBus.npc_interaction_available.emit(found_npc.npc_name, prompt_text)
	elif not available and _was_available:
		_nearest_npc = null
		EventBus.npc_interaction_unavailable.emit()

	_was_available = available


func _find_nearest_npc(player_position: Vector3) -> NPCBase:
	var nearest: NPCBase
	var nearest_distance := interaction_range
	for node in get_tree().get_nodes_in_group("npc"):
		if node is NPCBase:
			var npc := node as NPCBase
			var distance := player_position.distance_to(npc.global_position)
			if distance <= nearest_distance:
				nearest = npc
				nearest_distance = distance
	return nearest
