class_name HomeInitialReveal
extends Node
## 家庭初始显影：场景加载时为配置的锚点生成常驻显影球（pinned），
## 让静态交互无需先触摸即可显示互动提示。与开场流程中衣柜/鞋柜的显影引导一致。

@export var anchor_paths: Array[NodePath] = []
@export var reveal_radius: float = 1.2
@export var reveal_color: Color = Color(0.65, 0.8, 1.0, 1.0)

var _touch_memory: TouchMemorySystem


func _ready() -> void:
	call_deferred("_spawn_reveals")


func _spawn_reveals() -> void:
	_touch_memory = get_tree().root.find_child("TouchMemorySystem", true, false) as TouchMemorySystem
	if not _touch_memory:
		push_warning("%s: TouchMemorySystem 未找到，跳过初始显影" % get_path())
		return
	for path in anchor_paths:
		var anchor := get_node_or_null(path) as Node3D
		if not anchor:
			push_warning("%s: 锚点缺失 %s" % [get_path(), path])
			continue
		_touch_memory.spawn_touch_memory(
			anchor.global_position,
			reveal_radius,
			30.0,
			reveal_radius,
			60.0,
			reveal_color,
			&"opening",
			&"default_contact",
			true
		)
