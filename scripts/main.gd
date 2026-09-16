extends Node3D

enum GameState { MENU, PLAYING, WON, LOST, PAUSED, REPLAY }

const ROUND_DURATION := 60.0
const REPLAY_BUFFER_SECONDS := 12.0
const REPLAY_SAMPLE_INTERVAL := 1.0 / 24.0
const AIM_MIN := Vector3(-6.22, 0.37, -1.18)
const AIM_MAX := Vector3(14.00, 2.60, 4.10)
const LOOMING_ENCODER := preload("res://scripts/brain/looming_encoder.gd")

var game_state := GameState.MENU
var time_left := ROUND_DURATION
var swings := 0
var escapes := 0
var impact_pulse := 0.0
var session_seed := 90210
var player: PlayerController
var apartment_layout: ApartmentLayout
var camera: Camera3D
var fly: FlyController
var swatter: SwatterController
var brain_client: BrainClient
var audio: AudioController
var ui: GameUI
var replay_view: ReplayView
var replay_samples: Array[Dictionary] = []
var replay_elapsed := 0.0
var replay_sample_timer := 0.0
var replay_playhead := 0.0
var replay_index := 0
var replay_previous_state := GameState.LOST
var replay_restore: Dictionary = {}
var telemetry_visible := true
var last_hit_checked := false
var camera_base_transform: Transform3D
var camera_trauma := 0.0
var camera_noise_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world()
	_build_gameplay()
	ui.show_intro()
	get_viewport().size_changed.connect(_on_viewport_resized)
	for argument in OS.get_cmdline_user_args():
		if argument == "--self-test":
			_run_export_self_test.call_deferred()
		elif argument.begins_with("--capture-preview="):
			var output_path := argument.trim_prefix("--capture-preview=")
			_capture_preview.call_deferred(output_path, false)
		elif argument.begins_with("--capture-gameplay="):
			var output_path := argument.trim_prefix("--capture-gameplay=")
			_capture_preview.call_deferred(output_path, true)
		elif argument.begins_with("--capture-kitchen="):
			var output_path := argument.trim_prefix("--capture-kitchen=")
			_capture_preview.call_deferred(output_path, true, "kitchen")
		elif argument.begins_with("--capture-bedroom="):
			var output_path := argument.trim_prefix("--capture-bedroom=")
			_capture_preview.call_deferred(output_path, true, "bedroom")
		elif argument.begins_with("--capture-replay="):
			var output_path := argument.trim_prefix("--capture-replay=")
			_capture_replay_preview.call_deferred(output_path)


func _process(delta: float) -> void:
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var aim_screen_position := screen_center if game_state == GameState.PLAYING else get_viewport().get_mouse_position()
	ui.set_crosshair_position(aim_screen_position)
	var aim_point := _screen_to_fly_plane(aim_screen_position)
	swatter.set_aim(aim_point)
	if game_state != GameState.REPLAY:
		_update_camera_feedback(delta)

	if game_state == GameState.PLAYING:
		time_left = maxf(0.0, time_left - delta)
		impact_pulse = maxf(0.0, impact_pulse - delta * 3.2)
		_update_fly_sensors(delta)
		_check_swept_hit()
		if game_state == GameState.PLAYING:
			replay_elapsed += delta
			replay_sample_timer += delta
			if replay_sample_timer >= REPLAY_SAMPLE_INTERVAL:
				replay_sample_timer = fmod(replay_sample_timer, REPLAY_SAMPLE_INTERVAL)
				_capture_replay_frame()
		if time_left <= 0.0:
			_finish_round(false)
	elif game_state == GameState.REPLAY:
		_step_replay(delta)

	ui.update_hud(time_left, swings, escapes, swatter.get_charge(), fly.get_activity(), fly.get_brain_mode(), fly.get_sensed_threat(), fly.get_circuit_response())
	audio.update_fly_energy(float(fly.get_activity().get("escape", 0.0)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("telemetry"):
		telemetry_visible = not telemetry_visible
		ui.set_telemetry_visible(telemetry_visible)
		get_viewport().set_input_as_handled()
		return
	if game_state == GameState.REPLAY and (event.is_action_pressed("replay") or event.is_action_pressed("pause")):
		_end_replay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("replay") and game_state in [GameState.WON, GameState.LOST]:
		_begin_replay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart") and game_state in [GameState.WON, GameState.LOST]:
		_start_round()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause") and game_state == GameState.PLAYING:
		_set_paused(true)
		return
	elif event.is_action_pressed("pause") and game_state == GameState.PAUSED:
		_set_paused(false)
		return

	if game_state != GameState.PLAYING:
		return
	if event.is_action_pressed("swing"):
		swatter.begin_windup()
		last_hit_checked = false
	elif event.is_action_released("swing"):
		swatter.release_swing()


func _start_round() -> void:
	get_tree().paused = false
	game_state = GameState.PLAYING
	time_left = ROUND_DURATION
	swings = 0
	escapes = 0
	impact_pulse = 0.0
	session_seed += 1
	replay_samples.clear()
	replay_elapsed = 0.0
	replay_sample_timer = 0.0
	fly.reset_fly(session_seed)
	swatter.reset_swatter()
	ui.hide_intro()
	ui.result_panel.visible = false
	ui.set_paused(false)
	audio.set_active(true)
	player.set_active(true)
	_capture_replay_frame()


func _finish_round(won: bool) -> void:
	if game_state not in [GameState.PLAYING, GameState.PAUSED]:
		return
	_capture_replay_frame()
	game_state = GameState.WON if won else GameState.LOST
	camera_trauma = 0.0
	audio.set_active(false)
	player.set_active(false)
	ui.show_result(won, time_left, swings, escapes)


func _capture_replay_frame() -> void:
	if fly == null or swatter == null:
		return
	replay_samples.append({
		"time": replay_elapsed,
		"camera": camera.global_transform,
		"fly": fly.global_transform,
		"fly_body": fly.body_root.transform,
		"wing_phase": fly.wing_phase,
		"airborne": fly.is_airborne(),
		"swatter": swatter.global_transform,
		"swatter_model": swatter.model_root.global_transform,
		"sensed": fly.get_sensed_threat().duplicate(true),
		"response": fly.get_circuit_response().duplicate(true),
	})
	while replay_samples.size() > 2 and replay_elapsed - float(replay_samples[0]["time"]) > REPLAY_BUFFER_SECONDS:
		replay_samples.pop_front()


func _begin_replay() -> void:
	if replay_samples.size() < 2:
		return
	replay_previous_state = game_state
	replay_playhead = 0.0
	replay_index = 0
	replay_restore = {
		"fly": fly.global_transform,
		"fly_body": fly.body_root.transform,
		"wing_phase": fly.wing_phase,
		"airborne": fly.is_airborne(),
		"shadow": fly.shadow.global_transform,
		"swatter": swatter.global_transform,
		"swatter_model": swatter.model_root.global_transform,
	}
	game_state = GameState.REPLAY
	get_tree().paused = true
	ui.visible = false
	var duration := float(replay_samples[-1]["time"]) - float(replay_samples[0]["time"])
	replay_view.show_clip(duration, "DIRECT HIT" if replay_previous_state == GameState.WON else "FLY SURVIVED")
	_step_replay(0.0)


func _step_replay(delta: float) -> void:
	var start_time := float(replay_samples[0]["time"])
	var duration := maxf(float(replay_samples[-1]["time"]) - start_time, 0.001)
	replay_playhead += delta
	if replay_playhead >= duration:
		replay_playhead = fmod(replay_playhead, duration)
		replay_index = 0
	var target_time := start_time + replay_playhead
	while replay_index < replay_samples.size() - 2 and float(replay_samples[replay_index + 1]["time"]) < target_time:
		replay_index += 1
	var before: Dictionary = replay_samples[replay_index]
	var after: Dictionary = replay_samples[replay_index + 1]
	var span := maxf(float(after["time"]) - float(before["time"]), 0.001)
	var blend := clampf((target_time - float(before["time"])) / span, 0.0, 1.0)
	var fly_pose: Transform3D = (before["fly"] as Transform3D).interpolate_with(after["fly"], blend)
	var fly_body_pose: Transform3D = (before["fly_body"] as Transform3D).interpolate_with(after["fly_body"], blend)
	var swatter_pose: Transform3D = (before["swatter"] as Transform3D).interpolate_with(after["swatter"], blend)
	var swatter_model_pose: Transform3D = (before["swatter_model"] as Transform3D).interpolate_with(after["swatter_model"], blend)
	var camera_pose: Transform3D = (before["camera"] as Transform3D).interpolate_with(after["camera"], blend)
	fly.global_transform = fly_pose
	fly.body_root.transform = fly_body_pose
	var phase := lerpf(float(before["wing_phase"]), float(after["wing_phase"]), blend)
	var airborne := bool(before["airborne"]) if blend < 0.5 else bool(after["airborne"])
	fly.apply_wing_pose(phase, airborne)
	fly.shadow.global_position = Vector3(fly_pose.origin.x, FlyController.FLOOR_Y + 0.01, fly_pose.origin.z)
	swatter.global_transform = swatter_pose
	swatter.model_root.global_transform = swatter_model_pose
	var display_frame := before.duplicate()
	display_frame["fly"] = fly_pose
	display_frame["camera"] = camera_pose
	replay_view.show_frame(display_frame, replay_playhead / duration, replay_playhead)


func _end_replay() -> void:
	fly.global_transform = replay_restore["fly"]
	fly.body_root.transform = replay_restore["fly_body"]
	fly.wing_phase = replay_restore["wing_phase"]
	fly.apply_wing_pose(fly.wing_phase, replay_restore["airborne"])
	fly.shadow.global_transform = replay_restore["shadow"]
	swatter.global_transform = replay_restore["swatter"]
	swatter.model_root.global_transform = replay_restore["swatter_model"]
	replay_view.hide_clip()
	ui.visible = true
	game_state = replay_previous_state
	get_tree().paused = false


func _update_fly_sensors(delta: float) -> void:
	var swatter_offset := swatter.global_position - fly.global_position
	var swatter_distance := swatter_offset.length()
	var swatter_proximity := clampf(1.0 - swatter_distance / 5.2, 0.0, 1.0)
	# The paddle contributes visual expansion only during a descending strike;
	# moving it away during charge-up does not activate the escape pathway.
	var strike_closing_speed := (
		swatter.get_downward_speed()
		if swatter.phase == SwatterController.Phase.STRIKE and swatter_offset.y > 0.0
		else 0.0
	)
	var swatter_closing := strike_closing_speed * swatter_offset.y / maxf(swatter_distance, 0.05)
	var swatter_features: Dictionary = LOOMING_ENCODER.encode(
		SwatterController.PADDLE_HALF_SIZE.x, swatter_distance, swatter_closing
	)
	var swatter_local := fly.global_transform.basis.inverse() * swatter_offset
	var swatter_side := clampf(swatter_local.x / maxf(swatter_distance, 0.01), -1.0, 1.0)
	var swatter_vertical := clampf(swatter_local.y / maxf(swatter_distance, 0.01), -1.0, 1.0)

	var player_offset := camera.global_position - fly.global_position
	var player_distance := player_offset.length()
	var player_proximity := clampf(1.0 - player_distance / 4.2, 0.0, 1.0)
	var player_velocity := player.get_movement_velocity()
	var player_motion := clampf(player_velocity.length() / PlayerController.MOVE_SPEED, 0.0, 1.0)
	var direction_to_fly := -player_offset.normalized() if player_distance > 0.01 else Vector3.ZERO
	var player_closing := maxf(0.0, player_velocity.dot(direction_to_fly))
	var player_features: Dictionary = LOOMING_ENCODER.encode(
		0.44, player_distance, player_closing
	)
	var player_local := fly.global_transform.basis.inverse() * player_offset
	var player_side := clampf(player_local.x / maxf(player_distance, 0.01), -1.0, 1.0)
	var player_vertical := clampf(player_local.y / maxf(player_distance, 0.01), -1.0, 1.0)

	var swatter_left := clampf(0.5 - swatter_side * 0.5, 0.0, 1.0)
	var swatter_right := 1.0 - swatter_left
	var player_left := clampf(0.5 - player_side * 0.5, 0.0, 1.0)
	var player_right := 1.0 - player_left
	var lc4_left := clampf(
		float(swatter_features.lc4) * swatter_left + float(player_features.lc4) * player_left,
		0.0,
		1.0
	)
	var lc4_right := clampf(
		float(swatter_features.lc4) * swatter_right + float(player_features.lc4) * player_right,
		0.0,
		1.0
	)
	var lplc2_left := clampf(
		float(swatter_features.lplc2) * swatter_left + float(player_features.lplc2) * player_left,
		0.0,
		1.0
	)
	var lplc2_right := clampf(
		float(swatter_features.lplc2) * swatter_right + float(player_features.lplc2) * player_right,
		0.0,
		1.0
	)
	var left_loom := maxf(lc4_left, lplc2_left)
	var right_loom := maxf(lc4_right, lplc2_right)
	var swatter_loom := maxf(float(swatter_features.lc4), float(swatter_features.lplc2))
	var player_loom := maxf(float(player_features.lc4), float(player_features.lplc2))
	var up_loom := clampf(
		swatter_loom * clampf(0.5 + swatter_vertical * 0.5, 0.0, 1.0)
		+ player_loom * clampf(0.5 + player_vertical * 0.5, 0.0, 1.0),
		0.0,
		1.0
	)
	var down_loom := clampf(
		swatter_loom * clampf(0.5 - swatter_vertical * 0.5, 0.0, 1.0)
		+ player_loom * clampf(0.5 - player_vertical * 0.5, 0.0, 1.0),
		0.0,
		1.0
	)
	var active_swatter_proximity := swatter_proximity * swatter_loom
	var player_threat_proximity := player_proximity * player_loom * player_motion
	var sensors := {
		"loom_left": left_loom,
		"loom_right": right_loom,
		"loom_up": up_loom,
		"loom_down": down_loom,
		"lc4_left": lc4_left,
		"lc4_right": lc4_right,
		"lplc2_left": lplc2_left,
		"lplc2_right": lplc2_right,
		"proximity": maxf(active_swatter_proximity, player_threat_proximity),
		"impact": impact_pulse,
	}
	var external_output := brain_client.step(delta, sensors)
	fly.set_sensors(delta, sensors, external_output)


func _check_swept_hit() -> void:
	if not swatter.is_dangerous() or last_hit_checked or fly.is_hit():
		return
	if swatter.global_position.y > fly.global_position.y + 0.28:
		return
	last_hit_checked = true
	if swatter.contains_world_point(fly.global_position):
		var hit_direction := fly.global_position - swatter.global_position
		hit_direction.y = 0.2
		fly.hit(hit_direction)
		audio.play_hit()
		camera_trauma = 1.0
		ui.flash_hit(true)
		_finish_round(true)


func _on_swatter_impact(_position: Vector3, intensity: float) -> void:
	if game_state != GameState.PLAYING:
		return
	impact_pulse = intensity
	if not fly.is_hit():
		var distance := swatter.spatial_distance_to(fly.global_position)
		if distance < 2.15:
			var near_miss := clampf((2.15 - distance) / 1.75, 0.18, 1.0) * intensity
			fly.add_near_miss(near_miss)
			camera_trauma = maxf(camera_trauma, near_miss * 0.46)
			audio.play_miss()
			ui.flash_hit(false)
		else:
			audio.play_miss()


func _on_swing_started(_intensity: float) -> void:
	if game_state == GameState.PLAYING:
		swings += 1
		audio.play_swing()


func _on_fly_escaped() -> void:
	if game_state == GameState.PLAYING:
		escapes += 1
		audio.play_dodge()


func _build_gameplay() -> void:
	brain_client = BrainClient.new()
	brain_client.name = "BrainClient"
	add_child(brain_client)

	fly = FlyController.new()
	fly.name = "Fly"
	fly.set_apartment_layout(apartment_layout)
	fly.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fly)
	fly.escaped.connect(_on_fly_escaped)

	swatter = SwatterController.new()
	swatter.name = "Swatter"
	swatter.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(swatter)
	swatter.bind_view_camera(camera)
	swatter.impact.connect(_on_swatter_impact)
	swatter.swing_started.connect(_on_swing_started)

	audio = AudioController.new()
	audio.name = "Audio"
	add_child(audio)
	audio.attach_fly(fly)

	ui = GameUI.new()
	ui.name = "UI"
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	ui.start_requested.connect(_start_round)
	ui.restart_requested.connect(_start_round)
	ui.resume_requested.connect(func(): _set_paused(false))
	replay_view = ReplayView.new()
	replay_view.name = "ReplayView"
	add_child(replay_view)
	replay_view.bind_world(get_viewport().world_3d, fly.get_rid())


func _set_paused(paused: bool) -> void:
	if paused and game_state != GameState.PLAYING:
		return
	if not paused and game_state != GameState.PAUSED:
		return
	game_state = GameState.PAUSED if paused else GameState.PLAYING
	get_tree().paused = paused
	if paused:
		camera_trauma = 0.0
	ui.set_paused(paused)
	audio.set_active(not paused)
	player.set_active(not paused)


func _build_world() -> void:
	apartment_layout = ApartmentLayout.new()
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("161a20")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8e0d5")
	environment.ambient_light_energy = 0.20
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var daylight := DirectionalLight3D.new()
	daylight.rotation_degrees = Vector3(-55.0, 33.0, 0.0)
	daylight.light_color = Color("d8e6ff")
	daylight.light_energy = 0.38
	daylight.shadow_enabled = true
	add_child(daylight)

	_add_room_light("LivingLight", Vector3(-3.0, 2.39, 2.10), Color("ffecd6"), 0.62, 7.5, true)
	_add_room_light("KitchenLight", Vector3(-3.3, 2.39, -0.45), Color("fff0dd"), 0.52, 6.0)
	_add_room_light("OfficeLight", Vector3(4.35, 2.39, 1.20), Color("f5e7dc"), 0.48, 5.0)
	_add_room_light("HallLight", Vector3(9.40, 2.39, 3.22), Color("ffebd8"), 0.51, 6.5)
	_add_room_light("BedroomLight", Vector3(11.75, 2.39, 0.45), Color("ffe4d2"), 0.57, 5.0)

	_load_apartment()

	player = PlayerController.new()
	player.name = "Player"
	player.set_apartment_layout(apartment_layout)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	camera = player.camera
	camera_base_transform = camera.transform


func _add_room_light(node_name: String, point: Vector3, tint: Color, energy: float, radius: float, casts_shadow := false) -> void:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = point
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = casts_shadow
	add_child(light)


func _load_apartment() -> void:
	var source := load("res://scenes/apartment.tscn") as PackedScene
	if source == null:
		push_error("The Modern Apartment scene could not be loaded.")
		return
	var imported_apartment := source.instantiate() as Node3D
	imported_apartment.name = "ModernApartment"
	add_child(imported_apartment)
	_register_apartment_geometry(imported_apartment)


func _register_apartment_geometry(node: Node) -> void:
	# The bedroom's supplied door is closed. Leave the doorway open for play.
	if node.name == "Door_001" and node is Node3D:
		(node as Node3D).visible = false
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var mesh_name := String(instance.name)
		if mesh_name in [
			"Plane_002_Black_001_0",
			"Plane_002_SprayedWallTexture_0",
			"Plane_002_Wood0035_0",
			"Plane_004_Wood049_0",
			"Plane_007_Wood049_0",
		]:
			instance.create_trimesh_collision()
			for child in instance.get_children():
				if child is StaticBody3D:
					(child as StaticBody3D).collision_layer = 2
					(child as StaticBody3D).collision_mask = 0
		if mesh_name in [
			"DiningTable_001_Wood049_0",
			"CouchSet_Material_2_0",
			"CouchSet_Material_1_0",
			"CouchSet_Material_9_0",
			"CouchSet_White1_0",
			"BedroomWardrobes_Wood049_0",
			"BookCase_Wood049_0",
		] or mesh_name.begins_with("Bed_Plain_Grey") or mesh_name.begins_with("Refrigator_001_BrushedMetal") or mesh_name.begins_with("Office_Desk_Black"):
			var bounds := instance.global_transform * instance.mesh.get_aabb()
			apartment_layout.register_solid(mesh_name, bounds.get_center(), bounds.size)
	for child in node.get_children():
		_register_apartment_geometry(child)
func _screen_to_fly_plane(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var plane_normal := -camera.global_transform.basis.z.normalized()
	var denominator := direction.dot(plane_normal)
	if absf(denominator) < 0.001:
		return fly.global_position
	var distance := (fly.global_position - origin).dot(plane_normal) / denominator
	var point := origin + direction * distance
	point.x = clampf(point.x, AIM_MIN.x, AIM_MAX.x)
	point.y = clampf(point.y, AIM_MIN.y, AIM_MAX.y)
	point.z = clampf(point.z, AIM_MIN.z, AIM_MAX.z)
	return point


func _on_viewport_resized() -> void:
	# Dynamic controls use anchors; the telemetry panel is intentionally pinned
	# near the lower left at the design resolution and remains readable when scaled.
	pass


func _update_camera_feedback(delta: float) -> void:
	camera_noise_time += delta
	camera_trauma = maxf(0.0, camera_trauma - delta * 2.6)
	var amount := camera_trauma * camera_trauma
	camera_base_transform = camera.transform
	camera.transform = camera_base_transform
	if amount <= 0.0001:
		return
	var horizontal := sin(camera_noise_time * 47.0) * 0.055 * amount
	var vertical := cos(camera_noise_time * 39.0) * 0.035 * amount
	camera.position += camera.transform.basis.x * horizontal + camera.transform.basis.y * vertical
	camera.rotation.z += sin(camera_noise_time * 31.0) * 0.006 * amount


func _capture_preview(output_path: String, gameplay: bool, room_name := "") -> void:
	# Used by local visual QA and intentionally excluded from normal gameplay.
	await get_tree().process_frame
	await get_tree().process_frame
	if gameplay:
		_start_round()
		if room_name == "kitchen":
			player.position = Vector3(-3.30, 0.16, 0.36)
			player.yaw = 0.0
			player._apply_look()
		elif room_name == "bedroom":
			player.position = Vector3(10.40, 0.16, 1.83)
			player.yaw = 0.0
			player._apply_look()
		Input.warp_mouse(get_viewport().get_visible_rect().size * 0.5)
		swatter.begin_windup()
		await get_tree().create_timer(0.55).timeout
	else:
		await get_tree().create_timer(0.25).timeout
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save preview image to %s (error %d)" % [output_path, error])
	else:
		print("Saved preview: %s" % output_path)
	audio.shutdown()
	get_tree().quit()


func _capture_replay_preview(output_path: String) -> void:
	# Local visual QA only. A real video still needs screen recording.
	await get_tree().process_frame
	await get_tree().process_frame
	_start_round()
	await get_tree().create_timer(1.2).timeout
	_finish_round(false)
	_begin_replay()
	_step_replay(0.6)
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save replay preview to %s (error %d)" % [output_path, error])
	else:
		print("Saved replay preview: %s" % output_path)
	audio.shutdown()
	get_tree().quit()


func _run_export_self_test() -> void:
	await get_tree().process_frame
	var controller := ConnectomeBrain.new()
	if not controller.is_loaded():
		push_error("Export self-test failed: %s" % controller.load_error)
		get_tree().quit(1)
		return
	var triggered := false
	for _step in range(90):
		var output := controller.step(1.0 / 60.0, {
			"loom_left": 1.0,
			"loom_right": 0.2,
			"proximity": 0.95,
			"impact": 0.0,
		})
		triggered = triggered or bool(output.get("trigger_escape", false))
	if not triggered:
		push_error("Export self-test failed: MaleCNS circuit did not trigger")
		get_tree().quit(1)
		return
	print("PASS: exported MaleCNS circuit loaded and triggered")
	audio.shutdown()
	get_tree().quit(0)
