extends Node3D
class_name TouchMemorySystem


## 触觉记忆系统 —— 世界空间轮廓反馈
##
## 原理：
##   1. 在摄像机前放置一片全屏 QuadMesh，挂载屏幕空间着色器
##   2. 左键触摸时，射线检测命中 3D 物体 → 记录命中的世界坐标
##   3. 着色器内用视线方向 + 线性深度 + inv_view_matrix 重建每像素世界坐标
##   4. 若像素世界坐标距命中点 < 球半径 → 做深度/法线边缘检测
##   5. 检测到的轮廓像素输出高亮色，其余 discard
##
## 效果：
##   - 反馈锁定在世界空间位置，与摄像机移动无关
##   - 仅渲染球体内物体的轮廓（球体边界不会出现伪影）
##   - 不依赖 INV_VIEW_MATRIX / INV_PROJECTION_MATRIX 等版本受限的内置变量

# ---- 可调参数 ----

@export_group("Debug", "debug_")
@export var debug_mode: bool = false
@export var debug_ambient: float = 0.15

@export_group("Touch", "touch_")
@export var touch_max_distance: float = 3.0

@export_group("Feedback", "feedback_")
@export var feedback_world_radius: float = 2.0              # 命中点周围世界空间球半径（米）
@export var feedback_color: Color = Color(0.4, 0.75, 1.0, 1.0)  # 轮廓发光色
@export var feedback_duration: float = 3.0                  # 触摸记忆消退时间（秒）
@export var feedback_depth_threshold: float = 0.003
@export var feedback_normal_threshold: float = 0.25

# ---- 内部 ----

var _camera: Camera3D = null
var _quad: MeshInstance3D = null
var _material: ShaderMaterial = null
var _touch_time: float = -999.0             # 上次触摸时间戳
var _last_hit_point: Vector3 = Vector3.ZERO  # 上次触摸的 3D 世界坐标
var _has_active_touch: bool = false          # 是否仍有活跃的触摸反馈

# 调试模式
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
	# 创建 QuadMesh（默认 1×1，UV 0-1）
	_quad = MeshInstance3D.new()
	_quad.name = "TouchFeedbackQuad"
	var quad_mesh := QuadMesh.new()
	quad_mesh.orientation = PlaneMesh.FACE_Z  # 面朝 -Z（摄像机方向）
	_quad.mesh = quad_mesh

	# 加载着色器
	var shader := load("res://assets/shaders/touch_feedback.gdshader") as Shader
	if not shader:
		push_error("TouchMemorySystem: 无法加载 touch_feedback.gdshader")
		return

	_material = ShaderMaterial.new()
	_material.shader = shader
	# ShaderMaterial 的透明行为完全由着色器的 render_mode blend_mix 控制，
	# 不需要（也没有）BaseMaterial3D 那样的 transparency 属性
	# 初始状态：无触摸，全透明
	_material.set_shader_parameter("alpha_multiplier", 0.0)
	_material.set_shader_parameter("world_radius", feedback_world_radius)
	_material.set_shader_parameter("edge_color", feedback_color)
	_material.set_shader_parameter("depth_threshold", feedback_depth_threshold)
	_material.set_shader_parameter("normal_threshold", feedback_normal_threshold)

	# 深度线性化参数（由顶点着色器 view_ray + inv_view_matrix 重建世界坐标）
	_material.set_shader_parameter("camera_near", _camera.near)
	_material.set_shader_parameter("camera_far", _camera.far)

	# 逆观察矩阵（着色器需要，兼容无 INV_VIEW_MATRIX 内置变量的版本）
	_material.set_shader_parameter("inv_view_matrix", _get_inv_view_matrix())

	# 渲染优先级：确保在场景不透明物体之后渲染（才能采到完整深度/法线缓冲）
	# 范围 [-128, 127]，127 = 最大值
	_material.render_priority = 127

	_quad.material_override = _material

	# 挂到摄像机下，随摄像机移动/旋转
	_camera.add_child(_quad)

	# 更新 Quad 大小以覆盖全屏
	_update_quad_transform()


func _update_quad_transform() -> void:
	# Quad 在摄像机本地空间中，面朝 -Z 方向
	# 放置于近裁剪面之前，缩放至恰好覆盖视锥体
	var near: float = _camera.near + 0.01
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h: float = near * tan(fov_rad * 0.5)
	var aspect: float = float(_camera.get_viewport().size.x) / float(_camera.get_viewport().size.y)
	var half_w: float = half_h * aspect

	_quad.position = Vector3(0.0, 0.0, -near)
	_quad.scale = Vector3(half_w * 2.0, half_h * 2.0, 1.0)


# ---- 摄像机矩阵 ----

func _get_inv_view_matrix() -> Projection:
	# inv_view_matrix = 观察矩阵的逆 = 摄像机在世界空间中的变换
	return Projection(_camera.global_transform)


# ---- 触摸探测 ----

## 执行一次触摸（由 PlayerController 左键触发）
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

	# 记录 3D 世界坐标，传给着色器
	_last_hit_point = result.position
	_touch_time = Time.get_ticks_msec() / 1000.0
	_has_active_touch = true

	# 只传世界坐标和激活透明度
	_material.set_shader_parameter("touch_world_pos", _last_hit_point)
	_material.set_shader_parameter("alpha_multiplier", 1.0)


# ---- 生命周期 ----

func _process(_delta: float) -> void:
	if not _material or not _has_active_touch:
		return

	# 摄像机移动时，逆观察矩阵每帧更新，确保世界坐标重建正确
	_material.set_shader_parameter("inv_view_matrix", _get_inv_view_matrix())

	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _touch_time
	if elapsed < feedback_duration:
		var alpha: float = 1.0 - elapsed / feedback_duration
		_material.set_shader_parameter("alpha_multiplier", alpha)
	else:
		# 完全消退
		_material.set_shader_parameter("alpha_multiplier", 0.0)
		_has_active_touch = false
		_touch_time = -999.0


func _input(event: InputEvent) -> void:
	# F3 切换调试模式
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F3:
			debug_mode = not debug_mode
			_apply_debug_mode()
		# F4 切换反馈半径（1m / 2.5m）
		elif event.keycode == KEY_F4:
			feedback_world_radius = 2.5 if feedback_world_radius > 1.5 else 1.0
			_material.set_shader_parameter("world_radius", feedback_world_radius)


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
