class_name ReplayView
extends CanvasLayer

## Two cameras render the same paused apartment while the recorded actor poses
## and telemetry are restored frame by frame. This is an in-game video aid, not
## a claim that the connectome reproduces biological fly behavior.

const INK := Color("e9f2ee")
const MUTED := Color("879891")
const TEAL := Color("64d9c9")
const ORANGE := Color("ed9558")
const PANEL := Color("10191e")

var player_camera: Camera3D
var fly_camera: Camera3D
var fly_key_light: OmniLight3D
var fly_rid: RID
var timeline_fill: ColorRect
var timestamp_label: Label
var threat_label: Label
var circuit_label: Label
var clip_label: Label


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	visible = false


func bind_world(world: World3D, subject_rid: RID) -> void:
	var player_view := player_camera.get_viewport() as SubViewport
	var fly_view := fly_camera.get_viewport() as SubViewport
	player_view.world_3d = world
	fly_view.world_3d = world
	fly_rid = subject_rid


func show_clip(duration: float, outcome: String) -> void:
	clip_label.text = "%s  /  LAST %.1f SECONDS" % [outcome, duration]
	fly_key_light.visible = true
	visible = true


func hide_clip() -> void:
	fly_key_light.visible = false
	visible = false


func show_frame(frame: Dictionary, progress: float, seconds: float) -> void:
	player_camera.global_transform = frame.get("camera", Transform3D.IDENTITY)
	var fly_pose: Transform3D = frame.get("fly", Transform3D.IDENTITY)
	var player_position := player_camera.global_position
	var toward_player := player_position - fly_pose.origin
	if toward_player.length_squared() < 0.01:
		toward_player = Vector3.BACK
	var focus := fly_pose.origin + Vector3.UP * 0.02
	var front := -fly_pose.basis.z.normalized()
	var right := fly_pose.basis.x.normalized()
	var three_quarter := (front * 0.78 + right * 0.38 + toward_player.normalized() * 0.12).normalized()
	var preferred := focus + three_quarter * 0.58 + Vector3.UP * 0.15
	var query := PhysicsRayQueryParameters3D.create(focus, preferred)
	query.exclude = [fly_rid]
	var obstruction := fly_camera.get_world_3d().direct_space_state.intersect_ray(query)
	fly_camera.global_position = preferred if obstruction.is_empty() else focus + toward_player.normalized() * 0.72 + Vector3.UP * 0.18
	fly_camera.look_at(focus, Vector3.UP)
	timeline_fill.scale.x = clampf(progress, 0.0, 1.0)
	timestamp_label.text = "%04.1f s" % seconds
	var sensed: Dictionary = frame.get("sensed", {})
	var response: Dictionary = frame.get("response", {})
	var activity: Dictionary = response.get("activity", {})
	threat_label.text = "LC4 SPEED %.2f  /  LPLC2 SIZE %.2f" % [
		maxf(float(sensed.get("lc4_left", 0.0)), float(sensed.get("lc4_right", 0.0))),
		maxf(float(sensed.get("lplc2_left", 0.0)), float(sensed.get("lplc2_right", 0.0))),
	]
	var takeoff_caption := "DNp01" if str(response.get("mode", "")) == "MALECNS SENSORIMOTOR" else "TAKEOFF"
	circuit_label.text = "%s %.2f    ESCAPE %.2f    %s" % [
		takeoff_caption,
		float(activity.get("dn_takeoff", response.get("takeoff_drive", 0.0))),
		float(response.get("escape_drive", 0.0)),
		str(response.get("selected_action", "NONE")).replace("_", " "),
	]


func _build_interface() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var background := ColorRect.new()
	background.color = Color("071015")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 28)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	root.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "ESCAPE / CIRCUIT     SPLIT-SCREEN REPLAY"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	clip_label = Label.new()
	clip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clip_label.add_theme_font_size_override("font_size", 12)
	clip_label.add_theme_color_override("font_color", TEAL)
	header.add_child(clip_label)

	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 12)
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(views)
	player_camera = _view_column(views, "PLAYER / SWATTER", 64.0)
	fly_camera = _view_column(views, "FLY / CIRCUIT", 42.0)
	fly_key_light = OmniLight3D.new()
	fly_key_light.light_color = Color(0.90, 0.96, 1.0)
	fly_key_light.light_energy = 1.15
	fly_key_light.omni_range = 1.2
	fly_key_light.shadow_enabled = false
	fly_key_light.visible = false
	fly_camera.add_child(fly_key_light)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _panel_style())
	layout.add_child(footer)
	var footer_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		footer_margin.add_theme_constant_override(side, 18)
	for side in ["margin_top", "margin_bottom"]:
		footer_margin.add_theme_constant_override(side, 12)
	footer.add_child(footer_margin)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	footer_margin.add_child(details)
	var readouts := HBoxContainer.new()
	readouts.add_theme_constant_override("separation", 24)
	details.add_child(readouts)
	threat_label = _readout(readouts, TEAL)
	circuit_label = _readout(readouts, ORANGE)
	var timeline := HBoxContainer.new()
	timeline.add_theme_constant_override("separation", 12)
	details.add_child(timeline)
	var track := ColorRect.new()
	track.color = Color("26343a")
	track.custom_minimum_size = Vector2(100, 7)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timeline.add_child(track)
	timeline_fill = ColorRect.new()
	timeline_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timeline_fill.color = ORANGE
	track.add_child(timeline_fill)
	timestamp_label = Label.new()
	timestamp_label.custom_minimum_size = Vector2(62, 18)
	timestamp_label.add_theme_font_size_override("font_size", 11)
	timestamp_label.add_theme_color_override("font_color", INK)
	timeline.add_child(timestamp_label)
	var boundary := Label.new()
	boundary.text = "Measured fruit-fly contacts; movement remains engineered.  Fly art: schmoldt.art / CC BY 4.0.  V or Esc: close replay"
	boundary.add_theme_font_size_override("font_size", 10)
	boundary.add_theme_color_override("font_color", MUTED)
	details.add_child(boundary)


func _view_column(parent: HBoxContainer, caption: String, fov: float) -> Camera3D:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEAL)
	column.add_child(label)
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(500, 400)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(frame)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(680, 560)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	frame.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = fov
	camera.current = true
	viewport.add_child(camera)
	return camera


func _readout(parent: HBoxContainer, color: Color) -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style
