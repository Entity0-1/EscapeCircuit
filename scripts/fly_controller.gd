class_name FlyController
extends CharacterBody3D

signal escaped
signal recovered

enum State { PERCHED, TAKEOFF, FLYING, DODGING, RECOVERING, HIT }

const FLOOR_Y := 0.16
const CRUISE_SPEED := 3.25
const DODGE_SPEED := 10.50
const NATURAL_TAKEOFF_SPEED := 7.80
const THREAT_TAKEOFF_SPEED := 13.60
const TAKEOFF_DURATION := 0.24
const NEURAL_STEERING_RATE := 15.0
const VERTICAL_CRUISE_MULTIPLIER := 1.55
const VERTICAL_DODGE_MULTIPLIER := 1.42
const PERCH_REACTION_TIME := 0.040
const PERCH_LOOM_THRESHOLD := 0.006
const BODY_RADIUS := 0.052
const IMPORTED_FLY_PATH := "res://assets/models/fly_housefly_ccby/scene.gltf"
const IMPORTED_FLY_SIZE := 0.18
const VOLUME_MIN := ApartmentLayout.FLY_MIN
const VOLUME_MAX := ApartmentLayout.FLY_MAX
const PERCH_POINTS := ApartmentLayout.PERCH_POINTS

var state := State.FLYING
var connectome_brain := ConnectomeBrain.new()
var fallback_brain := FallbackBrain.new()
var brain_output: Dictionary = {}
var sensed_threat: Dictionary = {}
var rng := RandomNumberGenerator.new()
var desired_direction := Vector3.FORWARD
var wander_target := Vector3.ZERO
var state_time := 0.0
var decision_time := 0.0
var dodge_cooldown := 0.0
var shock_input := 0.0
var perceived_loom := 0.0
var perceived_proximity := 0.0
var perch_alert_time := 0.0
var takeoff_threatened := false
var wing_phase := 0.0
var body_root: Node3D
var imported_model: Node3D
var left_wing: MeshInstance3D
var right_wing: MeshInstance3D
var left_wing_pivot: Node3D
var right_wing_pivot: Node3D
var shadow: MeshInstance3D
var apartment_layout: ApartmentLayout
var architecture_shape: SphereShape3D


func set_apartment_layout(value: ApartmentLayout) -> void:
	apartment_layout = value


func _ready() -> void:
	architecture_shape = SphereShape3D.new()
	architecture_shape.radius = BODY_RADIUS
	_build_model()
	reset_fly(7319)


func reset_fly(seed_value: int) -> void:
	rng.seed = seed_value
	connectome_brain.reset()
	fallback_brain.reset()
	sensed_threat.clear()
	state = State.FLYING
	state_time = 0.0
	decision_time = 2.5
	dodge_cooldown = 0.0
	shock_input = 0.0
	perceived_loom = 0.0
	perceived_proximity = 0.0
	perch_alert_time = 0.0
	takeoff_threatened = false
	wing_phase = 0.0
	global_position = ApartmentLayout.FLY_START
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	visible = true
	wander_target = _random_air_point()


func set_sensors(delta: float, sensors: Dictionary, external_output: Dictionary = {}) -> void:
	var enriched := sensors.duplicate()
	enriched["impact"] = maxf(float(enriched.get("impact", 0.0)), shock_input)
	sensed_threat = enriched.duplicate()
	perceived_loom = maxf(
		float(enriched.get("loom_left", 0.0)),
		float(enriched.get("loom_right", 0.0))
	)
	perceived_proximity = clampf(float(enriched.get("proximity", 0.0)), 0.0, 1.0)
	if not external_output.is_empty():
		brain_output = external_output.duplicate(true)
	elif connectome_brain.is_loaded():
		brain_output = connectome_brain.step(delta, enriched)
	else:
		brain_output = fallback_brain.step(delta, enriched)
	shock_input = maxf(0.0, shock_input - delta * 2.8)


func add_near_miss(intensity: float) -> void:
	shock_input = maxf(shock_input, clampf(intensity, 0.0, 1.0))
	dodge_cooldown = 0.0


func hit(direction: Vector3) -> void:
	if state == State.HIT:
		return
	state = State.HIT
	state_time = 0.0
	velocity = direction.normalized() * 2.0 + Vector3.UP * 2.5


func is_hit() -> bool:
	return state == State.HIT


func get_activity() -> Dictionary:
	return brain_output.get("activity", {})


func get_sensed_threat() -> Dictionary:
	return sensed_threat


func get_circuit_response() -> Dictionary:
	return brain_output


func get_brain_mode() -> String:
	var default_mode := "MALECNS SENSORIMOTOR" if connectome_brain.is_loaded() else "PROTOTYPE CIRCUIT"
	return str(brain_output.get("mode", default_mode))


func is_airborne() -> bool:
	return state in [State.TAKEOFF, State.FLYING, State.DODGING, State.RECOVERING]


func _physics_process(delta: float) -> void:
	state_time += delta
	decision_time -= delta
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)

	match state:
		State.PERCHED:
			_update_perched(delta)
		State.TAKEOFF:
			_update_takeoff(delta)
		State.FLYING:
			_update_flight_behavior(delta)
		State.DODGING:
			_update_dodge(delta)
		State.RECOVERING:
			_update_recovery(delta)
		State.HIT:
			_update_hit(delta)

	_update_animation(delta)


func _update_perched(delta: float) -> void:
	body_root.rotation.x = lerp_angle(body_root.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
	body_root.rotation.z = lerp_angle(body_root.rotation.z, 0.0, 1.0 - exp(-12.0 * delta))
	var looming_swatter := (
		perceived_proximity > 0.35
		and perceived_loom > PERCH_LOOM_THRESHOLD
	)
	if looming_swatter:
		perch_alert_time += delta
	else:
		perch_alert_time = maxf(0.0, perch_alert_time - delta * 2.5)
	var neural_alarm := (
		bool(brain_output.get("trigger_escape", false))
		or float(brain_output.get("escape_drive", 0.0)) > 0.34
		or float(brain_output.get("takeoff_drive", 0.0)) > 0.46
	)
	if dodge_cooldown <= 0.0 and (neural_alarm or perch_alert_time >= PERCH_REACTION_TIME):
		_begin_perch_takeoff(true)
		return
	velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
	if decision_time <= 0.0:
		_begin_perch_takeoff(false)


func _begin_perch_takeoff(threatened: bool) -> void:
	state = State.TAKEOFF
	state_time = 0.0
	takeoff_threatened = threatened
	perch_alert_time = 0.0
	dodge_cooldown = 0.72 if threatened else 0.35

	var launch_direction := _neural_motor_direction(desired_direction) if threatened else Vector3.ZERO
	launch_direction.y = 0.0
	if launch_direction.length_squared() < 0.01:
		launch_direction = Vector3(
			rng.randf_range(-1.0, 1.0),
			0.0,
			rng.randf_range(-1.0, 1.0)
		)
	launch_direction = launch_direction.normalized()
	var lateral := Vector3(-launch_direction.z, 0.0, launch_direction.x)
	var upward_drive := 0.72 if threatened else 0.52
	desired_direction = (
		launch_direction * 0.78
		+ lateral * rng.randf_range(-0.22, 0.22)
		+ Vector3.UP * upward_drive
	).normalized()
	var launch_speed := THREAT_TAKEOFF_SPEED if threatened else NATURAL_TAKEOFF_SPEED
	velocity = desired_direction * launch_speed
	wander_target = _random_air_point()
	decision_time = _destination_decision_time()
	if threatened:
		emit_signal("escaped")


func _update_takeoff(delta: float) -> void:
	var progress := clampf(state_time / TAKEOFF_DURATION, 0.0, 1.0)
	var initial_speed := THREAT_TAKEOFF_SPEED if takeoff_threatened else NATURAL_TAKEOFF_SPEED
	var target_speed := DODGE_SPEED if takeoff_threatened else CRUISE_SPEED
	var burst_speed := lerpf(initial_speed, target_speed, progress * progress)
	if takeoff_threatened:
		var neural_direction := _neural_motor_direction(desired_direction)
		desired_direction = desired_direction.lerp(
			neural_direction,
			1.0 - exp(-NEURAL_STEERING_RATE * 0.55 * delta)
		).normalized()
	velocity = velocity.lerp(desired_direction * burst_speed, 1.0 - exp(-18.0 * delta))
	var previous_position := global_position
	_move_inside_apartment(delta)
	_face_velocity(delta, global_position - previous_position)
	if state_time >= TAKEOFF_DURATION:
		state = State.DODGING if takeoff_threatened else State.FLYING
		state_time = 0.0


func _update_flight_behavior(delta: float) -> void:
	if bool(brain_output.get("trigger_escape", false)) and dodge_cooldown <= 0.0:
		_begin_dodge()
		return

	var distance_to_target := global_position.distance_to(wander_target)
	if distance_to_target < 0.30:
		if _is_perch_point(wander_target):
			if _motor_value("landing_drive", 1.0) >= 0.55:
				global_position = wander_target
				state = State.PERCHED
				state_time = 0.0
				decision_time = rng.randf_range(0.65, 1.45)
				perch_alert_time = 0.0
				velocity = Vector3.ZERO
				return
			wander_target = _random_air_point()
			decision_time = _destination_decision_time()
			return
		wander_target = _choose_destination()
		decision_time = _destination_decision_time()
	elif decision_time <= 0.0:
		wander_target = _choose_destination()
		decision_time = _destination_decision_time()

	var navigation_target := (
		apartment_layout.route_point(global_position, wander_target)
		if apartment_layout != null else wander_target
	)
	var navigation_direction := navigation_target - global_position
	if navigation_direction.length_squared() > 0.01:
		navigation_direction = navigation_direction.normalized()
	else:
		navigation_direction = desired_direction
	var neural_direction := _neural_motor_direction(navigation_direction)
	var neural_weight := clampf(
		maxf(
			float(brain_output.get("escape_drive", 0.0)),
			maxf(absf(_motor_value("yaw_drive", 0.0)), absf(_motor_value("pitch_drive", 0.0)))
		) * 0.92,
		0.0,
		0.88
	)
	desired_direction = (
		navigation_direction * (1.0 - neural_weight)
		+ neural_direction * neural_weight
	).normalized()
	var bob := Vector3.UP * sin(state_time * 8.5) * 0.12
	var cruise_scale := lerpf(0.88, 1.13, _motor_value("flight_power", 0.48))
	var target_velocity := desired_direction * CRUISE_SPEED * cruise_scale
	target_velocity.y *= VERTICAL_CRUISE_MULTIPLIER
	velocity = velocity.lerp(target_velocity + bob, 1.0 - exp(-4.8 * delta))
	var previous_position := global_position
	_move_inside_apartment(delta)
	_face_velocity(delta, global_position - previous_position)


func _begin_dodge() -> void:
	state = State.DODGING
	state_time = 0.0
	dodge_cooldown = 0.78
	var fallback_direction := velocity.normalized() if velocity.length_squared() > 0.01 else desired_direction
	desired_direction = _neural_motor_direction(fallback_direction)
	emit_signal("escaped")


func _update_dodge(delta: float) -> void:
	var neural_direction := _neural_motor_direction(desired_direction)
	desired_direction = desired_direction.lerp(
		neural_direction,
		1.0 - exp(-NEURAL_STEERING_RATE * delta)
	).normalized()
	var speed_curve := clampf(1.25 - state_time * 0.55, 0.62, 1.0)
	var power_scale := lerpf(0.90, 1.12, _motor_value("flight_power", 0.5))
	velocity = desired_direction * DODGE_SPEED * speed_curve * power_scale
	velocity.y *= VERTICAL_DODGE_MULTIPLIER
	var previous_position := global_position
	_move_inside_apartment(delta)
	_face_velocity(delta, global_position - previous_position)
	if state_time >= 0.64:
		state = State.RECOVERING
		state_time = 0.0
		wander_target = _choose_destination()


func _update_recovery(delta: float) -> void:
	var navigation_target := (
		apartment_layout.route_point(global_position, wander_target)
		if apartment_layout != null else wander_target
	)
	var recovery_direction := (navigation_target - global_position).normalized()
	var neural_direction := _neural_motor_direction(recovery_direction)
	var neural_weight := clampf(float(brain_output.get("escape_drive", 0.0)) * 0.55, 0.0, 0.55)
	recovery_direction = (recovery_direction * (1.0 - neural_weight) + neural_direction * neural_weight).normalized()
	var cruise_scale := lerpf(0.88, 1.13, _motor_value("flight_power", 0.48))
	var recovery_velocity := recovery_direction * CRUISE_SPEED * cruise_scale
	recovery_velocity.y *= VERTICAL_CRUISE_MULTIPLIER
	velocity = velocity.lerp(recovery_velocity, 1.0 - exp(-4.5 * delta))
	var previous_position := global_position
	_move_inside_apartment(delta)
	_face_velocity(delta, global_position - previous_position)
	if state_time > 0.42:
		state = State.FLYING
		state_time = 0.0
		decision_time = _destination_decision_time()
		emit_signal("recovered")


func _update_hit(delta: float) -> void:
	velocity += Vector3.DOWN * 7.5 * delta
	global_position += velocity * delta
	body_root.rotate_x(delta * 8.0)
	body_root.rotate_z(delta * 5.0)
	if global_position.y < FLOOR_Y:
		global_position.y = FLOOR_Y
		velocity = Vector3.ZERO


func _face_velocity(delta: float, traveled: Vector3 = Vector3.ZERO) -> void:
	var motion := traveled / maxf(delta, 0.0001) if traveled.length_squared() > 0.000001 else velocity
	var horizontal := Vector3(motion.x, 0.0, motion.z)
	if horizontal.length_squared() >= 0.0004:
		var target_yaw := atan2(-horizontal.x, -horizontal.z)
		var yaw_rate := 100.0 if state in [State.TAKEOFF, State.DODGING] else 60.0
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-yaw_rate * delta))
	if motion.length_squared() < 0.0004:
		return
	var target_pitch := atan2(motion.y, maxf(horizontal.length(), 0.01))
	body_root.rotation.x = lerp_angle(body_root.rotation.x, target_pitch * 0.68, 1.0 - exp(-18.0 * delta))
	var target_roll := _motor_value("roll_drive", 0.0) * 0.62
	body_root.rotation.z = lerp_angle(body_root.rotation.z, target_roll, 1.0 - exp(-13.0 * delta))


func _neural_motor_direction(fallback_direction: Vector3) -> Vector3:
	var yaw_drive := _motor_value("yaw_drive", _motor_value("turn_bias", 0.0))
	var pitch_command := _motor_value("pitch_drive", 0.0)
	var forward_drive := maxf(0.18, _motor_value("forward_drive", 0.58))
	var local_command := Vector3(yaw_drive, pitch_command, -forward_drive)
	var world_command := global_transform.basis * local_command
	if world_command.length_squared() > 0.01:
		return world_command.normalized()
	if fallback_direction.length_squared() > 0.01:
		return fallback_direction.normalized()
	return -global_transform.basis.z.normalized()


func _motor_value(channel: String, default_value: float) -> float:
	return float(brain_output.get(channel, default_value))


func _clamp_to_volume() -> void:
	var before := global_position
	global_position.x = clampf(global_position.x, VOLUME_MIN.x, VOLUME_MAX.x)
	global_position.y = clampf(global_position.y, VOLUME_MIN.y, VOLUME_MAX.y)
	global_position.z = clampf(global_position.z, VOLUME_MIN.z, VOLUME_MAX.z)
	if not is_equal_approx(before.x, global_position.x):
		desired_direction.x *= -1.0
	if not is_equal_approx(before.y, global_position.y):
		desired_direction.y *= -1.0
	if not is_equal_approx(before.z, global_position.z):
		desired_direction.z *= -1.0


func _move_inside_apartment(delta: float) -> void:
	var step_count := maxi(1, ceili(velocity.length() * delta / 0.09))
	var step_delta := delta / float(step_count)
	for _step in range(step_count):
		var previous_position := global_position
		global_position += velocity * step_delta
		_resolve_apartment_obstacles()
		_clamp_to_volume()
		if _is_inside_architecture(global_position) or _crosses_architecture(previous_position, global_position):
			global_position = previous_position
			velocity *= -0.18
			decision_time = minf(decision_time, 0.15)


func _resolve_apartment_obstacles() -> void:
	if apartment_layout == null:
		return
	for obstacle in apartment_layout.solids:
		var expanded: AABB = obstacle.grow(BODY_RADIUS)
		if not expanded.has_point(global_position):
			continue
		var end := expanded.end
		var distances := [
			global_position.x - expanded.position.x,
			end.x - global_position.x,
			global_position.y - expanded.position.y,
			end.y - global_position.y,
			global_position.z - expanded.position.z,
			end.z - global_position.z,
		]
		var nearest_face := 0
		for index in range(1, distances.size()):
			if float(distances[index]) < float(distances[nearest_face]):
				nearest_face = index
		match nearest_face:
			0:
				global_position.x = expanded.position.x - 0.001
				velocity.x = minf(velocity.x, 0.0)
			1:
				global_position.x = end.x + 0.001
				velocity.x = maxf(velocity.x, 0.0)
			2:
				global_position.y = expanded.position.y - 0.001
				velocity.y = minf(velocity.y, 0.0)
			3:
				global_position.y = end.y + 0.001
				velocity.y = maxf(velocity.y, 0.0)
			4:
				global_position.z = expanded.position.z - 0.001
				velocity.z = minf(velocity.z, 0.0)
			5:
				global_position.z = end.z + 0.001
				velocity.z = maxf(velocity.z, 0.0)


func is_inside_apartment_obstacle() -> bool:
	return (apartment_layout != null and apartment_layout.is_fly_inside_solid(global_position, BODY_RADIUS)) or _is_inside_architecture(global_position)


func _is_inside_architecture(point: Vector3) -> bool:
	if architecture_shape == null or not is_inside_tree():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = architecture_shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 2
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _crosses_architecture(from_point: Vector3, to_point: Vector3) -> bool:
	if not is_inside_tree() or from_point.is_equal_approx(to_point):
		return false
	var query := PhysicsRayQueryParameters3D.create(from_point, to_point)
	query.collision_mask = 2
	query.hit_back_faces = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _random_air_point() -> Vector3:
	if apartment_layout != null:
		return apartment_layout.random_air_point(rng)
	return Vector3(
		rng.randf_range(VOLUME_MIN.x + 0.35, VOLUME_MAX.x - 0.35),
		rng.randf_range(VOLUME_MIN.y + 0.30, VOLUME_MAX.y - 0.25),
		rng.randf_range(VOLUME_MIN.z + 0.35, VOLUME_MAX.z - 0.35)
	)


func _choose_destination() -> Vector3:
	var landing_probability := 0.26 * _motor_value("landing_drive", 1.0)
	if rng.randf() < landing_probability:
		return PERCH_POINTS[rng.randi_range(0, PERCH_POINTS.size() - 1)]
	return _random_air_point()


func _destination_decision_time() -> float:
	if apartment_layout != null and apartment_layout.room_at(global_position) != apartment_layout.room_at(wander_target):
		return rng.randf_range(5.0, 7.5)
	return rng.randf_range(1.3, 2.6)


func _is_perch_point(point: Vector3) -> bool:
	for perch_point in PERCH_POINTS:
		if point.distance_to(perch_point) < 0.02:
			return true
	return false


func _update_animation(delta: float) -> void:
	if not body_root:
		return
	var airborne := is_airborne()
	var frantic := state in [State.TAKEOFF, State.DODGING, State.RECOVERING]
	var neural_wing_rate := lerpf(48.0, 76.0, _motor_value("flight_power", 0.48))
	wing_phase += delta * (maxf(72.0, neural_wing_rate) if frantic else (neural_wing_rate if airborne else 9.0))
	apply_wing_pose(wing_phase, airborne)
	body_root.position.y = sin(Time.get_ticks_msec() * 0.008) * (0.025 if airborne else 0.006)
	var height_above_floor := maxf(0.0, global_position.y - FLOOR_Y)
	shadow.global_position = Vector3(global_position.x, FLOOR_Y + 0.01, global_position.z)
	shadow.global_rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	shadow.scale = Vector3.ONE * clampf(1.0 - height_above_floor * 0.10, 0.34, 0.82)
	var shadow_material := shadow.material_override as StandardMaterial3D
	if shadow_material:
		var shadow_color := shadow_material.albedo_color
		shadow_color.a = clampf(0.24 - height_above_floor * 0.035, 0.045, 0.22)
		shadow_material.albedo_color = shadow_color


func apply_wing_pose(phase: float, airborne: bool) -> void:
	var flap := sin(phase) * (0.68 if airborne else 0.08)
	if left_wing and right_wing:
		left_wing.rotation.z = -0.18 + flap
		right_wing.rotation.z = 0.18 - flap
	if left_wing_pivot and right_wing_pivot:
		left_wing_pivot.rotation.z = -flap
		right_wing_pivot.rotation.z = flap
		left_wing_pivot.rotation.y = -flap * 0.18
		right_wing_pivot.rotation.y = flap * 0.18


func _build_model() -> void:
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	if not _build_imported_model():
		_build_procedural_model()

	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.13)
	shadow.mesh = quad
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.28)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_material
	shadow.rotation.x = -PI / 2.0
	add_child(shadow)
	shadow.top_level = true

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = BODY_RADIUS
	collision.shape = shape
	add_child(collision)


func _build_imported_model() -> bool:
	var source_scene := load(IMPORTED_FLY_PATH) as PackedScene
	if source_scene == null:
		push_warning("Could not load %s; using the procedural fly." % IMPORTED_FLY_PATH)
		return false
	var scene_root := source_scene.instantiate() as Node3D
	if scene_root == null:
		return false
	imported_model = Node3D.new()
	imported_model.name = "ImportedFlyModel"
	body_root.add_child(imported_model)
	imported_model.add_child(scene_root)
	var bounds := AABB()
	var has_mesh := false
	var wing_source: MeshInstance3D
	for node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null:
			continue
		if part.name.begins_with("Cylinder001"):
			part.hide() # Display pedestal from the source scene, not part of the fly.
			continue
		if part.name.begins_with("Object008_MultiMat_0d"):
			wing_source = part
		var local_transform := imported_model.global_transform.affine_inverse() * part.global_transform
		var part_bounds := local_transform * part.mesh.get_aabb()
		bounds = bounds.merge(part_bounds) if has_mesh else part_bounds
		has_mesh = true
	if not has_mesh or wing_source == null or not _rig_imported_wings(wing_source):
		imported_model.queue_free()
		imported_model = null
		return false
	var longest_side := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var model_scale := IMPORTED_FLY_SIZE / maxf(longest_side, 0.001)
	imported_model.scale = Vector3.ONE * model_scale
	# The source fly faces +Z. Our controller treats -Z as forward.
	imported_model.rotation.y = PI
	imported_model.position = -(imported_model.transform.basis * bounds.get_center())
	return true


func _rig_imported_wings(source: MeshInstance3D) -> bool:
	var source_mesh := source.mesh
	if source_mesh.get_surface_count() != 1:
		return false
	var arrays := source_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.size() < 6 or indices.size() % 3 != 0:
		return false
	var left_indices := PackedInt32Array()
	var right_indices := PackedInt32Array()
	for triangle in range(0, indices.size(), 3):
		var x := (vertices[indices[triangle]].x + vertices[indices[triangle + 1]].x + vertices[indices[triangle + 2]].x) / 3.0
		var side := left_indices if x < 0.0 else right_indices
		side.append_array(indices.slice(triangle, triangle + 3))
	if left_indices.is_empty() or right_indices.is_empty():
		return false
	left_wing_pivot = _add_imported_wing(source, arrays, left_indices, Vector3(-7.0, 29.0, 7.0), "LeftWing")
	right_wing_pivot = _add_imported_wing(source, arrays, right_indices, Vector3(7.0, 29.0, 7.0), "RightWing")
	source.hide()
	return true


func _add_imported_wing(source: MeshInstance3D, arrays: Array, side_indices: PackedInt32Array, hinge: Vector3, wing_name: String) -> Node3D:
	var wing_arrays := arrays.duplicate(true)
	wing_arrays[Mesh.ARRAY_INDEX] = side_indices
	var wing_mesh := ArrayMesh.new()
	wing_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wing_arrays)
	wing_mesh.surface_set_material(0, source.get_active_material(0))
	var pivot := Node3D.new()
	pivot.name = wing_name + "Pivot"
	source.get_parent().add_child(pivot)
	pivot.transform = source.transform * Transform3D(Basis.IDENTITY, hinge)
	var wing := MeshInstance3D.new()
	wing.name = wing_name
	wing.mesh = wing_mesh
	wing.position = -hinge
	pivot.add_child(wing)
	return pivot


func _build_procedural_model() -> void:

	var dark := _material(Color("15181b"), 0.62, 0.18)
	var amber := _material(Color("d88b3d"), 0.48, 0.12)
	var eye_material := _material(Color("a92633"), 0.4, 0.1)
	var wing_material := _material(Color(0.62, 0.93, 0.91, 0.42), 0.2, 0.0, true)

	_add_sphere(body_root, Vector3(0.0, 0.02, 0.10), Vector3(0.18, 0.16, 0.25), dark)
	_add_sphere(body_root, Vector3(0.0, 0.02, -0.20), Vector3(0.15, 0.14, 0.28), amber)
	_add_sphere(body_root, Vector3(0.0, 0.03, 0.31), Vector3(0.16, 0.14, 0.15), dark)
	_add_sphere(body_root, Vector3(-0.105, 0.055, 0.35), Vector3(0.075, 0.085, 0.065), eye_material)
	_add_sphere(body_root, Vector3(0.105, 0.055, 0.35), Vector3(0.075, 0.085, 0.065), eye_material)

	left_wing = _add_wing(body_root, Vector3(-0.23, 0.08, -0.03), -0.34, wing_material)
	right_wing = _add_wing(body_root, Vector3(0.23, 0.08, -0.03), 0.34, wing_material)

	for side in [-1.0, 1.0]:
		for z_pos in [-0.14, 0.04, 0.22]:
			_add_leg(body_root, Vector3(side * 0.10, -0.05, z_pos), Vector3(side * 0.34, -0.17, z_pos + 0.08), dark)


func _add_sphere(parent: Node3D, position_value: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radial_segments = 14
	mesh.rings = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = position_value
	mesh_instance.scale = scale_value
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_wing(parent: Node3D, position_value: Vector3, angle: float, material: Material) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 6
	wing.mesh = mesh
	wing.scale = Vector3(0.28, 0.025, 0.48)
	wing.position = position_value
	wing.rotation.y = angle
	wing.material_override = material
	parent.add_child(wing)
	return wing


func _add_leg(parent: Node3D, from: Vector3, to: Vector3, material: Material) -> void:
	var leg := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 6
	leg.mesh = mesh
	leg.position = (from + to) * 0.5
	leg.material_override = material
	leg.look_at_from_position(leg.position, to, Vector3.FORWARD)
	leg.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	parent.add_child(leg)


func _material(color: Color, roughness: float, metallic: float, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
