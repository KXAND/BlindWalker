class_name DistanceHUD
extends CanvasLayer
## 任务点距离 HUD：实时显示玩家到下一个未到达任务点的距离。
## 任务顺序：小区楼下(GroundFloor) → 小卖部(ShopClosed) → 远处小卖部(StreetReturn)

# ---- 任务点定义（按剧情推进顺序） ----
const TASK_POINTS: Array[Dictionary] = [
	{ "id": "ground_floor", "position": Vector3(-28.7, 1.0, 14.5), "label": "小区楼下" },
	{ "id": "shop_closed",   "position": Vector3(10.0, 1.0, -10.0), "label": "小卖部" },
	{ "id": "street_return", "position": Vector3(15.0, 1.0, -15.0), "label": "远处小卖部" },
]

const DISTANCE_FORMAT := "%s: %.0f 米"

var _current_index: int = 0
var _all_done: bool = false
var _show_distance: bool = false
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 3
	_build_ui()
	_label.visible = false
	EventBus.cutscene_ended.connect(_on_cutscene_ended)


func _process(_delta: float) -> void:
	if not _show_distance or _all_done:
		_label.visible = false
		return

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		return

	var target_pos: Vector3 = TASK_POINTS[_current_index]["position"]
	var distance := player.global_position.distance_to(target_pos)
	_label.text = DISTANCE_FORMAT % [TASK_POINTS[_current_index]["label"], distance]
	_label.visible = true


func _on_cutscene_ended(cutscene_id: String) -> void:
	if cutscene_id == "intro_fullscreen":
		_show_distance = true
		return

	if _all_done:
		return

	if cutscene_id == TASK_POINTS[_current_index]["id"]:
		_current_index += 1
		if _current_index >= TASK_POINTS.size():
			_all_done = true
			_label.visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DistancePanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -200.0
	_panel.offset_right = -12.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = 38.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	_panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.name = "DistanceLabel"
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	_label.add_theme_constant_override("outline_size", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_panel.add_child(_label)
	add_child(_panel)
