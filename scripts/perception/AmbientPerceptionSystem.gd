extends Node3D
class_name AmbientPerceptionSystem

## 环境感知提示系统。
##
## 这里只表达玩家主观感受到的热源方向和近身气流，不参与光照、物理、
## 触觉记忆或互动显影判断。风线是玩家周围的感知效果，不和场景几何交互。

const HEAT_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform vec2 cue_center = vec2(0.5, 0.5);
uniform float cue_strength = 0.0;
uniform float cue_radius = 0.42;
uniform float elapsed_time = 0.0;
uniform vec4 cue_color : source_color = vec4(1.0, 0.56, 0.18, 0.16);

void fragment() {
	float d = distance(UV, cue_center);
	float haze = smoothstep(cue_radius, 0.0, d);
	float soft_haze = pow(haze, 1.7);
	float pulse = 0.9 + 0.1 * sin(elapsed_time * 1.7);
	ALBEDO = cue_color.rgb;
	ALPHA = soft_haze * cue_strength * cue_color.a * pulse;
}
"""

const WIND_STREAK_COUNT := 18
const WIND_FIELD_RADIUS := 1.8
const WIND_TRAVEL_DISTANCE := 1.4
const WIND_STREAK_LENGTH := 0.55
const WIND_STREAK_THICKNESS := 0.012

class WindStreakState:
	var offset: Vector3
	var phase: float
	var speed: float
	var height: float

@export_group("Heat Cue", "heat_")
@export var heat_enabled: bool = true
@export var heat_direction: Vector3 = Vector3(-0.35, 0.82, -0.45)
@export_range(0.0, 1.0, 0.01) var heat_intensity: float = 0.75
@export_range(0.15, 0.8, 0.01) var heat_radius: float = 0.42
@export var heat_color: Color = Color(1.0, 0.56, 0.18, 0.16)

@export_group("Airflow Cue", "wind_")
@export var wind_enabled: bool = true
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, -0.25)
@export_range(0.0, 1.0, 0.01) var wind_strength: float = 0.55
@export var wind_color: Color = Color(0.72, 0.9, 1.0, 0.18)

@export_group("References")
@export var camera_path: NodePath = ^"Head/Camera3D"

var _camera: Camera3D = null
var _heat_quad: MeshInstance3D = null
var _heat_material: ShaderMaterial = null
var _elapsed_time: float = 0.0
var _last_heat_strength: float = 0.0

var _wind_root: Node3D = null
var _wind_streaks: Array[MeshInstance3D] = []
var _wind_data: Array[WindStreakState] = []


func _ready() -> void:
	_camera = _find_camera()
	if not _camera:
		push_error("AmbientPerceptionSystem: 未找到 Camera3D")
		return

	_create_heat_cue()
	_create_wind_cue()


func _process(delta: float) -> void:
	if not _camera:
		return

	_elapsed_time += delta
	_update_heat_quad_transform()
	_update_heat_cue()
	_update_wind_cue(delta)


func get_heat_cue_strength() -> float:
	return _last_heat_strength


func get_wind_streak_count() -> int:
	return _wind_streaks.size()


func get_wind_direction() -> Vector3:
	return _safe_direction(wind_direction, Vector3.FORWARD)


func _find_camera() -> Camera3D:
	var parent := get_parent()
	if parent:
		var configured_camera := parent.get_node_or_null(camera_path) as Camera3D
		if configured_camera:
			return configured_camera
	return get_viewport().get_camera_3d()


func _create_heat_cue() -> void:
	_heat_quad = MeshInstance3D.new()
	_heat_quad.name = "HeatCueQuad"
	var quad_mesh := QuadMesh.new()
	quad_mesh.orientation = PlaneMesh.FACE_Z
	_heat_quad.mesh = quad_mesh
	_heat_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := Shader.new()
	shader.code = HEAT_SHADER_CODE
	_heat_material = ShaderMaterial.new()
	_heat_material.shader = shader
	_heat_material.render_priority = 8
	_heat_quad.material_override = _heat_material

	_camera.add_child(_heat_quad)
	_update_heat_quad_transform()


func _update_heat_quad_transform() -> void:
	if not _heat_quad or not _camera:
		return

	var near := _camera.near + 0.012
	var fov_rad := deg_to_rad(_camera.fov)
	var half_h := near * tan(fov_rad * 0.5)
	var viewport_size: Vector2i = _camera.get_viewport().size
	var aspect := 16.0 / 9.0
	if viewport_size.y > 0:
		aspect = float(viewport_size.x) / float(viewport_size.y)
	var half_w := half_h * aspect

	_heat_quad.position = Vector3(0.0, 0.0, -near)
	_heat_quad.scale = Vector3(half_w * 2.0, half_h * 2.0, 1.0)


func _update_heat_cue() -> void:
	if not _heat_material:
		return

	var strength := 0.0
	var center := Vector2(0.5, 0.5)
	if heat_enabled and heat_intensity > 0.0:
		var direction := _safe_direction(heat_direction, Vector3.UP)
		var point := _camera.global_position + direction * 80.0
		if not _camera.is_position_behind(point):
			var viewport_size: Vector2i = _camera.get_viewport().size
			if viewport_size.x > 0 and viewport_size.y > 0:
				center = _camera.unproject_position(point) / Vector2(viewport_size)
				var offscreen := maxf(
					maxf(-center.x, center.x - 1.0),
					maxf(-center.y, center.y - 1.0)
				)
				var edge_fade := clampf(1.0 - maxf(offscreen, 0.0) / maxf(heat_radius, 0.01), 0.0, 1.0)
				strength = heat_intensity * edge_fade

	_last_heat_strength = strength
	_heat_material.set_shader_parameter("cue_center", center)
	_heat_material.set_shader_parameter("cue_strength", strength)
	_heat_material.set_shader_parameter("cue_radius", heat_radius)
	_heat_material.set_shader_parameter("cue_color", heat_color)
	_heat_material.set_shader_parameter("elapsed_time", _elapsed_time)


func _create_wind_cue() -> void:
	_wind_root = Node3D.new()
	_wind_root.name = "AirflowCueRoot"
	add_child(_wind_root)

	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(WIND_STREAK_LENGTH, WIND_STREAK_THICKNESS, WIND_STREAK_THICKNESS)

	var rng := RandomNumberGenerator.new()
	rng.seed = 16016
	for i in range(WIND_STREAK_COUNT):
		var streak := MeshInstance3D.new()
		streak.name = "AirflowCue_%02d" % i
		streak.mesh = base_mesh
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.no_depth_test = true
		material.albedo_color = wind_color
		streak.material_override = material

		_wind_root.add_child(streak)
		_wind_streaks.append(streak)
		var state := WindStreakState.new()
		state.offset = _random_wind_offset(rng)
		state.phase = rng.randf()
		state.speed = rng.randf_range(0.18, 0.36)
		state.height = rng.randf_range(0.65, 1.75)
		_wind_data.append(state)


func _random_wind_offset(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(0.3, WIND_FIELD_RADIUS)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _update_wind_cue(delta: float) -> void:
	if not _wind_root:
		return

	var direction := _safe_direction(wind_direction, Vector3.RIGHT)
	var enabled_strength := wind_strength if wind_enabled else 0.0
	var wind_basis := _basis_from_x_axis(direction)
	var player_position := global_position

	for i in range(_wind_streaks.size()):
		var streak := _wind_streaks[i]
		var data := _wind_data[i]
		data.phase = fposmod(data.phase + delta * data.speed * (0.35 + enabled_strength), 1.0)

		var travel := (data.phase - 0.5) * WIND_TRAVEL_DISTANCE
		var fade := sin(data.phase * PI)
		var offset := data.offset
		offset.y = data.height + sin((_elapsed_time * 1.6) + float(i)) * 0.08

		streak.visible = enabled_strength > 0.01
		streak.global_transform = Transform3D(wind_basis, player_position + offset + direction * travel)

		var material := streak.material_override as StandardMaterial3D
		if material:
			var color := wind_color
			color.a *= enabled_strength * fade
			material.albedo_color = color


func _basis_from_x_axis(x_axis: Vector3) -> Basis:
	var x := _safe_direction(x_axis, Vector3.RIGHT)
	var y := Vector3.UP
	if absf(x.dot(y)) > 0.95:
		y = Vector3.FORWARD
	var z := x.cross(y).normalized()
	y = z.cross(x).normalized()
	return Basis(x, y, z)


func _safe_direction(value: Vector3, fallback: Vector3) -> Vector3:
	if value.length_squared() <= 0.0001:
		return fallback.normalized()
	return value.normalized()
