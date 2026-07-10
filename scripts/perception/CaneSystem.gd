class_name CaneSystem
extends Node3D
## 盲杖系统：实体杖身，全长不可缩短、不穿模。
## 用 intersect_shape（引擎形状重叠检测）覆盖整根杖身。
## 两种穿模场景都处理：
##   1. 鼠标扫动 → 分步推进到最后一个安全姿态
##   2. 玩家位移 → 搜索最近安全姿态；无解时临时缩短可视长度防止画面穿墙

@export var cone_angle: float = GameConfig.CANE_SWEEP_ANGLE
@export var pitch_angle: float = 60.0
@export var cane_length: float = GameConfig.CANE_LENGTH

var _target_angle: float = 0.0
var _target_pitch: float = 0.0
var _current_angle: float = 0.0
var _current_pitch: float = 0.0
var _rod: MeshInstance3D
var _body_area: Area3D
var _tip_area: Area3D
var _was_hitting: bool = false
var _cane_shape: BoxShape3D
var _contact_shape: BoxShape3D
var _visible_length: float = 0.0

const _RaycastUtil = preload("res://scripts/core/RaycastUtil.gd")

const ROD_THICKNESS := 0.035
const ROD_Y_OFFSET := -0.25
const TIP_RADIUS := 0.18
const LAYER_ENVIRONMENT := 1
const MAX_SWEEP_STEP := deg_to_rad(3.0)
const RECOVERY_STEP := deg_to_rad(6.0)
const HIT_RETRACT := 0.04
const MIN_VISIBLE_LENGTH := 0.2


func _ready() -> void:
	_cane_shape = BoxShape3D.new()
	_cane_shape.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, cane_length)
	_contact_shape = BoxShape3D.new()
	_visible_length = cane_length
	_create_visuals()
	_set_visible_length(cane_length)


func apply_sweep(delta: Vector2) -> Vector2:
	if not GameState.is_input_enabled():
		return Vector2.ZERO

	var half_yaw := deg_to_rad(cone_angle * 0.5)
	var half_pitch := deg_to_rad(pitch_angle * 0.5)

	var yaw_result := _apply_axis(_target_angle, delta.x, -half_yaw, half_yaw)
	var pitch_result := _apply_axis(_target_pitch, delta.y, -half_pitch, half_pitch)

	_target_angle = yaw_result.x
	_target_pitch = pitch_result.x

	return Vector2(yaw_result.y, pitch_result.y)


func get_tip_area() -> Area3D:
	return _tip_area


func _physics_process(_delta: float) -> void:
	var safe_pose := _advance_to_safe_pose(_current_angle, _current_pitch, _target_angle, _target_pitch)
	_current_angle = safe_pose.x
	_current_pitch = safe_pose.y

	# 玩家位移可能把整根杖带进墙里。此时不能直接应用当前姿态，需要重新找安全姿态。
	if _shape_overlaps(_current_angle, _current_pitch):
		var recovery_pose := _find_recovery_pose()
		_current_angle = recovery_pose.x
		_current_pitch = recovery_pose.y

	var full_length_safe := not _shape_overlaps(_current_angle, _current_pitch)
	rotation = Vector3(_current_pitch, _current_angle, 0.0)
	_set_visible_length(cane_length if full_length_safe else _blocked_visible_length())

	# --- 接触检测 + 音效 ---
	_detect_contact()


func _detect_contact() -> void:
	var parent_body := get_parent() as CollisionObject3D
	var exclude_rid := parent_body.get_rid() if parent_body else RID()
	var space_state := get_world_3d().direct_space_state

	# 用可视长度检测接触，避免应急缩短后仍按全长持续判定为穿墙。
	var rod_center := global_position + global_transform.basis * Vector3(0.0, ROD_Y_OFFSET, -_visible_length * 0.5)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _contact_shape
	shape_query.transform = Transform3D(global_transform.basis, rod_center)
	shape_query.collision_mask = LAYER_ENVIRONMENT
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	if exclude_rid:
		shape_query.exclude = [exclude_rid]

	var shape_results := space_state.intersect_shape(shape_query, 8)

	if shape_results.is_empty():
		_was_hitting = false
		return

	# 有接触：沿杖身方向补射线获取精确接触点
	var from := global_position + global_transform.basis * Vector3(0.0, ROD_Y_OFFSET, 0.0)
	var to := global_position + global_transform.basis * Vector3(0.0, ROD_Y_OFFSET, -_visible_length)
	var ray_result := _RaycastUtil.query_body(space_state, from, to, exclude_rid)

	var contact_point: Vector3
	var contact_normal: Vector3
	var hit_collider: Object

	if not ray_result.is_empty():
		contact_point = ray_result["position"]
		contact_normal = ray_result["normal"]
		hit_collider = ray_result["collider"]
	else:
		contact_point = rod_center
		contact_normal = Vector3.UP
		hit_collider = shape_results[0].collider

	EventBus.cane_hit_object.emit(_object_name(hit_collider), contact_point, contact_normal)
	if not _was_hitting:
		EventBus.audio_requested.emit("cane_hit", contact_point, 0.0)
	_was_hitting = true


## 从当前姿态分步靠近目标姿态，避免一次大位移直接跳进深重叠。
func _advance_to_safe_pose(from_angle: float, from_pitch: float, to_angle: float, to_pitch: float) -> Vector2:
	var max_delta := maxf(absf(to_angle - from_angle), absf(to_pitch - from_pitch))
	var steps := maxi(1, ceili(max_delta / MAX_SWEEP_STEP))
	var safe_pose := Vector2(from_angle, from_pitch)

	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var angle := lerpf(from_angle, to_angle, t)
		var pitch := lerpf(from_pitch, to_pitch, t)
		if _shape_overlaps(angle, pitch):
			return safe_pose
		safe_pose = Vector2(angle, pitch)

	return safe_pose


## 在玩家移动把杖带进障碍时，搜索离当前姿态最近的安全姿态。
func _find_recovery_pose() -> Vector2:
	var half_yaw := deg_to_rad(cone_angle * 0.5)
	var half_pitch := deg_to_rad(pitch_angle * 0.5)
	var best_pose := Vector2(_current_angle, _current_pitch)
	var best_score := INF

	var pitch_steps := ceili(pitch_angle / rad_to_deg(RECOVERY_STEP))
	var yaw_steps := ceili(cone_angle / rad_to_deg(RECOVERY_STEP))

	for pitch_index in range(-pitch_steps, pitch_steps + 1):
		var pitch := clampf(_current_pitch + float(pitch_index) * RECOVERY_STEP, -half_pitch, half_pitch)
		for yaw_index in range(-yaw_steps, yaw_steps + 1):
			var angle := clampf(_current_angle + float(yaw_index) * RECOVERY_STEP, -half_yaw, half_yaw)
			if _shape_overlaps(angle, pitch):
				continue
			var score := absf(angle - _current_angle) + absf(pitch - _current_pitch)
			if score < best_score:
				best_score = score
				best_pose = Vector2(angle, pitch)

	return best_pose


## 全长姿态无解时的最后防线：临时缩短可视杆，保证画面不穿墙。
func _blocked_visible_length() -> float:
	var parent_body := get_parent() as CollisionObject3D
	var exclude_rid := parent_body.get_rid() if parent_body else RID()
	var space_state := get_world_3d().direct_space_state
	var from := global_position + global_transform.basis * Vector3(0.0, ROD_Y_OFFSET, 0.0)
	var to := global_position + global_transform.basis * Vector3(0.0, ROD_Y_OFFSET, -cane_length)
	var ray_result := _RaycastUtil.query_body(space_state, from, to, exclude_rid)

	if ray_result.is_empty():
		return MIN_VISIBLE_LENGTH

	var hit_position: Vector3 = ray_result["position"]
	var length := from.distance_to(hit_position) - HIT_RETRACT
	return clampf(length, MIN_VISIBLE_LENGTH, cane_length)


func _set_visible_length(length: float) -> void:
	_visible_length = clampf(length, MIN_VISIBLE_LENGTH, cane_length)

	if _rod and _rod.mesh is BoxMesh:
		var box_mesh := _rod.mesh as BoxMesh
		box_mesh.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, _visible_length)
		_rod.position = Vector3(0.0, ROD_Y_OFFSET, -_visible_length * 0.5)

	_contact_shape.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, _visible_length)

	if _body_area:
		_body_area.position = Vector3(0.0, ROD_Y_OFFSET, -_visible_length * 0.5)
		var body_shape := _body_area.get_node_or_null("BodyCollisionShape") as CollisionShape3D
		if body_shape and body_shape.shape is BoxShape3D:
			var body_box := body_shape.shape as BoxShape3D
			body_box.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, _visible_length)

	if _tip_area:
		_tip_area.position = Vector3(0.0, ROD_Y_OFFSET, -_visible_length)


## 检测指定角度下杖身是否与环境重叠（intersect_shape 覆盖整根杖身）
func _shape_overlaps(angle: float, pitch: float) -> bool:
	var current_basis := global_transform.basis
	var parent_basis := current_basis * Basis.from_euler(rotation).inverse()
	var test_basis := parent_basis * Basis.from_euler(Vector3(pitch, angle, 0.0))

	var rod_center_local := Vector3(0.0, ROD_Y_OFFSET, -cane_length * 0.5)
	var rod_center_world := global_position + test_basis * rod_center_local

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _cane_shape
	query.transform = Transform3D(test_basis, rod_center_world)
	query.collision_mask = LAYER_ENVIRONMENT
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var parent_body := get_parent() as CollisionObject3D
	if parent_body:
		query.exclude = [parent_body.get_rid()]

	var space_state := get_world_3d().direct_space_state
	var results := space_state.intersect_shape(query, 8)
	return results.size() > 0


func _apply_axis(current: float, delta: float, min_value: float, max_value: float) -> Vector2:
	var target := current + delta
	var clamped_value := clampf(target, min_value, max_value)
	return Vector2(clamped_value, target - clamped_value)


func _create_visuals() -> void:
	_rod = MeshInstance3D.new()
	_rod.name = "CaneRod"
	_rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, cane_length)
	_rod.mesh = box_mesh
	_rod.position = Vector3(0.0, ROD_Y_OFFSET, -cane_length * 0.5)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.3
	_rod.material_override = mat
	add_child(_rod)

	_body_area = Area3D.new()
	_body_area.name = "CaneBodyArea"
	_body_area.monitoring = true
	_body_area.monitorable = false
	_body_area.position = Vector3(0.0, ROD_Y_OFFSET, -cane_length * 0.5)
	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyCollisionShape"
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, cane_length)
	body_shape.shape = body_box
	_body_area.add_child(body_shape)
	add_child(_body_area)

	_tip_area = Area3D.new()
	_tip_area.name = "CaneTipArea"
	_tip_area.monitoring = true
	_tip_area.monitorable = true
	_tip_area.add_to_group("cane_tip")
	_tip_area.position = Vector3(0.0, ROD_Y_OFFSET, -cane_length)
	var tip_shape := CollisionShape3D.new()
	tip_shape.name = "TipCollisionShape"
	var sphere := SphereShape3D.new()
	sphere.radius = TIP_RADIUS
	tip_shape.shape = sphere
	_tip_area.add_child(tip_shape)
	add_child(_tip_area)


func _object_name(object: Object) -> String:
	if object is Node:
		return (object as Node).name
	return "Object"
