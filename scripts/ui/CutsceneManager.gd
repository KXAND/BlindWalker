class_name CutsceneManager
extends Node
## 演出控制器：播放叙事序列，并在播放期间按需锁定输入和 gameplay。

@export var subtitle_label: Label
@export var speaker_label: Label
@export var cutscene_duration: float = 2.0
@export var initial_sequence: Resource
@export var play_initial_sequence_on_ready: bool = false

const CANVAS_LAYER := 5
const _NarrativeLine = preload("res://scripts/core/NarrativeLine.gd")
const _NarrativeSequence = preload("res://scripts/core/NarrativeSequence.gd")

var _subtitle_panel: Panel
var _current_sequence: Resource
var _line_index: int = -1
var _line_elapsed: float = 0.0
var _line_duration: float = 0.0
var _input_locked_by_sequence: bool = false
var _gameplay_locked_by_sequence: bool = false
var _is_playing_sequence: bool = false


func _ready() -> void:
	if not subtitle_label:
		_create_subtitle_ui()
	if play_initial_sequence_on_ready and initial_sequence:
		call_deferred("play_sequence", initial_sequence)


func _exit_tree() -> void:
	_clear_narrative_locks()


func _process(delta: float) -> void:
	if not _is_playing_sequence:
		return
	_line_elapsed += delta
	if _line_elapsed >= _line_duration:
		_advance_line()


func _input(event: InputEvent) -> void:
	if not _is_playing_sequence:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_advance_line()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_finish_sequence()


## 兼容旧接口：保留按 id 播放单句演出的能力。
func play(cutscene_id: String) -> void:
	var sequence := _NarrativeSequence.new()
	sequence.sequence_id = StringName(cutscene_id)
	sequence.lock_input = true
	sequence.lock_gameplay = false
	sequence.default_line_duration = cutscene_duration

	var line := _NarrativeLine.new()
	line.text = _subtitle_for(cutscene_id)
	line.duration = cutscene_duration
	sequence.lines = [line]
	play_sequence(sequence)


func play_sequence(sequence: Resource) -> bool:
	if not sequence:
		return false
	if _is_playing_sequence:
		if GameConfig.DEBUG:
			print("[DEBUG][CutsceneManager] sequence rejected reason=already_playing current=%s next=%s" % [
				_current_sequence.sequence_id,
				sequence.sequence_id,
			])
		return false
	if sequence.lines.is_empty():
		if GameConfig.DEBUG:
			print("[DEBUG][CutsceneManager] sequence ignored reason=no_lines id=%s" % sequence.sequence_id)
		return false

	_current_sequence = sequence
	_line_index = -1
	_is_playing_sequence = true
	_input_locked_by_sequence = sequence.lock_input
	_gameplay_locked_by_sequence = sequence.lock_gameplay
	if _input_locked_by_sequence:
		GameState.set_cutscene_active(true)
	if _gameplay_locked_by_sequence:
		GameState.set_gameplay_locked(true)

	EventBus.cutscene_started.emit(String(sequence.sequence_id))
	if GameConfig.DEBUG:
		print("[DEBUG][CutsceneManager] sequence started id=%s lines=%d lock_input=%s lock_gameplay=%s" % [
			sequence.sequence_id,
			sequence.lines.size(),
			sequence.lock_input,
			sequence.lock_gameplay,
		])

	_advance_line()
	return true


func is_sequence_playing() -> bool:
	return _is_playing_sequence


func _advance_line() -> void:
	if not _is_playing_sequence:
		return

	AudioManager.stop_2d()
	_line_index += 1
	if _line_index >= _current_sequence.lines.size():
		_finish_sequence()
		return

	var line := _current_sequence.lines[_line_index] as Resource
	_line_elapsed = 0.0
	_line_duration = _duration_for(line)
	_show_line(line)
	_play_line_audio(line)

	if GameConfig.DEBUG:
		print("[DEBUG][CutsceneManager] line index=%d speaker=%s text=%s audio=%s duration=%.2f" % [
			_line_index,
			line.get("speaker_name"),
			line.get("text"),
			line.get("audio_id"),
			_line_duration,
		])


func _finish_sequence() -> void:
	if not _is_playing_sequence:
		return

	var sequence_id := String(_current_sequence.sequence_id)
	AudioManager.stop_2d()
	_hide_subtitle()
	_clear_narrative_locks()
	_current_sequence = null
	_line_index = -1
	_line_elapsed = 0.0
	_line_duration = 0.0
	_is_playing_sequence = false
	EventBus.cutscene_ended.emit(sequence_id)
	if GameConfig.DEBUG:
		print("[DEBUG][CutsceneManager] sequence ended id=%s" % sequence_id)


func _clear_narrative_locks() -> void:
	if _input_locked_by_sequence:
		GameState.set_cutscene_active(false)
	if _gameplay_locked_by_sequence:
		GameState.set_gameplay_locked(false)
	_input_locked_by_sequence = false
	_gameplay_locked_by_sequence = false


func _duration_for(line: Resource) -> float:
	var duration: float = line.get("duration")
	if duration > 0.0:
		return duration
	if _current_sequence and _current_sequence.default_line_duration > 0.0:
		return _current_sequence.default_line_duration
	return 2.0


func _show_line(line: Resource) -> void:
	if not subtitle_label:
		return

	subtitle_label.text = line.get("text")
	subtitle_label.visible = true
	if _subtitle_panel:
		_subtitle_panel.visible = true

	if not speaker_label:
		return
	var speaker_name: String = line.get("speaker_name")
	var show_speaker := not speaker_name.strip_edges().is_empty()
	speaker_label.visible = show_speaker
	speaker_label.text = speaker_name if show_speaker else ""


func _play_line_audio(line: Resource) -> void:
	var audio_id: StringName = line.get("audio_id")
	if audio_id == &"":
		return
	AudioManager.play_2d(String(audio_id), 0.0, &"narrative")


func _hide_subtitle() -> void:
	if subtitle_label:
		subtitle_label.visible = false
	if speaker_label:
		speaker_label.visible = false
	if _subtitle_panel:
		_subtitle_panel.visible = false


func _subtitle_for(cutscene_id: String) -> String:
	match cutscene_id:
		"intro":
			return "失去视觉，用盲杖、触摸和声音找到回家的路。"
		"outro":
			return "你到达了目的地。黑暗中仍然有路可走。"
	return ""


func _create_subtitle_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CutsceneCanvasLayer"
	layer.layer = CANVAS_LAYER
	add_child(layer)

	_subtitle_panel = Panel.new()
	_subtitle_panel.name = "SubtitlePanel"
	_subtitle_panel.visible = false
	_subtitle_panel.anchor_left = 0.12
	_subtitle_panel.anchor_right = 0.88
	_subtitle_panel.anchor_top = 0.72
	_subtitle_panel.anchor_bottom = 0.92
	_subtitle_panel.offset_left = 0.0
	_subtitle_panel.offset_right = 0.0
	_subtitle_panel.offset_top = 0.0
	_subtitle_panel.offset_bottom = 0.0
	layer.add_child(_subtitle_panel)

	var margin := MarginContainer.new()
	margin.name = "SubtitleMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_subtitle_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "SubtitleVBox"
	margin.add_child(vbox)

	speaker_label = Label.new()
	speaker_label.name = "SpeakerLabel"
	speaker_label.visible = false
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	speaker_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(speaker_label)

	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.visible = false
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(subtitle_label)
