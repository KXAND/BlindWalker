extends Control

## 加载动画控制器 — 所有 UI 纯代码构建，运行时加载纹理和着色器
const VIGNETTE_SHADER := """shader_type canvas_item;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 center_vec = UV - vec2(0.5, 0.5);
	vec2 ellipse = center_vec * vec2(16.0 / 9.0, 1.0);
	float dist = length(ellipse);
	float inner_radius = mix(0.7, -0.05, darkness);
	float vignette = smoothstep(inner_radius, inner_radius + 0.05, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vignette);
}"""

@export var target_scene: String = "res://scenes/main/Main.tscn"
@export var min_display_time: float = 2.0

var _street_bg: TextureRect
var _vignette_overlay: ColorRect
var _title_label: Label
var _loading_label: Label
var _progress_bar: ProgressBar
var _tip_label: Label
var _vignette_material: ShaderMaterial

var _elapsed: float = 0.0
var _dot_count: int = 0
var _dot_timer: float = 0.0
var _scene_loaded: bool = false
var _started_transition: bool = false
var _awaiting_click: bool = false
var _click_prompt: Label
var _separator: HSeparator
var _breath_tween: Tween

var _tips: Array[String] = ["感受脚下的路...", "聆听周围的声音...", "信任手中的盲杖...", "黑暗中也能找到方向..."]
var _tip_index: int = 0
var _tip_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	build_ui()

	var img: Image = Image.new()
	var err: Error = img.load("res://assets/textures/loading_street_blur.png")
	if err == OK:
		var tex: ImageTexture = ImageTexture.create_from_image(img)
		_street_bg.texture = tex
		print("LoadingScreen: texture loaded ", tex.get_size())
	else:
		printerr("LoadingScreen: texture load FAILED, error=", err)

	_title_label.modulate.a = 0.0
	_loading_label.modulate.a = 0.0
	_progress_bar.modulate.a = 0.0
	_tip_label.modulate.a = 0.0

	var tw: Tween = create_tween()
	tw.tween_property(_title_label, "modulate:a", 1.0, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(_loading_label, "modulate:a", 1.0, 0.6)
	tw.parallel().tween_property(_progress_bar, "modulate:a", 1.0, 0.6)
	tw.parallel().tween_property(_tip_label, "modulate:a", 1.0, 0.6)

	ResourceLoader.load_threaded_request(target_scene)


func build_ui() -> void:
	_street_bg = TextureRect.new()
	_street_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_street_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_street_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_street_bg)

	_vignette_overlay = ColorRect.new()
	_vignette_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_overlay.color = Color(0, 0, 0, 0)
	_vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader: Shader = Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.set_shader_parameter("darkness", 0.0)
	_vignette_overlay.material = _vignette_material
	add_child(_vignette_overlay)

	print("LoadingScreen: vignette darkness=", _vignette_material.get_shader_parameter("darkness"))

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "BlindWalker"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.uppercase = true
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	vbox.add_child(_title_label)

	var sep: HSeparator = HSeparator.new()
	sep.custom_minimum_size = Vector2(80, 0)
	_separator = sep
	vbox.add_child(sep)

	_loading_label = Label.new()
	_loading_label.text = "正在准备"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 18)
	_loading_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(_loading_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(200, 0)
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)

	_tip_label = Label.new()
	_tip_label.text = _tips[0]
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", 14)
	_tip_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	vbox.add_child(_tip_label)

	_click_prompt = Label.new()
	_click_prompt.text = "点击任意位置开始游戏"
	_click_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_click_prompt.add_theme_font_size_override("font_size", 16)
	_click_prompt.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_click_prompt.modulate.a = 0.0
	vbox.add_child(_click_prompt)


func _process(delta: float) -> void:
	if _started_transition:
		return
	_elapsed += delta

	# 省略号（加载完成后停止）
	if not _scene_loaded:
		_dot_timer += delta
		if _dot_timer >= 0.4:
			_dot_timer = 0.0
			_dot_count = (_dot_count + 1) % 4
			_loading_label.text = "正在准备" + "".lpad(_dot_count, ".")

	# 提示轮播（加载完成后停止）
	if not _scene_loaded:
		_tip_timer += delta
		if _tip_timer >= 3.0:
			_tip_timer = 0.0
			_tip_index = (_tip_index + 1) % _tips.size()
			var tw: Tween = create_tween()
			tw.tween_property(_tip_label, "modulate:a", 0.0, 0.3)
			tw.tween_callback(func(): _tip_label.text = _tips[_tip_index])
			tw.tween_property(_tip_label, "modulate:a", 1.0, 0.3)

	# 加载进度
	var arr: Array = []
	var st: int = ResourceLoader.load_threaded_get_status(target_scene, arr)
	var raw_prog: float = 0.0
	if arr.size() > 0:
		raw_prog = arr[0] as float
		_progress_bar.value = move_toward(_progress_bar.value, minf(raw_prog * 100.0, 95.0), 30.0 * delta)

	# 晕影直接跟随原始加载进度，不再依赖进度条平滑值
	if not _scene_loaded:
		var td: float = clamp(raw_prog, 0.0, 0.95)
		var cd: float = _vignette_material.get_shader_parameter("darkness")
		_vignette_material.set_shader_parameter("darkness", move_toward(cd, td, 1.5 * delta))

	if st == ResourceLoader.THREAD_LOAD_LOADED and not _scene_loaded:
		_scene_loaded = true
		_progress_bar.value = 100.0
		_on_loading_complete()


func _on_loading_complete() -> void:
	if _elapsed < min_display_time:
		await get_tree().create_timer(min_display_time - _elapsed).timeout
	if _started_transition:
		return

	# 阶段1：淡出加载元素（省略号+进度条+提示）
	var tw_1: Tween = create_tween()
	tw_1.set_parallel(true)
	tw_1.tween_property(_loading_label, "modulate:a", 0.0, 0.4)
	tw_1.tween_property(_progress_bar, "modulate:a", 0.0, 0.4)
	tw_1.tween_property(_tip_label, "modulate:a", 0.0, 0.4)
	await tw_1.finished

	# 阶段2：切换到"准备完成"并渐入 + 晕影到全黑
	_loading_label.text = "准备完成"
	var tw_2: Tween = create_tween()
	tw_2.set_parallel(true)
	tw_2.tween_property(_loading_label, "modulate:a", 1.0, 0.5)
	tw_2.tween_method(_set_darkness,
		_vignette_material.get_shader_parameter("darkness"), 1.0, 0.6)
	await tw_2.finished

	# 阶段3：淡入点击提示
	_awaiting_click = true
	var tw_3: Tween = create_tween()
	tw_3.tween_property(_click_prompt, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
	await tw_3.finished

	# 阶段4：呼吸闪烁效果（往返循环）
	_breath_tween = create_tween()
	_breath_tween.tween_property(_click_prompt, "modulate:a", 0.3, 0.8).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_click_prompt, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.set_loops()


func _gui_input(event: InputEvent) -> void:
	if not _awaiting_click:
		return
	if event is InputEventMouseButton and event.pressed:
		_awaiting_click = false
		_start_quit_transition()
	elif event is InputEventKey and event.pressed and not event.echo:
		_awaiting_click = false
		_start_quit_transition()


func _start_quit_transition() -> void:
	if _started_transition:
		return
	_started_transition = true

	# 杀掉呼吸闪烁 tween，防止它跟退出淡出冲突
	if _breath_tween and _breath_tween.is_valid():
		_breath_tween.kill()

	# 退出过渡：淡出所有 UI 元素 → 纯黑停留 → 切换场景
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_title_label, "modulate:a", 0.0, 0.5)
	tw.tween_property(_separator, "modulate:a", 0.0, 0.5)
	tw.tween_property(_loading_label, "modulate:a", 0.0, 0.5)
	tw.tween_property(_click_prompt, "modulate:a", 0.0, 0.3)
	tw.tween_property(_street_bg, "modulate:a", 0.0, 0.5)
	await tw.finished
	await get_tree().create_timer(0.4).timeout

	var s: PackedScene = ResourceLoader.load_threaded_get(target_scene) as PackedScene
	if s:
		get_tree().change_scene_to_packed(s)
	else:
		get_tree().change_scene_to_file(target_scene)


func _set_darkness(value: float) -> void:
	_vignette_material.set_shader_parameter("darkness", value)
