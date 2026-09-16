class_name PlayerController
extends Node3D

## Lightweight first-person apartment controller. The player walks on the floor,
## looks freely in 3D, and is kept outside the major furniture footprints.

const MOVE_SPEED := 3.15
const MOUSE_SENSITIVITY := 0.0022
const EYE_HEIGHT := 1.72
const PLAYER_RADIUS := 0.32
const ROOM_MIN := ApartmentLayout.PLAYER_MIN
const ROOM_MAX := ApartmentLayout.PLAYER_MAX

var camera: Camera3D
var active := false
var pitch := -0.075
var yaw := 0.0
var walk_phase := 0.0
var current_input := Vector2.ZERO
var movement_velocity := Vector3.ZERO
var apartment_layout: ApartmentLayout


func set_apartment_layout(value: ApartmentLayout) -> void:
	apartment_layout = value


func _ready() -> void:
	position = ApartmentLayout.PLAYER_START
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	camera.fov = 64.0
	camera.current = true
	add_child(camera)
	_apply_look()


func set_active(value: bool) -> void:
	active = value
	current_input = Vector2.ZERO
	movement_velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE
	if camera:
		camera.position.x = 0.0
		camera.position.z = 0.0
		camera.rotation = Vector3(pitch, 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not active or not event is InputEventMouseMotion:
		return
	yaw -= event.relative.x * MOUSE_SENSITIVITY
	pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.18, 1.05)
	_apply_look()
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not active:
		movement_velocity = Vector3.ZERO
		camera.position.y = lerpf(camera.position.y, EYE_HEIGHT, 1.0 - exp(-8.0 * delta))
		return
	current_input = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	_apply_movement(current_input, delta)
	_update_head_bob(delta, current_input.length())


func move_for_test(input_vector: Vector2, delta: float) -> void:
	_apply_movement(input_vector.limit_length(1.0), delta)


func get_movement_velocity() -> Vector3:
	return movement_velocity


func _apply_movement(input_vector: Vector2, delta: float) -> void:
	var previous_position := position
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var direction := right * input_vector.x + forward * -input_vector.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var displacement := direction * MOVE_SPEED * delta
	var step_count := maxi(1, ceili(displacement.length() / 0.10))
	var step := displacement / float(step_count)
	for _step in range(step_count):
		var candidate := position
		candidate.x = clampf(candidate.x + step.x, ROOM_MIN.x, ROOM_MAX.x)
		if not _is_blocked(candidate):
			position.x = candidate.x

		candidate = position
		candidate.z = clampf(candidate.z + step.z, ROOM_MIN.y, ROOM_MAX.y)
		if not _is_blocked(candidate):
			position.z = candidate.z
	movement_velocity = (position - previous_position) / maxf(delta, 0.0001)


func _is_blocked(candidate: Vector3) -> bool:
	if apartment_layout != null and apartment_layout.is_player_blocked(candidate, PLAYER_RADIUS):
		return true
	var probe := SphereShape3D.new()
	probe.radius = PLAYER_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * 1.0)
	query.collision_mask = 2
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _update_head_bob(delta: float, movement_amount: float) -> void:
	if movement_amount > 0.05:
		walk_phase += delta * 9.5
	var target_height := EYE_HEIGHT
	if movement_amount > 0.05:
		target_height += sin(walk_phase) * 0.022
	camera.position = Vector3(
		0.0,
		lerpf(camera.position.y, target_height, 1.0 - exp(-12.0 * delta)),
		0.0
	)
	camera.rotation = Vector3(pitch, 0.0, 0.0)


func _apply_look() -> void:
	rotation.y = yaw
	if camera:
		camera.rotation = Vector3(pitch, 0.0, 0.0)
