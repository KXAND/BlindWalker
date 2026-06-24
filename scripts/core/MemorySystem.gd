extends Node3D

const GLOW_TEXTURE_SIZE := 128


class RevealSphere:
	var center: Vector3
	var normal: Vector3
	var tangent_a: Vector3
	var tangent_b: Vector3
	var base_offset: Vector3
	var radius: float
	var age: float
	var max_age: float
	var strength: float
	var pauses_when_near: bool
	var afterglow_spawned: bool
	var phase: float
	var sprite: Sprite3D


@export_node_path("Camera3D") var observer_path: NodePath = ^"../Player/Head/Camera3D"
@export_node_path("CanvasLayer") var hud_path: NodePath = ^"../GameHud"
@export var ray_distance: float = 5.0
@export var max_spheres: int = 128
@export var active_initial_radius: float = 1.5
@export var active_lifetime: float = 30.0
@export var active_pause_distance: float = 10.0
@export var afterglow_radius: float = 1.5
@export var afterglow_initial_strength: float = 0.4
@export var afterglow_lifetime: float = 60.0
@export var afterglow_trigger_strength: float = 0.45
@export var afterglow_layers: int = 3
@export var afterglow_offset_radius: float = 0.28
@export var ghost_start_distance: float = 4.0
@export var ghost_jitter_radius: float = 0.22
@export var ghost_jitter_speed: float = 1.3
@export var active_far_strength_scale: float = 0.42
@export var blur_radius: float = 0.004
@export var near_reveal_distance: float = 1.2
@export var far_forget_distance: float = 5.0
@export var approach_speed: float = 5.0
@export var decay_speed: float = 0.9
@export var debug_min_strength: float = 0.35
@export var background_color: Color = Color(0.039216, 0.039216, 0.078431, 1.0)

var _observer: Camera3D
var _hud: CanvasLayer
var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _mask_root: Node3D
var _depth_material: StandardMaterial3D
var _glow_texture: Texture2D
var _active_spheres: Array[RevealSphere] = []
var _afterglow_spheres: Array[RevealSphere] = []
var _debug_mode: bool = false
var _feedback_lines: Array[Dictionary] = []


func _ready() -> void:
	_observer = get_node_or_null(observer_path) as Camera3D
	_hud = get_node_or_null(hud_path) as CanvasLayer

	if _observer == null:
		push_warning("MemorySystem could not find observer at %s" % observer_path)
		set_process(false)
		set_process_unhandled_input(false)
		return

	_setup_depth_material()
	_glow_texture = _create_glow_texture(GLOW_TEXTURE_SIZE)
	_setup_mask_viewport()
	_build_mask_geometry()
	_configure_main_camera()
	_sync_mask_camera()
	_on_main_viewport_size_changed()
	get_viewport().size_changed.connect(_on_main_viewport_size_changed)
	call_deferred("_configure_hud")
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	_sync_mask_camera()
	_update_spheres(delta)
	_update_feedback_lines(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_debug_mode = not _debug_mode
		if _hud != null and _hud.has_method("set_debug_mode"):
			_hud.call("set_debug_mode", _debug_mode)
		_refresh_sphere_visuals()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return
		_cast_paint_ray()


func _setup_depth_material() -> void:
	_depth_material = StandardMaterial3D.new()
	_depth_material.resource_local_to_scene = true
	_depth_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_depth_material.albedo_color = Color.BLACK
	_depth_material.cull_mode = BaseMaterial3D.CULL_BACK
	_depth_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _setup_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "MaskViewport"
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_mask_viewport.world_3d = get_viewport().world_3d
	add_child(_mask_viewport)

	_mask_root = Node3D.new()
	_mask_root.name = "MaskRoot"
	_mask_viewport.add_child(_mask_root)

	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.current = true
	_mask_camera.cull_mask = 1 << 1
	_mask_camera.environment = null
	_mask_viewport.add_child(_mask_camera)


func _build_mask_geometry() -> void:
	_register_depth_targets(get_parent())


func _register_depth_targets(root: Node) -> void:
	for child in root.get_children():
		if child == self or child == _hud or child == _mask_viewport or child == _mask_root:
			continue

		if child is Node3D and _is_mask_target(child as Node3D):
			var depth_proxy := _create_depth_proxy(child as Node3D)
			if depth_proxy != null:
				_mask_root.add_child(depth_proxy)

		_register_depth_targets(child)


func _is_mask_target(node: Node3D) -> bool:
	if node.is_in_group(&"memory_ignore"):
		return false

	if node is CSGShape3D:
		return node.visible

	if node is MeshInstance3D:
		return node.visible and (node as MeshInstance3D).mesh != null

	return false


func _create_depth_proxy(node: Node3D) -> Node3D:
	var proxy := node.duplicate() as Node3D
	if proxy == null:
		return null

	proxy.name = "Depth_" + node.name
	proxy.top_level = true
	proxy.global_transform = node.global_transform

	if proxy is CSGShape3D:
		var csg_proxy := proxy as CSGShape3D
		csg_proxy.use_collision = false
		csg_proxy.material = _depth_material
		csg_proxy.layers = 1 << 1

	if proxy is MeshInstance3D:
		var mesh_proxy := proxy as MeshInstance3D
		mesh_proxy.material_override = _depth_material
		mesh_proxy.layers = 1 << 1

	return proxy


func _configure_main_camera() -> void:
	_observer.cull_mask = 1


func _configure_hud() -> void:
	if _hud == null:
		return

	if _hud.has_method("set_mask_texture"):
		_hud.call("set_mask_texture", _mask_viewport.get_texture())
	if _hud.has_method("set_background_color"):
		_hud.call("set_background_color", background_color)
	if _hud.has_method("set_blur_radius"):
		_hud.call("set_blur_radius", blur_radius)
	if _hud.has_method("set_debug_mode"):
		_hud.call("set_debug_mode", _debug_mode)


func _sync_mask_camera() -> void:
	_mask_camera.global_transform = _observer.global_transform
	_mask_camera.fov = _observer.fov
	_mask_camera.near = _observer.near
	_mask_camera.far = _observer.far


func _on_main_viewport_size_changed() -> void:
	if _mask_viewport == null:
		return

	_mask_viewport.size = get_viewport().get_visible_rect().size


func _cast_paint_ray() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_center := viewport_size * 0.5
	var ray_origin := _observer.project_ray_origin(screen_center)
	var ray_direction := _observer.project_ray_normal(screen_center)
	var ray_end := ray_origin + (ray_direction * ray_distance)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var player := _observer.get_parent().get_parent() as CollisionObject3D
	if player != null:
		query.exclude = [player.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end_point := ray_end

	if not hit.is_empty():
		end_point = hit.position
		_spawn_reveal_sphere(hit.position, hit.normal if hit.has("normal") else Vector3.UP)

	_spawn_feedback_line(ray_origin, end_point, not hit.is_empty())


func _spawn_reveal_sphere(hit_position: Vector3, hit_normal: Vector3) -> void:
	_active_spheres.append(_make_sphere(hit_position, hit_normal, active_initial_radius, active_lifetime, 1.0, true))
	_trim_sphere_budget()


func _make_sphere(center: Vector3, normal: Vector3, radius: float, max_age: float, strength: float, pauses_when_near: bool) -> RevealSphere:
	var sphere := RevealSphere.new()
	sphere.center = center
	sphere.normal = normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var tangent_seed := Vector3.UP if absf(sphere.normal.y) < 0.95 else Vector3.RIGHT
	sphere.tangent_a = sphere.normal.cross(tangent_seed).normalized()
	sphere.tangent_b = sphere.normal.cross(sphere.tangent_a).normalized()
	sphere.base_offset = Vector3.ZERO
	sphere.radius = radius
	sphere.age = 0.0
	sphere.max_age = max_age
	sphere.strength = strength
	sphere.pauses_when_near = pauses_when_near
	sphere.afterglow_spawned = not pauses_when_near
	sphere.phase = absf((center.x * 0.73) + (center.y * 1.13) + (center.z * 1.91))
	sphere.sprite = _create_reveal_sprite(sphere)
	_apply_sphere_visual(sphere)
	return sphere


func _create_reveal_sprite(sphere: RevealSphere) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _glow_texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.pixel_size = (sphere.radius * 2.0) / float(GLOW_TEXTURE_SIZE)
	sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	sprite.layers = 1 << 1
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mask_root.add_child(sprite)
	return sprite


func _update_spheres(delta: float) -> void:
	var observer_position := _observer.global_position

	for index in range(_active_spheres.size() - 1, -1, -1):
		var sphere := _active_spheres[index]
		var distance_to_observer := observer_position.distance_to(sphere.center)
		var target_strength := _memory_from_distance(distance_to_observer)
		var blend_speed := approach_speed if target_strength > sphere.strength else decay_speed
		sphere.strength = lerpf(sphere.strength, target_strength, minf(1.0, delta * blend_speed))

		if distance_to_observer >= active_pause_distance:
			sphere.age += delta
			var life_ratio := clampf(sphere.age / maxf(sphere.max_age, 0.001), 0.0, 1.0)
			sphere.radius = active_initial_radius * (1.0 - life_ratio)

		if not sphere.afterglow_spawned and distance_to_observer >= ghost_start_distance and sphere.strength <= afterglow_trigger_strength:
			_spawn_afterglow_cluster(sphere)
			sphere.afterglow_spawned = true
			_trim_sphere_budget()

		if sphere.age >= sphere.max_age or sphere.radius <= 0.01 or sphere.strength <= 0.01:
			_free_sphere(_active_spheres, index)
		else:
			_apply_sphere_visual(sphere)

	for index in range(_afterglow_spheres.size() - 1, -1, -1):
		var sphere := _afterglow_spheres[index]
		sphere.age += delta
		var age_factor := 1.0 - clampf(sphere.age / maxf(sphere.max_age, 0.001), 0.0, 1.0)
		sphere.strength = afterglow_initial_strength * age_factor

		if sphere.strength <= 0.01 or sphere.age >= sphere.max_age:
			_free_sphere(_afterglow_spheres, index)
		else:
			_apply_sphere_visual(sphere)


func _apply_sphere_visual(sphere: RevealSphere) -> void:
	if sphere.sprite == null:
		return

	var distance_to_observer := _observer.global_position.distance_to(sphere.center)
	var ghost_blend := clampf(
		(distance_to_observer - ghost_start_distance) / maxf(far_forget_distance - ghost_start_distance, 0.001),
		0.0,
		1.0
	)
	var surface_offset := maxf(0.03, sphere.radius * 0.06)
	var visual_strength := maxf(sphere.strength, debug_min_strength) if _debug_mode else sphere.strength
	if sphere.pauses_when_near and not _debug_mode:
		visual_strength *= lerpf(1.0, active_far_strength_scale, ghost_blend)
	var jitter_offset := Vector3.ZERO
	if ghost_blend > 0.0:
		var time_seconds := Time.get_ticks_msec() * 0.001
		var jitter_multiplier := 1.35 if not sphere.pauses_when_near else 1.0
		var jitter_scale := ghost_jitter_radius * ghost_blend * jitter_multiplier * maxf(sphere.radius / maxf(active_initial_radius, 0.001), 0.65)
		jitter_offset += sphere.tangent_a * sin((time_seconds * ghost_jitter_speed) + sphere.phase) * jitter_scale
		jitter_offset += sphere.tangent_b * cos((time_seconds * ghost_jitter_speed * 1.23) + (sphere.phase * 1.7)) * (jitter_scale * 0.75)

	var sprite_basis := Basis(sphere.tangent_a, sphere.tangent_b, sphere.normal)
	sphere.sprite.global_transform = Transform3D(
		sprite_basis,
		sphere.center + sphere.base_offset + (sphere.normal * surface_offset) + jitter_offset
	)
	sphere.sprite.pixel_size = maxf((sphere.radius * 2.0) / float(GLOW_TEXTURE_SIZE), 0.0001)
	sphere.sprite.modulate = Color(1.0, 1.0, 1.0, visual_strength)
	sphere.sprite.visible = visual_strength > 0.001


func _refresh_sphere_visuals() -> void:
	for sphere in _active_spheres:
		_apply_sphere_visual(sphere)
	for sphere in _afterglow_spheres:
		_apply_sphere_visual(sphere)


func _spawn_afterglow_cluster(active_sphere: RevealSphere) -> void:
	for layer_index in range(maxi(afterglow_layers, 1)):
		_afterglow_spheres.append(_make_afterglow_from_active(active_sphere, layer_index))


func _make_afterglow_from_active(active_sphere: RevealSphere, layer_index: int) -> RevealSphere:
	var layer_factor: float = float(layer_index)
	var inherited_radius: float = maxf(
		active_sphere.radius * (1.08 + (layer_factor * 0.1)),
		afterglow_radius * (0.75 + (layer_factor * 0.12))
	)
	var inherited_strength: float = minf(
		afterglow_initial_strength * (1.0 - (layer_factor * 0.16)),
		active_sphere.strength * (0.72 - (layer_factor * 0.08))
	)
	var afterglow := _make_sphere(
		active_sphere.center,
		active_sphere.normal,
		inherited_radius,
		afterglow_lifetime,
		inherited_strength,
		false
	)
	var offset_angle := (active_sphere.phase * 0.37) + (layer_factor * TAU / maxf(float(maxi(afterglow_layers, 1)), 1.0) * 0.85)
	var offset_scale := maxf(
		afterglow_offset_radius * (1.0 + (layer_factor * 0.45)),
		inherited_radius * (0.16 + (layer_factor * 0.05))
	)
	afterglow.base_offset = (
		(active_sphere.tangent_a * cos(offset_angle) * offset_scale) +
		(active_sphere.tangent_b * sin(offset_angle) * offset_scale * 0.8)
	)
	afterglow.phase = active_sphere.phase + 1.9 + (layer_factor * 0.83)
	_apply_sphere_visual(afterglow)
	return afterglow


func _trim_sphere_budget() -> void:
	while _active_spheres.size() + _afterglow_spheres.size() > max_spheres:
		if not _afterglow_spheres.is_empty():
			_free_sphere(_afterglow_spheres, 0)
		elif not _active_spheres.is_empty():
			_free_sphere(_active_spheres, 0)
		else:
			return


func _free_sphere(spheres: Array[RevealSphere], index: int) -> void:
	var sphere := spheres[index]
	if sphere.sprite != null:
		sphere.sprite.queue_free()
	spheres.remove_at(index)


func _memory_from_distance(distance_to_target: float) -> float:
	if distance_to_target <= near_reveal_distance:
		return 1.0
	if distance_to_target >= far_forget_distance:
		return 0.0

	var t := clampf(
		(distance_to_target - near_reveal_distance) / maxf(far_forget_distance - near_reveal_distance, 0.001),
		0.0,
		1.0
	)
	return 1.0 - (t * t * (3.0 - (2.0 * t)))


func _create_glow_texture(size: int) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_radius := size * 0.5

	for y in range(size):
		for x in range(size):
			var distance_to_center := Vector2(x, y).distance_to(center) / max_radius
			var alpha := 0.0
			if distance_to_center <= 0.58:
				alpha = 1.0
			elif distance_to_center < 1.0:
				var edge_t := clampf((distance_to_center - 0.58) / 0.42, 0.0, 1.0)
				alpha = 1.0 - (edge_t * edge_t * (3.0 - (2.0 * edge_t)))
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)


func _spawn_feedback_line(start: Vector3, ending: Vector3, hit: bool) -> void:
	var immediate_mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.8 if hit else 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(ending)
	immediate_mesh.surface_end()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	_feedback_lines.append({
		"node": mesh_instance,
		"time_left": 0.6
	})


func _update_feedback_lines(delta: float) -> void:
	for index in range(_feedback_lines.size() - 1, -1, -1):
		var entry := _feedback_lines[index]
		entry.time_left -= delta
		if entry.time_left <= 0.0:
			(entry.node as Node).queue_free()
			_feedback_lines.remove_at(index)
		else:
			_feedback_lines[index] = entry
