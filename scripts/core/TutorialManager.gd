extends Node
## 会话级上下文教程管理器。监听事件、维护教程栈和已读状态，不参与玩法判定。

const INTRO_CONTROLS := &"intro_controls"
const STUMBLE := &"stumble"
const FALL := &"fall"
const INTRO_DELAY_SECONDS := 0.5

const _PROMPTS := {
	INTRO_CONTROLS: preload("res://assets/tutorials/intro_controls.tres"),
	STUMBLE: preload("res://assets/tutorials/stumble.tres"),
	FALL: preload("res://assets/tutorials/fall.tres"),
}

var _seen: Dictionary = {}
var _queued: Dictionary = {}
var _stack: Array[StringName] = []
var _current_id: StringName = &""
var _current_prompt: Resource
var _cutscene_active: bool = false
var _pending_stumble: bool = false
var _pending_fall: bool = false

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
	EventBus.player_died.connect(_on_player_died)


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


func _on_balance_recovered() -> void:
	if _pending_stumble:
		enqueue_tutorial(STUMBLE, false)
		_pending_stumble = false
	if _pending_fall:
		enqueue_tutorial(FALL, false)
		_pending_fall = false
	_try_show_next()


func _on_player_died() -> void:
	_pause_current_prompt()


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
