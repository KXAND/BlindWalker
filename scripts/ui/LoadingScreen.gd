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

const READY_CIRCLE_DARKNESS := 0.62
const BREATH_DARKNESS_LOW := 0.58
const BREATH_DARKNESS_HIGH := 0.66

@export var target_scene: String = "res://scenes/main/Main.tscn"
@export var min_display_time: float = 2.0
@export var loading_music_path: String = "res://assets/audio/music/Dust on the Piano Keys_1.mp3"
@export var intro_text_path: String = "res://assets/text/loading_intro.bbcode"

var _street_bg: TextureRect
var _vignette_overlay: ColorRect
var _title_image: TextureRect
var _loading_label: Label
var _progress_bar: ProgressBar
var _tip_label: Label
var _intro_button: Button
var _intro_overlay: CenterContainer
var _intro_panel: PanelContainer
var _intro_text: RichTextLabel
var _intro_close_button: Button
var _vignette_material: ShaderMaterial
var _music_player: AudioStreamPlayer
var _target_darkness: float = 0.0

var _elapsed: float = 0.0
var _dot_count: int = 0
var _dot_timer: float = 0.0
var _scene_loaded: bool = false
var _started_transition: bool = false
var _awaiting_click: bool = false
var _click_prompt: Label
var _separator: HSeparator
var _breath_tween: Tween
var _circle_breath_tween: Tween

var _tips: Array[String] = ["感受脚下的路...", "聆听周围的声音...", "信任手中的盲杖...", "黑暗中也能找到方向..."]
var _tip_index: int = 0
var _tip_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	build_ui()
	_start_loading_music()
	_load_intro_text()

	var tex := ResourceLoader.load("res://assets/textures/loading_street_blur.png") as Texture2D
	if tex:
		_street_bg.texture = tex
		print("LoadingScreen: texture loaded ", tex.get_size())
	else:
		printerr("LoadingScreen: texture load FAILED")

	# 标题和分隔线隐藏，加载完成后才显示
	_title_image.visible = false
	_loading_label.modulate.a = 0.0
	_progress_bar.modulate.a = 0.0
	_tip_label.modulate.a = 0.0
	_separator.visible = false

	var tw: Tween = create_tween()
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
	_set_darkness(0.0)
	_vignette_overlay.material = _vignette_material
	add_child(_vignette_overlay)

	print("LoadingScreen: vignette darkness=", _vignette_material.get_shader_parameter("darkness"))

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_intro_button = Button.new()
	_intro_button.name = "IntroButton"
	_intro_button.text = "i"
	_intro_button.tooltip_text = "项目介绍 / 开发者介绍"
	_intro_button.anchor_left = 1.0
	_intro_button.anchor_right = 1.0
	_intro_button.anchor_top = 0.0
	_intro_button.anchor_bottom = 0.0
	_intro_button.offset_left = -72.0
	_intro_button.offset_right = -24.0
	_intro_button.offset_top = 24.0
	_intro_button.offset_bottom = 72.0
	_intro_button.add_theme_font_size_override("font_size", 30)
	_intro_button.add_theme_color_override("font_color", Color.WHITE)
	_intro_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_intro_button.add_theme_color_override("font_pressed_color", Color.BLACK)
	_intro_button.add_theme_color_override("font_focus_color", Color.WHITE)
	_intro_button.add_theme_stylebox_override("normal", _make_intro_button_style(Color(0.0, 0.0, 0.0, 0.78), Color(1.0, 1.0, 1.0, 0.9)))
	_intro_button.add_theme_stylebox_override("hover", _make_intro_button_style(Color(0.08, 0.08, 0.08, 0.88), Color(1.0, 1.0, 1.0, 1.0)))
	_intro_button.add_theme_stylebox_override("pressed", _make_intro_button_style(Color(1.0, 1.0, 1.0, 0.9), Color(0.0, 0.0, 0.0, 1.0)))
	_intro_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_intro_button.pressed.connect(_show_intro_panel)
	add_child(_intro_button)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_title_image = TextureRect.new()
	_title_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_image.custom_minimum_size = Vector2(1000, 560)
	_title_image.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title_tex := ResourceLoader.load("res://assets/textures/title_循暗晓明.png") as Texture2D
	if title_tex:
		_title_image.texture = title_tex
		print("LoadingScreen: title image loaded")
	else:
		# 兜底：回退为文字标题
		var fallback_label := Label.new()
		fallback_label.text = "循暗晓明"
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.add_theme_font_size_override("font_size", 42)
		fallback_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		_apply_text_outline(fallback_label, 4)
		vbox.add_child(fallback_label)
		_title_image = null
		printerr("LoadingScreen: title image load FAILED")
		return

	vbox.add_child(_title_image)

	var sep: HSeparator = HSeparator.new()
	sep.custom_minimum_size = Vector2(80, 0)
	_separator = sep
	vbox.add_child(sep)

	_loading_label = Label.new()
	_loading_label.text = "正在加载中"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 18)
	_loading_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_apply_text_outline(_loading_label, 3)
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
	_apply_text_outline(_tip_label, 2)
	vbox.add_child(_tip_label)

	_click_prompt = Label.new()
	_click_prompt.text = "点击任意位置开始游戏"
	_click_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_click_prompt.add_theme_font_size_override("font_size", 16)
	_click_prompt.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_apply_text_outline(_click_prompt, 3)
	_click_prompt.modulate.a = 0.0
	vbox.add_child(_click_prompt)

	_build_intro_overlay()


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
			_loading_label.text = "正在加载中" + "".lpad(_dot_count, ".")

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
		_set_darkness(move_toward(_target_darkness, td, 1.5 * delta))

	if st == ResourceLoader.THREAD_LOAD_LOADED and not _scene_loaded:
		_scene_loaded = true
		_progress_bar.value = 100.0
		_on_loading_complete()


func _on_loading_complete() -> void:
	if _elapsed < min_display_time:
		await get_tree().create_timer(min_display_time - _elapsed).timeout
	if _started_transition:
		return

	# 阶段1：遮罩从外到内推进至全黑，同时淡出加载元素
	var tw_1: Tween = create_tween()
	tw_1.set_parallel(true)
	tw_1.tween_method(_set_darkness,
		_vignette_material.get_shader_parameter("darkness"), 1.0, 0.8)
	tw_1.tween_property(_loading_label, "modulate:a", 0.0, 0.5)
	tw_1.tween_property(_progress_bar, "modulate:a", 0.0, 0.5)
	tw_1.tween_property(_tip_label, "modulate:a", 0.0, 0.5)
	await tw_1.finished

	# _loading_label 和 _tip_label 已完成使命，隐藏
	_loading_label.visible = false
	_tip_label.visible = false
	_progress_bar.visible = false

	# 阶段2：画面全黑，显示标题
	if _title_image:
		_title_image.modulate.a = 0.0
		_title_image.visible = true
		_separator.modulate.a = 0.0
		_separator.visible = true
		var tw_2: Tween = create_tween()
		tw_2.set_parallel(true)
		tw_2.tween_property(_title_image, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_OUT)
		tw_2.tween_property(_separator, "modulate:a", 1.0, 0.8)
		await tw_2.finished

	# 阶段3：淡入点击提示
	_awaiting_click = true
	var tw_3: Tween = create_tween()
	tw_3.tween_property(_click_prompt, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
	await tw_3.finished

	# 阶段4：点击提示轻微呼吸
	_breath_tween = create_tween()
	_breath_tween.tween_property(_click_prompt, "modulate:a", 0.75, 1.2).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_click_prompt, "modulate:a", 1.0, 1.2).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.set_loops()


func _gui_input(event: InputEvent) -> void:
	if not _awaiting_click:
		return
	if _intro_overlay and _intro_overlay.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
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
	if _circle_breath_tween and _circle_breath_tween.is_valid():
		_circle_breath_tween.kill()

	# 退出过渡：圆形收缩到黑场 → 切换场景
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	if _title_image:
		tw.tween_property(_title_image, "modulate:a", 0.0, 0.5)
	tw.tween_property(_separator, "modulate:a", 0.0, 0.5)
	tw.tween_property(_loading_label, "modulate:a", 0.0, 0.5)
	tw.tween_property(_intro_button, "modulate:a", 0.0, 0.5)
	tw.tween_property(_intro_panel, "modulate:a", 0.0, 0.5)
	tw.tween_property(_intro_close_button, "modulate:a", 0.0, 0.5)
	tw.tween_property(_click_prompt, "modulate:a", 0.0, 0.3)
	tw.tween_property(_street_bg, "modulate:a", 0.0, 0.5)
	tw.tween_method(_set_darkness, _vignette_material.get_shader_parameter("darkness"), 1.0, 0.55)
	if _music_player and _music_player.playing:
		tw.tween_property(_music_player, "volume_db", -36.0, 0.5)
	await tw.finished
	if _music_player and _music_player.playing:
		_music_player.stop()
	await get_tree().create_timer(0.4).timeout

	var s: PackedScene = ResourceLoader.load_threaded_get(target_scene) as PackedScene
	if s:
		get_tree().change_scene_to_packed(s)
	else:
		get_tree().change_scene_to_file(target_scene)


func _set_darkness(value: float) -> void:
	_target_darkness = value
	_vignette_material.set_shader_parameter("darkness", value)


func _start_circle_breath() -> void:
	if _circle_breath_tween and _circle_breath_tween.is_valid():
		_circle_breath_tween.kill()
	_circle_breath_tween = create_tween()
	_circle_breath_tween.tween_method(_set_darkness, _target_darkness, BREATH_DARKNESS_LOW, 2.0).set_ease(Tween.EASE_IN_OUT)
	_circle_breath_tween.tween_method(_set_darkness, BREATH_DARKNESS_LOW, BREATH_DARKNESS_HIGH, 2.0).set_ease(Tween.EASE_IN_OUT)
	_circle_breath_tween.tween_method(_set_darkness, BREATH_DARKNESS_HIGH, READY_CIRCLE_DARKNESS, 2.0).set_ease(Tween.EASE_IN_OUT)
	_circle_breath_tween.set_loops()


func _show_intro_panel() -> void:
	_intro_overlay.visible = true
	_intro_button.visible = false


func _hide_intro_panel() -> void:
	_intro_overlay.visible = false
	_intro_button.visible = true


func _build_intro_overlay() -> void:
	_intro_overlay = CenterContainer.new()
	_intro_overlay.name = "IntroOverlay"
	_intro_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_overlay.visible = false
	add_child(_intro_overlay)

	var overlay_layout := VBoxContainer.new()
	overlay_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_layout.add_theme_constant_override("separation", 12)
	_intro_overlay.add_child(overlay_layout)

	_intro_panel = PanelContainer.new()
	_intro_panel.name = "IntroPanel"
	_intro_panel.custom_minimum_size = Vector2(720, 250)
	overlay_layout.add_child(_intro_panel)

	var intro_margin := MarginContainer.new()
	intro_margin.add_theme_constant_override("margin_left", 18)
	intro_margin.add_theme_constant_override("margin_right", 18)
	intro_margin.add_theme_constant_override("margin_top", 12)
	intro_margin.add_theme_constant_override("margin_bottom", 12)
	_intro_panel.add_child(intro_margin)

	_intro_text = RichTextLabel.new()
	_intro_text.name = "IntroText"
	_intro_text.bbcode_enabled = true
	_intro_text.scroll_active = true
	_intro_text.fit_content = false
	_intro_text.custom_minimum_size = Vector2(680, 220)
	_intro_text.add_theme_font_size_override("normal_font_size", 15)
	_intro_text.add_theme_color_override("default_color", Color(0.82, 0.82, 0.78))
	_apply_text_outline(_intro_text, 2)
	intro_margin.add_child(_intro_text)

	_intro_close_button = Button.new()
	_intro_close_button.name = "IntroCloseButton"
	_intro_close_button.text = "关闭介绍"
	_apply_text_outline(_intro_close_button, 2)
	_intro_close_button.pressed.connect(_hide_intro_panel)
	overlay_layout.add_child(_intro_close_button)


func _start_loading_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "LoadingMusicPlayer"
	add_child(_music_player)

	var stream := ResourceLoader.load(loading_music_path) as AudioStream
	if not stream:
		push_warning("LoadingScreen: music load FAILED path=%s" % loading_music_path)
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	_music_player.stream = stream
	_music_player.volume_db = AudioManager.music_volume_db(-8.0)
	AudioManager.audio_settings_changed.connect(_sync_music_volume)
	_music_player.play()
	print("LoadingScreen: music playing path=", loading_music_path)


func _sync_music_volume() -> void:
	if _music_player:
		_music_player.volume_db = AudioManager.music_volume_db(-8.0)


func _load_intro_text() -> void:
	if not _intro_text:
		return

	var text := ""
	if FileAccess.file_exists(intro_text_path):
		text = FileAccess.get_file_as_string(intro_text_path)
	else:
		text = "[font_size=28][b]循暗晓明[/b][/font_size]\n\n项目介绍文本未找到。"
		push_warning("LoadingScreen: intro text missing path=%s" % intro_text_path)

	_intro_text.text = text
	print("LoadingScreen: intro text loaded path=", intro_text_path)


func _apply_text_outline(control: Control, outline_size: int) -> void:
	control.add_theme_constant_override("outline_size", outline_size)
	control.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))


func _make_intro_button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style
