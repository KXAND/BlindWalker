class_name StepResult
extends RefCounted

enum StepResultType { SUCCESS, STAGGER, FALL }

var type: StepResultType = StepResultType.SUCCESS
var displacement: Vector3 = Vector3.ZERO


func _init(result_type: StepResultType = StepResultType.SUCCESS, result_displacement: Vector3 = Vector3.ZERO) -> void:
	type = result_type
	displacement = result_displacement
