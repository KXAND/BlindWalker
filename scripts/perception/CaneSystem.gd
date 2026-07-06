class_name CaneSystem
extends Node3D

@export var cone_angle: float = GameConfig.CANE_SWEEP_ANGLE
@export var cane_length: float = GameConfig.CANE_LENGTH
@export var sweep_sensitivity: float = 0.005
@export var view_controller_path: NodePath = ^"../ViewController"

var input_enabled: bool = true

var _current_angle: float = 0.0
var _view_controller: ViewController
var _rod: CSGBox3D
var _tip_area: Area3D


func _ready() -> void:
	_view_controller = get_node_or_null(view_controller_path) as ViewController
	_create_visuals()
	_update_visual_length(cane_length)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		_apply_sweep(-event.relative.x * sweep_sensitivity)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func get_tip_area() -> Area3D:
	return _tip_area


func _physics_process(_delta: float) -> void:
	var from := global_position
	var to := global_transform * Vector3(0.0, 0.0, -cane_length)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var parent_body := get_parent() as CollisionObject3D
	if parent_body:
		query.exclude = [parent_body.get_rid()]

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		_update_visual_length(cane_length)
		return

	var hit_point: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var hit_collider: Object = result["collider"]
	var hit_distance := global_position.distance_to(hit_point)
	_update_visual_length(hit_distance)
	EventBus.cane_hit_object.emit(_object_name(hit_collider), hit_point, hit_normal)


func _apply_sweep(delta_angle: float) -> void:
	var half_cone := deg_to_rad(cone_angle * 0.5)
	var target_angle := _current_angle + delta_angle
	var clamped_angle := clampf(target_angle, -half_cone, half_cone)
	var overflow := target_angle - clamped_angle

	_current_angle = clamped_angle
	rotation.y = _current_angle

	if not is_zero_approx(overflow) and _view_controller:
		_view_controller.rotate_view(overflow, 0.0)


func _create_visuals() -> void:
	if not _rod:
		_rod = CSGBox3D.new()
		_rod.name = "CaneRod"
		_rod.use_collision = false
		add_child(_rod)

	if not _tip_area:
		_tip_area = Area3D.new()
		_tip_area.name = "CaneTipArea"
		_tip_area.monitoring = true
		_tip_area.monitorable = true
		_tip_area.add_to_group("cane_tip")
		add_child(_tip_area)

		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.18
		shape.shape = sphere
		_tip_area.add_child(shape)


func _update_visual_length(length: float) -> void:
	var visible_length := maxf(length, 0.05)
	if _rod:
		_rod.size = Vector3(0.035, 0.035, visible_length)
		_rod.position = Vector3(0.0, -0.25, -visible_length * 0.5)
	if _tip_area:
		_tip_area.position = Vector3(0.0, -0.25, -visible_length)


func _object_name(object: Object) -> String:
	if object is Node:
		return (object as Node).name
	return "Object"
