extends Node3D
class_name TouchMemorySystem


## 触觉记忆系统 —— 多球显影/残影轮廓反馈
##
## 参考 Three.js 逻辑：
##   - 每次点击生成一个 显影球(active) + 一个 残影球(afterglow)
##   - 显影球：玩家远离时随时间缩小，靠近(<DIST_NEAR)时暂停
##   - 残影球：长期缓慢衰减，不受距离影响
##   - 新触摸不会清除旧轮廓，多球同时生效
##
## 着色器内对每个像素：
##   - 重建世界坐标
##   - 遍历所有球，取包含该像素的球的最大强度
##   - 强度 > 0 且在球内 → 做边缘检测 → 输出轮廓

# ---- 常量（与 Three.js 对应） ----

const _RaycastUtil = preload("res://scripts/core/RaycastUtil.gd")
const _TouchSphere = preload("res://scripts/core/TouchSphere.gd")

const MAX_SPHERES: int = 64
const INITIAL_RADIUS: float = 1.5
const ACTIVE_LIFE: float = 30.0
const DIST_NEAR: float = 10.0

const AFTERGLOW_RADIUS: float = 1.5
const AFTERGLOW_INIT_STRENGTH: float = 0.4
const AFTERGLOW_LIFE: float = 60.0


# ---- 可调参数 ----

@export_group("Debug", "debug_")
@export var debug_mode: bool = false
@export var debug_ambient: float = 0.15
@export var debug_afterglow_strength: float = 0.35  # 调试模式下的全局残影强度

@export_group("Feedback", "feedback_")
@export var feedback_color: Color = Color(0.4, 0.75, 1.0, 1.0)  # 轮廓发光色
@export var feedback_depth_threshold: float = 0.003
@export var feedback_surface_alpha: float = 0.055  # 圆柱等平滑表面缺少边缘时的最低显影强度

@export_group("Pinned Ring", "ring_")
@export var ring_color: Color = Color(1.0, 0.75, 0.25, 1.0)  # 固定环颜色（暖金色）
@export var ring_width: float = 0.10  # 环宽占显影球半径的比例

# ---- 内部 ----

var _camera: Camera3D = null
var _quad: MeshInstance3D = null
var _material: ShaderMaterial = null

# 显影球与残影球
var _active_spheres: Array[_TouchSphere] = []
var _afterglow_spheres: Array[_TouchSphere] = []
var _foot_reveal_sphere: _TouchSphere = null
var _pinned_memory_ids: Array[int] = []
var _next_memory_id: int = 0

# 调试用
var _debug_light: DirectionalLight3D = null
var _debug_ambient_stored: float = 0.0
var _environment: Environment = null


func _ready() -> void:
	_camera = _find_camera()
	if not _camera:
		push_error("TouchMemorySystem: 未找到 Camera3D")
		return

	_create_foot_reveal_sphere()
	_create_fullscreen_quad()
	_apply_debug_mode()


func _find_camera() -> Camera3D:
	var parent: Node = get_parent()
	if parent:
		var head: Node = parent.get_node_or_null("Head")
		if head:
			return head.get_node_or_null("Camera3D")
	return get_viewport().get_camera_3d()


func _create_fullscreen_quad() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "TouchFeedbackQuad"
	var quad_mesh := QuadMesh.new()
	quad_mesh.orientation = PlaneMesh.FACE_Z
	_quad.mesh = quad_mesh

	var shader := load("res://assets/shaders/touch_feedback.gdshader") as Shader
	if not shader:
		push_error("TouchMemorySystem: 无法加载 touch_feedback.gdshader")
		return

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.render_priority = 127

	_material.set_shader_parameter("edge_color", feedback_color)
	_material.set_shader_parameter("surface_alpha", feedback_surface_alpha)
	_material.set_shader_parameter("depth_threshold", feedback_depth_threshold)
	_material.set_shader_parameter("debug_mode", 1.0 if debug_mode else 0.0)
	_material.set_shader_parameter("debug_afterglow_strength", debug_afterglow_strength)
	_material.set_shader_parameter("camera_near", _camera.near)
	_material.set_shader_parameter("camera_far", _camera.far)
	_material.set_shader_parameter("inv_view_matrix", _get_inv_view_matrix())
	_material.set_shader_parameter("viewport_size", Vector2(_camera.get_viewport().size))
	_material.set_shader_parameter("ring_color", ring_color)
	_material.set_shader_parameter("ring_width", ring_width)

	_update_sphere_uniforms()

	_quad.material_override = _material
	_camera.add_child(_quad)
	_update_quad_transform()


func _update_quad_transform() -> void:
	if not _quad or not _camera:
		return

	var near: float = _camera.near + 0.01
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h: float = near * tan(fov_rad * 0.5)
	var aspect: float = float(_camera.get_viewport().size.x) / float(_camera.get_viewport().size.y)
	var half_w: float = half_h * aspect

	_quad.position = Vector3(0.0, 0.0, -near)
	_quad.scale = Vector3(half_w * 2.0, half_h * 2.0, 1.0)


func _get_inv_view_matrix() -> Projection:
	return Projection(_camera.global_transform)


func _create_foot_reveal_sphere() -> void:
	# 脚下球复用普通活动显影的全部视觉规则，只把生命周期改为常驻并持续跟随。
	_foot_reveal_sphere = _TouchSphere.new()
	_configure_active_reveal_visual(
		_foot_reveal_sphere,
		global_position,
		GameConfig.TOUCH_MEMORY_RADIUS,
		_ContactProfileProvider.reveal_color(null),
		&"default_contact"
	)
	_update_foot_reveal_from_ground()


func _update_foot_reveal_from_ground() -> void:
	if not _foot_reveal_sphere:
		return
	var player := get_parent() as Node3D
	if not player:
		return
	_foot_reveal_sphere.center = player.global_position
	var exclude_rid: RID = player.get_rid() if player is CharacterBody3D else RID()
	var result := _RaycastUtil.query_body(
		get_world_3d().direct_space_state,
		player.global_position + Vector3.UP * 1.5,
		player.global_position + Vector3.DOWN * 1.5,
		exclude_rid
	)
	if result.is_empty():
		_foot_reveal_sphere.color = _ContactProfileProvider.reveal_color(null)
		_foot_reveal_sphere.contact_profile_id = &"default_contact"
		return
	var profile := _ContactProfileProvider.resolve_profile(result["collider"], &"foot")
	_foot_reveal_sphere.center = result["position"]
	_foot_reveal_sphere.color = _ContactProfileProvider.reveal_color(profile)
	_foot_reveal_sphere.contact_profile_id = _ContactProfileProvider.profile_id(profile)


func _configure_active_reveal_visual(
	sphere: _TouchSphere,
	center: Vector3,
	radius: float,
	reveal_color: Color,
	contact_profile_id: StringName
) -> void:
	sphere.center = center
	sphere.radius = radius
	sphere.initial_radius = radius
	sphere.color = reveal_color
	sphere.contact_profile_id = contact_profile_id
	sphere.strength = 1.0


# ---- 球数据更新 ----

func _update_sphere_uniforms() -> void:
	if not _material:
		return

	# 脚下球与普通活动显影处于同一层级；普通临时显影在重叠时后写入并优先显示。
	# 固定球优先保留；普通临时球按“新→旧”写入，保证最新生成的显影球
	# 始终落在 64 槽渲染范围内，避免旧球积压把新显影挤出槽位。
	var all_spheres: Array[_TouchSphere] = []
	_append_render_spheres(all_spheres, _active_spheres, true)
	_append_render_spheres(all_spheres, _afterglow_spheres, true)
	if _foot_reveal_sphere:
		all_spheres.append(_foot_reveal_sphere)
	_append_render_spheres(all_spheres, _active_spheres, false, true)
	_append_render_spheres(all_spheres, _afterglow_spheres, false, true)

	var count: int = mini(all_spheres.size(), MAX_SPHERES)

	var pos_array := PackedVector3Array()
	var rad_array := PackedFloat32Array()
	var str_array := PackedFloat32Array()
	var color_array := PackedColorArray()
	var pinned_array := PackedFloat32Array()
	pos_array.resize(MAX_SPHERES)
	rad_array.resize(MAX_SPHERES)
	str_array.resize(MAX_SPHERES)
	color_array.resize(MAX_SPHERES)
	pinned_array.resize(MAX_SPHERES)

	for i in range(MAX_SPHERES):
		if i < count:
			var s: _TouchSphere = all_spheres[i]
			pos_array[i] = s.center
			rad_array[i] = s.radius
			str_array[i] = s.strength
			color_array[i] = s.color
			pinned_array[i] = 1.0 if s.is_pinned else 0.0
		else:
			pos_array[i] = Vector3.ZERO
			rad_array[i] = 0.0
			str_array[i] = 0.0
			color_array[i] = feedback_color
			pinned_array[i] = 0.0

	_material.set_shader_parameter("sphere_positions", pos_array)
	_material.set_shader_parameter("sphere_radii", rad_array)
	_material.set_shader_parameter("sphere_strengths", str_array)
	_material.set_shader_parameter("sphere_colors", color_array)
	_material.set_shader_parameter("sphere_pinned", pinned_array)
	_material.set_shader_parameter("sphere_count", count)
	_update_pinned_ring_uniforms()


## 固定环专用数组：按 memory_id 去重（活动球优先），每个记忆点只画一个环。
func _update_pinned_ring_uniforms() -> void:
	if not _material:
		return
	var pinned_spheres := _pinned_spheres_for_ring()
	var count: int = mini(pinned_spheres.size(), MAX_SPHERES)

	var pos_array := PackedVector3Array()
	var rad_array := PackedFloat32Array()
	var str_array := PackedFloat32Array()
	pos_array.resize(MAX_SPHERES)
	rad_array.resize(MAX_SPHERES)
	str_array.resize(MAX_SPHERES)

	for i in range(MAX_SPHERES):
		if i < count:
			var s: _TouchSphere = pinned_spheres[i]
			pos_array[i] = s.center
			rad_array[i] = s.radius
			str_array[i] = s.strength
		else:
			pos_array[i] = Vector3.ZERO
			rad_array[i] = 0.0
			str_array[i] = 0.0

	_material.set_shader_parameter("pinned_sphere_count", count)
	_material.set_shader_parameter("pinned_sphere_positions", pos_array)
	_material.set_shader_parameter("pinned_sphere_radii", rad_array)
	_material.set_shader_parameter("pinned_sphere_strengths", str_array)


func _pinned_spheres_for_ring() -> Array[_TouchSphere]:
	var result: Array[_TouchSphere] = []
	var seen: Dictionary = {}
	for sphere: _TouchSphere in _active_spheres:
		if sphere.is_pinned and not seen.has(sphere.memory_id):
			seen[sphere.memory_id] = true
			result.append(sphere)
	for sphere: _TouchSphere in _afterglow_spheres:
		if sphere.is_pinned and not seen.has(sphere.memory_id):
			seen[sphere.memory_id] = true
			result.append(sphere)
	return result


func _append_render_spheres(
	output: Array[_TouchSphere],
	spheres: Array[_TouchSphere],
	pinned: bool,
	newest_first: bool = false
) -> void:
	if newest_first:
		# 从新到旧追加：最新生成的球最先占槽，旧球超限时最后被挤出。
		for i in range(spheres.size() - 1, -1, -1):
			var sphere: _TouchSphere = spheres[i]
			if sphere.is_pinned == pinned:
				output.append(sphere)
		return
	for sphere in spheres:
		if sphere.is_pinned == pinned:
			output.append(sphere)


# ---- 触摸探测 ----

## 执行一次手触摸（由 InputManager 左键触发）。
## 射线方向：默认沿相机正前方，可通过 TOUCH_YAW_OFFSET_DEG 调整左右偏移。
func try_touch() -> void:
	if not _camera or not _material:
		return

	# 手触以相机为起点并跟随视角俯仰，避免做成屏幕中心无语义的固定点击。
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z.normalized()
	var direction: Vector3 = forward.rotated(
		_camera.global_transform.basis.y,
		deg_to_rad(GameConfig.TOUCH_YAW_OFFSET_DEG)
	).normalized()
	var to: Vector3 = from + direction * GameConfig.TOUCH_DISTANCE

	var player: Node = get_parent()
	var exclude_rid: RID = player.get_rid() if player is CharacterBody3D else RID()
	var result := _RaycastUtil.query_body(space_state, from, to, exclude_rid)
	if result.is_empty():
		return

	# 接触表现由 ContactProfile 决定颜色/语义，手触和盲杖共用同一套材质解释。
	var profile: Resource = _ContactProfileProvider.resolve_profile(result["collider"], &"hand")
	spawn_touch_memory(
		result["position"],
		GameConfig.TOUCH_MEMORY_RADIUS,
		ACTIVE_LIFE,
		GameConfig.TOUCH_AFTERGLOW_RADIUS,
		AFTERGLOW_LIFE,
		_ContactProfileProvider.reveal_color(profile),
		&"hand",
		_ContactProfileProvider.profile_id(profile)
	)


## 在指定世界坐标位置生成一组触觉记忆球（显影 + 残影）。
## 供外部系统（如 CaneSystem）在已有接触点时直接调用，无需重复射线检测。
func spawn_touch_memory(
	hit_point: Vector3,
	active_radius: float,
	active_life: float,
	afterglow_radius: float,
	afterglow_life: float,
	reveal_color: Color = Color(0.4, 0.75, 1.0, 1.0),
	_source: StringName = &"unknown",
	contact_profile_id: StringName = &"default_contact",
	pinned: bool = false
) -> bool:
	if not _material:
		return false
	var memory_id := _next_memory_id
	_next_memory_id += 1

	# 显影球提供短期强反馈，告诉玩家“刚摸到这里”。
	var active_sphere := _TouchSphere.new()
	_configure_active_reveal_visual(
		active_sphere,
		hit_point,
		active_radius,
		reveal_color,
		contact_profile_id
	)
	active_sphere.memory_id = memory_id
	active_sphere.age = 0.0
	active_sphere.max_age = active_life
	active_sphere.is_pinned = pinned
	_active_spheres.append(active_sphere)

	# 残影球提供长期弱反馈，让玩家可以拼出刚探索过的空间轮廓。
	var afterglow_sphere := _TouchSphere.new()
	afterglow_sphere.center = hit_point
	afterglow_sphere.radius = afterglow_radius
	afterglow_sphere.initial_radius = afterglow_radius
	afterglow_sphere.color = reveal_color
	afterglow_sphere.contact_profile_id = contact_profile_id
	afterglow_sphere.memory_id = memory_id
	afterglow_sphere.age = 0.0
	afterglow_sphere.max_age = afterglow_life
	afterglow_sphere.strength = AFTERGLOW_INIT_STRENGTH
	afterglow_sphere.is_pinned = pinned
	_afterglow_spheres.append(afterglow_sphere)

	# 临时记忆超过上限时只淘汰未保留项，保留项由独立的 8 个名额约束。
	_trim_temporary_spheres(_active_spheres)
	_trim_temporary_spheres(_afterglow_spheres)

	_update_sphere_uniforms()
	return true


func toggle_pinned_memory_at_screen_center() -> bool:
	if not _camera:
		return false
	var memory_id: int = _memory_id_at_screen_center()
	if memory_id < 0:
		return false
	var was_pinned: bool = _pinned_memory_ids.has(memory_id)
	_toggle_pinned_memory(memory_id)
	AudioManager.play_2d("memory_unpin" if was_pinned else "memory_pin", -8.0, &"touch_memory")
	_update_sphere_uniforms()
	return true


func _toggle_pinned_memory(memory_id: int) -> void:
	if _pinned_memory_ids.has(memory_id):
		_pinned_memory_ids.erase(memory_id)
		_set_memory_pinned(memory_id, false)
	else:
		if _pinned_memory_ids.size() >= GameConfig.MAX_PINNED_MEMORY_POINTS:
			var oldest_memory_id: int = int(_pinned_memory_ids.pop_front())
			_set_memory_pinned(oldest_memory_id, false)
		_pinned_memory_ids.append(memory_id)
		_set_memory_pinned(memory_id, true)


func _memory_id_at_screen_center() -> int:
	var viewport: Viewport = _camera.get_viewport()
	var screen_center: Vector2 = viewport.get_visible_rect().get_center()
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_center)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_center).normalized()
	var nearest_distance: float = INF
	var selected_memory_id: int = -1
	var selectable_spheres: Array[_TouchSphere] = _active_spheres.duplicate()
	selectable_spheres.append_array(_afterglow_spheres)
	for sphere: _TouchSphere in selectable_spheres:
		if sphere.strength <= 0.01 or sphere.radius <= 0.01:
			continue
		var hit_distance: float = _ray_sphere_hit_distance(ray_origin, ray_direction, sphere.center, sphere.radius)
		if hit_distance >= 0.0 and hit_distance < nearest_distance:
			nearest_distance = hit_distance
			selected_memory_id = sphere.memory_id
	return selected_memory_id


func _ray_sphere_hit_distance(origin: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var offset := origin - center
	var projection := offset.dot(direction)
	var discriminant := projection * projection - (offset.length_squared() - radius * radius)
	if discriminant < 0.0:
		return -1.0
	var root: float = sqrt(discriminant)
	var near_distance: float = -projection - root
	if near_distance >= 0.0:
		return near_distance
	var far_distance: float = -projection + root
	return far_distance if far_distance >= 0.0 else -1.0


func _set_memory_pinned(memory_id: int, pinned: bool) -> void:
	for sphere in _active_spheres:
		if sphere.memory_id == memory_id:
			sphere.is_pinned = pinned
	for sphere in _afterglow_spheres:
		if sphere.memory_id == memory_id:
			sphere.is_pinned = pinned


func _trim_temporary_spheres(spheres: Array[_TouchSphere]) -> void:
	while spheres.size() > MAX_SPHERES:
		var oldest_temporary_index := -1
		for i in range(spheres.size()):
			if not spheres[i].is_pinned:
				oldest_temporary_index = i
				break
		if oldest_temporary_index < 0:
			return
		spheres.remove_at(oldest_temporary_index)


func is_world_position_revealed(world_position: Vector3) -> bool:
	return are_any_points_revealed([world_position])


func are_any_points_revealed(points: Array[Vector3]) -> bool:
	for point in points:
		if _is_point_in_spheres(point, _active_spheres):
			return true
		if _is_point_in_spheres(point, _afterglow_spheres):
			return true
	return false


func _is_point_in_spheres(point: Vector3, spheres: Array[_TouchSphere]) -> bool:
	for sphere in spheres:
		if sphere.strength <= 0.01 or sphere.radius <= 0.01:
			continue
		if point.distance_to(sphere.center) <= sphere.radius:
			return true
	return false


# ---- 生命周期 ----

func _process(delta: float) -> void:
	if not _material:
		return

	_update_foot_reveal_from_ground()
	_material.set_shader_parameter("inv_view_matrix", _get_inv_view_matrix())
	_material.set_shader_parameter("viewport_size", Vector2(_camera.get_viewport().size))

	var should_update: bool = false

	# 显影球：远离时随时间缩小，靠近时暂停
	for i in range(_active_spheres.size() - 1, -1, -1):
		var s: _TouchSphere = _active_spheres[i]
		if s.is_pinned:
			continue
		var dist_to_player: float = _camera.global_position.distance_to(s.center)

		if dist_to_player >= DIST_NEAR:
			s.age += delta
			var life_ratio: float = s.age / s.max_age
			s.radius = s.initial_radius * (1.0 - life_ratio)
		# 近距离时 age/radius 保持不变（暂停）

		s.strength = 1.0

		if s.age >= s.max_age or s.radius <= 0.01:
			_active_spheres.remove_at(i)
			should_update = true

	# 残影球：长期缓慢衰减
	for i in range(_afterglow_spheres.size() - 1, -1, -1):
		var s: _TouchSphere = _afterglow_spheres[i]
		if s.is_pinned:
			continue
		s.age += delta
		var age_factor: float = 1.0 - (s.age / s.max_age)
		s.strength = AFTERGLOW_INIT_STRENGTH * age_factor

		if s.strength <= 0.01 or s.age >= s.max_age:
			_afterglow_spheres.remove_at(i)
			should_update = true

	if _foot_reveal_sphere or should_update or _active_spheres.size() > 0 or _afterglow_spheres.size() > 0:
		_update_sphere_uniforms()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F3:
				# F3 是面向玩家的无障碍功能：点亮全部视野。
				debug_mode = not debug_mode
				_apply_debug_mode()
				if _material:
					_material.set_shader_parameter("debug_mode", 1.0 if debug_mode else 0.0)
				_update_sphere_uniforms()
			KEY_H:
				if not GameConfig.DEBUG:
					return
				# H 键：切换调试残影模式（显示全部残影）
				debug_mode = not debug_mode
				if _material:
					_material.set_shader_parameter("debug_mode", 1.0 if debug_mode else 0.0)
				_update_sphere_uniforms()
				print("[DEBUG][TouchMemorySystem] debug mode: ", "ON" if debug_mode else "OFF")


# ---- 调试模式 ----

func _apply_debug_mode() -> void:
	if not _environment:
		var parent: Node = get_parent()
		if parent:
			var root: Node = parent.get_parent()
			if root:
				var we: Node = root.get_node_or_null("WorldEnvironment")
				if we:
					_environment = we.environment
	if not _environment:
		return

	if debug_mode:
		_debug_ambient_stored = _environment.ambient_light_energy
		_environment.ambient_light_energy = debug_ambient

		if not _debug_light:
			_debug_light = DirectionalLight3D.new()
			_debug_light.name = "DebugLight"
			_debug_light.light_color = Color(0.9, 0.92, 1.0)
			_debug_light.light_energy = 0.25
			_debug_light.shadow_enabled = false
			var root: Node = get_parent()
			if root:
				var r3d: Node = root.get_parent()
				if r3d:
					r3d.add_child(_debug_light)
			_debug_light.global_rotation_degrees = Vector3(-60, 30, 0)
		if GameConfig.DEBUG:
			print("[DEBUG][TouchMemorySystem] debug mode ON — ambient light enabled")
	else:
		_environment.ambient_light_energy = _debug_ambient_stored
		if _debug_light:
			_debug_light.queue_free()
			_debug_light = null
		if GameConfig.DEBUG:
			print("[DEBUG][TouchMemorySystem] debug mode OFF — restored original lighting")
const _ContactProfileProvider = preload("res://scripts/interaction/ContactProfileProvider.gd")
