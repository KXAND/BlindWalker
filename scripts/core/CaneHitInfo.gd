class_name CaneHitInfo
extends RefCounted

var collider: Object
var point: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.ZERO


func _init(hit_collider: Object = null, hit_point: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
	collider = hit_collider
	point = hit_point
	normal = hit_normal
