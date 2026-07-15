class_name CaneSystem
extends Node3D
## 盲杖系统：实体杖身，全长不可缩短、不穿模。
## 用 intersect_shape（引擎形状重叠检测）覆盖整根杖身。
## 两种穿模场景都处理：
##   1. 鼠标扫动 → 分步推进到最后一个安全姿态
##   2. 玩家位移 → 搜索最近安全姿态；无解时临时缩短可视长度防止画面穿墙

@export var cone_angle: float = GameConfig.CANE_SWEEP_ANGLE
@export var pitch_angle: float = 120.0
@export var cane_length: float = GameConfig.CANE_LENGTH
@export var touch_memory_path: NodePath = ^"../TouchMemorySystem"

var _touch_memory: TouchMemorySystem = null
var _target_angle: float = 0.0
var _target_pitch: float = 0.0
var _current_angle: float = 0.0
var _current_pitch: float = 0.0
var _rod: MeshInstance3D
var _body_area: Area3D
var _tip_area: Area3D
var _cane_shape: BoxShape3D
var _contact_shape: BoxShape3D
var _visible_length: float = 0.0
var _has_last_cane_memory_point: bool = false
var _last_cane_memory_point: Vector3 = Vector3.ZERO
var _last_cane_memory_profile_id: StringName = &""
var _cane_touch_elapsed: float = 0.0
var _contact_break_elapsed: float = GameConfig.CANE_TOUCH_CONTACT_BREAK_GRACE
var _contact_segment_active: bool = false
var _pending_contact_info: Dictionary = {}

const _RaycastUtil = preload("res://scripts/core/RaycastUtil.gd")

const ROD_THICKNESS := 0.035
const ROD_Y_OFFSET := -0.25
const TIP_RADIUS := 0.18
const LAYER_ENVIRONMENT := 1
const MAX_SWEEP_STEP := deg_to_rad(3.0)
const RECOVERY_STEP := deg_to_rad(6.0)
const HIT_RETRACT := 0.04
const MIN_VISIBLE_LENGTH := 0.2
const SIDE_CONTACT_SCAN_RADIUS := 0.25
const SIDE_CONTACT_SAMPLES := 12


func _ready() -> void:
	_cane_shape = BoxShape3D.new()
	_cane_shape.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, cane_length)
	_contact_shape = BoxShape3D.new()
	_contact_shape.size = Vector3(ROD_THICKNESS, ROD_THICKNESS, cane_length)
	_visible_length = cane_length
	_create_visuals()
	_set_visible_length(cane_length)
	_touch_memory = get_node_or_null(touch_memory_path) as TouchMemorySystem


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


func _physics_process(delta: float) -> void:
	_cane_touch_elapsed += delta
	_pending_contact_info = {}

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

	var contact_info := _pending_contact_info
	if contact_info.is_empty():
		contact_info = _full_length_contact_info()
	if contact_info.is_empty():
		_set_visible_length(cane_length if full_length_safe else MIN_VISIBLE_LENGTH)
		_update_contact_segment(false, delta)
		return

	_update_contact_segment(true, delta)
	_set_visible_length(_blocked_visible_length(contact_info))
	_emit_contact_feedback(
		contact_info["collider"],
		contact_info["position"],
		contact_info["normal"]
	)


func _emit_contact_feedback(hit_collider: Object, contact_point: Vector3, contact_normal: Vector3) -> void:
	var profile: Resource = _ContactProfileProvider.resolve_profile(hit_collider, &"cane")
	var memory_spawned := _try_spawn_cane_touch_memory(contact_point, profile)
	if memory_spawned:
		EventBus.cane_hit_object.emit(_object_name(hit_collider), contact_point, contact_normal)
		var sound_id := _ContactProfileProvider.cane_sound_id(profile)
		if sound_id != &"":
			EventBus.audio_requested.emit(String(sound_id), contact_point, 0.0)
		elif GameConfig.DEBUG:
			print("[DEBUG][CaneSystem] no cane sound profile=%s reason=empty_sound_id" % _ContactProfileProvider.profile_id(profile))


func _try_spawn_cane_touch_memory(contact_point: Vector3, profile: Resource) -> bool:
	if not _touch_memory:
		return false
	var profile_id := _ContactProfileProvider.profile_id(profile)
	if not _should_spawn_cane_touch_memory(contact_point, profile_id):
		return false

	var cane_radius: float = GameConfig.CANE_TOUCH_MEMORY_RADIUS
	var cane_afterglow_radius: float = GameConfig.CANE_TOUCH_AFTERGLOW_RADIUS
	var spawned := _touch_memory.spawn_touch_memory(
		contact_point,
		cane_radius,
		GameConfig.CANE_TOUCH_MEMORY_LIFETIME,
		cane_afterglow_radius,
		GameConfig.CANE_TOUCH_MEMORY_LIFETIME * 2.0,
		_ContactProfileProvider.reveal_color(profile),
		&"cane",
		profile_id
	)

	if spawned:
		_contact_segment_active = true
		_has_last_cane_memory_point = true
		_last_cane_memory_point = contact_point
		_last_cane_memory_profile_id = profile_id
		_cane_touch_elapsed = 0.0
	return spawned


func _should_spawn_cane_touch_memory(contact_point: Vector3, profile_id: StringName) -> bool:
	if not _contact_segment_active:
		return true
	if not _has_last_cane_memory_point:
		return true
	if _last_cane_memory_profile_id != profile_id:
		return true
	if _last_cane_memory_point.distance_to(contact_point) < GameConfig.CANE_TOUCH_MEMORY_MIN_DISTANCE:
		return false
	return _cane_touch_elapsed >= GameConfig.CANE_TOUCH_MEMORY_COOLDOWN


func _update_contact_segment(has_contact: bool, delta: float) -> void:
	if has_contact:
		_contact_break_elapsed = 0.0
		return

	_contact_break_elapsed += delta
	if _contact_break_elapsed >= GameConfig.CANE_TOUCH_CONTACT_BREAK_GRACE:
		_contact_segment_active = false


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
			_pending_contact_info = _contact_info_for_pose(angle, pitch)
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


## 使用全长盲杖获取接触信息，避免可视杆缩短后丢失碰撞反馈。
func _full_length_contact_info() -> Dictionary:
	return _contact_info_for_basis(global_transform.basis)


## 获取指定目标姿态下的接触信息。用于“下一步会撞上”的预测反馈。
func _contact_info_for_pose(angle: float, pitch: float) -> Dictionary:
	return _contact_info_for_basis(_basis_for_pose(angle, pitch))


func _contact_info_for_basis(cane_basis: Basis) -> Dictionary:
	var parent_body := get_parent() as CollisionObject3D
	var exclude_rid := parent_body.get_rid() if parent_body else RID()
	var space_state := get_world_3d().direct_space_state
	var ray_result := _forward_surface_contact(space_state, cane_basis, exclude_rid)
	if not ray_result.is_empty():
		return ray_result

	var rod_center := global_position + cane_basis * Vector3(0.0, ROD_Y_OFFSET, -cane_length * 0.5)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _cane_shape
	shape_query.transform = Transform3D(cane_basis, rod_center)
	shape_query.collision_mask = LAYER_ENVIRONMENT
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	if exclude_rid:
		shape_query.exclude = [exclude_rid]

	var shape_results := space_state.intersect_shape(shape_query, 8)
	if shape_results.is_empty():
		return {}

	var side_result := _side_surface_contact(space_state, cane_basis, exclude_rid)
	if not side_result.is_empty():
		return side_result

	var rest_info := space_state.get_rest_info(shape_query)
	if not rest_info.is_empty():
		return {
			"position": rest_info.get("point", rest_info.get("position", rod_center)),
			"normal": rest_info.get("normal", Vector3.UP),
			"collider": rest_info.get("collider", null),
		}

	var contact_points := space_state.collide_shape(shape_query, 16)
	if not contact_points.is_empty():
		return {
			"position": _nearest_contact_point(contact_points, global_position),
			"normal": Vector3.UP,
			"collider": shape_results[0].collider,
		}

	# 极端重叠兜底：不要再把点放在杆中心，至少放在杖尖方向，避免显影绑定到整根盲杖。
	return {
		"position": global_position + cane_basis * Vector3(0.0, ROD_Y_OFFSET, -cane_length),
		"normal": Vector3.UP,
		"collider": shape_results[0].collider,
	}


## 细杆碰撞可能发生在杆身边缘；多条平行射线比单中心线更接近真实接触面。
func _forward_surface_contact(
	space_state: PhysicsDirectSpaceState3D,
	cane_basis: Basis,
	exclude_rid: RID
) -> Dictionary:
	var half_thickness := ROD_THICKNESS * 0.5
	var offsets := [
		Vector2.ZERO,
		Vector2(half_thickness, 0.0),
		Vector2(-half_thickness, 0.0),
		Vector2(0.0, half_thickness),
		Vector2(0.0, -half_thickness),
	]
	var best_result: Dictionary = {}
	var best_distance := INF

	for offset in offsets:
		var from := global_position + cane_basis * Vector3(offset.x, ROD_Y_OFFSET + offset.y, 0.0)
		var to := global_position + cane_basis * Vector3(offset.x, ROD_Y_OFFSET + offset.y, -cane_length)
		var result := _RaycastUtil.query_body(space_state, from, to, exclude_rid)
		if result.is_empty():
			continue

		var distance := from.distance_to(result["position"])
		if distance < best_distance:
			best_distance = distance
			best_result = {
				"position": result["position"],
				"normal": result["normal"],
				"collider": result["collider"],
			}

	return best_result


## 杖身侧面扫到柱子/墙角时，沿杆身采样并向横截面方向短射线求障碍物表面点。
func _side_surface_contact(
	space_state: PhysicsDirectSpaceState3D,
	cane_basis: Basis,
	exclude_rid: RID
) -> Dictionary:
	var x_axis := cane_basis.x.normalized()
	var y_axis := cane_basis.y.normalized()
	var side_dirs: Array[Vector3] = [
		x_axis,
		-x_axis,
		y_axis,
		-y_axis,
		(x_axis + y_axis).normalized(),
		(x_axis - y_axis).normalized(),
		(-x_axis + y_axis).normalized(),
		(-x_axis - y_axis).normalized(),
	]
	var best_result: Dictionary = {}
	var best_distance := INF

	for sample_index in range(SIDE_CONTACT_SAMPLES):
		var t := float(sample_index + 1) / float(SIDE_CONTACT_SAMPLES)
		var axis_point := global_position + cane_basis * Vector3(0.0, ROD_Y_OFFSET, -cane_length * t)
		for side_dir in side_dirs:
			var to: Vector3 = axis_point + side_dir * SIDE_CONTACT_SCAN_RADIUS
			var result := _RaycastUtil.query_body(space_state, axis_point, to, exclude_rid)
			if result.is_empty():
				continue

			var distance := axis_point.distance_to(result["position"])
			if distance < best_distance:
				best_distance = distance
				best_result = {
					"position": result["position"],
					"normal": result["normal"],
					"collider": result["collider"],
				}

	return best_result


func _nearest_contact_point(points: PackedVector3Array, reference: Vector3) -> Vector3:
	var best_point := points[0]
	var best_distance := reference.distance_to(best_point)
	for point in points:
		var distance := reference.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = point
	return best_point


## 全长姿态无解时的最后防线：临时缩短可视杆，保证画面不穿墙。
func _blocked_visible_length(contact_info: Dictionary) -> float:
	if contact_info.is_empty():
		return MIN_VISIBLE_LENGTH

	var from := global_position + global_transform.basis * Vector3(0.0, ROD_Y_OFFSET, 0.0)
	var hit_position: Vector3 = contact_info["position"]
	var length := from.distance_to(hit_position) - HIT_RETRACT
	return clampf(length, MIN_VISIBLE_LENGTH, cane_length)


func _is_floor_hit(normal: Vector3) -> bool:
	return normal.dot(Vector3.UP) > 0.85


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
	var test_basis := _basis_for_pose(angle, pitch)

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


func _basis_for_pose(angle: float, pitch: float) -> Basis:
	var current_basis := global_transform.basis
	var parent_basis := current_basis * Basis.from_euler(rotation).inverse()
	return parent_basis * Basis.from_euler(Vector3(pitch, angle, 0.0))


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
const _ContactProfileProvider = preload("res://scripts/interaction/ContactProfileProvider.gd")
