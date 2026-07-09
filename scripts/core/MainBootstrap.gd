extends Node3D
## 场景入口引导：主场景加载完成后进入 PLAYING 状态。


func _ready() -> void:
	if GameState.current_state == GameState.State.LOADING:
		GameState.set_playing()
