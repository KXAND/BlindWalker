class_name PlayerAttributes
extends Node
## 玩家血量组件。只管理数值和事件，不决定失败流程。

@export var max_hp: int = GameConfig.MAX_HP
@export var idle_heal_delay: float = 3.0
@export var min_idle_heal_per_second: float = 0.5
@export var max_idle_heal_per_second: float = 5.0

var hp: int = GameConfig.MAX_HP
var _idle_timer: float = 0.0
var _heal_accumulator: float = 0.0
var _gait_controller: GaitController


func _ready() -> void:
	add_to_group("player_attributes")
	hp = max_hp
	_gait_controller = get_parent() as GaitController


func _process(delta: float) -> void:
	if not _can_idle_heal():
		_idle_timer = 0.0
		_heal_accumulator = 0.0
		return

	_idle_timer += delta
	if _idle_timer < idle_heal_delay:
		return

	var hp_ratio := float(hp) / float(max_hp)
	var heal_per_second := lerpf(min_idle_heal_per_second, max_idle_heal_per_second, 1.0 - hp_ratio)
	_heal_accumulator += heal_per_second * delta
	var heal_amount := int(floorf(_heal_accumulator))
	if heal_amount > 0:
		_heal_accumulator -= float(heal_amount)
		heal(heal_amount)


func take_damage(amount: int) -> void:
	_take_damage(amount, false)


func take_damage_ignoring_gameplay_lock(amount: int) -> void:
	_take_damage(amount, true)


func _take_damage(amount: int, ignore_gameplay_lock: bool) -> void:
	if GameState.is_gameplay_locked() and not ignore_gameplay_lock:
		if GameConfig.DEBUG:
			print("[DEBUG][PlayerAttributes] damage ignored reason=gameplay_locked amount=%d" % amount)
		return
	if amount <= 0 or hp <= 0:
		return

	var applied_damage: int = mini(amount, hp)
	hp = maxi(hp - applied_damage, 0)
	_idle_timer = 0.0
	_heal_accumulator = 0.0
	if GameConfig.DEBUG:
		print("[DEBUG][PlayerAttributes] damaged=%d hp=%d/%d" % [applied_damage, hp, max_hp])
	EventBus.player_damaged.emit(applied_damage, hp)

	if hp == 0:
		if GameConfig.DEBUG:
			print("[DEBUG][PlayerAttributes] died")
		EventBus.player_died.emit()


func heal(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return

	var old_hp := hp
	hp = mini(hp + amount, max_hp)
	var healed := hp - old_hp
	if healed > 0:
		if GameConfig.DEBUG:
			print("[DEBUG][PlayerAttributes] healed=%d hp=%d/%d" % [healed, hp, max_hp])
		EventBus.player_healed.emit(healed, hp)


func _can_idle_heal() -> bool:
	if hp <= 0 or hp >= max_hp:
		return false
	if not GameState.is_playing() or GameState.is_gameplay_locked():
		return false
	if _gait_controller and _gait_controller.has_move_intent():
		return false
	return true
