class_name TrafficLane
extends Path3D
## 由少量关卡路径点构建固定车道，供交通车辆循环跟随。

@export var lane_points: PackedVector3Array = PackedVector3Array()


func _enter_tree() -> void:
	var lane_curve := Curve3D.new()
	for point in lane_points:
		lane_curve.add_point(point)
	curve = lane_curve
