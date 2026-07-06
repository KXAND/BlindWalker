class_name ViewController
extends Node

@export var mouse_sensitivity: float = 0.002
@export var head_path: NodePath = ^"Head"

var input_enabled: bool = true

var _player: Node3D
var _head: Node3D
var _pitch: float = 0.0


func _ready() -> void:
	_player = get_parent() as Node3D
	if _player:
		_head = _player.get_node_or_null(head_path) as Node3D


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.is_key_pressed(GameConfig.KEY_LOOK_DIRECT):
		rotate_view(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)


func rotate_view(h_angle: float, v_angle: float) -> void:
	if not _player or not _head:
		return

	_player.rotate_y(h_angle)
	_pitch = clampf(_pitch + v_angle, deg_to_rad(-80.0), deg_to_rad(80.0))
	_head.rotation.x = _pitch


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
