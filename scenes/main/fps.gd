extends Label
## FPS 调试显示 —— 默认隐藏，按 F4 切换显示（仅 DEBUG 构建生效）


func _ready() -> void:
	visible = false


func _process(_delta: float) -> void:
	text = "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS))


func _input(event: InputEvent) -> void:
	if not GameConfig.DEBUG:
		return
	if event is InputEventKey and event.pressed and event.keycode == GameConfig.KEY_FPS_TOGGLE:
		visible = not visible
