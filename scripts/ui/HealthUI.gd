class_name HealthUI
extends CanvasLayer
## 血量数字显示 HUD —— 仅用于辅助开发测试。
## 主要玩家反馈渠道为音效，此 UI 不作为游戏体验核心。
## Issue #0012

var _label: Label


func _ready() -> void:
	layer = 1
	_label = Label.new()
	_label.name = "HpLabel"
	_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_label.offset_left = 12.0
	_label.offset_top = 8.0
	add_child(_label)

	# 主动读取初始值，防止首帧空显示
	var attrs := _find_player_attributes()
	if attrs:
		_update_display(attrs.hp, attrs.max_hp)
	else:
		_label.text = "HP: ? / ?"

	EventBus.player_damaged.connect(_on_hp_changed)
	EventBus.player_healed.connect(_on_hp_changed)


func _on_hp_changed(_amount: int, current_hp: int) -> void:
	var attrs := _find_player_attributes()
	var max_hp: int = GameConfig.MAX_HP
	if attrs:
		max_hp = attrs.max_hp
	_update_display(current_hp, max_hp)


func _update_display(current_hp: int, max_hp: int) -> void:
	_label.text = "HP: %d / %d" % [maxi(0, current_hp), max_hp]


func _find_player_attributes() -> PlayerAttributes:
	return get_tree().get_first_node_in_group("player_attributes") as PlayerAttributes
