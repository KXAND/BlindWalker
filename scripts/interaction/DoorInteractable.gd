class_name DoorInteractable
extends "res://scripts/interaction/Interactable.gd"
## 门交互：在打开/关闭状态之间切换门轴角度，并在关门前检查玩家占位。

@export var pivot_path: NodePath = ^"../Pivot"
@export var open_angle_degrees: float = 90.0
@export var animation_duration: float = 0.35
@export var open_sound_id: StringName = &"door_open"
@export var close_sound_id: StringName = &"door_close"
## 关门占位阻止盒：定义在关闭状态的门轴局部空间中，用于拒绝会卡住玩家的关门。
@export var closed_block_center_local: Vector3 = Vector3(0.0, -0.15, 0.45)
@export var closed_block_half_extents: Vector3 = Vector3(0.55, 1.35, 0.75)

var _pivot: Node3D
var _closed_rotation_degrees: Vector3
var _is_open: bool = false
var _is_animating: bool = false


func _ready() -> void:
	super._ready()
	requires_line_of_sight = false
	_pivot = get_node_or_null(pivot_path) as Node3D
	if not _pivot:
		push_error("%s: pivot_path missing or invalid" % get_path())
		return
	_closed_rotation_degrees = _pivot.rotation_degrees


func can_interact(player: Node3D) -> bool:
	return not _is_animating and super.can_interact(player)


func get_interaction_prompt(_player: Node3D) -> String:
	if _is_open:
		return "按 E 关门"
	return "按 E 开门"


func interact(player: Node3D) -> bool:
	if not can_interact(player) or not _pivot:
		return false
	if _is_open and _would_block_player_when_closed(player):
		if GameConfig.DEBUG:
			print("[DEBUG][DoorInteractable] close blocked path=%s" % get_path())
		return false

	var target_open := not _is_open
	_is_open = target_open
	_is_animating = true
	if target_open:
		_play_interaction_sound(open_sound_id)

	var target_rotation := _closed_rotation_degrees
	if target_open:
		target_rotation.y += open_angle_degrees

	var tween := create_tween()
	tween.tween_property(_pivot, "rotation_degrees", target_rotation, animation_duration)
	tween.finished.connect(_on_tween_finished.bind(target_open))
	if GameConfig.DEBUG:
		print("[DEBUG][DoorInteractable] toggled path=%s open=%s" % [get_path(), str(target_open)])
	return true


func is_open() -> bool:
	return _is_open


func is_animating() -> bool:
	return _is_animating


func _on_tween_finished(opened: bool) -> void:
	_is_animating = false
	if not opened:
		_play_interaction_sound(close_sound_id)


func _would_block_player_when_closed(player: Node3D) -> bool:
	if not player or not _pivot:
		return false
	var closed_transform := _closed_pivot_global_transform()
	for point in _player_occupancy_points(player):
		if _point_inside_closed_block(point, closed_transform):
			return true
	return false


func _player_occupancy_points(player: Node3D) -> Array[Vector3]:
	const PLAYER_CENTER_HEIGHT := 0.95
	const PLAYER_RADIUS := 0.35
	const PLAYER_HALF_HEIGHT := 0.6
	var center := player.global_position + Vector3.UP * PLAYER_CENTER_HEIGHT
	var right := player.global_transform.basis.x.normalized() * PLAYER_RADIUS
	var forward := player.global_transform.basis.z.normalized() * PLAYER_RADIUS
	var up := Vector3.UP * PLAYER_HALF_HEIGHT
	return [
		center,
		center + right,
		center - right,
		center + forward,
		center - forward,
		center + up,
		center - up,
	]


func _point_inside_closed_block(world_point: Vector3, closed_transform: Transform3D) -> bool:
	var local := closed_transform.affine_inverse() * world_point - closed_block_center_local
	return absf(local.x) <= closed_block_half_extents.x \
			and absf(local.y) <= closed_block_half_extents.y \
			and absf(local.z) <= closed_block_half_extents.z


func _closed_pivot_global_transform() -> Transform3D:
	var parent := _pivot.get_parent_node_3d()
	var local_transform := _pivot.transform
	local_transform.basis = Basis.from_euler(_degrees_to_radians(_closed_rotation_degrees))
	if parent:
		return parent.global_transform * local_transform
	return local_transform


func _degrees_to_radians(value: Vector3) -> Vector3:
	return Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))
