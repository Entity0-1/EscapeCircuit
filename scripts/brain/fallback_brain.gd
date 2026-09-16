class_name FallbackBrain
extends RefCounted

## A deterministic, connectome-inspired controller used while the MaleCNS service
## is unavailable. It preserves the eventual brain-service input/output contract;
## it is intentionally labeled as a prototype throughout the UI.

const RESPONSE_RATE := 9.0
const ADAPTATION_RATE := 0.7

var visual_left := 0.0
var visual_right := 0.0
var escape_drive := 0.0
var motor_bias := 0.0
var adaptation := 0.0


func reset() -> void:
	visual_left = 0.0
	visual_right = 0.0
	escape_drive = 0.0
	motor_bias = 0.0
	adaptation = 0.0


func step(delta: float, sensors: Dictionary) -> Dictionary:
	var left_input: float = clampf(float(sensors.get("loom_left", 0.0)), 0.0, 1.0)
	var right_input: float = clampf(float(sensors.get("loom_right", 0.0)), 0.0, 1.0)
	var proximity: float = clampf(float(sensors.get("proximity", 0.0)), 0.0, 1.0)
	var impact: float = clampf(float(sensors.get("impact", 0.0)), 0.0, 1.0)
	var loom_up: float = clampf(float(sensors.get("loom_up", 0.0)), 0.0, 1.0)
	var loom_down: float = clampf(float(sensors.get("loom_down", 0.0)), 0.0, 1.0)
	var response_alpha := 1.0 - exp(-RESPONSE_RATE * delta)

	visual_left = lerpf(visual_left, left_input, response_alpha)
	visual_right = lerpf(visual_right, right_input, response_alpha)

	var combined_loom := maxf(visual_left, visual_right)
	var target_escape := clampf(combined_loom * 0.92 + proximity * 0.22 + impact, 0.0, 1.0)
	escape_drive = lerpf(escape_drive, target_escape, response_alpha)
	motor_bias = lerpf(motor_bias, visual_left - visual_right, response_alpha)

	adaptation = maxf(0.0, adaptation - ADAPTATION_RATE * delta)
	var trigger := escape_drive > 0.45 + adaptation * 0.15
	if trigger:
		adaptation = 1.0
	var yaw_drive := clampf(motor_bias, -1.0, 1.0)
	var pitch_drive := clampf((loom_down - loom_up) * escape_drive * 1.25, -1.0, 1.0)
	var flight_power := clampf(0.46 + escape_drive * 0.54, 0.0, 1.0)

	return {
		"escape_drive": escape_drive,
		"turn_bias": yaw_drive,
		"forward_drive": clampf(0.58 + flight_power * 0.42, 0.0, 1.0),
		"takeoff_drive": escape_drive,
		"yaw_drive": yaw_drive,
		"pitch_drive": pitch_drive,
		"roll_drive": clampf(-yaw_drive * 0.75, -1.0, 1.0),
		"flight_power": flight_power,
		"landing_drive": clampf(1.0 - maxf(escape_drive, proximity * 0.72), 0.0, 1.0),
		"trigger_escape": trigger,
		"activity": {
			"visual_left": visual_left,
			"visual_right": visual_right,
			"escape": escape_drive,
			"motor": absf(motor_bias),
		},
		"mode": "PROTOTYPE CIRCUIT",
	}
