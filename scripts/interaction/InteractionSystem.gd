class_name InteractionSystem
extends Node
## 通用互动焦点系统：只负责选择当前可互动对象、显示提示并转发互动请求。

@export var camera_path: NodePath = ^"../Head/Camera3D"
@export var touch_memory_path: NodePath = ^"../TouchMemorySystem"
@export var prompt_screen_offset: Vector2 = Vector2(0.0, -36.0)
@export var max_focus_distance: float = 3.0

const CANVAS_LAYER := 4

var _player: GaitController
var _camera: Camera3D
var _touch_memory: TouchMemorySystem
var _focus: Area3D
var _canvas_layer: CanvasLayer
var _prompt_panel: Panel
var _prompt_label: Label


func _ready() -> void:
	_player = get_parent() as GaitController
	_camera = get_node_or_null(camera_path) as Camera3D
	_touch_memory = get_node_or_null(touch_memory_path) as TouchMemorySystem
	_create_prompt_ui()


func _process(_delta: float) -> void:
	_focus = _select_focus()
	_update_prompt()


func try_interact() -> bool:
	if not GameState.is_input_enabled() or not _player:
		return false
	if _player.is_balance_view_locked():
		return false
	var focus := _select_focus()
	if not focus:
		return false
	if not _is_candidate_valid(focus, true):
		return false
	var interacted := bool(focus.call("interact", _player))
	if interacted:
		get_viewport().set_input_as_handled()
	return interacted


func debug_get_focus() -> Area3D:
	return _focus


func debug_is_prompt_visible() -> bool:
	return _prompt_panel != null and _prompt_panel.visible


func _select_focus() -> Area3D:
	if not _player or not _camera:
		return null
	var best: Area3D = null
	var best_angle := INF
	var best_distance := INF
	var best_priority := -2147483648

	for node in get_tree().get_nodes_in_group("interactable"):
		var interactable := node as Area3D
		if not interactable or not _has_interactable_api(interactable):
			continue
		if not _is_candidate_valid(interactable, true):
			continue

		var anchor := interactable.call("get_prompt_anchor") as Node3D
		var to_anchor := anchor.global_position - _camera.global_position
		var distance := to_anchor.length()
		var angle := _focus_angle_to(anchor.global_position)
		if _is_better_candidate(interactable, angle, distance, best_angle, best_distance, best_priority):
			best = interactable
			best_angle = angle
			best_distance = distance
			best_priority = int(interactable.get("interaction_priority"))

	return best


func _is_candidate_valid(interactable: Area3D, include_line_of_sight: bool) -> bool:
	if not is_instance_valid(interactable):
		return false
	if not bool(interactable.call("is_player_inside")):
		return false
	if not bool(interactable.call("can_interact", _player)):
		return false
	var anchor := interactable.call("get_prompt_anchor") as Node3D
	if not anchor:
		return false
	var distance := _camera.global_position.distance_to(anchor.global_position)
	if distance > max_focus_distance:
		return false
	var angle := _focus_angle_to(anchor.global_position)
	if angle > deg_to_rad(float(interactable.get("focus_angle_degrees"))):
		return false
	if include_line_of_sight and bool(interactable.get("requires_line_of_sight")) and not _has_line_of_sight(interactable, anchor):
		return false
	return true


func _is_better_candidate(
	interactable: Area3D,
	angle: float,
	distance: float,
	best_angle: float,
	best_distance: float,
	best_priority: int
) -> bool:
	const ANGLE_EPS := deg_to_rad(3.0)
	const DISTANCE_EPS := 0.25
	if angle < best_angle - ANGLE_EPS:
		return true
	if angle > best_angle + ANGLE_EPS:
		return false
	if distance < best_distance - DISTANCE_EPS:
		return true
	if distance > best_distance + DISTANCE_EPS:
		return false
	return int(interactable.get("interaction_priority")) > best_priority


func _focus_angle_to(world_position: Vector3) -> float:
	var forward := -_camera.global_transform.basis.z.normalized()
	var to_target := (world_position - _camera.global_position).normalized()
	return acos(clampf(forward.dot(to_target), -1.0, 1.0))


func _has_line_of_sight(interactable: Area3D, anchor: Node3D) -> bool:
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_camera.global_position, anchor.global_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _line_of_sight_excludes()
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var collider := result.get("collider") as Node
	if not collider:
		return true
	return _node_related_to(collider, interactable) or _node_related_to(collider, interactable.call("get_reveal_target") as Node)


func _line_of_sight_excludes() -> Array[RID]:
	var excludes: Array[RID] = []
	if _player:
		excludes.append(_player.get_rid())
	var cane := _player.get_node_or_null("CaneSystem") if _player else null
	if cane:
		for child in cane.find_children("*", "CollisionObject3D", true, false):
			var collision := child as CollisionObject3D
			if collision:
				excludes.append(collision.get_rid())
	return excludes


func _node_related_to(node: Node, target: Node) -> bool:
	if not node or not target:
		return false
	if node == target:
		return true
	if target.is_ancestor_of(node):
		return true
	if node.is_ancestor_of(target):
		return true
	return false


func _update_prompt() -> void:
	if not _prompt_panel:
		return
	if not _focus or not bool(_focus.get("show_prompt")) or not _is_focus_revealed(_focus):
		_prompt_panel.visible = false
		return
	var anchor := _focus.call("get_prompt_anchor") as Node3D
	if not anchor or _camera.is_position_behind(anchor.global_position):
		_prompt_panel.visible = false
		return
	_prompt_label.text = String(_focus.call("get_interaction_prompt", _player))
	var screen_pos := _camera.unproject_position(anchor.global_position) + prompt_screen_offset
	_prompt_panel.position = screen_pos - _prompt_panel.size * 0.5
	_prompt_panel.visible = true


func _is_focus_revealed(interactable: Area3D) -> bool:
	if not _touch_memory:
		return false
	return _touch_memory.are_any_points_revealed(interactable.call("get_reveal_points"))


func _has_interactable_api(node: Node) -> bool:
	return node.has_method("is_player_inside") \
			and node.has_method("can_interact") \
			and node.has_method("get_prompt_anchor") \
			and node.has_method("get_reveal_target") \
			and node.has_method("get_reveal_points") \
			and node.has_method("get_interaction_prompt") \
			and node.has_method("interact")


func _create_prompt_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "InteractionPromptLayer"
	_canvas_layer.layer = CANVAS_LAYER
	add_child(_canvas_layer)

	_prompt_panel = Panel.new()
	_prompt_panel.name = "InteractionPromptPanel"
	_prompt_panel.visible = false
	_prompt_panel.custom_minimum_size = Vector2(120, 34)
	_canvas_layer.add_child(_prompt_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_prompt_panel.add_child(margin)

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82, 1.0))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_prompt_label.add_theme_constant_override("outline_size", 3)
	margin.add_child(_prompt_label)
