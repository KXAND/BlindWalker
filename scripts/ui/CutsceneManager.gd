class_name CutsceneManager
extends Node

## 简单演出控制器：播放字幕/相机 tween，并临时禁用玩家输入。
@export var subtitle_label: Label
@export var cutscene_camera: Camera3D
@export var cutscene_duration: float = 2.0

var _active_tween: Tween
var _camera_start_position: Vector3


func _ready() -> void:
	if not subtitle_label:
		_create_subtitle_label()


func play(cutscene_id: String) -> void:
	if _active_tween:
		_active_tween.kill()

	EventBus.cutscene_started.emit(cutscene_id)
	_set_player_input(false)
	_show_subtitle(_subtitle_for(cutscene_id))

	var camera := _resolve_camera()
	if not camera:
		_finish_cutscene(cutscene_id)
		return

	cutscene_camera = camera
	_camera_start_position = camera.position
	camera.current = true

	var offset := Vector3(0.0, 0.0, 0.25) if cutscene_id == "intro" else Vector3(0.0, 0.0, -0.25)
	camera.position = _camera_start_position + offset
	_active_tween = create_tween()
	_active_tween.tween_property(camera, "position", _camera_start_position, cutscene_duration)
	_active_tween.tween_callback(_finish_cutscene.bind(cutscene_id))


func _finish_cutscene(cutscene_id: String) -> void:
	_hide_subtitle()
	_set_player_input(true)
	EventBus.cutscene_ended.emit(cutscene_id)
	_active_tween = null


func _set_player_input(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if node.has_method("set_input_enabled"):
			node.call("set_input_enabled", enabled)
		for child in node.get_children():
			if child.has_method("set_input_enabled"):
				child.call("set_input_enabled", enabled)


func _show_subtitle(text: String) -> void:
	if not subtitle_label:
		return
	subtitle_label.text = text
	subtitle_label.visible = true


func _hide_subtitle() -> void:
	if subtitle_label:
		subtitle_label.visible = false


func _subtitle_for(cutscene_id: String) -> String:
	match cutscene_id:
		"intro":
			return "失去视觉，用盲杖、触摸和声音找到回家的路。"
		"outro":
			return "你到达了目的地。黑暗中仍然有路可走。"
	return ""


func _resolve_camera() -> Camera3D:
	if cutscene_camera:
		return cutscene_camera

	var viewport_camera := get_viewport().get_camera_3d()
	if viewport_camera:
		return viewport_camera

	for node in get_tree().root.find_children("*", "Camera3D", true, false):
		var camera := node as Camera3D
		if camera and camera.current:
			return camera
	return null


func _create_subtitle_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CutsceneCanvasLayer"
	add_child(layer)

	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.visible = false
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.anchor_left = 0.15
	subtitle_label.anchor_right = 0.85
	subtitle_label.anchor_top = 0.78
	subtitle_label.anchor_bottom = 0.92
	subtitle_label.offset_left = 0.0
	subtitle_label.offset_right = 0.0
	subtitle_label.offset_top = 0.0
	subtitle_label.offset_bottom = 0.0
	layer.add_child(subtitle_label)
