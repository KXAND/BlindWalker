class_name NarrativeLine
extends Resource
## 叙事行：叙事序列中的单条台词或旁白。

@export var speaker_id: StringName = &""
@export var speaker_name: String = ""
@export_multiline var text: String = ""
@export var audio_id: StringName = &""
@export var duration: float = 0.0
