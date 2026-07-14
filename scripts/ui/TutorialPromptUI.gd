class_name TutorialPromptUI
extends CanvasLayer
## 上下文教程显示层。只负责卡片、关闭提示和 TAB 长按确认。

signal dismissed()

const DISMISS_KEY := KEY_TAB
const DISMISS_HOLD_SECONDS := 0.8

var _hold_elapsed: float = 0.0
var _panel: Panel
var _title_label: Label
var _body_label: Label
var _dismiss_hint_label: Label
var _dismiss_button: TutorialDismissButton


func _ready() -> void:
	layer = 4
	_build_ui()
	hide_prompt()


func _process(delta: float) -> void:
	if not is_prompt_visible():
		return
	if Input.is_key_pressed(DISMISS_KEY):
		_hold_elapsed = minf(_hold_elapsed + delta, DISMISS_HOLD_SECONDS)
		_dismiss_button.progress = _hold_elapsed / DISMISS_HOLD_SECONDS
		if _hold_elapsed >= DISMISS_HOLD_SECONDS:
			hide_prompt()
			dismissed.emit()
	else:
		_reset_hold()


func show_prompt(title: String, body: String) -> void:
	_title_label.text = title
	_body_label.text = body
	_reset_hold()
	_panel.visible = true


func hide_prompt() -> void:
	_reset_hold()
	if _panel:
		_panel.visible = false


func is_prompt_visible() -> bool:
	return _panel and _panel.visible


func dismiss_progress() -> float:
	return _hold_elapsed / DISMISS_HOLD_SECONDS


func dismiss_hint_text() -> String:
	return _dismiss_hint_label.text if _dismiss_hint_label else ""


func _reset_hold() -> void:
	_hold_elapsed = 0.0
	if _dismiss_button:
		_dismiss_button.progress = 0.0


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "TutorialPanel"
	_panel.visible = false
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 28.0
	_panel.offset_top = 28.0
	_panel.offset_right = 388.0
	_panel.offset_bottom = 212.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.03, 0.82)
	style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "TutorialMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "TutorialVBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.name = "TutorialTitle"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.52, 1.0))
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_title_label.add_theme_constant_override("outline_size", 3)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.name = "TutorialBody"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	_body_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_body_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_body_label)

	_dismiss_hint_label = Label.new()
	_dismiss_hint_label.name = "TutorialDismissHint"
	_dismiss_hint_label.text = "长按 %s 关闭" % OS.get_keycode_string(DISMISS_KEY)
	_dismiss_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dismiss_hint_label.add_theme_font_size_override("font_size", 13)
	_dismiss_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.64))
	_dismiss_hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_dismiss_hint_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_dismiss_hint_label)

	_dismiss_button = TutorialDismissButton.new()
	_dismiss_button.name = "TutorialDismissButton"
	_dismiss_button.anchor_left = 1.0
	_dismiss_button.anchor_right = 1.0
	_dismiss_button.anchor_top = 0.0
	_dismiss_button.anchor_bottom = 0.0
	_dismiss_button.offset_left = -42.0
	_dismiss_button.offset_right = -12.0
	_dismiss_button.offset_top = 12.0
	_dismiss_button.offset_bottom = 42.0
	_panel.add_child(_dismiss_button)
