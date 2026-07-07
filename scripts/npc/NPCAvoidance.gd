class_name NPCAvoidance
extends Node

## 盲杖进入 NPC 避让区时，让 NPC 临时横移一步；不负责 NPC 的路径巡逻。
@export var avoid_distance: float = 1.0
@export var cooldown_time: float = 2.0
@export var avoid_duration: float = 0.35
@export var avoid_area_radius: float = 0.9

var _npc_base: NPCBase
var _avoid_area: Area3D
var _cooldown: float = 0.0
var _avoiding: bool = false


func _ready() -> void:
	_npc_base = get_parent() as NPCBase
	_create_avoid_area()
	call_deferred("_connect_to_cane_tip")


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)


func _create_avoid_area() -> void:
	_avoid_area = Area3D.new()
	_avoid_area.name = "AvoidanceArea"
	_avoid_area.monitorable = true
	_avoid_area.monitoring = true
	add_child(_avoid_area)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = avoid_area_radius
	shape.shape = sphere
	_avoid_area.add_child(shape)


func _connect_to_cane_tip() -> void:
	for node in get_tree().get_nodes_in_group("cane_tip"):
		if node is Area3D:
			var cane_area := node as Area3D
			if not cane_area.area_entered.is_connected(_on_cane_area_entered):
				cane_area.area_entered.connect(_on_cane_area_entered.bind(cane_area))
			if not cane_area.area_exited.is_connected(_on_cane_area_exited):
				cane_area.area_exited.connect(_on_cane_area_exited.bind(cane_area))


func _on_cane_area_entered(area: Area3D, cane_area: Area3D) -> void:
	if area != _avoid_area or _cooldown > 0.0 or _avoiding or not _npc_base:
		return

	EventBus.cane_entered_npc_zone.emit(_npc_base.npc_name)
	_start_avoidance(cane_area)


func _on_cane_area_exited(area: Area3D, _cane_area: Area3D) -> void:
	if area == _avoid_area and _npc_base:
		EventBus.cane_exited_npc_zone.emit(_npc_base.npc_name)


func _start_avoidance(cane_area: Area3D) -> void:
	_avoiding = true
	_cooldown = cooldown_time
	_npc_base.pause_pathing()

	var cane_forward := -cane_area.global_transform.basis.z
	cane_forward.y = 0.0
	if cane_forward.length_squared() < 0.001:
		cane_forward = Vector3.FORWARD
	cane_forward = cane_forward.normalized()

	var lateral := cane_forward.cross(Vector3.UP).normalized()
	var away := _npc_base.global_position - cane_area.global_position
	away.y = 0.0
	if lateral.dot(away) < 0.0:
		lateral = -lateral

	var tween := create_tween()
	tween.tween_property(_npc_base, "global_position", _npc_base.global_position + lateral * avoid_distance, avoid_duration)
	tween.tween_callback(_finish_avoidance)


func _finish_avoidance() -> void:
	_avoiding = false
	if _npc_base:
		_npc_base.resume_pathing()
