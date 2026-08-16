class_name TrafficSystem
extends Node3D
## 场景级交通协调器，负责车辆冲击结算和致死后的道路边复活。

signal vehicle_impacted_player(hit_position: Vector3, impact_speed: float, damage: int)
signal player_respawned(respawn_position: Vector3)

var _pending_player: Node3D
var _pending_respawn_position: Vector3
var _has_pending_respawn: bool = false

const DAMAGE_SPEED_SQUARED_SCALE := 5.0


func _ready() -> void:
	EventBus.game_state_changed.connect(_on_game_state_changed)


func _exit_tree() -> void:
	if EventBus.game_state_changed.is_connected(_on_game_state_changed):
		EventBus.game_state_changed.disconnect(_on_game_state_changed)


func nearest_respawn_position(hit_position: Vector3) -> Vector3:
	var nearest_position := hit_position
	var nearest_distance_squared := INF
	for candidate in get_tree().get_nodes_in_group("traffic_respawn_point"):
		var point := candidate as Node3D
		if not point or not is_ancestor_of(point):
			continue
		var distance_squared := hit_position.distance_squared_to(point.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_position = point.global_position
	return nearest_position


func calculate_impact_damage(impact_speed: float) -> int:
	var horizontal_speed := maxf(impact_speed, 0.0)
	return roundi(DAMAGE_SPEED_SQUARED_SCALE * horizontal_speed * horizontal_speed)


func report_vehicle_impact(
		player: Node3D,
		hit_position: Vector3,
		impact_speed: float,
		impact_direction: Vector3
) -> bool:
	if not GameState.is_playing() or not is_instance_valid(player):
		return false
	var attributes := player.get_node_or_null("PlayerAttributes") as PlayerAttributes
	if not attributes or attributes.hp <= 0:
		return false
	var damage := calculate_impact_damage(impact_speed)
	if damage <= 0:
		return false

	var is_lethal := damage >= attributes.hp
	if is_lethal:
		# 必须先记录复活点；take_damage 会同步触发死亡和失败状态。
		_pending_player = player
		_pending_respawn_position = nearest_respawn_position(hit_position)
		_has_pending_respawn = true
	if GameConfig.DEBUG:
		print("[DEBUG][TrafficSystem] vehicle impact speed=%.2f damage=%d at %s" % [
			impact_speed,
			damage,
			hit_position,
		])
	vehicle_impacted_player.emit(hit_position, impact_speed, damage)
	attributes.take_damage_ignoring_gameplay_lock(damage)
	if attributes.hp > 0:
		var gait := player as GaitController
		if gait:
			var displacement := clampf(0.35 * maxf(impact_speed, 0.0), 0.0, 2.0)
			gait.apply_external_impact(damage, impact_direction, displacement)
	return true


func _on_game_state_changed(old_state: StringName, new_state: StringName) -> void:
	if old_state != &"FAILURE" or new_state != &"PLAYING" or not _has_pending_respawn:
		return
	if is_instance_valid(_pending_player):
		if _pending_player.has_method("teleport_to"):
			_pending_player.call("teleport_to", _pending_respawn_position)
		else:
			_pending_player.global_position = _pending_respawn_position
		if GameConfig.DEBUG:
			print("[DEBUG][TrafficSystem] player respawned at %s" % _pending_respawn_position)
		player_respawned.emit(_pending_respawn_position)
	_pending_player = null
	_has_pending_respawn = false
