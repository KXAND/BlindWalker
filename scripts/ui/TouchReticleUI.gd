class_name TouchReticleUI
extends CanvasLayer
## 左手触摸射线提示。只绘制 UI，不读取输入。

const RETICLE_LAYER := 3

var _reticle: Control


func _ready() -> void:
	layer = RETICLE_LAYER
	_build_reticle()


func _process(_delta: float) -> void:
	visible = GameState.is_input_enabled()


func _build_reticle() -> void:
	_reticle = _TouchReticle.new()
	_reticle.name = "TouchReticle"
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_reticle)


class _TouchReticle:
	extends Control

	const RETICLE_COLOR := Color(0.42, 0.78, 1.0, 0.86)
	const RETICLE_DIM_COLOR := Color(0.42, 0.78, 1.0, 0.28)
	const RETICLE_CENTER := Vector2(0.16, 0.54)

	func _draw() -> void:
		var viewport_size := get_viewport_rect().size
		var center := Vector2(viewport_size.x * RETICLE_CENTER.x, viewport_size.y * RETICLE_CENTER.y)
		var radius := clampf(minf(viewport_size.x, viewport_size.y) * 0.026, 14.0, 24.0)
		var line_width := 2.0

		draw_arc(center, radius, deg_to_rad(30), deg_to_rad(330), 48, RETICLE_DIM_COLOR, line_width, true)
		draw_arc(center, radius * 0.55, deg_to_rad(205), deg_to_rad(335), 20, RETICLE_COLOR, line_width, true)
		draw_circle(center, radius * 0.12, RETICLE_COLOR)

		var left_tip := center + Vector2(-radius * 1.15, 0.0)
		var right_tip := center + Vector2(radius * 0.9, 0.0)
		var top_tip := center + Vector2(0.0, -radius * 0.9)
		var bottom_tip := center + Vector2(0.0, radius * 0.9)
		draw_line(left_tip, center + Vector2(-radius * 0.42, 0.0), RETICLE_COLOR, line_width, true)
		draw_line(center + Vector2(radius * 0.38, 0.0), right_tip, RETICLE_DIM_COLOR, line_width, true)
		draw_line(top_tip, center + Vector2(0.0, -radius * 0.42), RETICLE_DIM_COLOR, line_width, true)
		draw_line(center + Vector2(0.0, radius * 0.42), bottom_tip, RETICLE_DIM_COLOR, line_width, true)

		var hand_base := center + Vector2(-radius * 2.1, radius * 0.15)
		draw_line(hand_base, center + Vector2(-radius * 1.25, -radius * 0.15), RETICLE_COLOR, line_width, true)
		draw_line(hand_base + Vector2(radius * 0.18, -radius * 0.32), center + Vector2(-radius * 1.05, -radius * 0.52), RETICLE_DIM_COLOR, line_width, true)
		draw_line(hand_base + Vector2(radius * 0.18, radius * 0.3), center + Vector2(-radius * 1.04, radius * 0.28), RETICLE_DIM_COLOR, line_width, true)
