class_name HandrailInteractable
extends "res://scripts/interaction/Interactable.gd"
## 扶栏互动：切换玩家步态系统中的扶栏辅助状态。

@export var grab_sound_id: StringName = &"handrail_grab"
@export var release_sound_id: StringName = &"handrail_release"


func _ready() -> void:
	super._ready()
	requires_line_of_sight = false


func get_interaction_prompt(player: Node3D) -> String:
	if _player_is_assisted_by_this(player):
		return "按 E 松开"
	return prompt_text


func interact(player: Node3D) -> bool:
	if not can_interact(player):
		return false
	if not _player_supports_handrail(player):
		return false
	if _player_is_assisted_by_this(player):
		player.call("clear_handrail_assist", self)
		_play_interaction_sound(release_sound_id)
		if GameConfig.DEBUG:
			print("[DEBUG][HandrailInteractable] released path=%s" % get_path())
	else:
		player.call("set_handrail_assist", self)
		_play_interaction_sound(grab_sound_id)
		if GameConfig.DEBUG:
			print("[DEBUG][HandrailInteractable] grabbed path=%s" % get_path())
	return true


func _player_supports_handrail(player: Node3D) -> bool:
	return player \
			and player.has_method("set_handrail_assist") \
			and player.has_method("clear_handrail_assist") \
			and player.has_method("is_handrail_assisted_by")


func _player_is_assisted_by_this(player: Node3D) -> bool:
	if not _player_supports_handrail(player):
		return false
	return bool(player.call("is_handrail_assisted_by", self))
