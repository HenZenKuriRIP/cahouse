extends Node
## Abstracts keyboard/mouse vs gamepad. Aim falls back to mouse unless right stick used.
const STICK_DEADZONE := 0.3
var using_gamepad: bool = false
var last_stick_aim: Vector2 = Vector2.RIGHT

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE):
		using_gamepad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false

func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func get_stick_aim() -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if v.length() > STICK_DEADZONE:
		last_stick_aim = v.normalized()
		return last_stick_aim
	return Vector2.ZERO
