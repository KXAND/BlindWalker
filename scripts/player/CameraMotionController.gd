class_name CameraMotionController
extends Camera3D
## 身体失衡镜头层。只做临时视觉偏移，结束后回到初始局部姿态。

enum MotionState { IDLE, LIGHT_STUMBLE, UNSTABLE_STUMBLE, FALL, TUMBLE, GET_UP }

var _base_position: Vector3
var _base_rotation: Vector3
var _state: int = MotionState.IDLE
var _time: float = 0.0
var _duration: float = 0.0
var _get_up_start_position: Vector3
var _get_up_start_rotation: Vector3


func _ready() -> void:
	_base_position = position
	_base_rotation = rotation
	EventBus.player_light_stumbled.connect(_on_light_stumbled)
	EventBus.player_unstable_stumbled.connect(_on_unstable_stumbled)
	EventBus.player_fall_started.connect(_on_fall_started)
	EventBus.player_tumble_started.connect(_on_tumble_started)
	EventBus.player_get_up_started.connect(_on_get_up_started)
	EventBus.player_balance_recovered.connect(_on_balance_recovered)


func _process(delta: float) -> void:
	_time += delta
	match _state:
		MotionState.IDLE:
			_apply_transform(_base_position, _base_rotation)
		MotionState.LIGHT_STUMBLE:
			_update_stumble(false)
		MotionState.UNSTABLE_STUMBLE:
			_update_stumble(true)
		MotionState.FALL:
			_update_fall()
		MotionState.TUMBLE:
			_update_tumble()
		MotionState.GET_UP:
			_update_get_up()


func debug_motion_state() -> StringName:
	match _state:
		MotionState.IDLE:
			return &"idle"
		MotionState.LIGHT_STUMBLE:
			return &"light_stumble"
		MotionState.UNSTABLE_STUMBLE:
			return &"unstable_stumble"
		MotionState.FALL:
			return &"fall"
		MotionState.TUMBLE:
			return &"tumble"
		MotionState.GET_UP:
			return &"get_up"
	return &"unknown"


func _on_light_stumbled() -> void:
	_start(MotionState.LIGHT_STUMBLE, GameConfig.LIGHT_STUMBLE_RECOVER_TIME)


func _on_unstable_stumbled(qte_window: float) -> void:
	_start(MotionState.UNSTABLE_STUMBLE, qte_window)


func _on_fall_started() -> void:
	_start(MotionState.FALL, 0.45)


func _on_tumble_started() -> void:
	_start(MotionState.TUMBLE, GameConfig.TUMBLE_MAX_TIME)


func _on_get_up_started(duration: float) -> void:
	_get_up_start_position = position
	_get_up_start_rotation = rotation
	_start(MotionState.GET_UP, duration)


func _on_balance_recovered() -> void:
	_start(MotionState.IDLE, 0.0)
	_apply_transform(_base_position, _base_rotation)


func _start(next_state: int, duration: float) -> void:
	_state = next_state
	_time = 0.0
	_duration = duration


func _update_stumble(strong: bool) -> void:
	var t := _progress()
	var fade := 1.0 - t
	var amp := 1.0 if strong else 0.45
	var pos := _base_position + Vector3(
		sin(_time * 42.0) * 0.035 * amp * fade,
		sin(_time * 31.0) * 0.025 * amp * fade,
		0.0
	)
	var rot := _base_rotation + Vector3(
		sin(_time * 29.0) * deg_to_rad(2.5) * amp * fade,
		0.0,
		sin(_time * 37.0) * deg_to_rad(4.5) * amp * fade
	)
	_apply_transform(pos, rot)
	if t >= 1.0:
		_start(MotionState.IDLE, 0.0)


func _update_fall() -> void:
	var t := _progress()
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var pos := _base_position + Vector3(0.0, -0.85 * eased, 0.08 * eased)
	var rot := _base_rotation + Vector3(deg_to_rad(-34.0) * eased, 0.0, deg_to_rad(15.0) * eased)
	_apply_transform(pos, rot)
	if t >= 1.0:
		_start(MotionState.TUMBLE, GameConfig.TUMBLE_MAX_TIME)


func _update_tumble() -> void:
	var pos := _base_position + Vector3(
		sin(_time * 18.0) * 0.04,
		-0.85 + sin(_time * 21.0) * 0.05,
		0.08
	)
	var rot := _base_rotation + Vector3(
		deg_to_rad(-34.0) + sin(_time * 12.0) * deg_to_rad(6.0),
		0.0,
		sin(_time * 15.0) * deg_to_rad(25.0)
	)
	_apply_transform(pos, rot)


func _update_get_up() -> void:
	var t := _progress()
	var eased := t * t * (3.0 - 2.0 * t)
	_apply_transform(
		_get_up_start_position.lerp(_base_position, eased),
		_get_up_start_rotation.lerp(_base_rotation, eased)
	)
	if t >= 1.0:
		_start(MotionState.IDLE, 0.0)


func _progress() -> float:
	if _duration <= 0.0:
		return 1.0
	return clampf(_time / _duration, 0.0, 1.0)


func _apply_transform(pos: Vector3, rot: Vector3) -> void:
	position = pos
	rotation = rot
