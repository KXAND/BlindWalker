class_name TutorialDismissButton
extends Control
## 教程关闭符号：圆形加叉，长按 TAB 时绘制外圈进度。

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(30.0, 30.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.38
	var base_color := Color(1.0, 1.0, 1.0, 0.7)
	var progress_color := Color(1.0, 0.86, 0.18, 1.0)
	draw_arc(center, radius, 0.0, TAU, 48, base_color, 2.0, true)
	if progress > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, progress_color, 3.0, true)

	var cross_extent := radius * 0.42
	draw_line(center + Vector2(-cross_extent, -cross_extent), center + Vector2(cross_extent, cross_extent), base_color, 2.0, true)
	draw_line(center + Vector2(cross_extent, -cross_extent), center + Vector2(-cross_extent, cross_extent), base_color, 2.0, true)
