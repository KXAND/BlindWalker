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
		# 非 gameplay 状态要清空持续输入意图，避免菜单/叙事结束后继承上一帧移动或 QTE 按住状态。
		if _player:
			_player.set_movement_input(Vector2.ZERO)
			_player.set_recovery_qte_pressed(false)
		return

	# WASD 是连续移动输入，放在 _process 轮询以持续转发当前移动意图。
	var movement_input := Vector2.ZERO
	movement_input.x = float(Input.is_key_pressed(GameConfig.KEY_RIGHT)) - float(Input.is_key_pressed(GameConfig.KEY_LEFT))
	movement_input.y = float(Input.is_key_pressed(GameConfig.KEY_BACKWARD)) - float(Input.is_key_pressed(GameConfig.KEY_FORWARD))
	_player.set_movement_input(movement_input)
	if _player.is_recovery_qte_active():
		# 失衡 QTE 期间，SHIFT + SPACE 被解释为“稳住身体”，不再作为普通移动修饰键传递。
		_player.set_recovery_qte_pressed(
			Input.is_key_pressed(GameConfig.KEY_CAUTIOUS)
					and Input.is_key_pressed(GameConfig.KEY_HIGH_STEP)
		)
		_player.set_cautious(false)
		_player.set_high_step(false)
		return
	# 正常移动阶段，SHIFT 和 SPACE 分别表达谨慎/高抬腿这两个步态修饰意图。
	_player.set_cautious(Input.is_key_pressed(GameConfig.KEY_CAUTIOUS))
	_player.set_high_step(Input.is_key_pressed(GameConfig.KEY_HIGH_STEP))


func _unhandled_input(event: InputEvent) -> void:
	# Gameplay 输入放在 _unhandled_input，让 UI、菜单和叙事先消费 SPACE/ESC/点击等事件。
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
		# 摔倒/起身时镜头由 CameraMotionController 表达身体状态，禁止鼠标覆盖这段反馈。
		return

	var direct_look := Input.is_key_pressed(GameConfig.KEY_LOOK_DIRECT)
	var yaw_delta := -event.relative.x * look_sensitivity
	var pitch_delta := -event.relative.y * look_sensitivity

	if direct_look:
		# 按住 R 时进入直接看向模式，绕过盲杖，方便调试视角或快速观察路线。
		_rotate_player_yaw(yaw_delta)
		_rotate_head_pitch(pitch_delta)
		return

	# 默认先用鼠标驱动盲杖扫动，只有杖到达可摆动边界后的溢出才转成视角旋转。
	var cane_delta := Vector2(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	var overflow := cane_delta
	if _cane:
		overflow = _cane.apply_sweep(cane_delta)

	# overflow 使用盲杖灵敏度单位，转视角前换算到 look_sensitivity，保证两套手感可独立调参。
	var ratio := look_sensitivity / mouse_sensitivity
	_rotate_player_yaw(overflow.x * ratio)
	_rotate_head_pitch(overflow.y * ratio)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if GameState.is_settings_menu_active():
		# 菜单打开时鼠标归 UI 使用，不应同时触发手触探测。
		return
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		# 第一次点击只用于重新捕获鼠标，避免同一次点击既锁鼠标又触发 gameplay。
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if _player and _player.is_balance_view_locked():
		# 身体失衡锁视角期间也锁手触，避免摔倒/起身反馈中继续发起探测。
		return
	if event.button_index == GameConfig.KEY_TOUCH and _touch_memory and GameState.is_input_enabled():
		# 右键是“手触”探测入口；它属于 gameplay 输入，所以仍要通过状态闸门。
		_touch_memory.try_touch()


func _handle_key_pressed(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			# ESC 由设置菜单或叙事层处理；这里不再发起 gameplay 行为。
			return
		GameConfig.KEY_INTERACT:
			# E 是世界交互键，只在 gameplay 状态下交给 InteractionSystem。
			if _interaction_system and GameState.is_input_enabled():
				_interaction_system.try_interact()
		GameConfig.KEY_CANE_TOGGLE:
			# T 在 gameplay 中切换盲杖收放；过渡期间由 CaneSystem 忽略重复切换。
			if _cane and GameState.is_input_enabled():
				_cane.toggle_deployment()


func _rotate_player_yaw(delta: float) -> void:
	if _player and not is_zero_approx(delta):
		# FPS 两轴模型：身体只绕 Y 轴转向，避免把 roll 混进玩家胶囊体。
		_player.rotate_y(delta)


func _rotate_head_pitch(delta: float) -> void:
	if not _head:
		return
	# pitch 单独挂在 Head 上，便于夹角限制；这里不需要四元数的任意姿态能力。
	_head_pitch = clampf(_head_pitch + delta, PITCH_MIN, PITCH_MAX)
	_head.rotation.x = _head_pitch


func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
