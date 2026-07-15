class_name HealthUI
extends CanvasLayer
## 血量 HUD 与受伤/濒死屏幕边缘反馈。
## Issue #0012

const DAMAGE_VIGNETTE_SHADER := """shader_type canvas_item;
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float danger_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float danger_width : hint_range(0.0, 0.25) = 0.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5, 0.5);
	float edge_distance = max(abs(centered_uv.x), abs(centered_uv.y)) * 2.0;
	float danger_edge = smoothstep(1.0 - danger_width, 1.0, edge_distance) * danger_alpha;
	float flash_edge = smoothstep(0.55, 1.0, edge_distance) * damage_flash;
	float alpha = max(danger_edge, flash_edge);
	COLOR = vec4(0.95, 0.0, 0.0, alpha);
}"""

const LOW_HP_THRESHOLD := 0.5
const MAX_DANGER_WIDTH := 0.25
const MAX_DANGER_ALPHA := 0.95
const DAMAGE_FLASH_DECAY := 2.8
const DANGER_ALPHA_SMOOTH := 3.5
const DANGER_WIDTH_SMOOTH := 2.5

var _label: Label
var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _damage_flash: float = 0.0
var _danger_alpha: float = 0.0
var _danger_width: float = 0.0
var _current_hp: int = GameConfig.MAX_HP
var _max_hp: int = GameConfig.MAX_HP
var _pulse_time: float = 0.0


func _ready() -> void:
	layer = 1
	_build_vignette()
	_label = Label.new()
	_label.name = "HpLabel"
	_label.visible = false
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label.offset_left = 12.0
	_label.offset_top = 8.0
	add_child(_label)

	# 主动读取初始值，防止首帧空显示
	var attrs := _find_player_attributes()
	if attrs:
		_current_hp = attrs.hp
		_max_hp = attrs.max_hp
		_update_display(attrs.hp, attrs.max_hp)
	else:
		_label.text = "HP: ? / ?"

	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_healed.connect(_on_hp_changed)


func _process(delta: float) -> void:
	_pulse_time += delta
	_damage_flash = move_toward(_damage_flash, 0.0, DAMAGE_FLASH_DECAY * delta)

	var hp_ratio := _hp_ratio()
	var low_hp_factor := clampf((LOW_HP_THRESHOLD - hp_ratio) / LOW_HP_THRESHOLD, 0.0, 1.0)
	var pulse := 0.8 + 0.2 * sin(_pulse_time * TAU * 1.4)
	var target_alpha := low_hp_factor * pulse * MAX_DANGER_ALPHA
	var target_width := low_hp_factor * MAX_DANGER_WIDTH

	_danger_alpha = move_toward(_danger_alpha, target_alpha, DANGER_ALPHA_SMOOTH * delta)
	_danger_width = move_toward(_danger_width, target_width, DANGER_WIDTH_SMOOTH * delta)
	_apply_vignette()


func _on_hp_changed(_amount: int, current_hp: int) -> void:
	var attrs := _find_player_attributes()
	var max_hp: int = GameConfig.MAX_HP
	if attrs:
		max_hp = attrs.max_hp
	_current_hp = current_hp
	_max_hp = max_hp
	_update_display(current_hp, max_hp)


func _on_player_damaged(_amount: int, current_hp: int) -> void:
	_damage_flash = 1.0
	_on_hp_changed(_amount, current_hp)


func _update_display(current_hp: int, max_hp: int) -> void:
	_label.text = "HP: %d / %d" % [maxi(0, current_hp), max_hp]


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "DamageVignette"
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = DAMAGE_VIGNETTE_SHADER
	_vignette_material.shader = shader
	_vignette.material = _vignette_material
	add_child(_vignette)
	_apply_vignette()


func _apply_vignette() -> void:
	if not _vignette_material:
		return
	_vignette_material.set_shader_parameter("damage_flash", _damage_flash)
	_vignette_material.set_shader_parameter("danger_alpha", _danger_alpha)
	_vignette_material.set_shader_parameter("danger_width", _danger_width)


func _hp_ratio() -> float:
	if _max_hp <= 0:
		return 0.0
	return clampf(float(_current_hp) / float(_max_hp), 0.0, 1.0)


func _find_player_attributes() -> PlayerAttributes:
	return get_tree().get_first_node_in_group("player_attributes") as PlayerAttributes
