extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8

@onready var touch_memory: TouchMemorySystem = $TouchMemorySystem


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# 左键触发触觉探测（盲人触摸感知）
			if touch_memory:
				touch_memory.try_touch()
	
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				else:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	var input_dir := Vector2(
		int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A)),
		int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
	)
	var move_speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		var deceleration := move_speed * delta * 10.0
		velocity.x = move_toward(velocity.x, 0.0, deceleration)
		velocity.z = move_toward(velocity.z, 0.0, deceleration)

	move_and_slide()
