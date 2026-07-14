class_name QtePromptUI
extends CanvasLayer
## 失衡踉跄 QTE 提示。只负责显示，不读取输入。

var _panel: Panel
var _label: Label
var _remaining: float = 0.0
var _progress: float = 0.0
var _recovering: bool = false


func _ready() -> void:
	layer = 4
	visible = false
	_build_ui()
	EventBus.player_unstable_stumbled.connect(_on_unstable_stumbled)
	EventBus.player_recovery_qte_progress.connect(_on_qte_progress)
	EventBus.player_balance_recovered.connect(_hide_prompt)
	EventBus.player_fall_started.connect(_hide_prompt)
	EventBus.player_get_up_started.connect(_on_get_up_started)
	EventBus.game_state_changed.connect(_on_game_state_changed)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_text()


func debug_is_prompt_visible() -> bool:
	return visible


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "QtePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -220.0
	_panel.offset_right = 220.0
	_panel.offset_top = -96.0
	_panel.offset_bottom = -36.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	style.border_color = Color(1.0, 1.0, 1.0, 0.86)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.name = "QteLabel"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	_panel.add_child(_label)


func _on_unstable_stumbled(qte_window: float) -> void:
	_remaining = qte_window
	_progress = 0.0
	_recovering = false
	visible = true
	_update_text()


func _on_qte_progress(progress: float, recovering: bool) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	_recovering = recovering
	_remaining = (1.0 - _progress) * GameConfig.UNSTABLE_STUMBLE_QTE_WINDOW
	_update_text()


func _on_get_up_started(_duration: float) -> void:
	_hide_prompt()


func _on_game_state_changed(_old_state: StringName, _new_state: StringName) -> void:
	_hide_prompt()


func _hide_prompt() -> void:
	_remaining = 0.0
	_progress = 0.0
	_recovering = false
	visible = false


func _update_text() -> void:
	var direction := "恢复中" if _recovering else "失衡中"
	_label.text = "%s  SHIFT + SPACE  失衡 %.0f%%  剩余 %.1fs" % [
		direction,
		_progress * 100.0,
		_remaining
	]
