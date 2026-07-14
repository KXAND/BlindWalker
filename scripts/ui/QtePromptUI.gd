class_name QtePromptUI
extends CanvasLayer
## 失衡踉跄 QTE 提示。只负责显示，不读取输入。

var _panel: Panel
var _label: Label
var _recovering: bool = false
var _pulse_time: float = 0.0

const PROMPT_TEXT := "SHIFT + SPACE"
const COLOR_WAITING := Color(1.0, 0.86, 0.18, 1.0)
const COLOR_HOLDING := Color(0.82, 1.0, 0.78, 1.0)


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
	_pulse_time += _delta
	_update_style()


func debug_is_prompt_visible() -> bool:
	return visible


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "QtePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -118.0
	_panel.offset_right = 118.0
	_panel.offset_top = 124.0
	_panel.offset_bottom = 168.0
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
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.text = PROMPT_TEXT
	_panel.add_child(_label)


func _on_unstable_stumbled(_qte_window: float) -> void:
	if visible:
		return
	_recovering = false
	_pulse_time = 0.0
	visible = true
	_update_style()


func _on_qte_progress(_progress: float, recovering: bool) -> void:
	_recovering = recovering
	_update_style()


func _on_get_up_started(_duration: float) -> void:
	_hide_prompt()


func _on_game_state_changed(_old_state: StringName, _new_state: StringName) -> void:
	_hide_prompt()


func _hide_prompt() -> void:
	_recovering = false
	visible = false


func _update_style() -> void:
	if not _panel or not _label:
		return
	_label.text = PROMPT_TEXT
	_panel.pivot_offset = _panel.size * 0.5
	var style := _panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if _recovering:
		_panel.scale = Vector2.ONE
		style.bg_color = Color(0.02, 0.12, 0.05, 0.78)
		style.border_color = COLOR_HOLDING
		_label.add_theme_color_override("font_color", COLOR_HOLDING)
	else:
		var pulse := (sin(_pulse_time * TAU * 3.0) + 1.0) * 0.5
		_panel.scale = Vector2.ONE * lerpf(0.96, 1.04, pulse)
		style.bg_color = Color(0.18, 0.12, 0.0, lerpf(0.62, 0.82, pulse))
		style.border_color = COLOR_WAITING
		_label.add_theme_color_override("font_color", COLOR_WAITING)
	_panel.add_theme_stylebox_override("panel", style)
