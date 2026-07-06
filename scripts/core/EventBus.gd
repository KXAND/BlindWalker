extends Node

@warning_ignore("unused_signal")
signal player_damaged(amount: int, current_hp: int)
@warning_ignore("unused_signal")
signal player_healed(amount: int, current_hp: int)
@warning_ignore("unused_signal")
signal player_died()
@warning_ignore("unused_signal")
signal player_fell(fall_distance: float)

@warning_ignore("unused_signal")
signal gait_state_changed(old_state: StringName, new_state: StringName)

@warning_ignore("unused_signal")
signal cane_hit_object(object_name: String, hit_point: Vector3, hit_normal: Vector3)
@warning_ignore("unused_signal")
signal cane_entered_npc_zone(npc_name: String)
@warning_ignore("unused_signal")
signal cane_exited_npc_zone(npc_name: String)

@warning_ignore("unused_signal")
signal touch_detected(hit_point: Vector3)

@warning_ignore("unused_signal")
signal npc_interaction_available(npc_name: String, prompt: String)
@warning_ignore("unused_signal")
signal npc_interaction_unavailable()
@warning_ignore("unused_signal")
signal npc_interaction_triggered(npc_name: String)

@warning_ignore("unused_signal")
signal game_state_changed(old_state: StringName, new_state: StringName)

@warning_ignore("unused_signal")
signal cutscene_started(cutscene_id: String)
@warning_ignore("unused_signal")
signal cutscene_ended(cutscene_id: String)

@warning_ignore("unused_signal")
signal audio_requested(sound_id: String, position: Vector3, volume_db: float)
