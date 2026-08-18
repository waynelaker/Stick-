extends Node2D

var gymnast: StickGymnast
var skills: Array[Dictionary] = []
var selected_move := 0
var selected_keyframe := -1
var edit_mode := false
var updating_ui := false

var status: Label
var editor_panel: Control
var move_select: OptionButton
var move_name: LineEdit
var timeline: HSlider
var keyframe_markers: Control
var time_label: Label
var keyframe_select: OptionButton
var preview_button: Button
var duration_input: SpinBox
var loop_input: CheckBox
var import_dialog: FileDialog

func _ready() -> void:
	queue_redraw()
	_ensure_move_inputs()
	skills = AuthoredSkills.builtin_skills()
	gymnast = StickGymnast.new()
	add_child(gymnast)
	gymnast.ghost_keyframe_clicked.connect(_select_keyframe)
	gymnast.set_skill(skills[0], true)
	_build_interface()
	_refresh_moves()
	_refresh_keyframes()

func _process(_delta: float) -> void:
	if edit_mode and gymnast.playing:
		updating_ui = true
		timeline.value = gymnast.skill_time / float(gymnast.skill.duration) * 1000.0
		time_label.text = "%0.2f / %0.2fs" % [gymnast.skill_time, gymnast.skill.duration]
		updating_ui = false
		if not gymnast.playing:
			preview_button.text = "Preview"

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var play_mode := Button.new()
	play_mode.position = Vector2(18, 560)
	play_mode.size = Vector2(100, 38)
	play_mode.text = "Play mode"
	play_mode.pressed.connect(func(): _set_mode(false))
	layer.add_child(play_mode)
	var edit_mode_button := Button.new()
	edit_mode_button.position = Vector2(126, 560)
	edit_mode_button.size = Vector2(100, 38)
	edit_mode_button.text = "Edit mode"
	edit_mode_button.pressed.connect(func(): _set_mode(true))
	layer.add_child(edit_mode_button)
	status = Label.new()
	status.position = Vector2(246, 568)
	status.size = Vector2(570, 28)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.text = "G NORMAL  ·  T TAP  ·  D DISMOUNT  ·  SPACE PAUSE  ·  R RESTART"
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("#b5c4d8"))
	layer.add_child(status)
	var dismount_button := Button.new()
	dismount_button.position = Vector2(834, 560)
	dismount_button.size = Vector2(148, 38)
	dismount_button.text = "Dismount [D]"
	dismount_button.pressed.connect(_queue_dismount)
	layer.add_child(dismount_button)

	editor_panel = Control.new()
	editor_panel.position = Vector2(0, 610)
	editor_panel.size = Vector2(1000, 150)
	layer.add_child(editor_panel)
	var panel_background := ColorRect.new()
	panel_background.size = editor_panel.size
	panel_background.color = Color("#12243d")
	panel_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor_panel.add_child(panel_background)

	move_select = OptionButton.new()
	move_select.position = Vector2(18, 10)
	move_select.size = Vector2(190, 34)
	move_select.item_selected.connect(_on_move_selected)
	editor_panel.add_child(move_select)
	move_name = LineEdit.new()
	move_name.position = Vector2(218, 10)
	move_name.size = Vector2(160, 34)
	move_name.placeholder_text = "New move name"
	editor_panel.add_child(move_name)
	var add_move := Button.new()
	add_move.position = Vector2(388, 10)
	add_move.size = Vector2(100, 34)
	add_move.text = "Add move"
	add_move.pressed.connect(_add_move)
	editor_panel.add_child(add_move)
	var delete_move := Button.new()
	delete_move.position = Vector2(496, 10)
	delete_move.size = Vector2(110, 34)
	delete_move.text = "Delete move"
	delete_move.pressed.connect(_delete_move)
	editor_panel.add_child(delete_move)
	preview_button = Button.new()
	preview_button.position = Vector2(616, 10)
	preview_button.size = Vector2(90, 34)
	preview_button.text = "Preview"
	preview_button.pressed.connect(_toggle_preview)
	editor_panel.add_child(preview_button)
	var import_button := Button.new()
	import_button.position = Vector2(716, 10)
	import_button.size = Vector2(90, 34)
	import_button.text = "Import"
	import_button.pressed.connect(func(): import_dialog.popup_centered_ratio(0.75))
	editor_panel.add_child(import_button)
	var save_button := Button.new()
	save_button.position = Vector2(816, 10)
	save_button.size = Vector2(166, 34)
	save_button.text = "Save move"
	save_button.pressed.connect(_save_move)
	editor_panel.add_child(save_button)

	timeline = HSlider.new()
	timeline.position = Vector2(18, 55)
	timeline.size = Vector2(675, 28)
	timeline.min_value = 0
	timeline.max_value = 1000
	timeline.step = 1
	timeline.value_changed.connect(_on_timeline_changed)
	editor_panel.add_child(timeline)
	keyframe_markers = Control.new()
	keyframe_markers.position = Vector2(18, 55)
	keyframe_markers.size = Vector2(675, 28)
	# Empty space passes through to the slider; the child dot buttons still
	# receive clicks at their explicit keyframe positions.
	keyframe_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor_panel.add_child(keyframe_markers)
	time_label = Label.new()
	time_label.position = Vector2(706, 58)
	time_label.size = Vector2(125, 24)
	editor_panel.add_child(time_label)
	var drag_help := Label.new()
	drag_help.position = Vector2(836, 58)
	drag_help.size = Vector2(150, 24)
	drag_help.text = "Drag joints above"
	drag_help.add_theme_color_override("font_color", Color("#72ddf7"))
	editor_panel.add_child(drag_help)

	keyframe_select = OptionButton.new()
	keyframe_select.position = Vector2(18, 96)
	keyframe_select.size = Vector2(205, 34)
	keyframe_select.item_selected.connect(_on_keyframe_selected)
	editor_panel.add_child(keyframe_select)
	_add_editor_button(editor_panel, "Add keyframe", Vector2(233, 96), _add_keyframe)
	_add_editor_button(editor_panel, "Update keyframe", Vector2(354, 96), _update_keyframe, 145)
	_add_editor_button(editor_panel, "Delete keyframe", Vector2(509, 96), _delete_keyframe, 140)
	var duration_label := Label.new()
	duration_label.position = Vector2(666, 102)
	duration_label.text = "Duration"
	editor_panel.add_child(duration_label)
	duration_input = SpinBox.new()
	duration_input.position = Vector2(730, 96)
	duration_input.size = Vector2(105, 34)
	duration_input.min_value = 0.1
	duration_input.max_value = 30.0
	duration_input.step = 0.05
	duration_input.suffix = " s"
	duration_input.value_changed.connect(_on_duration_changed)
	editor_panel.add_child(duration_input)
	loop_input = CheckBox.new()
	loop_input.position = Vector2(850, 96)
	loop_input.size = Vector2(120, 34)
	loop_input.text = "Loop move"
	loop_input.toggled.connect(_on_loop_changed)
	editor_panel.add_child(loop_input)

	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = PackedStringArray(["*.json ; Stick! skill"])
	import_dialog.file_selected.connect(_import_move)
	layer.add_child(import_dialog)
	editor_panel.visible = false

func _add_editor_button(parent: Control, text: String, position: Vector2, callback: Callable, width := 112) -> void:
	var button := Button.new()
	button.position = position
	button.size = Vector2(width, 34)
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func _set_mode(wants_edit: bool) -> void:
	edit_mode = wants_edit
	editor_panel.visible = edit_mode
	gymnast.set_editor_enabled(edit_mode)
	if edit_mode:
		gymnast.set_skill(skills[selected_move], false)
		status.text = "EDIT MODE — SCRUB, DRAG A JOINT, THEN UPDATE OR ADD A KEYFRAME"
		_refresh_keyframes()
	else:
		gymnast.set_skill(skills[selected_move], true)
		status.text = "G NORMAL  ·  T TAP  ·  D DISMOUNT  ·  SPACE PAUSE  ·  R RESTART"

func _on_move_selected(index: int) -> void:
	if updating_ui:
		return
	selected_move = index
	selected_keyframe = -1
	gymnast.set_skill(skills[index], not edit_mode)
	_refresh_keyframes()

func _refresh_moves() -> void:
	updating_ui = true
	move_select.clear()
	for move in skills:
		move_select.add_item(str(move.name))
	move_select.select(clampi(selected_move, 0, skills.size() - 1))
	updating_ui = false

func _refresh_keyframes() -> void:
	updating_ui = true
	gymnast.set_selected_keyframe(selected_keyframe)
	keyframe_select.clear()
	for index in range(gymnast.skill.keyframes.size()):
		var frame: Dictionary = gymnast.skill.keyframes[index]
		keyframe_select.add_item("%02d  %0.2fs  %s" % [index + 1, frame.time, frame.get("label", "")])
	if selected_keyframe >= 0 and selected_keyframe < keyframe_select.item_count:
		keyframe_select.select(selected_keyframe)
	_refresh_keyframe_markers()
	timeline.value = gymnast.skill_time / float(gymnast.skill.duration) * 1000.0
	time_label.text = "%0.2f / %0.2fs" % [gymnast.skill_time, gymnast.skill.duration]
	duration_input.value = gymnast.skill.duration
	loop_input.button_pressed = gymnast.skill.loop
	updating_ui = false

func _on_timeline_changed(value: float) -> void:
	if updating_ui:
		return
	gymnast.playing = false
	preview_button.text = "Preview"
	var time := value / 1000.0 * float(gymnast.skill.duration)
	gymnast.seek(time)
	time_label.text = "%0.2f / %0.2fs" % [time, gymnast.skill.duration]
	selected_keyframe = -1
	gymnast.set_selected_keyframe(-1)
	keyframe_select.select(-1)
	_update_marker_selection()

func _on_duration_changed(value: float) -> void:
	if updating_ui:
		return
	var last_time := 0.0
	for frame in gymnast.skill.keyframes:
		last_time = maxf(last_time, float(frame.time))
	if value < last_time:
		updating_ui = true
		duration_input.value = last_time
		updating_ui = false
		status.text = "DURATION CANNOT END BEFORE THE LAST KEYFRAME"
		return
	gymnast.skill.duration = value
	_refresh_keyframes()

func _on_loop_changed(enabled: bool) -> void:
	if not updating_ui:
		gymnast.skill.loop = enabled

func _on_keyframe_selected(index: int) -> void:
	if updating_ui:
		return
	_select_keyframe(index)

func _select_keyframe(index: int) -> void:
	selected_keyframe = index
	gymnast.set_selected_keyframe(index)
	var time: float = gymnast.skill.keyframes[index].time
	gymnast.seek(time)
	updating_ui = true
	keyframe_select.select(index)
	timeline.value = time / float(gymnast.skill.duration) * 1000.0
	updating_ui = false
	time_label.text = "%0.2f / %0.2fs" % [time, gymnast.skill.duration]
	_update_marker_selection()

func _refresh_keyframe_markers() -> void:
	for child in keyframe_markers.get_children():
		keyframe_markers.remove_child(child)
		child.queue_free()
	for index in range(gymnast.skill.keyframes.size()):
		var frame: Dictionary = gymnast.skill.keyframes[index]
		var marker := Button.new()
		marker.set_meta("keyframe_index", index)
		marker.position = Vector2(float(frame.time) / float(gymnast.skill.duration) * keyframe_markers.size.x - 7.0, 7.0)
		marker.size = Vector2(14, 14)
		marker.flat = false
		marker.focus_mode = Control.FOCUS_NONE
		marker.tooltip_text = "%s — %0.2fs" % [frame.get("label", "Keyframe"), frame.time]
		marker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		marker.pressed.connect(_select_keyframe.bind(index))
		keyframe_markers.add_child(marker)
	_update_marker_selection()

func _update_marker_selection() -> void:
	for marker in keyframe_markers.get_children():
		var index := int(marker.get_meta("keyframe_index"))
		var selected := index == selected_keyframe
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#72ddf7") if selected else Color("#ffbc42")
		style.border_color = Color.WHITE if selected else Color("#fff5d6")
		style.set_border_width_all(2 if selected else 1)
		style.set_corner_radius_all(7)
		marker.add_theme_stylebox_override("normal", style)
		marker.add_theme_stylebox_override("hover", style)
		marker.add_theme_stylebox_override("pressed", style)

func _toggle_preview() -> void:
	if not gymnast.playing and not gymnast.skill.loop and gymnast.skill_time >= float(gymnast.skill.duration):
		gymnast.seek(0.0)
	gymnast.playing = not gymnast.playing
	preview_button.text = "Pause" if gymnast.playing else "Preview"

func _add_keyframe() -> void:
	selected_keyframe = gymnast.add_keyframe(gymnast.skill_time)
	_refresh_keyframes()
	status.text = "KEYFRAME ADDED"

func _update_keyframe() -> void:
	if selected_keyframe < 0:
		status.text = "SELECT A KEYFRAME TO UPDATE"
		return
	gymnast.update_keyframe(selected_keyframe)
	status.text = "KEYFRAME UPDATED"

func _delete_keyframe() -> void:
	if not gymnast.delete_keyframe(selected_keyframe):
		status.text = "KEEP AT LEAST TWO KEYFRAMES"
		return
	selected_keyframe = -1
	_refresh_keyframes()
	status.text = "KEYFRAME DELETED"

func _add_move() -> void:
	var requested_name := move_name.text.strip_edges()
	if requested_name.is_empty():
		status.text = "ENTER A NAME FOR THE NEW MOVE"
		return
	var move := AuthoredSkills.new_skill(requested_name, gymnast.current_pose_copy())
	var base_id: String = move.id
	var suffix := 2
	while _find_skill(str(move.id)) != null:
		move.id = "%s_%d" % [base_id, suffix]
		suffix += 1
	skills.append(move)
	selected_move = skills.size() - 1
	move_name.clear()
	gymnast.set_skill(move, false)
	_refresh_moves()
	_refresh_keyframes()
	status.text = "NEW MOVE CREATED — EDIT AND SAVE IT"

func _delete_move() -> void:
	if skills.size() <= 1:
		status.text = "KEEP AT LEAST ONE MOVE"
		return
	skills.remove_at(selected_move)
	selected_move = clampi(selected_move, 0, skills.size() - 1)
	gymnast.set_skill(skills[selected_move], false)
	selected_keyframe = -1
	_refresh_moves()
	_refresh_keyframes()
	status.text = "MOVE REMOVED FROM THIS EDITING SESSION"

func _save_move() -> void:
	var path := "res://skills/%s.stick.json" % str(gymnast.skill.id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status.text = "COULD NOT SAVE MOVE TO THE SKILLS FOLDER"
		return
	file.store_string(AuthoredSkills.skill_to_json(gymnast.skill))
	status.text = "SAVED %s TO SKILLS/%s.STICK.JSON" % [gymnast.skill.name.to_upper(), str(gymnast.skill.id).to_upper()]

func _import_move(path: String) -> void:
	var move := AuthoredSkills.load_skill(path)
	if move.is_empty():
		status.text = "COULD NOT IMPORT MOVE"
		return
	var base_id: String = move.id
	var suffix := 2
	while _find_skill(str(move.id)) != null:
		move.id = "%s_%d" % [base_id, suffix]
		suffix += 1
	skills.append(move)
	selected_move = skills.size() - 1
	gymnast.set_skill(move, false)
	_refresh_moves()
	_refresh_keyframes()
	status.text = "IMPORTED %s" % move.name.to_upper()

func _find_skill(id: String):
	for move in skills:
		if move.id == id:
			return move
	return null

func _unhandled_input(event: InputEvent) -> void:
	if edit_mode:
		return
	if event.is_action_pressed("move_tap"):
		var tap = _find_skill("tap_giant")
		if tap != null:
			status.text = gymnast.queue_skill(tap).to_upper()
	elif event.is_action_pressed("move_normal"):
		var normal = _find_skill("normal_giant")
		if normal != null:
			status.text = gymnast.queue_skill(normal).to_upper()
	elif event.is_action_pressed("move_dismount"):
		_queue_dismount()
	elif event.is_action_pressed("release_catch"):
		gymnast.playing = not gymnast.playing
	elif event.is_action_pressed("restart"):
		var normal = _find_skill("normal_giant")
		gymnast.set_skill(normal if normal != null else skills[0], true)

func _queue_dismount() -> void:
	if edit_mode:
		return
	var dismount = _find_skill("layout_back")
	if dismount != null:
		status.text = gymnast.queue_skill(dismount).to_upper()

func _ensure_move_inputs() -> void:
	_add_key_action("move_normal", KEY_G)
	_add_key_action("move_tap", KEY_T)
	_add_key_action("move_dismount", KEY_D)

func _add_key_action(action: StringName, key: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == key:
			return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action, key_event)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1000, 760), Color("#0e1a2b"))
