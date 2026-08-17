class_name OpeningInteractable
extends "res://scripts/interaction/Interactable.gd"

@export var action: StringName = &""
var routine: Node


func interact(player: Node3D) -> bool:
	if not can_interact(player) or not routine:
		return false
	if not routine.perform_action(action, self):
		return false
	_play_interaction_sound()
	_mark_interacted()
	return true


func _ready() -> void:
	super._ready()
	add_to_group("opening_interactable")
