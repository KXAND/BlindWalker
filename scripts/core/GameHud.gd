extends CanvasLayer

const COMPOSITE_SHADER := preload("res://assets/materials/MemoryComposite.gdshader")

const INFO_TEXT := "⏸️ 靠近暂停缩小 · 按H切换调试残影"
const INFO_DEBUG_TEXT := "🔧 调试模式开启 · 显示全部残影"
const DEBUG_HINT_TEXT := "🔧 H键：调试模式（显示全部残影）"
const INSTRUCTION_TEXT := "🖱️ 点击画面锁定鼠标 | WASD 移动 | 鼠标环顾 | 左键涂色"

var _post_process_rect: ColorRect
var _post_process_material: ShaderMaterial
var _info_label: Label
var _debug_hint_label: Label
var _instruction_label: Label
var _crosshair: Control
var _pending_mask_texture: Texture2D
var _pending_background_color: Color = Color(0.039216, 0.039216, 0.078431, 1.0)
var _pending_blur_radius: float = 0.004


func _ready() -> void:
	layer = 10
	_create_post_process_rect()
	_create_labels()
	_crosshair = _create_crosshair()
	add_child(_crosshair)
	set_background_color(_pending_background_color)
	set_blur_radius(_pending_blur_radius)
	if _pending_mask_texture != null:
		set_mask_texture(_pending_mask_texture)
	_update_visibility()
	set_debug_mode(false)
	set_process(true)


func _process(_delta: float) -> void:
	_update_visibility()


func set_mask_texture(texture: Texture2D) -> void:
	_pending_mask_texture = texture
	if _post_process_material == null:
		return
	_post_process_material.set_shader_parameter("mask_texture", texture)


func set_background_color(color_value: Color) -> void:
	_pending_background_color = color_value
	if _post_process_material == null:
		return
	_post_process_material.set_shader_parameter("background_color", color_value)


func set_blur_radius(radius: float) -> void:
	_pending_blur_radius = radius
	if _post_process_material == null:
		return
	_post_process_material.set_shader_parameter("blur_radius", radius)


func set_debug_mode(enabled: bool) -> void:
	_info_label.text = INFO_DEBUG_TEXT if enabled else INFO_TEXT
	_info_label.label_settings.font_color = Color(1.0, 0.8, 0.25, 1.0) if enabled else Color(0.95, 0.96, 0.98, 1.0)
	_debug_hint_label.visible = not enabled
	if _post_process_material != null:
		_post_process_material.set_shader_parameter("debug_mode", enabled)


func _create_post_process_rect() -> void:
	_post_process_material = ShaderMaterial.new()
	_post_process_material.shader = COMPOSITE_SHADER
	_post_process_material.resource_local_to_scene = true

	_post_process_rect = ColorRect.new()
	_post_process_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_process_rect.anchor_right = 1.0
	_post_process_rect.anchor_bottom = 1.0
	_post_process_rect.material = _post_process_material
	add_child(_post_process_rect)


func _create_labels() -> void:
	_info_label = _create_label(INFO_TEXT, 14)
	_info_label.position = Vector2(20.0, 20.0)
	add_child(_info_label)

	_debug_hint_label = _create_label(DEBUG_HINT_TEXT, 12)
	_debug_hint_label.position = Vector2(20.0, 80.0)
	_debug_hint_label.label_settings.font_color = Color(1.0, 1.0, 1.0, 0.5)
	add_child(_debug_hint_label)

	_instruction_label = _create_label(INSTRUCTION_TEXT, 16)
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.anchor_left = 0.5
	_instruction_label.anchor_right = 0.5
	_instruction_label.anchor_top = 1.0
	_instruction_label.anchor_bottom = 1.0
	_instruction_label.offset_left = -320.0
	_instruction_label.offset_top = -56.0
	_instruction_label.offset_right = 320.0
	_instruction_label.offset_bottom = -24.0
	add_child(_instruction_label)


func _create_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.label_settings = _create_label_settings(font_size)
	return label


func _create_label_settings(font_size: int) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = Color(0.95, 0.96, 0.98, 1.0)
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.75)
	settings.outline_size = 6
	return settings


func _create_crosshair() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -10.0
	root.offset_top = -10.0
	root.offset_right = 10.0
	root.offset_bottom = 10.0

	var vertical := ColorRect.new()
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.color = Color(1.0, 1.0, 1.0, 0.75)
	vertical.anchor_left = 0.5
	vertical.anchor_right = 0.5
	vertical.anchor_top = 0.0
	vertical.anchor_bottom = 1.0
	vertical.offset_left = -1.0
	vertical.offset_right = 1.0
	root.add_child(vertical)

	var horizontal := ColorRect.new()
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal.color = Color(1.0, 1.0, 1.0, 0.75)
	horizontal.anchor_left = 0.0
	horizontal.anchor_right = 1.0
	horizontal.anchor_top = 0.5
	horizontal.anchor_bottom = 0.5
	horizontal.offset_top = -1.0
	horizontal.offset_bottom = 1.0
	root.add_child(horizontal)

	return root


func _update_visibility() -> void:
	var is_captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	_instruction_label.visible = not is_captured
	_crosshair.visible = is_captured
