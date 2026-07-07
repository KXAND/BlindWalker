class_name InputManager
extends Node

## 玩家输入聚合层。它只解释键鼠输入并调用组件接口，不承载步态、碰撞或触觉记忆规则。
@export var mouse_sensitivity: float = 0.005
@export var look_sensitivity: float = 0.002
@export var head_path: NodePath = ^"../Head"
@export var cane_path: NodePath = ^"../CaneSystem"
@export var touch_memory_path: NodePath = ^"../TouchMemorySystem"

var input_enabled: bool = true

var _player: GaitController
var _head: Node3D
var _cane: CaneSystem
var _touch_memory: TouchMemorySystem
var _head_pitch: float = 0.0


func _ready() -> void:
	# 输入管理器是玩家运行时输入的唯一入口；其它玩家组件只接收意图，不直接读取 Input。
	_player = get_parent() as GaitController
	_head = get_node_or_null(head_path) as Node3D
	_cane = get_node_or_null(cane_path) as CaneSystem
	_touch_memory = get_node_or_null(touch_memory_path) as TouchMemorySystem
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton and event.pressed:
		_handle_mouse_button(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key_pressed(event)


func _process(delta: float) -> void:
	if not input_enabled or not _player:
		return

	# SHIFT/SPACE 是持续输入，按帧缓存给步态系统；地形判定仍由 GaitController 自己负责。
	_player.set_cautious_active(Input.is_key_pressed(GameConfig.KEY_CAUTIOUS))
	_player.update_high_step(Input.is_key_pressed(GameConfig.KEY_HIGH_STEP), delta)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var direct_look := Input.is_key_pressed(GameConfig.KEY_LOOK_DIRECT)
	var yaw_delta := -event.relative.x * look_sensitivity
	var pitch_delta := -event.relative.y * look_sensitivity

	if direct_look:
		# R 模式锁定的是盲杖相对玩家的局部姿态；玩家整体转动时盲杖仍会跟随 Player 一起转。
		_rotate_player_yaw(yaw_delta)
		_rotate_head_pitch(pitch_delta)
		return

	var cane_delta := Vector2(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	var overflow := cane_delta
	if _cane:
		overflow = _cane.apply_sweep(cane_delta)

	# 默认模式下鼠标先挥杖，只有超出盲杖局部边界的余量才转动玩家/视角。
	_rotate_player_yaw(overflow.x * look_sensitivity / mouse_sensitivity)
	_rotate_head_pitch(overflow.y * look_sensitivity / mouse_sensitivity)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.button_index == GameConfig.KEY_TOUCH and _touch_memory:
		_touch_memory.try_touch()


func _handle_key_pressed(event: InputEventKey) -> void:
	match event.keycode:
		GameConfig.KEY_LEFT_FOOT:
			_dispatch_step_request(&"left")
		GameConfig.KEY_RIGHT_FOOT:
			_dispatch_step_request(&"right")
		KEY_ESCAPE:
			_toggle_mouse_capture()


func _dispatch_step_request(foot: StringName) -> void:
	if _player:
		_player.request_step(foot)


func _rotate_player_yaw(delta: float) -> void:
	if _player and not is_zero_approx(delta):
		_player.rotate_y(delta)


func _rotate_head_pitch(delta: float) -> void:
	if not _head:
		return

	_head_pitch = clampf(_head_pitch + delta, deg_to_rad(-80.0), deg_to_rad(80.0))
	_head.rotation.x = _head_pitch


func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
