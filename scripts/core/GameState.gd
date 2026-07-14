extends Node
## 线性流程状态机 + 输入闸门。本 MVP 只处理开始、成功和失败，不做检查点回滚。

enum State { LOADING, PLAYING, SUCCESS, FAILURE }

var current_state: State = State.LOADING

var _cutscene_active: bool = false
var _gameplay_locked: bool = false
var _quest_items: Dictionary = {}


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)


func set_playing() -> void:
	if current_state != State.LOADING:
		return
	_transition_to(State.PLAYING)


func set_victory() -> void:
	if _gameplay_locked:
		return
	if current_state != State.PLAYING:
		return
	_transition_to(State.SUCCESS)


func set_failure() -> void:
	_set_failure(false)


func is_playing() -> bool:
	return current_state == State.PLAYING


func set_cutscene_active(active: bool) -> void:
	_cutscene_active = active


func set_gameplay_locked(active: bool) -> void:
	_gameplay_locked = active


func is_gameplay_locked() -> bool:
	return _gameplay_locked


func is_input_enabled() -> bool:
	return current_state == State.PLAYING and not _cutscene_active


func collect_quest_item(item_id: StringName) -> bool:
	if item_id == &"":
		return false
	if _quest_items.has(item_id):
		return false
	_quest_items[item_id] = true
	EventBus.quest_item_collected.emit(item_id)
	if GameConfig.DEBUG:
		print("[DEBUG][GameState] quest_item_collected item_id=%s" % item_id)
	return true


func has_quest_item(item_id: StringName) -> bool:
	return _quest_items.has(item_id)


func get_quest_items() -> Array[StringName]:
	var items: Array[StringName] = []
	for key in _quest_items.keys():
		items.append(key)
	return items


## 重置状态机回 LOADING，供场景 reload 前调用。
## 不做其他副作用（不移动玩家、不清空音效）。
## 必须在 reload_current_scene() 之前调用，否则新场景的 set_playing() 守卫会卡住。
func reset_to_loading() -> void:
	current_state = State.LOADING
	_cutscene_active = false
	_gameplay_locked = false
	_quest_items.clear()


func _on_player_died() -> void:
	_set_failure(true)


func _set_failure(ignore_gameplay_lock: bool) -> void:
	if _gameplay_locked and not ignore_gameplay_lock:
		return
	if current_state != State.PLAYING:
		return
	_transition_to(State.FAILURE)


func _transition_to(new_state: State) -> void:
	var old_state := current_state
	current_state = new_state
	if GameConfig.DEBUG:
		print("[DEBUG][GameState] %s -> %s" % [_state_name(old_state), _state_name(new_state)])
	EventBus.game_state_changed.emit(_state_name(old_state), _state_name(new_state))


func _state_name(state: State) -> StringName:
	match state:
		State.LOADING:
			return &"LOADING"
		State.PLAYING:
			return &"PLAYING"
		State.SUCCESS:
			return &"SUCCESS"
		State.FAILURE:
			return &"FAILURE"
	return &"UNKNOWN"
