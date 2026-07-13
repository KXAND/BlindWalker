class_name NarrativeSequence
extends Resource
## 叙事序列：按顺序播放的线性剧情内容。

@export var sequence_id: StringName = &""
@export var lines: Array = []
@export var lock_input: bool = true
@export var lock_gameplay: bool = true
@export var default_line_duration: float = 2.0
