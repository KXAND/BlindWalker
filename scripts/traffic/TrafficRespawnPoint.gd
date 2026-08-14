class_name TrafficRespawnPoint
extends Marker3D
## 由关卡显式放置的安全道路边复活锚点。


func _enter_tree() -> void:
	add_to_group("traffic_respawn_point")
