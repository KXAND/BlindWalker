class_name DistanceHUD
extends CanvasLayer
## 任务点距离 HUD：实时显示玩家到下一个未到达任务点的距离。
## 使用绝对路径 get_node() 跨 Viewport 获取引用，彻底规避 @export / group 的跨 Viewport 问题。

const DISTANCE_FORMAT := "%s: %.0f 米"
const PLAYER_PATH   := "/root/Main/GameViewportContainer/GameViewport/GameRoot/Player"
const TARGETS_ROOT  := "/root/Main/GameViewportContainer/GameViewport/GameRoot/DialogueTriggers"
const LOADING_SCENE := "res://scenes/main/LoadingScreen.tscn"

var _targets: Array[Node3D] = []
var _target_names: PackedStringArray = [
	"GroundFloor",
	"ShopClosed",
	"Endpoint",
]
var _labels: PackedStringArray = ["小区楼下", "小卖部", "路口小店"]
var _cutscene_ids: PackedStringArray = ["ground_floor", "shop_closed", "endpoint"]
var _current_index: int = 0
var _all_done: bool = false
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 3
	_resolve_targets()
	_build_ui()
	_set_hud_visible(false)
	EventBus.cutscene_ended.connect(_on_cutscene_ended)


func _resolve_targets() -> void:
	_targets.clear()
	for tname in _target_names:
		var node := get_node_or_null(TARGETS_ROOT + "/" + tname) as Node3D
		_targets.append(node)


func _process(_delta: float) -> void:
	var player := get_node_or_null(PLAYER_PATH) as Node3D
	if not player:
		_set_hud_visible(false)
		return

	if _all_done or _current_index >= _targets.size():
		_set_hud_visible(false)
		return

	var target: Node3D = _targets[_current_index]
	if not target:
		_set_hud_visible(false)
		return

	var distance := player.global_position.distance_to(target.global_position)
	_label.text = DISTANCE_FORMAT % [_labels[_current_index], distance]
	_set_hud_visible(true)


func _on_cutscene_ended(cutscene_id: String) -> void:
	if _all_done or _current_index >= _cutscene_ids.size():
		return

	if cutscene_id == _cutscene_ids[_current_index]:
		_current_index += 1
		if _current_index >= _cutscene_ids.size() or _current_index >= _targets.size():
			_all_done = true
			_set_hud_visible(false)
			if cutscene_id == &"endpoint":
				_end_game()


func _end_game() -> void:
	await get_tree().create_timer(1.0).timeout
	if AudioManager:
		AudioManager.stop_all()
	GameState.reset_to_loading()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _set_hud_visible(p_visible: bool) -> void:
	if _panel:
		_panel.visible = p_visible
	if _label:
		_label.visible = p_visible


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
	_label.text = "准备中..."

	_panel.add_child(_label)
	add_child(_panel)
