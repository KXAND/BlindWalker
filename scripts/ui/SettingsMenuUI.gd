class_name SettingsMenuUI
extends CanvasLayer
## 游戏内设置菜单。打开时不暂停世界模拟，只拦截玩家 gameplay 输入。

const LOADING_SCENE := "res://scenes/main/LoadingScreen.tscn"
const MENU_LAYER := 30

var _panel: Panel
var _music_slider: HSlider
var _sfx_slider: HSlider
var _resume_button: Button
var _restart_button: Button
var _home_button: Button
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = MENU_LAYER
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_sync_from_audio_settings()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if _is_cutscene_playing():
		return
	if not GameState.is_playing() and not GameState.is_settings_menu_active():
		return

	get_viewport().set_input_as_handled()
	if visible:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	if visible:
		return
	_previous_mouse_mode = Input.get_mouse_mode()
	visible = true
	GameState.set_settings_menu_active(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_resume_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	GameState.set_settings_menu_active(false)
	if GameState.is_playing():
		Input.set_mouse_mode(_previous_mouse_mode)


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "SettingsPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 360)
	_panel.offset_left = -210
	_panel.offset_top = -180
	_panel.offset_right = 210
	_panel.offset_bottom = 180
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)

	_music_slider = _add_volume_row(layout, "音乐")
	_sfx_slider = _add_volume_row(layout, "音效")

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 8)
	layout.add_child(spacer)

	_resume_button = _add_button(layout, "回到游戏")
	_restart_button = _add_button(layout, "重开本局")
	_home_button = _add_button(layout, "回到主页")

	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_resume_button.pressed.connect(close_menu)
	_restart_button.pressed.connect(_restart_run)
	_home_button.pressed.connect(_return_home)


func _add_volume_row(parent: VBoxContainer, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(58, 1)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	return slider


func _add_button(parent: VBoxContainer, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(1, 42)
	parent.add_child(button)
	return button


func _sync_from_audio_settings() -> void:
	_music_slider.value = AudioManager.get_music_volume()
	_sfx_slider.value = AudioManager.get_sfx_volume()


func _on_music_changed(value: float) -> void:
	AudioManager.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)


func _restart_run() -> void:
	close_menu()
	_stop_game_scene_music()
	AudioManager.stop_all()
	await get_tree().create_timer(0.08).timeout
	GameState.reset_to_loading()
	get_tree().reload_current_scene()


func _return_home() -> void:
	close_menu()
	_stop_game_scene_music()
	AudioManager.stop_all()
	await get_tree().create_timer(0.08).timeout
	GameState.reset_to_loading()
	get_tree().change_scene_to_file(LOADING_SCENE)


func _is_cutscene_playing() -> bool:
	for node in get_tree().get_nodes_in_group("cutscene_manager"):
		var manager := node as CutsceneManager
		if manager and manager.is_sequence_playing():
			return true
	return false


func _stop_game_scene_music() -> void:
	var game_root := get_tree().root.find_child("GameRoot", true, false)
	if game_root and game_root.has_method("stop_game_music"):
		game_root.call("stop_game_music")
