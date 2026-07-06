extends Node3D


func _ready() -> void:
	if GameState.current_state == GameState.State.LOADING:
		GameState.set_playing()
