class_name CaneSystem
extends Node3D
## 盲杖系统：局部 yaw/pitch 挥动、RayCast 碰撞检测、全杖 Area3D 防穿模、尖端 NPC 触发器。
## 不直接控制玩家视角——溢出量返回给 InputManager。

@export var cone_angle: float = GameConfig.CANE_SWEEP_ANGLE
@export var pitch_angle: float = 60.0
@export var cane_length: float = GameConfig.CANE_LENGTH

var _current_angle: float = 0.0
var _current_pitch: float = 0.0
var _rod: MeshInstance3D
var _body_area: Area3D
var _tip_area: Area3D
var _was_hitting: bool = false


func _ready() -> void:
	_create_visuals()
	_update_visual_length(cane_length)


func apply_sweep(delta: Vector2) -> Vector2:
	if not GameState.is_input_enabled():
		return Vector2.ZERO

	# 返回值是盲杖局部边界没有消耗掉的弧度余量，InputManager 再把它转成玩家/视角旋转。
	var half_yaw := deg_to_rad(cone_angle * 0.5)
	var half_pitch := deg_to_rad(pitch_angle * 0.5)
	var yaw_result := _apply_axis(_current_angle, delta.x, -half_yaw, half_yaw)
	var pitch_result := _apply_axis(_current_pitch, delta.y, -half_pitch, half_pitch)

	_current_angle = yaw_result.x
	_current_pitch = pitch_result.x
	rotation = Vector3(_current_pitch, _current_angle, 0.0)
	return Vector2(yaw_result.y, pitch_result.y)


func get_tip_area() -> Area3D:
	return _tip_area


func _physics_process(_delta: float) -> void:
	var from := global_position
	var to := global_transform * Vector3(0.0, 0.0, -cane_length)

	var parent_body := get_parent() as CollisionObject3D
	var exclude_rid := parent_body.get_rid() if parent_body else RID()
	var space_state := get_world_3d().direct_space_state
	var result := RaycastUtil.query_body(space_state, from, to, exclude_rid)

	if result.is_empty():
		_update_visual_length(cane_length)
		_was_hitting = false
		return

	var hit_point: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var hit_collider: Object = result["collider"]
	var hit_distance := global_position.distance_to(hit_point)
	_update_visual_length(hit_distance)
	EventBus.cane_hit_object.emit(_object_name(hit_collider), hit_point, hit_normal)
	if not _was_hitting:
		EventBus.audio_requested.emit("cane_hit", hit_point, 0.0)
	_was_hitting = true


func _apply_axis(current: float, delta: float, min_value: float, max_value: float) -> Vector2:
	var target := current + delta
	var clamped_value := clampf(target, min_value, max_value)
	return Vector2(clamped_value, target - clamped_value)


func _create_visuals() -> void:
	# --- Visual rod: MeshInstance3D + BoxMesh ---
	_rod = MeshInstance3D.new()
	_rod.name = "CaneRod"
	_rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.035, 0.035, cane_length)
	_rod.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.3
	_rod.material_override = mat
	add_child(_rod)

	# --- Full body Area3D: BoxShape3D, wall/terrain collision layer ---
	_body_area = Area3D.new()
	_body_area.name = "CaneBodyArea"
	_body_area.monitoring = true
	_body_area.monitorable = false
	var body_shape := CollisionShape3D.new()
	body_shape.name = "BodyCollisionShape"
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(0.035, 0.035, cane_length)
	body_shape.shape = body_box
	_body_area.add_child(body_shape)
	add_child(_body_area)

	# --- Tip Area3D: SphereShape3D, NPC collision layer, cane_tip group ---
	_tip_area = Area3D.new()
	_tip_area.name = "CaneTipArea"
	_tip_area.monitoring = true
	_tip_area.monitorable = true
	_tip_area.add_to_group("cane_tip")
	var tip_shape := CollisionShape3D.new()
	tip_shape.name = "TipCollisionShape"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	tip_shape.shape = sphere
	_tip_area.add_child(tip_shape)
	add_child(_tip_area)


func _update_visual_length(length: float) -> void:
	var visible_length := maxf(length, 0.05)

	# Update visual rod
	if _rod:
		var box_mesh := _rod.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(0.035, 0.035, visible_length)
		_rod.position = Vector3(0.0, -0.25, -visible_length * 0.5)

	# Update body collision shape
	if _body_area:
		var shape_node := _body_area.get_node_or_null("BodyCollisionShape")
		if shape_node and shape_node is CollisionShape3D:
			var box := (shape_node as CollisionShape3D).shape as BoxShape3D
			if box:
				box.size = Vector3(0.035, 0.035, visible_length)
		_body_area.position = Vector3(0.0, -0.25, -visible_length * 0.5)

	# Update tip area position
	if _tip_area:
		_tip_area.position = Vector3(0.0, -0.25, -visible_length)


func _object_name(object: Object) -> String:
	if object is Node:
		return (object as Node).name
	return "Object"
