extends Node

const TrafficCrossingScript = preload("res://scripts/traffic/TrafficCrossing.gd")
const TrafficVehicleScript = preload("res://scripts/traffic/TrafficVehicle.gd")
const TrafficSystemScript = preload("res://scripts/traffic/TrafficSystem.gd")
const TrafficRespawnPointScript = preload("res://scripts/traffic/TrafficRespawnPoint.gd")
const FirstCrosswalkTrafficScene = preload("res://scenes/traffic/FirstCrosswalkTraffic.tscn")
const GaitControllerScript = preload("res://scripts/player/GaitController.gd")
const PlayerAttributesScript = preload("res://scripts/player/PlayerAttributes.gd")
const StreetAmbienceZoneScript = preload("res://scripts/traffic/StreetAmbienceZone.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_crossing_waits_for_vehicle_clearance_before_full_green()
	_test_crossing_plays_phase_specific_beep_loop()
	_test_crossing_has_no_always_visible_signal()
	_test_traffic_scene_configures_clearance_and_vehicle_sensors()
	await _test_clearance_area_tracks_moving_vehicle_body()
	_test_stopped_vehicle_waits_for_player_before_starting()
	_test_running_vehicle_brakes_and_green_vehicle_does_not_honk()
	_test_vehicle_clearing_brakes_or_commits_by_stopping_distance()
	_test_vehicle_provides_spatial_engine_and_horn_feedback()
	_test_nearest_traffic_respawn_point_is_selected()
	_test_impact_damage_scales_with_squared_speed()
	_test_nonfatal_vehicle_impacts_map_to_balance_states()
	_test_vehicle_contact_only_damages_once_until_rearmed()
	_test_lethal_vehicle_impact_revives_at_pending_traffic_point()
	_test_street_ambience_fades_with_distance_from_zone()
	_test_street_ambience_player_tracks_listener_distance()
	await _finish()


func _test_crossing_waits_for_vehicle_clearance_before_full_green() -> void:
	var crossing = TrafficCrossingScript.new()
	crossing.red_duration = 3.0
	crossing.green_duration = 16.0
	crossing.audio_enabled = false
	add_child(crossing)
	var clearing_vehicle := Node3D.new()
	add_child(clearing_vehicle)
	crossing.register_clearance_vehicle(clearing_vehicle)

	var observed_phases: Array[int] = []
	crossing.phase_changed.connect(func(phase: int) -> void: observed_phases.append(phase))
	_expect_equal(crossing.get_traffic_phase(), TrafficCrossingScript.TrafficPhase.VEHICLE_FLOW, "过街点默认从车辆通行期开始")
	_expect_false(crossing.should_vehicles_stop(), "行人红灯时车辆不应停车")

	crossing.advance_cycle(3.0)
	_expect_equal(crossing.get_traffic_phase(), TrafficCrossingScript.TrafficPhase.VEHICLE_CLEARING, "红灯计时结束后应先进入车辆清空准备期")
	_expect_true(crossing.should_vehicles_stop(), "车辆清空准备期应阻止后续车辆越过停止线")
	_expect_false(crossing.is_pedestrian_green(), "清空区仍有车辆时不得宣布行人绿灯")
	_expect_equal(crossing.get_active_beep_sound_id(), &"traffic_red", "车辆清空准备期继续使用慢速提示音")

	crossing.advance_cycle(5.0)
	_expect_equal(crossing.get_traffic_phase(), TrafficCrossingScript.TrafficPhase.VEHICLE_CLEARING, "清空区有车时准备期不应按固定时间结束")
	crossing.unregister_clearance_vehicle(clearing_vehicle)
	_expect_true(crossing.is_pedestrian_green(), "最后一辆车离开清空区后才能宣布行人绿灯")
	_expect_equal(crossing.get_active_beep_sound_id(), &"traffic_green", "正式绿灯使用快速提示音")

	crossing.advance_cycle(15.9)
	_expect_true(crossing.is_pedestrian_green(), "绿灯未满 16 秒时不得提前结束")
	crossing.advance_cycle(0.1)
	_expect_equal(crossing.get_traffic_phase(), TrafficCrossingScript.TrafficPhase.VEHICLE_FLOW, "完整绿灯结束后回到车辆通行期")
	_expect_equal(observed_phases, [
		TrafficCrossingScript.TrafficPhase.VEHICLE_CLEARING,
		TrafficCrossingScript.TrafficPhase.PEDESTRIAN_GREEN,
		TrafficCrossingScript.TrafficPhase.VEHICLE_FLOW,
	], "相位事件应完整表达清空、绿灯和恢复通车")
	crossing.queue_free()
	clearing_vehicle.queue_free()


func _test_crossing_plays_phase_specific_beep_loop() -> void:
	var crossing = TrafficCrossingScript.new()
	crossing.red_duration = 1.0
	crossing.green_duration = 16.0
	add_child(crossing)

	_expect_equal(crossing.get_active_beep_sound_id(), &"traffic_red", "行人红灯使用慢速提示音")
	_expect_true(crossing.is_beep_playing(), "过街点启动后应循环播放相位提示音")
	crossing.advance_cycle(1.0)
	_expect_true(crossing.is_pedestrian_green(), "清空区为空时准备阶段应立即完成")
	_expect_equal(crossing.get_active_beep_sound_id(), &"traffic_green", "行人绿灯使用快速提示音")
	_expect_true(crossing.is_beep_playing(), "切换相位后提示音应继续播放")
	crossing.queue_free()


func _test_crossing_has_no_always_visible_signal() -> void:
	var traffic_scene := FirstCrosswalkTrafficScene.instantiate()
	var crossing := traffic_scene.get_node("Crossing")
	_expect_true(crossing.get_node_or_null("RedIndicator") == null, "路口不应包含常亮红灯指示节点")
	_expect_true(crossing.get_node_or_null("GreenIndicator") == null, "路口不应包含常亮绿灯指示节点")
	_expect_false(_contains_always_visible_signal(crossing), "路口模型不应使用自发光材质或灯光泄露信号状态")
	traffic_scene.free()


func _test_traffic_scene_configures_clearance_and_vehicle_sensors() -> void:
	var traffic_scene := FirstCrosswalkTrafficScene.instantiate()
	add_child(traffic_scene)
	var crossing := traffic_scene.get_node("Crossing") as TrafficCrossing
	_expect_near(crossing.red_duration, 16.0, 0.001, "实际关卡应提供完整 16 秒行人红灯")
	_expect_near(crossing.green_duration, 16.0, 0.001, "实际关卡应提供完整 16 秒行人绿灯")
	var clearance_area := traffic_scene.get_node_or_null("CrosswalkClearanceArea") as Area3D
	_expect_true(clearance_area != null, "实际关卡必须配置横道车辆清空区")
	if clearance_area:
		_expect_equal(clearance_area.collision_mask, 4, "清空区只监测车辆实体层")

	for vehicle_path in ["NorthboundLane/NorthboundCar", "SouthboundLane/SouthboundCar"]:
		var vehicle := traffic_scene.get_node(vehicle_path) as TrafficVehicle
		_expect_near(vehicle.base_speed, 8.0, 0.001, "实际关卡车辆巡航速度应为 8 m/s")
		_expect_near(vehicle.acceleration, 3.5, 0.001, "实际关卡车辆应平滑加速到巡航速度")
		_expect_near(vehicle.clearance_speed, 6.0, 0.001, "清空车辆目标速度不得超过 6 m/s")
		var forward_detection := vehicle.get_node_or_null("ForwardDetection") as Area3D
		var impact_area := vehicle.get_node_or_null("ImpactArea") as Area3D
		var physical_body := vehicle.get_node_or_null("PhysicalBody") as AnimatableBody3D
		_expect_true(forward_detection != null, "%s 必须具有独立前向检测区" % vehicle.name)
		_expect_true(impact_area != null, "%s 必须具有独立撞击区" % vehicle.name)
		_expect_true(physical_body != null, "%s 必须具有实体车身" % vehicle.name)
		if forward_detection:
			var forward_shape := forward_detection.get_node("CollisionShape3D") as CollisionShape3D
			var forward_box := forward_shape.shape as BoxShape3D
			_expect_near(forward_box.size.x, 2.7, 0.001, "前向检测走廊宽度应为 2.7 米")
			_expect_near(forward_box.size.z, 2.5, 0.001, "前向检测走廊长度应为 2.5 米")
			_expect_near(forward_shape.position.z, -3.15, 0.001, "前向检测走廊应从车头开始")
			_expect_true(forward_shape.position.z < 0.0, "前向检测走廊必须位于车辆本地前方")
			var emergency_braking_distance := (
				vehicle.base_speed * vehicle.base_speed
				/ (2.0 * vehicle.emergency_deceleration)
			)
			_expect_true(
				emergency_braking_distance > forward_box.size.z,
				"紧急制动距离必须大于探测走廊，运行中的车辆才不会保证停在玩家前"
			)
		if impact_area and physical_body:
			var impact_box := (impact_area.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
			var body_box := (physical_body.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
			_expect_true(impact_box.size.x <= body_box.size.x + 0.1, "撞击区应紧贴车身而不是作为预警区")
			_expect_true(impact_box.size.z <= body_box.size.z + 0.1, "撞击区长度应紧贴车身")
			_expect_equal(physical_body.collision_layer, 4, "车辆实体应使用独立碰撞层")
			vehicle.progress = vehicle.stop_progress
			var clearance_shape := clearance_area.get_node("CollisionShape3D") as CollisionShape3D
			var clearance_box := clearance_shape.shape as BoxShape3D
			var distance_from_clearance_center := absf(
				(vehicle.global_position - clearance_shape.global_position).dot(
					clearance_shape.global_transform.basis.z.normalized()
				)
			)
			var required_separation := clearance_box.size.z * 0.5 + body_box.size.z * 0.5
			_expect_true(
				distance_from_clearance_center > required_separation,
				"%s 停在停止线时车身必须完全位于清空区外" % vehicle.name
			)
	traffic_scene.queue_free()


func _test_clearance_area_tracks_moving_vehicle_body() -> void:
	await get_tree().process_frame
	var traffic_scene := FirstCrosswalkTrafficScene.instantiate()
	add_child(traffic_scene)
	var crossing := traffic_scene.get_node("Crossing") as TrafficCrossing
	var vehicle := traffic_scene.get_node("NorthboundLane/NorthboundCar") as TrafficVehicle
	var body := vehicle.get_node("PhysicalBody") as AnimatableBody3D
	crossing.set_process(false)
	(traffic_scene.get_node("SouthboundLane/SouthboundCar") as TrafficVehicle).set_physics_process(false)

	vehicle.progress = 30.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var occupancy: Dictionary = crossing.get("_clearance_vehicles")
	_expect_true(occupancy.has(body.get_instance_id()), "车辆进入横道后物理清空区必须记录车身")

	vehicle.progress = 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	occupancy = crossing.get("_clearance_vehicles")
	_expect_false(occupancy.has(body.get_instance_id()), "车辆节点离开横道后物理清空区必须移除车身")
	traffic_scene.queue_free()
	await get_tree().process_frame


func _test_stopped_vehicle_waits_for_player_before_starting() -> void:
	var crossing = TrafficCrossingScript.new()
	crossing.audio_enabled = false
	add_child(crossing)
	var lane := _create_test_lane()
	var vehicle = TrafficVehicleScript.new()
	vehicle.crossing = crossing
	vehicle.audio_enabled = false
	lane.add_child(vehicle)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0.0, 0.0, -2.0)

	var horn_events: Array[bool] = []
	vehicle.horn_requested.connect(func() -> void: horn_events.append(true))
	vehicle.register_forward_player(player)
	vehicle.advance_vehicle(0.5)
	_expect_equal(vehicle.get_motion_state(), TrafficVehicleScript.MotionState.STOPPED, "红灯放行但前方有玩家时车辆应保持停止")
	_expect_near(vehicle.get_current_speed(), 0.0, 0.001, "等待玩家时车辆速度应保持为零")
	_expect_equal(horn_events.size(), 1, "车辆首次因玩家无法起步时应立即鸣笛")

	vehicle.unregister_forward_player(player)
	vehicle.advance_vehicle(0.49)
	_expect_equal(vehicle.get_motion_state(), TrafficVehicleScript.MotionState.STOPPED, "前方刚清空时车辆仍应等待空闲确认")
	vehicle.advance_vehicle(0.01)
	_expect_equal(vehicle.get_motion_state(), TrafficVehicleScript.MotionState.STARTING, "前方连续空闲 0.5 秒后车辆才允许起步")
	_expect_true(vehicle.get_current_speed() > 0.0, "进入起步状态后速度应平滑增加")

	player.queue_free()
	vehicle.queue_free()
	lane.queue_free()
	crossing.queue_free()


func _test_running_vehicle_brakes_and_green_vehicle_does_not_honk() -> void:
	var crossing = TrafficCrossingScript.new()
	crossing.audio_enabled = false
	add_child(crossing)
	var lane := _create_test_lane()
	var vehicle = TrafficVehicleScript.new()
	vehicle.crossing = crossing
	vehicle.current_speed = 5.0
	vehicle.audio_enabled = false
	lane.add_child(vehicle)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0.0, 0.0, -4.0)
	var horn_events: Array[bool] = []
	vehicle.horn_requested.connect(func() -> void: horn_events.append(true))
	vehicle.register_forward_player(player)

	vehicle.advance_vehicle(0.1)
	_expect_equal(vehicle.get_motion_state(), TrafficVehicleScript.MotionState.BRAKING, "运行车辆发现玩家后应进入紧急制动")
	_expect_near(vehicle.get_current_speed(), 4.5, 0.001, "紧急制动应按配置连续降低速度")
	_expect_equal(horn_events.size(), 1, "运行车辆首次发现玩家时应立即鸣笛")

	var green_lane := _create_test_lane()
	var green_vehicle = TrafficVehicleScript.new()
	green_vehicle.crossing = crossing
	green_vehicle.audio_enabled = false
	green_lane.add_child(green_vehicle)
	var green_horn_events: Array[bool] = []
	green_vehicle.horn_requested.connect(func() -> void: green_horn_events.append(true))
	green_vehicle.register_forward_player(player)
	crossing.advance_cycle(crossing.red_duration)
	green_vehicle.advance_vehicle(1.0)
	_expect_true(crossing.is_pedestrian_green(), "清空区为空后应进入行人绿灯")
	_expect_equal(green_vehicle.get_motion_state(), TrafficVehicleScript.MotionState.STOPPED, "绿灯期间车辆应依法停车")
	_expect_equal(green_horn_events.size(), 0, "绿灯停车车辆不得向合法过街玩家鸣笛")

	player.queue_free()
	vehicle.queue_free()
	green_vehicle.queue_free()
	lane.queue_free()
	green_lane.queue_free()
	crossing.queue_free()


func _test_vehicle_clearing_brakes_or_commits_by_stopping_distance() -> void:
	var crossing = TrafficCrossingScript.new()
	crossing.red_duration = 0.1
	crossing.audio_enabled = false
	add_child(crossing)
	var clearing_vehicle := Node3D.new()
	add_child(clearing_vehicle)
	crossing.register_clearance_vehicle(clearing_vehicle)
	crossing.advance_cycle(0.1)
	_expect_true(crossing.is_vehicle_clearing(), "占用区有车时应保持车辆清空准备期")

	var braking_lane := _create_test_lane()
	var braking_vehicle = TrafficVehicleScript.new()
	braking_vehicle.crossing = crossing
	braking_vehicle.stop_progress = 10.0
	braking_vehicle.clearance_end_progress = 16.0
	braking_vehicle.current_speed = 5.0
	braking_vehicle.audio_enabled = false
	braking_lane.add_child(braking_vehicle)
	braking_vehicle.progress = 0.0
	for _step in range(80):
		braking_vehicle.advance_vehicle(0.1)
	_expect_false(braking_vehicle.is_committed_to_crossing(), "制动距离小于停止线剩余距离时车辆不应承诺通过")
	_expect_equal(braking_vehicle.get_motion_state(), TrafficVehicleScript.MotionState.STOPPED, "可停车车辆最终应停在停止线")
	_expect_near(braking_vehicle.progress, 10.0, 0.01, "可停车车辆不得停在人行横道内")
	_expect_near(braking_vehicle.get_current_speed(), 0.0, 0.001, "停止线前车辆速度应归零")

	var committed_lane := _create_test_lane()
	var committed_vehicle = TrafficVehicleScript.new()
	committed_vehicle.crossing = crossing
	committed_vehicle.stop_progress = 10.0
	committed_vehicle.clearance_end_progress = 16.0
	committed_vehicle.current_speed = 5.0
	committed_vehicle.audio_enabled = false
	committed_lane.add_child(committed_vehicle)
	committed_vehicle.progress = 9.0
	committed_vehicle.advance_vehicle(0.1)
	_expect_true(committed_vehicle.is_committed_to_crossing(), "制动距离超过停止线剩余距离时车辆应承诺通过")
	_expect_true(committed_vehicle.get_current_speed() > 5.0, "承诺通过车辆应平滑加速到清空目标速度")

	clearing_vehicle.queue_free()
	braking_vehicle.queue_free()
	committed_vehicle.queue_free()
	braking_lane.queue_free()
	committed_lane.queue_free()
	crossing.queue_free()


func _test_vehicle_provides_spatial_engine_and_horn_feedback() -> void:
	var crossing = TrafficCrossingScript.new()
	crossing.audio_enabled = false
	add_child(crossing)
	var lane := _create_test_lane()
	var vehicle = TrafficVehicleScript.new()
	vehicle.crossing = crossing
	lane.add_child(vehicle)
	_expect_true(vehicle.is_engine_audio_playing(), "动态车辆应持续播放可定位的 3D 引擎声")
	var idle_pitch: float = vehicle.get_engine_pitch_scale()

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	vehicle.register_forward_player(player)
	vehicle.advance_vehicle(0.1)
	_expect_true(vehicle.is_horn_audio_playing(), "车辆首次因玩家阻挡时应播放独立 3D 鸣笛声")

	vehicle.unregister_forward_player(player)
	vehicle.current_speed = vehicle.base_speed
	vehicle.update_audio_feedback()
	_expect_true(vehicle.get_engine_pitch_scale() > idle_pitch, "车辆行驶声的音高应随速度增加")

	player.queue_free()
	vehicle.queue_free()
	lane.queue_free()
	crossing.queue_free()


func _contains_always_visible_signal(root: Node) -> bool:
	if root is Light3D:
		return true
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface_index)
				if material is BaseMaterial3D and material.emission_enabled:
					return true
	for child in root.get_children():
		if _contains_always_visible_signal(child):
			return true
	return false


func _create_test_lane() -> Path3D:
	var lane := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0.0, 0.0, 40.0))
	lane.curve = curve
	add_child(lane)
	return lane


func _test_nearest_traffic_respawn_point_is_selected() -> void:
	var traffic_system = TrafficSystemScript.new()
	add_child(traffic_system)
	var west_point = TrafficRespawnPointScript.new()
	west_point.position = Vector3(-6.0, 0.0, 0.0)
	traffic_system.add_child(west_point)
	var east_point = TrafficRespawnPointScript.new()
	east_point.position = Vector3(6.0, 0.0, 0.0)
	traffic_system.add_child(east_point)

	_expect_equal(traffic_system.nearest_respawn_position(Vector3(-4.0, 0.0, 0.0)), Vector3(-6.0, 0.0, 0.0), "碰撞点靠西时选择西侧道路边复活点")
	_expect_equal(traffic_system.nearest_respawn_position(Vector3(5.0, 0.0, 0.0)), Vector3(6.0, 0.0, 0.0), "碰撞点靠东时选择东侧道路边复活点")
	traffic_system.queue_free()


func _test_impact_damage_scales_with_squared_speed() -> void:
	var traffic_system = TrafficSystemScript.new()
	_expect_equal(traffic_system.calculate_impact_damage(1.0), 5, "1 m/s 相对速度应造成 5 点伤害")
	_expect_equal(traffic_system.calculate_impact_damage(2.0), 20, "2 m/s 相对速度应造成 20 点伤害")
	_expect_equal(traffic_system.calculate_impact_damage(3.0), 45, "3 m/s 相对速度应造成 45 点伤害")
	_expect_equal(traffic_system.calculate_impact_damage(4.0), 80, "4 m/s 相对速度应造成 80 点伤害")
	_expect_equal(traffic_system.calculate_impact_damage(5.0), 125, "5 m/s 相对速度必须足以击倒满血玩家")
	traffic_system.free()


func _test_nonfatal_vehicle_impacts_map_to_balance_states() -> void:
	GameState.reset_to_loading()
	GameState.set_playing()
	var traffic_system = TrafficSystemScript.new()
	add_child(traffic_system)

	var light_player := _create_test_player()
	traffic_system.report_vehicle_impact(light_player, light_player.global_position, 1.0, Vector3.RIGHT)
	_expect_equal(light_player.get_node("PlayerAttributes").hp, 95, "低速撞击应按平方公式扣除 HP")
	_expect_equal(light_player.debug_balance_state(), &"light_stumble", "1–9 点撞击应触发轻踉跄")
	_expect_near(light_player.debug_external_impact_remaining_distance(), 0.35, 0.001, "低速撞击应记录速度相关的物理位移")

	var unstable_player := _create_test_player()
	GameState.set_gameplay_locked(true)
	traffic_system.report_vehicle_impact(unstable_player, unstable_player.global_position, 2.0, Vector3.FORWARD)
	_expect_equal(unstable_player.get_node("PlayerAttributes").hp, 80, "交通伤害不应被剧情输入锁忽略")
	_expect_equal(unstable_player.debug_balance_state(), &"unstable_stumble", "10–35 点撞击应触发失衡踉跄")
	_expect_near(unstable_player.debug_external_impact_remaining_distance(), 0.7, 0.001, "中速撞击应产生更长位移")
	GameState.set_gameplay_locked(false)

	var falling_player := _create_test_player()
	traffic_system.report_vehicle_impact(falling_player, falling_player.global_position, 3.0, Vector3.LEFT)
	_expect_equal(falling_player.get_node("PlayerAttributes").hp, 55, "3 m/s 撞击应造成 45 点伤害")
	_expect_equal(falling_player.debug_balance_state(), &"falling", "36–99 点撞击应直接触发摔倒")
	_expect_near(falling_player.debug_external_impact_remaining_distance(), 1.05, 0.001, "摔倒撞击仍应使用速度相关位移")

	light_player.queue_free()
	unstable_player.queue_free()
	falling_player.queue_free()
	traffic_system.queue_free()


func _test_vehicle_contact_only_damages_once_until_rearmed() -> void:
	GameState.reset_to_loading()
	GameState.set_playing()
	var traffic_system = TrafficSystemScript.new()
	add_child(traffic_system)
	var player := _create_test_player()
	var attributes := player.get_node("PlayerAttributes") as PlayerAttributes
	var lane := _create_test_lane()
	var vehicle = TrafficVehicleScript.new()
	vehicle.audio_enabled = false
	vehicle.traffic_system = traffic_system
	vehicle.current_speed = 2.0
	lane.add_child(vehicle)

	vehicle.register_impact_player(player)
	vehicle.register_impact_player(player)
	_expect_equal(attributes.hp, 80, "同一次持续接触只能结算一次伤害")
	vehicle.unregister_impact_player(player)
	vehicle.advance_vehicle(0.2)
	vehicle.register_impact_player(player)
	_expect_equal(attributes.hp, 80, "分离不足 0.3 秒时不得重新结算")
	vehicle.unregister_impact_player(player)
	vehicle.advance_vehicle(0.3)
	vehicle.current_speed = 2.0
	vehicle.register_impact_player(player)
	_expect_equal(attributes.hp, 60, "持续分离满 0.3 秒后再次接触应重新结算")

	vehicle.queue_free()
	lane.queue_free()
	player.queue_free()
	traffic_system.queue_free()


func _test_lethal_vehicle_impact_revives_at_pending_traffic_point() -> void:
	GameState.reset_to_loading()
	GameState.set_playing()
	GameState.set_gameplay_locked(true)

	var player = GaitControllerScript.new()
	player.name = "Player"
	player.set_physics_process(false)
	var attributes = PlayerAttributesScript.new()
	attributes.name = "PlayerAttributes"
	player.add_child(attributes)
	add_child(player)

	var traffic_system = TrafficSystemScript.new()
	add_child(traffic_system)
	var safe_point = TrafficRespawnPointScript.new()
	safe_point.position = Vector3(7.0, 0.0, 1.0)
	traffic_system.add_child(safe_point)

	traffic_system.report_vehicle_impact(player, Vector3(5.0, 0.0, 1.0), 5.0, Vector3.RIGHT)
	_expect_equal(attributes.hp, 0, "致死车辆碰撞应无视 gameplay 锁清空 HP")
	_expect_equal(GameState.current_state, GameState.State.FAILURE, "车辆致死应进入既有失败状态")

	GameState.set_gameplay_locked(false)
	attributes.revive()
	GameState.revive()
	_expect_equal(player.global_position, Vector3(7.0, 0.0, 1.0), "失败后选择重生应传送到记录的交通复活点")
	traffic_system.queue_free()
	player.queue_free()


func _create_test_player() -> GaitController:
	var player = GaitControllerScript.new()
	player.name = "Player"
	player.set_physics_process(false)
	var attributes = PlayerAttributesScript.new()
	attributes.name = "PlayerAttributes"
	player.add_child(attributes)
	add_child(player)
	return player


func _test_street_ambience_fades_with_distance_from_zone() -> void:
	var ambience_zone = StreetAmbienceZoneScript.new()
	ambience_zone.half_extents = Vector3(2.0, 1.0, 5.0)
	ambience_zone.fade_distance = 5.0
	ambience_zone.audio_enabled = false
	add_child(ambience_zone)

	_expect_near(ambience_zone.volume_linear_for_position(Vector3(1.0, 0.0, 0.0)), 1.0, 0.001, "街区底噪区内部保持正常音量")
	_expect_near(ambience_zone.volume_linear_for_position(Vector3(4.5, 0.0, 0.0)), 0.5, 0.001, "离开区域一半衰减距离时音量平滑降至一半")
	_expect_near(ambience_zone.volume_linear_for_position(Vector3(7.0, 0.0, 0.0)), 0.0, 0.001, "达到衰减距离后街区底噪静音")
	ambience_zone.queue_free()


func _test_street_ambience_player_tracks_listener_distance() -> void:
	var listener := Node3D.new()
	add_child(listener)
	var ambience_zone = StreetAmbienceZoneScript.new()
	ambience_zone.half_extents = Vector3(2.0, 1.0, 5.0)
	ambience_zone.fade_distance = 5.0
	ambience_zone.listener = listener
	add_child(ambience_zone)
	_expect_equal(
		ambience_zone.ambience_path,
		"res://assets/audio/sfx/street_ambience.ogg",
		"街区底噪默认应使用 Web 友好的 OGG 资源"
	)
	_expect_near(ambience_zone.base_volume_db, -3.0, 0.001, "街区底噪基础音量应清晰可闻")

	ambience_zone.update_ambience_volume()
	_expect_true(ambience_zone.is_ambience_playing(), "街区底噪区启动后应循环播放声音")
	_expect_near(ambience_zone.get_current_volume_linear(), 1.0, 0.001, "玩家在底噪区内部时播放器保持正常音量")
	listener.position = Vector3(7.0, 0.0, 0.0)
	ambience_zone.update_ambience_volume()
	_expect_near(ambience_zone.get_current_volume_linear(), 0.0, 0.001, "玩家远离街道后播放器应衰减到静音")
	ambience_zone.queue_free()
	listener.queue_free()


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected=%s actual=%s" % [message, expected, actual])


func _expect_true(value: bool, message: String) -> void:
	if not value:
		_failures.append("%s: expected=true actual=false" % message)


func _expect_false(value: bool, message: String) -> void:
	if value:
		_failures.append("%s: expected=false actual=true" % message)


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if not is_equal_approx(actual, expected) and absf(actual - expected) > tolerance:
		_failures.append("%s: expected=%f actual=%f" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[TEST][PASS] TrafficSystemTest")
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[TEST][FAIL] %s" % failure)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(1)
