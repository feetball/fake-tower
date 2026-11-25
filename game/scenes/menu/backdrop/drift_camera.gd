class_name DriftCamera
extends Camera3D
## Slow, handheld-feeling camera drift around a base position, always looking
## at a (also drifting) target. Incommensurate sine periods keep it from
## visibly looping.

@export var base_position := Vector3(-24.0, 19.0, 390.0)
@export var look_target := Vector3(-40.0, 8.0, -300.0)
@export var position_amp := Vector3(10.0, 4.0, 60.0)
@export var target_amp := Vector3(30.0, 4.0, 60.0)
@export var speed := 1.0
@export var start_time := 40.0
@export var roll_amp_deg := 0.6

var _t := 0.0


func _ready() -> void:
	_t = start_time
	_apply()


func _process(delta: float) -> void:
	_t += delta * speed
	_apply()


func _apply() -> void:
	var p := base_position + Vector3(
		sin(_t * 0.051) * position_amp.x,
		sin(_t * 0.083 + 1.0) * position_amp.y,
		sin(_t * 0.031 + 2.0) * position_amp.z)
	var target := look_target + Vector3(
		sin(_t * 0.043 + 0.5) * target_amp.x,
		sin(_t * 0.067) * target_amp.y,
		sin(_t * 0.029 + 1.5) * target_amp.z)
	look_at_from_position(p, target, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(sin(_t * 0.11) * roll_amp_deg))


## Smoothly re-frame the shot (e.g. when the menu switches to the lobby).
func glide_to(new_base: Vector3, new_target: Vector3, seconds: float = 3.0) -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "base_position", new_base, seconds)
	tw.tween_property(self, "look_target", new_target, seconds)
