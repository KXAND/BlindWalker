class_name NpcDialogue
extends RefCounted

var lines: Array[String] = []
var voice_paths: Array[String] = []


func _init(dialogue_lines: Array[String] = [], dialogue_voice_paths: Array[String] = []) -> void:
	lines = dialogue_lines
	voice_paths = dialogue_voice_paths
