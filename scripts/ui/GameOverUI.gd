class_name GameOverUI
extends CanvasLayer
## 胜利/失败结局 UI —— 显示全屏提示并等待玩家按空格重玩。
## Issue #0013
##
## 重置序列（按空格后）：
##   AudioManager.stop_all() → 等 0.08s（Web Audio 缓冲）→ GameState.reset_to_loading() → reload_current_scene()
##
## 层级规划：
##   HealthUI = 1, CutsceneManager CanvasLayer = 5, GameOverUI = 10

var _panel: Panel
var _label: Label


func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()
	EventBus.game_state_changed.connect(_on_game_state_changed)


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "BackPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.name = "MessageLabel"
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 32)
	_panel.add_child(_label)


func _on_game_state_changed(_old_state: StringName, new_state: StringName) -> void:
	if new_state == &"SUCCESS":
		_label.text = "你到达了目的地\n按 [空格] 重玩"
		visible = true
	elif new_state == &"FAILURE":
		_label.text = "血量耗尽\n按 [空格] 重玩"
		visible = true


func _input(event: InputEvent) -> void:
	# 仅在 UI 可见时响应空格，不经过 GameState.is_input_enabled()
	# （该函数在 SUCCESS/FAILURE 下返回 false）
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_do_reset()


func _do_reset() -> void:
	visible = false
	AudioManager.stop_all()
	await get_tree().create_timer(0.08).timeout
	GameState.reset_to_loading()
	get_tree().reload_current_scene()
