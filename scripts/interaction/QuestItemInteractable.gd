class_name QuestItemInteractable
extends "res://scripts/interaction/Interactable.gd"
## 任务物品互动：只记录 item_id，不实现购物篮或数量系统。

@export var item_id: StringName = &""
@export var on_collected_sequence: Resource


func can_interact(player: Node3D) -> bool:
	if item_id == &"":
		return false
	if GameState.has_quest_item(item_id):
		return false
	return super.can_interact(player)


func interact(player: Node3D) -> bool:
	if not can_interact(player):
		return false
	GameState.collect_quest_item(item_id)
	_play_interaction_sound()
	_play_narrative_sequence(on_collected_sequence)
	_mark_interacted()
	if GameConfig.DEBUG:
		print("[DEBUG][QuestItemInteractable] collected item_id=%s path=%s" % [item_id, get_path()])
	return true
