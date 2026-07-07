class_name NpcDialogue
extends RefCounted

## NPC 对话数据容器；文本和语音路径分离，便于后续接入配音资源。
var lines: Array[String] = []
var voice_paths: Array[String] = []


func _init(dialogue_lines: Array[String] = [], dialogue_voice_paths: Array[String] = []) -> void:
	lines = dialogue_lines
	voice_paths = dialogue_voice_paths
