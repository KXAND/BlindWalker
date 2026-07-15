class_name InputManager
extends Node
## 玩家输入聚合层。统一解释键鼠输入并转发给各组件，同时管理视角旋转。
## 视角控制归入此模块（ADR-0005），不创建独立 ViewController。

@export var mouse_sensitivity: float = 0.005
@export var look_sensitivity: float = 0.002
@export var head_path: NodePath = ^"../Head"
@export var cane_path: NodePath = ^"../CaneSystem"
@export var touch_memory_path: NodePath = ^"../TouchMemorySystem"
@export var interaction_system_path: NodePath = ^"../InteractionSystem"

const PITCH_MIN := deg_to_rad(-80.0)
const PITCH_MAX := deg_to_rad(80.0)

var _player: GaitController
var _head: Node3D
var _cane: CaneSystem
var _touch_memory: TouchMemorySystem
var _interaction_system: InteractionSystem
var _head_pitch: float = 0.0


func _ready() -> void:
	_player = get_parent() as GaitController
	_head = get_node_or_null(head_path) as Node3D
	_cane = get_node_or_null(cane_path) as CaneSystem
	_touch_memory = get_node_or_null(touch_memory_path) as TouchMemorySystem
	_interaction_system = get_node_or_null(interaction_system_path) as InteractionSystem
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Web 平台：阻止浏览器默认右键菜单，否则 MOUSE_BUTTON_RIGHT 会被拦截
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.eval("document.addEventListener('contextmenu', function(e){ e.preventDefault(); }, true);")


func _process(_delta: float) -> void:
	if not GameState.is_input_enabled() or not _player:
		if _player:
			_player.set_moving(false)
			_player.set_recovery_qte_pressed(false)
		return

	# W = continuous forward movement
	_player.set_moving(Input.is_key_pressed(GameConfig.KEY_FORWARD))
	if _player.is_recovery_qte_active():
		_player.set_recovery_qte_pressed(
			Input.is_key_pressed(GameConfig.KEY_CAUTIOUS)
					and Input.is_key_pressed(GameConfig.KEY_HIGH_STEP)
		)
		_player.set_cautious(false)
		_player.set_high_step(false)
		return
	# SHIFT / SPACE = modifier states
	_player.set_cautious(Input.is_key_pressed(GameConfig.KEY_CAUTIOUS))
	_player.set_high_step(Input.is_key_pressed(GameConfig.KEY_HIGH_STEP))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton and event.pressed:
		_handle_mouse_button(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key_pressed(event)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not GameState.is_input_enabled():
		return
	if _player and _player.is_balance_view_locked():
		return

	var direct_look := Input.is_key_pressed(GameConfig.KEY_LOOK_DIRECT)
	var yaw_delta := -event.relative.x * look_sensitivity
	var pitch_delta := -event.relative.y * look_sensitivity

	if direct_look:
		# R mode: mouse directly controls view
		_rotate_player_yaw(yaw_delta)
		_rotate_head_pitch(pitch_delta)
		return

	# Default mode: mouse drives cane sweep first, overflow rotates view
	var cane_delta := Vector2(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	var overflow := cane_delta
	if _cane:
		overflow = _cane.apply_sweep(cane_delta)

	var ratio := look_sensitivity / mouse_sensitivity
	_rotate_player_yaw(overflow.x * ratio)
	_rotate_head_pitch(overflow.y * ratio)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if GameState.is_settings_menu_active():
		return
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if _player and _player.is_balance_view_locked():
		return
	if event.button_index == GameConfig.KEY_TOUCH and _touch_memory and GameState.is_input_enabled():
		_touch_memory.try_touch()


func _handle_key_pressed(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			return
		GameConfig.KEY_INTERACT:
			if _interaction_system and GameState.is_input_enabled():
				_interaction_system.try_interact()


func _rotate_player_yaw(delta: float) -> void:
	if _player and not is_zero_approx(delta):
		_player.rotate_y(delta)


func _rotate_head_pitch(delta: float) -> void:
	if not _head:
		return
	_head_pitch = clampf(_head_pitch + delta, PITCH_MIN, PITCH_MAX)
	_head.rotation.x = _head_pitch


func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
