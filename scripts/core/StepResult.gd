class_name StepResult
extends RefCounted

## 单次迈步判定结果。当前实现主要直接执行位移，保留该结构给后续测试/重构使用。
enum StepResultType { SUCCESS, STAGGER, FALL }

var type: StepResultType = StepResultType.SUCCESS
var displacement: Vector3 = Vector3.ZERO


func _init(result_type: StepResultType = StepResultType.SUCCESS, result_displacement: Vector3 = Vector3.ZERO) -> void:
	type = result_type
	displacement = result_displacement
