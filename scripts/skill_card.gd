class_name StickSkillCard
extends Control

const GymnastScript = preload("res://scripts/gymnast.gd")

signal clicked(skill_index: int)
signal remove_clicked(routine_index: int)
signal preview_finished(skill_index: int, routine_index: int, from_routine: bool)

var skill: Dictionary = {}
var skill_index: int = -1
var routine_index: int = -1
var from_routine: bool = false
var selected := false
var preview_time := 0.0
var press_position := Vector2.ZERO
var press_pending := false
var preview_container: TextureRect
var preview_viewport: SubViewport
var preview_gymnast: Node2D

func setup(value: Dictionary, index: int, routine_card := false, sequence_index := -1) -> void:
	skill = value
	skill_index = index
	from_routine = routine_card
	routine_index = sequence_index
	custom_minimum_size = Vector2(174, 132) if not from_routine else Vector2(132, 112)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()

func set_selected(value: bool) -> void:
	selected = value
	if is_inside_tree():
		_refresh_live_preview()
	queue_redraw()

func _ready() -> void:
	_refresh_live_preview()

func _refresh_live_preview() -> void:
	if not selected:
		if preview_container != null:
			preview_container.queue_free()
		if preview_viewport != null:
			preview_viewport.queue_free()
		preview_container = null
		preview_viewport = null
		preview_gymnast = null
		return
	if preview_container != null or skill.is_empty():
		return
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(1000, 550)
	preview_viewport.transparent_bg = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(preview_viewport)
	preview_gymnast = GymnastScript.new()
	preview_viewport.add_child(preview_gymnast)
	var isolated_skill: Dictionary = skill.duplicate(true)
	isolated_skill.loop = false
	isolated_skill.default_follow = ""
	preview_gymnast.skill_completed.connect(_on_preview_skill_completed)
	preview_gymnast.set_skill(isolated_skill, true)
	preview_container = TextureRect.new()
	preview_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_container.offset_left = 7.0
	preview_container.offset_top = 7.0
	preview_container.offset_right = -7.0
	preview_container.offset_bottom = -45.0
	preview_container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_container.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_container.texture = preview_viewport.get_texture()
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_container)

func _on_preview_skill_completed(_completed_skill: Dictionary) -> void:
	preview_finished.emit(skill_index, routine_index, from_routine)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_position = event.position
			press_pending = true
		elif press_pending:
			press_pending = false
			if from_routine and event.position.x > size.x - 24.0 and event.position.y < 26.0:
				remove_clicked.emit(routine_index)
			elif event.position.distance_to(press_position) < 6.0:
				clicked.emit(skill_index)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview: Control = get_script().new()
	preview.setup(skill, skill_index, from_routine, routine_index)
	preview.modulate.a = 0.82
	set_drag_preview(preview)
	return {
		"kind":"stick_skill",
		"skill_index":skill_index,
		"routine_index":routine_index,
		"from_routine":from_routine,
	}

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_card_style(), rect)
	if skill.is_empty():
		return
	var difficulty: float = float(skill.get("difficulty", 0.0))
	var letter: String = StickScoring.difficulty_letter(difficulty)
	if not selected:
		draw_string(ThemeDB.fallback_font, Vector2(10, 30), str(skill.get("name", "Move")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 18, Color("#fff5d6"))
		draw_string(ThemeDB.fallback_font, Vector2(10, 54), "%s  |  %s" % [letter, str(skill.get("move_class", "swing")).capitalize()], HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 13, Color("#72ddf7"))
		var description := _move_description()
		draw_multiline_string(ThemeDB.fallback_font, Vector2(10, 76), description, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 12, 3, Color("#b5c4d8"))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(7, size.y - 8.0), str(skill.get("name", "Move")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 13.0, 11, Color("#fff5d6"))
	if from_routine:
		draw_circle(Vector2(size.x - 13.0, 13.0), 10.0, Color("#7b3241"))
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 18.0, 18.0), "X", HORIZONTAL_ALIGNMENT_LEFT, 12.0, 15, Color.WHITE)

func _move_description() -> String:
	var move_class: String = str(skill.get("move_class", "swing"))
	if move_class == "mount":
		return "Begins the routine from a static hang."
	if move_class == "release":
		return "Flight and regrasp - precise timing required."
	if move_class == "dismount":
		return "Release from the bar and try to stick."
	if _is_turn_skill():
		return "Changes direction or grip above the bar."
	return "Connecting swing used to build momentum."

func _is_turn_skill() -> bool:
	var id: String = str(skill.get("id", "")).to_lower()
	if id.contains("blind") or id.contains("pirouette") or id.contains("turn"):
		return true
	var frames: Array = skill.get("keyframes", [])
	if frames.size() < 2:
		return false
	return absf(float(frames[-1].pose.get("body_yaw", 0.0)) - float(frames[0].pose.get("body_yaw", 0.0))) > 0.25

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#19314e")
	style.border_color = Color("#385c7c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style

func _draw_thumbnail(rect: Rect2) -> void:
	draw_rect(rect, Color("#0b1729"), true)
	var frames: Array = skill.get("keyframes", [])
	if frames.is_empty():
		return
	var execution_index: int = clampi(int(skill.get("execution_keyframe", frames.size() / 2)), 0, frames.size() - 1)
	if selected:
		return
	var pose: Dictionary = frames[execution_index].get("pose", {})
	for required in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
		if not pose.has(required):
			return
	var points: Array[Vector2] = [Vector2(pose.hand), Vector2(pose.shoulder), Vector2(pose.hip), Vector2(pose.knee), Vector2(pose.ankle), Vector2(pose.head)]
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	var extent: Vector2 = maximum - minimum
	var scale_factor: float = minf((rect.size.x - 9.0) / maxf(extent.x, 30.0), (rect.size.y - 8.0) / maxf(extent.y, 30.0))
	var source_center: Vector2 = (minimum + maximum) * 0.5
	var mapped: Array[Vector2] = []
	for point in points:
		mapped.append(rect.get_center() + (point - source_center) * scale_factor)
	var hand: Vector2 = mapped[0]
	var shoulder: Vector2 = mapped[1]
	var hip: Vector2 = mapped[2]
	var knee: Vector2 = mapped[3]
	var feet: Vector2 = mapped[4]
	var head: Vector2 = mapped[5]
	var ink := Color("#f7e7bd")
	draw_circle(head, 4.2, ink)
	draw_line(hand, shoulder, ink, 2.0, true)
	draw_line(shoulder, hip, ink, 2.4, true)
	draw_line(hip, knee, ink, 2.2, true)
	draw_line(knee, feet, ink, 2.0, true)
	if selected:
		draw_rect(rect.grow(2.0), Color("#72f1b8"), false, 3.0)
