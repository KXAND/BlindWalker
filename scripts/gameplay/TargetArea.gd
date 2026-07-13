class_name TargetArea
extends Area3D
## 线性 MVP 的终点区域；玩家进入后请求 GameState 切到 SUCCESS。


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if GameState.is_gameplay_locked():
		return
	if body.is_in_group("player"):
		GameState.set_victory()
