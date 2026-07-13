class_name TouchSphere
## 触摸显影球数据结构 —— 消除 TouchMemorySystem 中的 Data Clump

var center: Vector3 = Vector3.ZERO
var radius: float = 0.0
var initial_radius: float = 0.0
var color: Color = Color(0.4, 0.75, 1.0, 1.0)
var contact_profile_id: StringName = &"default_contact"
var age: float = 0.0
var max_age: float = 0.0
var strength: float = 1.0
