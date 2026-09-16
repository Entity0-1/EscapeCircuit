extends SceneTree

const LOOMING_ENCODER := preload("res://scripts/brain/looming_encoder.gd")
const FLIGHT_TURN_BRAIN := preload("res://scripts/brain/flight_turn_brain.gd")

var failures := 0


func _init() -> void:
	_test_fallback_brain_is_deterministic()
	_test_lateral_bias_changes_sign()
	_test_escape_threshold()
	_test_malecns_artifact_is_loaded()
	_test_malecns_controller_escapes()
	_test_malecns_controller_emits_3d_motor_commands()
	_test_distinct_visual_features()
	_test_expansion_speed_changes_takeoff_latency()
	_test_turn_motif_observed_contacts()
	_test_ves041_suppresses_spontaneous_turns()
	if failures == 0:
		print("PASS: 10 neural-controller tests")
		quit(0)
	else:
		push_error("FAIL: %d test(s) failed" % failures)
		quit(1)


func _test_fallback_brain_is_deterministic() -> void:
	var first := FallbackBrain.new()
	var second := FallbackBrain.new()
	var sensors := {"loom_left": 0.8, "loom_right": 0.1, "proximity": 0.7, "impact": 0.0}
	var first_output: Dictionary
	var second_output: Dictionary
	for _step in range(12):
		first_output = first.step(1.0 / 60.0, sensors)
		second_output = second.step(1.0 / 60.0, sensors)
	_assert_close(float(first_output.escape_drive), float(second_output.escape_drive), "deterministic escape output")


func _test_lateral_bias_changes_sign() -> void:
	var left_brain := FallbackBrain.new()
	var right_brain := FallbackBrain.new()
	var left_output: Dictionary
	var right_output: Dictionary
	for _step in range(30):
		left_output = left_brain.step(1.0 / 60.0, {"loom_left": 1.0, "loom_right": 0.0})
		right_output = right_brain.step(1.0 / 60.0, {"loom_left": 0.0, "loom_right": 1.0})
	_assert(float(left_output.turn_bias) > 0.0, "left input produces positive bias")
	_assert(float(right_output.turn_bias) < 0.0, "right input produces negative bias")


func _test_escape_threshold() -> void:
	var brain := FallbackBrain.new()
	var triggered := false
	for _step in range(30):
		var output := brain.step(1.0 / 60.0, {"loom_left": 1.0, "loom_right": 1.0, "proximity": 1.0})
		triggered = triggered or bool(output.trigger_escape)
	_assert(triggered, "strong looming input triggers escape")


func _test_malecns_artifact_is_loaded() -> void:
	var brain := ConnectomeBrain.new()
	_assert(brain.is_loaded(), "checked-in MaleCNS circuit artifact loads")
	_assert(
		brain.get_observed_contacts("LC4", "L", "DNp01", "L") == 3782,
		"known observed MaleCNS contact count is preserved"
	)
	_assert(
		brain.get_observed_contacts("LC4", "L", "DNp03", "L") == 1827,
		"observed DNp03 collision-avoidance contacts are preserved"
	)


func _test_malecns_controller_escapes() -> void:
	var brain := ConnectomeBrain.new()
	var triggered := false
	var output: Dictionary = {}
	for _step in range(90):
		output = brain.step(1.0 / 60.0, {
			"loom_left": 1.0,
			"loom_right": 0.25,
			"proximity": 0.95,
			"impact": 0.0,
		})
		triggered = triggered or bool(output.get("trigger_escape", false))
	_assert(triggered, "strong looming input triggers the MaleCNS circuit")
	_assert(float(output.get("turn_bias", 0.0)) > 0.0, "MaleCNS circuit preserves lateral bias")
	_assert(str(output.get("mode", "")) == "MALECNS SENSORIMOTOR", "MaleCNS mode is labeled")


func _test_malecns_controller_emits_3d_motor_commands() -> void:
	var brain := ConnectomeBrain.new()
	var baseline := brain.step(1.0 / 60.0, {})
	var output: Dictionary = {}
	for _step in range(30):
		output = brain.step(1.0 / 60.0, {
			"loom_left": 1.0,
			"loom_right": 0.05,
			"loom_up": 1.0,
			"loom_down": 0.0,
			"proximity": 0.9,
			"impact": 0.0,
		})
	_assert(float(output.get("yaw_drive", 0.0)) > 0.0, "left-side threat produces rightward yaw")
	_assert(float(output.get("pitch_drive", 0.0)) < 0.0, "threat above produces a downward pitch command")
	_assert(float(output.get("takeoff_drive", 0.0)) > 0.4, "descending activity produces takeoff drive")
	_assert(float(output.get("flight_power", 0.0)) > float(baseline.get("flight_power", 0.0)), "threat increases flight power")
	_assert(float(output.get("landing_drive", 1.0)) < 0.4, "nearby threat suppresses landing")


func _test_distinct_visual_features() -> void:
	var stationary: Dictionary = LOOMING_ENCODER.encode(0.36, 1.0, 0.0)
	var receding: Dictionary = LOOMING_ENCODER.encode(0.36, 1.0, -3.0)
	var slow: Dictionary = LOOMING_ENCODER.encode(0.36, 1.0, 0.4)
	var fast: Dictionary = LOOMING_ENCODER.encode(0.36, 1.0, 4.0)
	var far: Dictionary = LOOMING_ENCODER.encode(0.36, 2.0, 4.0)
	_assert(float(stationary.lc4) == 0.0 and float(stationary.lplc2) == 0.0, "stationary object is not looming")
	_assert(float(receding.lc4) == 0.0 and float(receding.lplc2) == 0.0, "receding object is not looming")
	_assert(float(fast.lc4) > float(slow.lc4), "LC4 feature increases with angular expansion speed")
	_assert_close(float(fast.lplc2), float(slow.lplc2), "LPLC2 size feature is independent of speed")
	_assert(float(slow.lplc2) > float(far.lplc2), "LPLC2 feature depends on apparent angular size")


func _test_expansion_speed_changes_takeoff_latency() -> void:
	var slow_tick := _first_takeoff_tick(2.0)
	var fast_tick := _first_takeoff_tick(4.0)
	var smaller_size_tick := _first_takeoff_tick(4.0, 0.7)
	print("Modeled takeoff threshold: slow %d ms, fast %d ms" % [roundi(slow_tick * 1000.0 / 60.0), roundi(fast_tick * 1000.0 / 60.0)])
	_assert(fast_tick < slow_tick and slow_tick < 121, "faster expansion reaches connectome-weighted takeoff threshold sooner")
	_assert(fast_tick < smaller_size_tick and smaller_size_tick < 121, "larger LPLC2 size response also advances takeoff timing")


func _first_takeoff_tick(closing_speed: float, size_scale := 1.0) -> int:
	var feature: Dictionary = LOOMING_ENCODER.encode(0.36, 1.0, closing_speed)
	var brain := ConnectomeBrain.new()
	for tick in range(1, 121):
		var output := brain.step(1.0 / 60.0, {
			"lc4_left": float(feature.lc4) * 0.5,
			"lc4_right": float(feature.lc4) * 0.5,
			"lplc2_left": float(feature.lplc2) * 0.5 * size_scale,
			"lplc2_right": float(feature.lplc2) * 0.5 * size_scale,
			"proximity": 0.55,
		})
		if float(output.takeoff_drive) > 0.24:
			return tick
	return 121


func _test_turn_motif_observed_contacts() -> void:
	var brain := FLIGHT_TURN_BRAIN.new()
	_assert(brain.is_loaded(), "checked-in MaleCNS flight-turn motif loads")
	_assert(brain.get_observed_contacts("VES041", "L", "DNb01", "L") == 22, "observed VES041 inhibition contacts are preserved")
	_assert(brain.get_observed_contacts("DNb01", "R", "DNa15", "L") == 28, "observed contralateral turn contacts are preserved")


func _test_ves041_suppresses_spontaneous_turns() -> void:
	var searching := FLIGHT_TURN_BRAIN.new()
	var transiting := FLIGHT_TURN_BRAIN.new()
	var ves_ablated := FLIGHT_TURN_BRAIN.new()
	for target_key in ves_ablated.contacts:
		var incoming: Dictionary = ves_ablated.contacts[target_key]
		for source_key in incoming:
			if str(source_key).begins_with("VES041:"):
				incoming[source_key] = 0
	for _tick in range(20):
		searching.step(1.0 / 60.0, {"straight": 0.12})
		transiting.step(1.0 / 60.0, {"straight": 0.95})
		ves_ablated.step(1.0 / 60.0, {"straight": 0.95})
	var search_output: Dictionary = {}
	var transit_output: Dictionary = {}
	var ablated_output: Dictionary = {}
	for _tick in range(12):
		search_output = searching.step(1.0 / 60.0, {"right_pulse": 1.0, "straight": 0.12})
		transit_output = transiting.step(1.0 / 60.0, {"right_pulse": 1.0, "straight": 0.95})
		ablated_output = ves_ablated.step(1.0 / 60.0, {"right_pulse": 1.0, "straight": 0.95})
	_assert(float(search_output.turn_drive) > 0.25, "spontaneous-turn circuit produces a rightward command")
	_assert(float(transit_output.saccade_drive) < float(search_output.saccade_drive) * 0.55, "VES041-weighted inhibition suppresses turns in straight-flight mode")
	_assert(float(ablated_output.saccade_drive) > float(transit_output.saccade_drive) * 1.8, "ablating observed VES041 contacts restores turn response")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _assert_close(actual: float, expected: float, message: String) -> void:
	_assert(absf(actual - expected) < 0.000001, message)
