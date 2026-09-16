class_name GameUI
extends CanvasLayer

signal start_requested
signal restart_requested
signal resume_requested

const INK := Color("e9f2ee")
const MUTED := Color("879891")
const PANEL := Color(0.035, 0.052, 0.061, 0.92)
const TEAL := Color("64d9c9")
const ORANGE := Color("ed9558")
const RED := Color("e65c62")

var timer_label: Label
var swings_label: Label
var escapes_label: Label
var status_label: Label
var attribution_label: Label
var credit_label: Label
var telemetry_panel: PanelContainer
var charge_fill: ColorRect
var activity_fills: Dictionary = {}
var activity_values: Dictionary = {}
var dn_caption: Label
var intro_panel: PanelContainer
var result_panel: PanelContainer
var result_title: Label
var result_body: Label
var pause_panel: PanelContainer
var crosshair: Control
var flash_rect: ColorRect
var flash_tween: Tween


func _ready() -> void:
	layer = 20
	_build_interface()


func update_hud(time_left: float, swings: int, escapes: int, charge: float, activity: Dictionary, mode: String, sensed: Dictionary = {}, response: Dictionary = {}) -> void:
	timer_label.text = "%05.1f" % maxf(time_left, 0.0)
	swings_label.text = "%02d" % swings
	escapes_label.text = "%02d" % escapes
	charge_fill.scale.x = clampf(charge, 0.0, 1.0)
	status_label.text = mode
	dn_caption.text = "DNp01" if mode == "MALECNS SENSORIMOTOR" else "TAKEOFF"
	if mode == "MALECNS SENSORIMOTOR":
		attribution_label.text = "NEURAL MODE: MALECNS v1.0 SENSORIMOTOR CIRCUIT  •  CC BY 4.0"
	else:
		attribution_label.text = "NEURAL MODE: CONNECTOME-INSPIRED PLACEHOLDER"
	_set_activity("loom_left", float(sensed.get("loom_left", 0.0)))
	_set_activity("loom_right", float(sensed.get("loom_right", 0.0)))
	_set_activity("dn_takeoff", float(activity.get("dn_takeoff", response.get("takeoff_drive", 0.0))))
	_set_activity("escape", float(response.get("escape_drive", activity.get("escape", 0.0))))
	var turn := float(response.get("yaw_drive", 0.0))
	_set_activity("turn", absf(turn), "L" if turn < -0.01 else ("R" if turn > 0.01 else "–"))


func set_telemetry_visible(enabled: bool) -> void:
	telemetry_panel.visible = enabled


func set_crosshair_position(position_value: Vector2) -> void:
	crosshair.position = position_value - crosshair.size * 0.5


func show_intro() -> void:
	intro_panel.visible = true
	result_panel.visible = false


func hide_intro() -> void:
	intro_panel.visible = false


func show_result(won: bool, time_left: float, swings: int, escapes: int) -> void:
	result_panel.visible = true
	result_title.text = "DIRECT HIT" if won else "THE FLY ESCAPED"
	result_title.modulate = TEAL if won else ORANGE
	if won:
		result_body.text = "Caught with %0.1f seconds remaining\n%d swings  •  %d neural escapes\nPress V for the split-screen replay" % [time_left, swings, escapes]
	else:
		result_body.text = "The circuit survived the full minute\n%d swings  •  %d neural escapes\nPress V for the split-screen replay" % [swings, escapes]


func flash_hit(success: bool) -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	flash_rect.color = Color(0.35, 0.96, 0.76, 0.26) if success else Color(1.0, 0.45, 0.25, 0.16)
	flash_rect.visible = true
	flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "color:a", 0.0, 0.34)
	flash_tween.tween_callback(func(): flash_rect.visible = false)


func set_paused(paused: bool) -> void:
	pause_panel.visible = paused


func _build_interface() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.visible = false
	root.add_child(flash_rect)
	var identity_back := ColorRect.new()
	identity_back.color = Color(0.035, 0.052, 0.061, 0.82)
	identity_back.position = Vector2(20, 16)
	identity_back.size = Vector2(245, 64)
	identity_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(identity_back)

	var brand := Label.new()
	brand.text = "ESCAPE / CIRCUIT"
	brand.position = Vector2(30, 24)
	brand.add_theme_font_size_override("font_size", 24)
	brand.add_theme_color_override("font_color", INK)
	root.add_child(brand)

	status_label = Label.new()
	status_label.text = "PROTOTYPE CIRCUIT"
	status_label.position = Vector2(32, 58)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", TEAL)
	root.add_child(status_label)

	var metrics := HBoxContainer.new()
	metrics.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	metrics.position = Vector2(-354, 24)
	metrics.size = Vector2(324, 58)
	metrics.add_theme_constant_override("separation", 8)
	root.add_child(metrics)
	timer_label = _metric(metrics, "TIME", "60.0")
	swings_label = _metric(metrics, "SWINGS", "00")
	escapes_label = _metric(metrics, "DODGES", "00")

	telemetry_panel = PanelContainer.new()
	telemetry_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	telemetry_panel.position = Vector2(28, -256)
	telemetry_panel.size = Vector2(340, 222)
	telemetry_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, 12, Color(0.28, 0.48, 0.46, 0.42), 1))
	root.add_child(telemetry_panel)
	var brain_margin := MarginContainer.new()
	brain_margin.add_theme_constant_override("margin_left", 18)
	brain_margin.add_theme_constant_override("margin_right", 18)
	brain_margin.add_theme_constant_override("margin_top", 14)
	brain_margin.add_theme_constant_override("margin_bottom", 14)
	telemetry_panel.add_child(brain_margin)
	var brain_vbox := VBoxContainer.new()
	brain_vbox.add_theme_constant_override("separation", 6)
	brain_margin.add_child(brain_vbox)
	var brain_title := Label.new()
	brain_title.text = "SENSED THREAT / MODELED LOOM"
	brain_title.add_theme_font_size_override("font_size", 13)
	brain_title.add_theme_color_override("font_color", INK)
	brain_vbox.add_child(brain_title)
	_add_activity_row(brain_vbox, "LEFT", "loom_left", TEAL)
	_add_activity_row(brain_vbox, "RIGHT", "loom_right", TEAL)
	var circuit_title := Label.new()
	circuit_title.text = "CIRCUIT RESPONSE / CONNECTOME-WEIGHTED"
	circuit_title.add_theme_font_size_override("font_size", 11)
	circuit_title.add_theme_color_override("font_color", MUTED)
	brain_vbox.add_child(circuit_title)
	_add_activity_row(brain_vbox, "DNp01", "dn_takeoff", ORANGE)
	_add_activity_row(brain_vbox, "ESCAPE", "escape", ORANGE)
	_add_activity_row(brain_vbox, "TURN", "turn", RED)

	var charge_panel := PanelContainer.new()
	charge_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	charge_panel.position = Vector2(-300, -92)
	charge_panel.size = Vector2(270, 56)
	charge_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, 10, Color.TRANSPARENT, 0))
	root.add_child(charge_panel)
	var charge_margin := MarginContainer.new()
	charge_margin.add_theme_constant_override("margin_left", 14)
	charge_margin.add_theme_constant_override("margin_right", 14)
	charge_margin.add_theme_constant_override("margin_top", 10)
	charge_margin.add_theme_constant_override("margin_bottom", 10)
	charge_panel.add_child(charge_margin)
	var charge_box := VBoxContainer.new()
	charge_margin.add_child(charge_box)
	var charge_label := Label.new()
	charge_label.text = "SWING POWER"
	charge_label.add_theme_font_size_override("font_size", 11)
	charge_label.add_theme_color_override("font_color", MUTED)
	charge_box.add_child(charge_label)
	var charge_track := ColorRect.new()
	charge_track.custom_minimum_size = Vector2(240, 8)
	charge_track.color = Color("26343a")
	charge_box.add_child(charge_track)
	charge_fill = ColorRect.new()
	charge_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	charge_fill.color = ORANGE
	charge_fill.pivot_offset = Vector2.ZERO
	charge_track.add_child(charge_fill)

	crosshair = Control.new()
	crosshair.size = Vector2(34, 34)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	for rect_data in [
		[Vector2(15, 0), Vector2(4, 11)],
		[Vector2(15, 23), Vector2(4, 11)],
		[Vector2(0, 15), Vector2(11, 4)],
		[Vector2(23, 15), Vector2(11, 4)],
	]:
		var line := ColorRect.new()
		line.position = rect_data[0]
		line.size = rect_data[1]
		line.color = Color(0.92, 0.98, 0.95, 0.82)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(line)

	intro_panel = _build_modal(root, "CAN A FLY BRAIN\nESCAPE YOU?", "WASD to move  •  Mouse to look\nHold to charge  •  Release to strike\nT: telemetry  •  V: replay your last attempt", "BEGIN EXPERIMENT")
	var intro_button: Button = intro_panel.get_node("Margin/Content/Action")
	intro_button.pressed.connect(func(): emit_signal("start_requested"))

	result_panel = _build_modal(root, "DIRECT HIT", "", "RUN IT AGAIN")
	result_title = result_panel.get_node("Margin/Content/Title")
	result_body = result_panel.get_node("Margin/Content/Body")
	var result_button: Button = result_panel.get_node("Margin/Content/Action")
	result_button.pressed.connect(func(): emit_signal("restart_requested"))
	result_panel.visible = false

	pause_panel = _build_modal(root, "EXPERIMENT PAUSED", "Press Escape to continue", "RESUME")
	var pause_button: Button = pause_panel.get_node("Margin/Content/Action")
	pause_button.pressed.connect(func(): emit_signal("resume_requested"))
	pause_panel.visible = false

	var footer_strip := ColorRect.new()
	footer_strip.color = Color(0.035, 0.052, 0.061, 0.90)
	footer_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer_strip.offset_top = -28
	footer_strip.offset_bottom = 0
	footer_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer_strip)
	attribution_label = Label.new()
	attribution_label.text = "NEURAL MODE: CONNECTOME-INSPIRED PLACEHOLDER"
	attribution_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	attribution_label.position = Vector2(-440, -25)
	attribution_label.add_theme_font_size_override("font_size", 10)
	attribution_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.66, 0.7))
	root.add_child(attribution_label)
	credit_label = Label.new()
	credit_label.text = "APARTMENT: Visthétique / CC BY 4.0     FLY: schmoldt.art / CC BY 4.0"
	credit_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credit_label.position = Vector2(30, -25)
	credit_label.add_theme_font_size_override("font_size", 10)
	credit_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.66, 0.7))
	root.add_child(credit_label)


func _metric(parent: Container, caption: String, value: String) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(102, 58)
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL, 10, Color.TRANSPARENT, 0))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 10)
	caption_label.add_theme_color_override("font_color", MUTED)
	box.add_child(caption_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", INK)
	box.add_child(value_label)
	return value_label


func _add_activity_row(parent: VBoxContainer, caption: String, key: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(54, 14)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", MUTED)
	row.add_child(label)
	if key == "dn_takeoff":
		dn_caption = label
	var track := ColorRect.new()
	track.custom_minimum_size = Vector2(188, 9)
	track.color = Color("26343a")
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(track)
	var fill := ColorRect.new()
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.color = color
	fill.pivot_offset = Vector2.ZERO
	track.add_child(fill)
	activity_fills[key] = fill
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(40, 14)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", INK)
	row.add_child(value_label)
	activity_values[key] = value_label


func _set_activity(key: String, value: float, direction := "") -> void:
	var fill: ColorRect = activity_fills.get(key)
	if fill:
		fill.scale.x = clampf(value, 0.0, 1.0)
	var value_label: Label = activity_values.get(key)
	if value_label:
		value_label.text = direction + ("%.2f" % clampf(value, 0.0, 1.0)) if direction.is_empty() else direction + " %.1f" % clampf(value, 0.0, 1.0)


func _build_modal(parent: Control, title_text: String, body_text: String, action_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Modal"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-250, -170)
	panel.size = Vector2(500, 340)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.04, 0.047, 0.97), 18, Color(0.35, 0.75, 0.69, 0.52), 1))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 38)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 34)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 24)
	margin.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "CONNECTOME GAMEPLAY STUDY / 001"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", TEAL)
	content.add_child(eyebrow)
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", INK)
	content.add_child(title)
	var body := Label.new()
	body.name = "Body"
	body.text = body_text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", MUTED)
	content.add_child(body)
	var button := Button.new()
	button.name = "Action"
	button.text = action_text
	button.custom_minimum_size = Vector2(250, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("10201e"))
	button.add_theme_stylebox_override("normal", _panel_style(TEAL, 8, Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("hover", _panel_style(Color("8af0e1"), 8, Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("45b7a9"), 8, Color.TRANSPARENT, 0))
	content.add_child(button)
	return panel


func _panel_style(color: Color, radius: int, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	return style
