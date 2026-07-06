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

@export_group("Touch", "touch_")
@export var touch_max_distance: float = 5.0

@export_group("Feedback", "feedback_")
@export var feedback_color: Color = Color(0.4, 0.75, 1.0, 1.0)  # 轮廓发光色
@export var feedback_depth_threshold: float = 0.003
@export var feedback_normal_threshold: float = 0.25

# ---- 内部 ----

var _camera: Camera3D = null
var _quad: MeshInstance3D = null
var _material: ShaderMaterial = null

# 显影球与残影球
var _active_spheres: Array[Dictionary] = []
var _afterglow_spheres: Array[Dictionary] = []

# 调试用
var _debug_light: DirectionalLight3D = null
var _debug_ambient_stored: float = 0.0
var _environment: Environment = null


func _ready() -> void:
	_camera = _find_camera()
	if not _camera:
		push_error("TouchMemorySystem: 未找到 Camera3D")
		return

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

	# 外观参数
	_material.set_shader_parameter("edge_color", feedback_color)
	_material.set_shader_parameter("depth_threshold", feedback_depth_threshold)
	_material.set_shader_parameter("normal_threshold", feedback_normal_threshold)
	_material.set_shader_parameter("debug_mode", 1.0 if debug_mode else 0.0)
	_material.set_shader_parameter("debug_afterglow_strength", debug_afterglow_strength)

	# 深度线性化参数
	_material.set_shader_parameter("camera_near", _camera.near)
	_material.set_shader_parameter("camera_far", _camera.far)

	# 逆观察矩阵
	_material.set_shader_parameter("inv_view_matrix", _get_inv_view_matrix())

	# 初始化球数组（着色器内 MAX_SPHERES 大小）
	_update_sphere_uniforms()

	_material.render_priority = 127

	_quad.material_override = _material
	_camera.add_child(_quad)
	_update_quad_transform()


func _update_quad_transform() -> void:
	var near: float = _camera.near + 0.01
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h: float = near * tan(fov_rad * 0.5)
	var aspect: float = float(_camera.get_viewport().size.x) / float(_camera.get_viewport().size.y)
	var half_w: float = half_h * aspect

	_quad.position = Vector3(0.0, 0.0, -near)
	_quad.scale = Vector3(half_w * 2.0, half_h * 2.0, 1.0)


func _get_inv_view_matrix() -> Projection:
	return Projection(_camera.global_transform)


# ---- 球数据更新 ----

func _update_sphere_uniforms() -> void:
	if not _material:
		return

	var all_spheres: Array = _active_spheres.duplicate()
	all_spheres.append_array(_afterglow_spheres)

	var count: int = mini(all_spheres.size(), MAX_SPHERES)

	var pos_array := PackedVector3Array()
	var rad_array := PackedFloat32Array()
	var str_array := PackedFloat32Array()
	pos_array.resize(MAX_SPHERES)
	rad_array.resize(MAX_SPHERES)
	str_array.resize(MAX_SPHERES)

	for i in range(MAX_SPHERES):
		if i < count:
			var s: Dictionary = all_spheres[i]
			pos_array[i] = s.center
			rad_array[i] = s.radius
			str_array[i] = s.strength
		else:
			pos_array[i] = Vector3.ZERO
			rad_array[i] = 0.0
			str_array[i] = 0.0

	_material.set_shader_parameter("sphere_positions", pos_array)
	_material.set_shader_parameter("sphere_radii", rad_array)
	_material.set_shader_parameter("sphere_strengths", str_array)
	_material.set_shader_parameter("sphere_count", count)


# ---- 触摸探测 ----

## 执行一次触摸（由 GaitController 左键触发）
func try_touch() -> void:
	if not _camera or not _material:
		return

	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z.normalized()
	var to: Vector3 = from + forward * touch_max_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false

	# 排除玩家自身
	var player: Node = get_parent()
	if player is CharacterBody3D:
		query.exclude = [player.get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_point: Vector3 = result.position
	EventBus.audio_requested.emit("touch", hit_point, 0.0)

	# 生成显影球
	_active_spheres.append({
		"center": hit_point,
		"radius": INITIAL_RADIUS,
		"age": 0.0,
		"max_age": ACTIVE_LIFE,
		"strength": 1.0
	})

	# 生成残影球
	_afterglow_spheres.append({
		"center": hit_point,
		"radius": AFTERGLOW_RADIUS,
		"age": 0.0,
		"max_age": AFTERGLOW_LIFE,
		"strength": AFTERGLOW_INIT_STRENGTH
	})

	# 保持上限，避免着色器数组溢出
	if _active_spheres.size() > MAX_SPHERES:
		_active_spheres.pop_front()
	if _afterglow_spheres.size() > MAX_SPHERES:
		_afterglow_spheres.pop_front()

	_update_sphere_uniforms()


# ---- 生命周期 ----

func _process(delta: float) -> void:
	if not _material:
		return

	# 摄像机移动时更新逆观察矩阵
	_material.set_shader_parameter("inv_view_matrix", _get_inv_view_matrix())

	var should_update: bool = false

	# 显影球：远离时随时间缩小，靠近时暂停
	for i in range(_active_spheres.size() - 1, -1, -1):
		var s: Dictionary = _active_spheres[i]
		var dist_to_player: float = _camera.global_position.distance_to(s.center)

		if dist_to_player >= DIST_NEAR:
			s.age += delta
			var life_ratio: float = s.age / s.max_age
			s.radius = INITIAL_RADIUS * (1.0 - life_ratio)
		# 近距离时 age/radius 保持不变（暂停）

		s.strength = 1.0

		if s.age >= s.max_age or s.radius <= 0.01:
			_active_spheres.remove_at(i)
			should_update = true

	# 残影球：长期缓慢衰减
	for i in range(_afterglow_spheres.size() - 1, -1, -1):
		var s: Dictionary = _afterglow_spheres[i]
		s.age += delta
		var age_factor: float = 1.0 - (s.age / s.max_age)
		s.strength = AFTERGLOW_INIT_STRENGTH * age_factor

		if s.strength <= 0.01 or s.age >= s.max_age:
			_afterglow_spheres.remove_at(i)
			should_update = true

	if should_update or _active_spheres.size() > 0 or _afterglow_spheres.size() > 0:
		_update_sphere_uniforms()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F3:
				debug_mode = not debug_mode
				_apply_debug_mode()
				if _material:
					_material.set_shader_parameter("debug_mode", 1.0 if debug_mode else 0.0)
			KEY_H:
				# H 键：切换调试残影模式（显示全部残影）
				debug_mode = not debug_mode
				if _material:
					_material.set_shader_parameter("debug_mode", 1.0 if debug_mode else 0.0)
				print("TouchMemorySystem 调试模式: ", "ON" if debug_mode else "OFF")


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
		print("调试模式 ON — 环境光启用")
	else:
		_environment.ambient_light_energy = _debug_ambient_stored
		if _debug_light:
			_debug_light.queue_free()
			_debug_light = null
		print("调试模式 OFF — 恢复原始光照")
