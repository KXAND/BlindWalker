extends Node3D


func _ready() -> void:
	# 主场景加载完成后进入 PLAYING，避免终点触发时仍停留在 LOADING。
	if GameState.current_state == GameState.State.LOADING:
		GameState.set_playing()
