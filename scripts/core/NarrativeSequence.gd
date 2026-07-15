class_name NarrativeSequence
extends Resource
## 叙事序列：按顺序播放的线性剧情内容。

@export var sequence_id: StringName = &""
@export var lines: Array = []
@export var lock_input: bool = true
@export var lock_gameplay: bool = true
@export var default_line_duration: float = 2.0
@export_enum("subtitle", "fullscreen") var presentation_mode: String = "subtitle"
@export var fullscreen_background_color: Color = Color.BLACK
@export var hold_final_line_for_input: bool = false
@export var final_line_prompt: String = ""
