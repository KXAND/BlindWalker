class_name PlayerAttributes
extends Node

@export var max_hp: int = GameConfig.MAX_HP

var hp: int = GameConfig.MAX_HP


func _ready() -> void:
	hp = max_hp


func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return

	var applied_damage: int = mini(amount, hp)
	hp = maxi(hp - applied_damage, 0)
	print("PlayerAttributes: damaged=%d hp=%d/%d" % [applied_damage, hp, max_hp])
	EventBus.player_damaged.emit(applied_damage, hp)

	if hp == 0:
		print("PlayerAttributes: died")
		EventBus.player_died.emit()


func heal(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return

	var old_hp := hp
	hp = mini(hp + amount, max_hp)
	var healed := hp - old_hp
	if healed > 0:
		print("PlayerAttributes: healed=%d hp=%d/%d" % [healed, hp, max_hp])
		EventBus.player_healed.emit(healed, hp)
