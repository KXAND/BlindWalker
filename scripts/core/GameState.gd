extends Node

enum State { LOADING, PLAYING, SUCCESS, FAILURE }

var current_state: State = State.LOADING


func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)


func set_playing() -> void:
	if current_state != State.LOADING:
		return
	_transition_to(State.PLAYING)


func set_victory() -> void:
	if current_state != State.PLAYING:
		return
	_transition_to(State.SUCCESS)


func set_failure() -> void:
	if current_state != State.PLAYING:
		return
	_transition_to(State.FAILURE)


func is_playing() -> bool:
	return current_state == State.PLAYING


func _on_player_died() -> void:
	set_failure()


func _transition_to(new_state: State) -> void:
	var old_state := current_state
	current_state = new_state
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
