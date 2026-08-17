class_name OpeningRoutine
extends Node
## 开场家庭流程：起床、取杖、早餐和处理满垃圾桶。

const OPENING_ITEM_WAKE := &"opening_woke_up"
const OPENING_ITEM_CLOTHES := &"opening_clothes_changed"
const OPENING_ITEM_CANE := &"opening_cane_taken"
const OPENING_ITEM_BREAKFAST := &"opening_breakfast"
const OPENING_ITEM_TRASH := &"opening_trash_done"
const OPENING_ACTION_DIALOGUE := &"dialogue"
const OPENING_ACTION_CLOTHES := &"clothes"
const OPENING_ACTION_CANE := &"cane"
const OPENING_ACTION_BREAKFAST := &"breakfast"
const OPENING_ACTION_TRASH := &"trash"
const DIALOGUE_SPEAKER := "晓明"

const InteractableScript = preload("res://scripts/gameplay/OpeningInteractable.gd")
const NarrativeLineScript = preload("res://scripts/core/NarrativeLine.gd")
const NarrativeSequenceScript = preload("res://scripts/core/NarrativeSequence.gd")

var _player: Node3D
var _cane: CaneSystem
var _touch_memory: TouchMemorySystem
var _manager: CutsceneManager
var _pending_action: StringName = &""
var _active_interactable: Node
var _opening_complete := false


func _ready() -> void:
	add_to_group("opening_routine_active")
	_manager = get_tree().root.find_child("CutsceneManager", true, false) as CutsceneManager
	_player = get_parent().get_node_or_null("Player") as Node3D
	if not _player:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		_cane = _player.get_node_or_null("CaneSystem") as CaneSystem
		_touch_memory = _player.get_node_or_null("TouchMemorySystem") as TouchMemorySystem
	EventBus.cutscene_ended.connect(_on_cutscene_ended)
	call_deferred("_begin_opening")


func _process(_delta: float) -> void:
	if _opening_complete:
		return
	# Prevent the old route triggers from firing while the home routine is active.
	for node in get_tree().get_nodes_in_group("narrative_trigger"):
		(node as Area3D).set_deferred("monitoring", false)


func _begin_opening() -> void:
	if not _player:
		await get_tree().process_frame
		_player = get_parent().get_node_or_null("Player") as Node3D
		if not _player:
			_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player:
			_cane = _player.get_node_or_null("CaneSystem") as CaneSystem
			_touch_memory = _player.get_node_or_null("TouchMemorySystem") as TouchMemorySystem
	if not _manager or GameState.has_quest_item(OPENING_ITEM_TRASH):
		_opening_complete = true
		remove_from_group("opening_routine_active")
		_enable_route_triggers(true)
		return
	_enable_route_triggers(false)
	if _manager.is_sequence_playing():
		return
	if not GameState.has_quest_item(OPENING_ITEM_WAKE):
		GameState.collect_quest_item(OPENING_ITEM_WAKE)
	if not GameState.has_quest_item(OPENING_ITEM_CLOTHES):
		_enable_action(OPENING_ACTION_CLOTHES, "换衣服", "Wardrobe2", 1.0)
	elif not GameState.has_quest_item(OPENING_ITEM_BREAKFAST):
		_enable_action(OPENING_ACTION_BREAKFAST, "吃早餐", "Breakfast")
	elif not GameState.has_quest_item(OPENING_ITEM_TRASH):
		_enable_action(OPENING_ACTION_TRASH, "处理垃圾", "IndoorTrashCan")
	elif not GameState.has_quest_item(OPENING_ITEM_CANE):
		_enable_action(OPENING_ACTION_CANE, "拿盲杖", "ShoeCabinet")


func perform_action(action: StringName, _source: Node) -> bool:
	if _pending_action != &"" or _opening_complete or (_manager and _manager.is_sequence_playing()):
		return false
	if action == OPENING_ACTION_CLOTHES and GameState.has_quest_item(OPENING_ITEM_WAKE) and not GameState.has_quest_item(OPENING_ITEM_CLOTHES):
		GameState.collect_quest_item(OPENING_ITEM_CLOTHES)
		_pending_action = action
		_play_sequence(action, ["我像往常一样，慢慢的换衣服", "衣服换好了，去吃早餐吧"])
		return true
	if action == OPENING_ACTION_BREAKFAST and GameState.has_quest_item(OPENING_ITEM_CLOTHES) and not GameState.has_quest_item(OPENING_ITEM_BREAKFAST):
		GameState.collect_quest_item(OPENING_ITEM_BREAKFAST)
		_pending_action = action
		_play_sequence(action, ["母亲做的早饭还是一如既往的用心", "早餐吃完了，收拾一下垃圾","把垃圾扔到门口垃圾桶吧"])
		return true
	if action == OPENING_ACTION_TRASH and GameState.has_quest_item(OPENING_ITEM_BREAKFAST) and not GameState.has_quest_item(OPENING_ITEM_TRASH):
		GameState.collect_quest_item(OPENING_ITEM_TRASH)
		_pending_action = action
		_play_sequence(action, ["我拎起垃圾走到门口，准备放进门口的垃圾桶。", "嗯？垃圾桶好像满了？那拿到楼下垃圾桶扔了吧", "好久没出门了，先拿上盲杖吧。"])
		return true
	if action == OPENING_ACTION_CANE and GameState.has_quest_item(OPENING_ITEM_TRASH) and not GameState.has_quest_item(OPENING_ITEM_CANE):
		GameState.collect_quest_item(OPENING_ITEM_CANE)
		_pending_action = action
		_play_sequence(action, ["我拿起放在鞋柜旁的盲杖。", "手中传来盲杖的触感，可以出发了。"])
		return true
	return false


func _play_sequence(action: StringName, texts: Array[String], speaker: String = "") -> void:
	var sequence := NarrativeSequenceScript.new()
	sequence.sequence_id = StringName("opening_" + String(action))
	sequence.lock_input = true
	sequence.lock_gameplay = true
	sequence.default_line_duration = 3.0
	sequence.lines = []
	for text in texts:
		var line := NarrativeLineScript.new()
		line.speaker_name = speaker
		line.text = text
		line.duration = 3.0
		sequence.lines.append(line)
	_manager.play_sequence(sequence)


func _on_cutscene_ended(sequence_id: String) -> void:
	if sequence_id == "intro_fullscreen" and _pending_action == &"":
		if not GameState.has_quest_item(OPENING_ITEM_WAKE):
			GameState.collect_quest_item(OPENING_ITEM_WAKE)
		_pending_action = OPENING_ACTION_DIALOGUE
		_play_sequence(OPENING_ACTION_DIALOGUE, [
			"还是没有奇迹吗，也是，奇迹怎么会有这么容易发生呢。",
			"先去换衣服吧。",
		], DIALOGUE_SPEAKER)
		return
	if _pending_action == &"" or sequence_id != "opening_" + String(_pending_action):
		return
	var completed_action := _pending_action
	_pending_action = &""
	if completed_action == OPENING_ACTION_DIALOGUE:
		_enable_action(OPENING_ACTION_CLOTHES, "换衣服", "Wardrobe2", 1.0)
	elif completed_action == OPENING_ACTION_CLOTHES:
		_enable_action(OPENING_ACTION_BREAKFAST, "吃早餐", "Breakfast")
	elif completed_action == OPENING_ACTION_BREAKFAST:
		_enable_action(OPENING_ACTION_TRASH, "处理垃圾", "IndoorTrashCan")
	elif completed_action == OPENING_ACTION_TRASH:
		_enable_action(OPENING_ACTION_CANE, "拿盲杖", "ShoeCabinet")
	elif completed_action == OPENING_ACTION_CANE:
		if _cane and not _cane.is_deployed():
			_cane.toggle_deployment()
		_opening_complete = true
		remove_from_group("opening_routine_active")
		_enable_route_triggers(true)


func _enable_action(action: StringName, prompt: String, anchor_name: String, height_offset: float = 0.0) -> void:
	if is_instance_valid(_active_interactable):
		_active_interactable.queue_free()
	_active_interactable = InteractableScript.new()
	_active_interactable.action = action
	_active_interactable.routine = self
	_active_interactable.prompt_text = "按 E %s" % prompt
	var prompt_anchor := Marker3D.new()
	prompt_anchor.name = "OpeningAnchor"
	_active_interactable.add_child(prompt_anchor)
	_active_interactable.prompt_anchor_path = NodePath("OpeningAnchor")
	_active_interactable.reveal_target_path = NodePath("OpeningAnchor")
	_active_interactable.repeat_policy = Interactable.RepeatPolicy.ONCE
	_active_interactable.requires_line_of_sight = false
	_active_interactable.interaction_priority = 100
	_active_interactable.focus_angle_degrees = 90.0
	add_child(_active_interactable)
	var anchor := get_tree().root.find_child(anchor_name, true, false) as Node3D
	if not anchor:
		_active_interactable.global_position = _player.global_position
	else:
		_active_interactable.global_position = anchor.global_position
	_active_interactable.global_position += Vector3.UP * height_offset
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	shape_node.shape = shape
	_active_interactable.add_child(shape_node)
	if _touch_memory:
		_touch_memory.spawn_touch_memory(
			_active_interactable.global_position,
			1.2,
			30.0,
			1.2,
			60.0,
			Color(0.65, 0.8, 1.0, 1.0),
			&"opening",
			&"default_contact",
			true
		)


func _enable_route_triggers(active: bool) -> void:
	for node in get_tree().get_nodes_in_group("narrative_trigger"):
		(node as Area3D).set_deferred("monitoring", active)
