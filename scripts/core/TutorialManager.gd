extends Node
## 会话级上下文教程管理器。监听事件、维护教程栈和已读状态，不参与玩法判定。

const INTRO_CONTROLS := &"intro_controls"
const REVEAL := &"reveal"
const CANE_CONTROLS := &"cane_controls"
const STUMBLE := &"stumble"
const FALL := &"fall"
const HEALTH_REST := &"health_rest"
const ACCESSIBILITY_HINT := &"accessibility_hint"
const EXIT_DOOR := &"exit_door"
const INTRO_DELAY_SECONDS := 0.5
const HEALTH_REST_THRESHOLD := 50
const CANE_QUEST_ITEM := &"opening_cane_taken"
const EXIT_DOOR_QUEST_ITEM := &"exit_door_first_interaction"
const FALL_COUNT_FOR_HINT := 2

const _PROMPTS := {
	INTRO_CONTROLS: preload("res://assets/tutorials/intro_controls.tres"),
	REVEAL: preload("res://assets/tutorials/reveal.tres"),
	CANE_CONTROLS: preload("res://assets/tutorials/cane_controls.tres"),
	STUMBLE: preload("res://assets/tutorials/stumble.tres"),
	FALL: preload("res://assets/tutorials/fall.tres"),
	HEALTH_REST: preload("res://assets/tutorials/health_rest.tres"),
	ACCESSIBILITY_HINT: preload("res://assets/tutorials/accessibility_hint.tres"),
	EXIT_DOOR: preload("res://assets/tutorials/exit_door.tres"),
}

var _seen: Dictionary = {}
var _queued: Dictionary = {}
var _stack: Array[StringName] = []
var _current_id: StringName = &""
var _current_prompt: Resource
var _cutscene_active: bool = false
var _pending_stumble: bool = false
var _pending_fall: bool = false
var _fall_count: int = 0
var _pending_f3_hint: bool = false

var _ui: TutorialPromptUI


func _ready() -> void:
	_ui = TutorialPromptUI.new()
	_ui.name = "TutorialPromptUI"
	_ui.dismissed.connect(_confirm_current_prompt)
	add_child(_ui)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.cutscene_started.connect(_on_cutscene_started)
	EventBus.cutscene_ended.connect(_on_cutscene_ended)
	EventBus.player_light_stumbled.connect(_on_stumbled)
	EventBus.player_unstable_stumbled.connect(_on_unstable_stumbled)
	EventBus.player_fall_started.connect(_on_fall_started)
	EventBus.player_balance_recovered.connect(_on_balance_recovered)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.touch_memory_spawned.connect(_on_touch_memory_spawned)
	EventBus.quest_item_collected.connect(_on_quest_item_collected)


func enqueue_tutorial(tutorial_id: StringName, try_show: bool = true) -> bool:
	if _seen.has(tutorial_id) or _queued.has(tutorial_id) or _current_id == tutorial_id:
		return false
	if not _PROMPTS.has(tutorial_id):
		if GameConfig.DEBUG:
			print("[DEBUG][TutorialManager] unknown tutorial id=%s" % tutorial_id)
		return false
	if _is_showing_prompt():
		_suspend_current_prompt_to_stack()
	_stack.push_back(tutorial_id)
	_queued[tutorial_id] = true
	if GameConfig.DEBUG:
		print("[DEBUG][TutorialManager] queued id=%s stack=%d" % [tutorial_id, _stack.size()])
	if try_show:
		_try_show_next()
	return true


func _on_game_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if new_state == &"PLAYING":
		_queue_intro_after_delay()
		_try_show_next()
	elif new_state == &"SUCCESS" or new_state == &"FAILURE":
		_pause_current_prompt()


func _on_cutscene_started(_cutscene_id: String) -> void:
	_cutscene_active = true
	_pause_current_prompt()


func _on_cutscene_ended(_cutscene_id: String) -> void:
	_cutscene_active = false
	_try_show_next()


func _on_stumbled() -> void:
	_pending_stumble = true


func _on_unstable_stumbled(_qte_window: float) -> void:
	_pending_stumble = true


func _on_fall_started() -> void:
	_pending_fall = true
	_fall_count += 1
	if _fall_count == FALL_COUNT_FOR_HINT:
		# 第二次摔倒后提示无障碍功能，与摔倒教程同路径延迟到起身后显示。
		_pending_f3_hint = true


func _on_balance_recovered() -> void:
	if _pending_stumble:
		enqueue_tutorial(STUMBLE, false)
		_pending_stumble = false
	if _pending_fall:
		enqueue_tutorial(FALL, false)
		_pending_fall = false
	if _pending_f3_hint:
		enqueue_tutorial(ACCESSIBILITY_HINT, false)
		_pending_f3_hint = false
	_try_show_next()


func _on_player_damaged(_amount: int, current_hp: int) -> void:
	if current_hp > 0 and current_hp < HEALTH_REST_THRESHOLD:
		enqueue_tutorial(HEALTH_REST)


func _on_player_died() -> void:
	_pause_current_prompt()


func _on_touch_memory_spawned(source: StringName) -> void:
	# 只有玩家主动感知（手触或杖触）生成的显影球才触发教程；
	# 开场引导等系统生成的记忆球不算玩家首次感知。
	if source != &"hand" and source != &"cane":
		return
	enqueue_tutorial(REVEAL)


func _on_quest_item_collected(item_id: StringName) -> void:
	if item_id == CANE_QUEST_ITEM:
		enqueue_tutorial(CANE_CONTROLS)
	elif item_id == EXIT_DOOR_QUEST_ITEM:
		enqueue_tutorial(EXIT_DOOR)


func _queue_intro_after_delay() -> void:
	await get_tree().create_timer(INTRO_DELAY_SECONDS).timeout
	enqueue_tutorial(INTRO_CONTROLS)


func _try_show_next() -> void:
	if not _can_show_prompt():
		return
	if _current_id == &"" and not _stack.is_empty():
		var next_id: StringName = _stack.pop_back()
		_queued.erase(next_id)
		_show_prompt(next_id)
	elif _current_id != &"":
		_show_panel()


func _can_show_prompt() -> bool:
	if GameState.current_state != GameState.State.PLAYING:
		return false
	if _cutscene_active:
		return false
	if _ui and _ui.is_prompt_visible():
		return false
	return _current_id != &"" or not _stack.is_empty()


func _show_prompt(tutorial_id: StringName) -> void:
	_current_id = tutorial_id
	_current_prompt = _PROMPTS[tutorial_id] as Resource
	_ui.show_prompt(_current_prompt.title, _current_prompt.body)
	if GameConfig.DEBUG:
		print("[DEBUG][TutorialManager] show id=%s" % tutorial_id)


func _confirm_current_prompt() -> void:
	if _current_id == &"":
		return
	_seen[_current_id] = true
	if GameConfig.DEBUG:
		print("[DEBUG][TutorialManager] dismissed id=%s" % _current_id)
	_current_id = &""
	_current_prompt = null
	_hide_panel()
	_try_show_next()


func _pause_current_prompt() -> void:
	_hide_panel()


func _suspend_current_prompt_to_stack() -> void:
	if _current_id == &"":
		return
	_stack.push_back(_current_id)
	_queued[_current_id] = true
	_current_id = &""
	_current_prompt = null
	_hide_panel()


func _is_showing_prompt() -> bool:
	return _ui and _ui.is_prompt_visible() and _current_id != &""


func _show_panel() -> void:
	if _ui and _current_prompt:
		_ui.show_prompt(_current_prompt.title, _current_prompt.body)


func _hide_panel() -> void:
	if _ui:
		_ui.hide_prompt()
