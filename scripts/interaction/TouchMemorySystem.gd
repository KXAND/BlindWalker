extends Node3D
class_name TouchMemorySystem


## 触觉记忆系统
## 模拟视障者触摸感知：点击产生光源照亮表面，光照衰减后留下物体轮廓（记忆痕迹）
##
## 流程：
##   1. 左键点击 → 射线检测击中点
##   2. 在击中点创建 OmniLight3D 照亮物体表面（无高光反射）
##   3. 光源逐渐衰减（默认 5 秒）
##   4. 衰减至阈值时轮廓渐显，光源完全消失后仅剩轮廓
##   5. 轮廓缓慢消失（默认 15 秒），模拟记忆消退

# ---- 可调参数 ----
@export var debug_mode: bool = false               # 调试模式：开启后提供全局光照，按 F3 切换
@export var debug_ambient: float = 0.15            # 调试环境光亮度（可见的暗，保留物体基本轮廓）
@export var light_start_energy: float = 0.3       # 光源初始亮度
@export var light_range: float = 2.5               # 聚光灯光源照射距离（需覆盖 max_ray_distance）
@export var light_color: Color = Color.WHITE              # 纯白光（盲人无色彩感知）
@export var spot_angle: float = 30.0               # 聚光灯锥角（度）
@export var spot_attenuation: float = 0.8          # 锥边缘柔和度
@export var light_attenuation: float = 0.3         # 衰减曲线：越小越均匀（0=恒定, 1=线性, 2=平方反比）
@export var decay_duration: float = 5.0            # 光源完全衰减的时间（秒）
@export var outline_start_ratio: float = 0.25      # 光源能量降到这个比例时开始显示轮廓
@export var outline_max_alpha: float = 0.55        # 轮廓最大不透明度
@export var outline_width: float = 0.018           # 轮廓线宽度
@export var outline_color: Color = Color(0.85, 0.85, 0.85)  # 轮廓颜色（灰度，无色彩倾向）
@export var outline_persist: float = 15.0          # 轮廓持续时间（秒）
@export var max_ray_distance: float = 2.5          # 触摸最大距离（模拟手臂长度）

# ---- 内部 ----
var _camera: Camera3D = null
var _outline_shader: Shader = null
var _world_root: Node3D = null           # 静态世界根节点（光源挂此节点下，避免随玩家移动）
var _debug_light: DirectionalLight3D = null
var _debug_ambient_stored: float = 0.0
var _environment: Environment = null

## 单次触摸记录
class TouchRecord:
	var light: Light3D               # 动态光源（SpotLight3D，方向与摄像机朝向一致）
	var target_node: Node3D          # 被击中的 CSG/Mesh 节点
	var outline_material: ShaderMaterial  # 轮廓材质（挂在 next_pass 上）
	var age: float = 0.0             # 光源年龄
	var outline_age: float = 0.0     # 轮廓年龄
	var phase: int = 0               # 0=光照阶段, 1=轮廓阶段
	var hit_objects: Array = []      # 已处理过的节点（去重用）


var _records: Array[TouchRecord] = []


func _ready() -> void:
	_find_camera()
	_find_world_root()
	_load_shader()
	_apply_debug_mode()


func _find_camera() -> void:
	var parent := get_parent()
	if parent:
		var head := parent.get_node_or_null("Head")
		if head:
			_camera = head.get_node_or_null("Camera3D")
	if not _camera:
		_camera = get_viewport().get_camera_3d()


## 找到静态世界根节点（Player 的父节点 GameRoot），光源必须挂此节点下避免随玩家移动
func _find_world_root() -> void:
	var p := get_parent()
	if p:
		_world_root = p.get_parent() as Node3D
	if not _world_root:
		push_error("TouchMemorySystem: 无法找到世界根节点")


## F3 切换调试模式
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		debug_mode = not debug_mode
		_apply_debug_mode()


## 调试模式：创建/销毁全局光照 + 设置环境光
func _apply_debug_mode() -> void:
	if not _world_root:
		return

	# 获取 WorldEnvironment 节点
	if not _environment:
		var we := _world_root.get_node_or_null("WorldEnvironment")
		if we:
			_environment = we.environment
	if not _environment:
		return

	if debug_mode:
		# 存储原始环境光值
		_debug_ambient_stored = _environment.ambient_light_energy
		_environment.ambient_light_energy = debug_ambient

		if not _debug_light:
			_debug_light = DirectionalLight3D.new()
			_debug_light.name = "DebugLight"
			_debug_light.light_color = Color(0.9, 0.92, 1.0)
			_debug_light.light_energy = 0.25
			_debug_light.shadow_enabled = false
			_world_root.add_child(_debug_light)
			# 从上方斜照，产生立体感
			_debug_light.global_rotation_degrees = Vector3(-60, 30, 0)
		print("调试模式 ON — 全局光照已启用")
	else:
		_environment.ambient_light_energy = _debug_ambient_stored

		if _debug_light:
			_debug_light.queue_free()
			_debug_light = null
		print("调试模式 OFF — 恢复全黑场景")


func _load_shader() -> void:
	_outline_shader = load("res://assets/shaders/touch_outline.gdshader")
	if not _outline_shader:
		push_error("TouchMemorySystem: 无法加载轮廓 shader")
	else:
		print("TouchMemorySystem: 轮廓 shader 加载成功")


## 由 PlayerController 调用，执行一次触摸探测
func try_touch() -> void:
	if not _camera:
		return

	# 使用节点自身的 get_world_3d()（而非相机的），确保从正确的物理世界查询
	var space_state := get_world_3d().direct_space_state
	var from := _camera.global_position
	var forward := -_camera.global_transform.basis.z.normalized()
	var to := from + forward * max_ray_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1           # 第 1 层
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	# 排除玩家自身碰撞体
	var player := get_parent()
	if player is CharacterBody3D:
		query.exclude = [player.get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.get("normal", Vector3.UP)
	var hit_collider: Node = result.collider

	# 找到实际的视觉节点（CSG/Mesh，而非 CollisionShape）
	var visual_node := _find_visual_node(hit_collider)
	if not visual_node:
		return

	_create_touch(hit_point, hit_normal, visual_node)


## 沿节点树向上查找 CSGShape3D 或 MeshInstance3D
func _find_visual_node(collider: Node) -> Node3D:
	var node := collider
	while node:
		if node is CSGShape3D or node is MeshInstance3D:
			return node as Node3D
		node = node.get_parent()
	return collider as Node3D


## 检查节点是否已在某条记录中被处理过
func _is_already_touched(node: Node3D) -> bool:
	for rec in _records:
		if rec.target_node == node:
			return true
	return false


func _create_touch(pos: Vector3, normal: Vector3, target: Node3D) -> void:
	# 光源初始位置放在摄像机处（模拟从眼睛照射出去的光）
	var light_pos := _camera.global_position

	# ---- 创建 SpotLight（方向与摄像机朝向一致） ----
	var light := SpotLight3D.new()
	light.light_color = light_color
	light.light_energy = light_start_energy
	light.spot_range = light_range
	light.spot_angle = spot_angle
	light.spot_attenuation = spot_attenuation
	light.spot_angle_attenuation = 1.0
	light.light_specular = 0.0            # 无高光反射
	light.light_indirect_energy = 0.0     # 无间接光照
	if _world_root:
		_world_root.add_child(light)
	else:
		add_child(light)
	light.global_position = light_pos
	# 让聚光灯朝向摄像机前方（-Z 方向，即射线方向）
	light.global_transform.basis = _camera.global_transform.basis

	# ---- 创建轮廓材质 ----
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = _outline_shader
	outline_mat.set_shader_parameter("outline_color", Color(outline_color, 0.0))
	outline_mat.set_shader_parameter("outline_width", outline_width)

	# ---- 将轮廓材质挂到目标物体的 next_pass ----
	# 先检查是否已有记录（避免多次触摸同一物体导致 next_pass 堆叠）
	if not _is_already_touched(target):
		var mat = target.get("material")
		if mat and mat is StandardMaterial3D:
			var dup_mat = mat.duplicate()
			dup_mat.next_pass = outline_mat
			target.set("material", dup_mat)

	var rec := TouchRecord.new()
	rec.light = light
	rec.target_node = target
	rec.outline_material = outline_mat
	rec.age = 0.0
	rec.outline_age = 0.0
	rec.phase = 0

	_records.append(rec)


func _process(delta: float) -> void:
	if _records.is_empty():
		return

	var to_remove: Array[TouchRecord] = []

	for rec in _records:
		match rec.phase:
			0:
				_process_light_phase(rec, delta, to_remove)
			1:
				_process_outline_phase(rec, delta, to_remove)

	# 清理已完成的记录
	for rec in to_remove:
		_records.erase(rec)


## 光照阶段：衰减光源亮度，到阈值后过渡到轮廓阶段
func _process_light_phase(rec: TouchRecord, delta: float, to_remove: Array[TouchRecord]) -> void:
	rec.age += delta
	var ratio := 1.0 - (rec.age / decay_duration)

	if ratio <= 0.0:
		# 光源完全衰减，移除之，进入轮廓阶段
		if is_instance_valid(rec.light):
			rec.light.queue_free()
		rec.phase = 1
		rec.outline_age = 0.0
		# 确保轮廓 alpha 到达最大值
		_set_outline_alpha(rec, outline_max_alpha)
		return

	# 更新光源亮度
	if is_instance_valid(rec.light):
		rec.light.light_energy = light_start_energy * ratio

	# 检查是否进入轮廓过渡区间
	if ratio <= outline_start_ratio:
		# 将 ratio 从 [outline_start_ratio, 0] 映射到轮廓 alpha [0, 1]
		var t := 1.0 - (ratio / outline_start_ratio)  # 0 → outline_start_ratio 时, t 从 1 → 0
		# 实际上当 ratio 从 outline_start_ratio 降到 0 时，轮廓从 0 升到 1
		# ratio / outline_start_ratio: 1 → 0
		# 1 - (ratio / outline_start_ratio): 0 → 1 ✓
		t = clamp(t, 0.0, 1.0)
		_set_outline_alpha(rec, t * outline_max_alpha)


## 轮廓阶段：轮廓逐渐消失
func _process_outline_phase(rec: TouchRecord, delta: float, to_remove: Array[TouchRecord]) -> void:
	rec.outline_age += delta
	var ratio := 1.0 - (rec.outline_age / outline_persist)

	if ratio <= 0.0:
		to_remove.append(rec)
		return

	_set_outline_alpha(rec, ratio * outline_max_alpha)


func _set_outline_alpha(rec: TouchRecord, alpha: float) -> void:
	if not is_instance_valid(rec.outline_material):
		return
	var col := rec.outline_material.get_shader_parameter("outline_color") as Color
	col.a = alpha
	rec.outline_material.set_shader_parameter("outline_color", col)
