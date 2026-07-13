class_name ContactProfile
extends Resource
## 触碰属性：对象或部件被手触/杖触感知时使用的反馈配置。
## 它不是渲染材质，也不等同于真实材质。

@export var id: StringName = &"default_contact"
@export var display_name: String = "默认触碰属性"
@export var reveal_color: Color = Color(0.4, 0.75, 1.0, 1.0)
@export var cane_sound_id: StringName = &"cane_tap_default"
