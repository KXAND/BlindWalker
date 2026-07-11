class_name RaycastUtil
## 共享射线查询工具，消除多处重复的 PhysicsRayQueryParameters3D 构造代码。


static func query_body(
	space_state: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	exclude_rid: RID = RID()
) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if exclude_rid != RID():
		query.exclude = [exclude_rid]
	return space_state.intersect_ray(query)
