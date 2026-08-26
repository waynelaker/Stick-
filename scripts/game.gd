extends Node2D

const SkillCardScript = preload("res://scripts/skill_card.gd")
const RoutineDropZoneScript = preload("res://scripts/routine_drop_zone.gd")

var gymnast: StickGymnast
var skills: Array[Dictionary] = []
var selected_move := 0
var selected_keyframe := -1
var edit_mode := false
var current_mode := "game"
var updating_ui := false
var scoring: StickScoring = StickScoring.new()
var displayed_d_score: float = 0.0

var status: Label
var play_panel: Control
var editor_panel: Control
var transition_editor_panel: Control
var routine_panel: Control
var play_search: LineEdit
var play_code: LineEdit
var play_class_filter: OptionButton
var play_move_list: ItemList
var play_move_indices: Array[int] = []
var routine_search: LineEdit
var routine_code: LineEdit
var routine_class_filter: OptionButton
var routine_move_list: ItemList
var routine_sequence_label: Label
var routine_move_indices: Array[int] = []
var score_panel: Control
var score_total_label: Label
var score_current_label: Label
var score_groups_label: Label
var score_group_legend_label: Label
var score_element_labels: Array[Label] = []
var move_select: OptionButton
var move_name: LineEdit
var timeline: HSlider
var keyframe_markers: Control
var time_label: Label
var keyframe_select: OptionButton
var preview_button: Button
var duration_input: SpinBox
var loop_input: CheckBox
var move_class_input: OptionButton
var ghosts_input: CheckBox
var undo_button: Button
var redo_button: Button
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var dragging_keyframe_time := -1
var keyframe_time_drag_recorded := false
var routine: Array[Dictionary] = []
var playback_routine: Array[Dictionary] = []
var routine_playing := false
var routine_position := 0
var observed_transition_serial := 0
var browser_transition_serial := 0
var transition_inputs: Dictionary = {}
var pose_depth_inputs: Dictionary = {}
var execution_keyframe_button: Button
var game_panel: Control
var compose_panel: Control
var game_search: LineEdit
var game_class_filter: OptionButton
var skill_grid: GridContainer
var routine_cards: HBoxContainer
var compose_d_label: Label
var compose_details: Label
var perform_controls: Control
var timing_button: Button
var performance_score_label: Label
var performance_feedback_label: Label
var recovery_controls: Control
var game_phase := "compose"
var execution_score := 10.0
var stick_bonus := 0.0
var execution_attempted := false
var execution_deductions: Array[String] = []
var release_failed := false
var failed_routine_index := -1
var performance_d_score := 0.0
var selected_compose_skill_id := ""
var selected_compose_source := ""
var selected_compose_routine_index := -1
var ui_layer: CanvasLayer
var routine_library_panel: Control
var routine_library_list: VBoxContainer
var routine_name_input: LineEdit
var saved_routines: Array[Dictionary] = []
var editing_saved_routine_index := -1
var hints_input: CheckBox
var repeat_routine_button: Button
var queued_move_popup: Label
var performance_elapsed := 0.0
var performance_stage := "idle"
var performance_next_index := 0
var performance_connector: Dictionary = {}
var performance_complex: Dictionary = {}
var performance_transition_serial := 0
var performance_resume_index := 1
const ROUTINE_SAVE_PATH := "user://stick_routines.json"
const PERFORMANCE_LIMIT := 60.0
const HISTORY_LIMIT := 100
const SKILL_SHORTCUT_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
const SKILL_SHORTCUT_LABELS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

func _ready() -> void:
	queue_redraw()
	_ensure_move_inputs()
	skills = AuthoredSkills.builtin_skills()
	_ensure_skill_shortcuts()
	gymnast = StickGymnast.new()
	add_child(gymnast)
	gymnast.ghost_keyframe_clicked.connect(_select_keyframe)
	gymnast.pose_edit_started.connect(_record_change)
	gymnast.skill_completed.connect(_on_skill_completed)
	gymnast.set_idle_hang()
	_build_interface()
	_refresh_moves()
	_refresh_keyframes()
	_set_mode("game")

func _process(delta: float) -> void:
	if score_panel != null and score_panel.visible:
		displayed_d_score = move_toward(displayed_d_score, scoring.d_score(), delta * 2.0)
		score_total_label.text = "D  %0.2f" % displayed_d_score
		score_current_label.text = "PERFORMING  %s" % str(gymnast.skill.name).to_upper() if gymnast.playing else "READY — COMPLETE AN ELEMENT TO SCORE"
	if edit_mode and gymnast.playing:
		updating_ui = true
		timeline.value = gymnast.skill_time / float(gymnast.skill.duration) * 1000.0
		time_label.text = "%0.2f / %0.2fs" % [gymnast.skill_time, gymnast.skill.duration]
		updating_ui = false
		if not gymnast.playing:
			preview_button.text = "Preview"
	if routine_playing:
		if gymnast.transition_serial != observed_transition_serial:
			observed_transition_serial = gymnast.transition_serial
			routine_position += 1
			execution_attempted = false
			release_failed = false
			gymnast.clear_execution_preview()
			if routine_position >= playback_routine.size():
				routine_playing = false
				status.text = "ROUTINE COMPLETE — CONTINUING LAST SWING"
				_refresh_routine_display()
			elif routine_position < playback_routine.size():
				_queue_next_routine_move()
		if routine_playing and routine_position >= playback_routine.size() - 1 and not gymnast.playing:
			routine_playing = false
			status.text = "ROUTINE COMPLETE"
	if gymnast.transition_serial != browser_transition_serial:
		browser_transition_serial = gymnast.transition_serial
		_refresh_move_browsers()
	if current_mode == "game" and game_phase == "perform":
		if performance_stage != "awaiting_start" and performance_stage != "finished":
			performance_elapsed += delta
			if performance_elapsed >= PERFORMANCE_LIMIT:
				_time_up()
				return
		if performance_stage == "queued_complex" and gymnast.transition_serial != performance_transition_serial:
			performance_transition_serial = gymnast.transition_serial
			performance_stage = "complex_execution"
			execution_attempted = false
			_clear_queued_move_popup()
			performance_feedback_label.text = "%s STARTED — TIME THE EXECUTION" % str(performance_complex.get("name", "Move")).to_upper()
		if performance_stage == "complex_execution" and gymnast.playing and not execution_attempted:
			_update_execution_prompt()
		if performance_stage == "dismount_landing" and gymnast.playing and not execution_attempted:
			_update_landing_prompt()
		_update_performance_score()

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	ui_layer = layer
	add_child(layer)
	var mode_menu := MenuButton.new()
	mode_menu.position = Vector2(1012, 12)
	mode_menu.size = Vector2(256, 38)
	mode_menu.text = "☰  Menu"
	mode_menu.get_popup().add_item("Game", 0)
	mode_menu.get_popup().add_item("Content creation", 1)
	mode_menu.get_popup().id_pressed.connect(_on_mode_menu_selected)
	layer.add_child(mode_menu)
	status = Label.new()
	status.position = Vector2(1012, 58)
	status.size = Vector2(256, 44)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "STATIC HANG — CHOOSE A MOVE OR BUILD A ROUTINE BELOW"
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("#b5c4d8"))
	layer.add_child(status)
	_build_score_panel(layer)

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
	move_select.size = Vector2(140, 34)
	move_select.item_selected.connect(_on_move_selected)
	editor_panel.add_child(move_select)
	move_name = LineEdit.new()
	move_name.position = Vector2(166, 10)
	move_name.size = Vector2(120, 34)
	move_name.placeholder_text = "New move name"
	editor_panel.add_child(move_name)
	var add_move := Button.new()
	add_move.position = Vector2(294, 10)
	add_move.size = Vector2(60, 34)
	add_move.text = "New"
	add_move.pressed.connect(_add_move)
	editor_panel.add_child(add_move)
	var delete_move := Button.new()
	var rename_move := Button.new()
	rename_move.position = Vector2(362, 10)
	rename_move.size = Vector2(68, 34)
	rename_move.text = "Rename"
	rename_move.pressed.connect(_rename_move)
	editor_panel.add_child(rename_move)
	var copy_move := Button.new()
	copy_move.position = Vector2(438, 10)
	copy_move.size = Vector2(60, 34)
	copy_move.text = "Copy"
	copy_move.pressed.connect(_copy_move)
	editor_panel.add_child(copy_move)
	delete_move.position = Vector2(506, 10)
	delete_move.size = Vector2(65, 34)
	delete_move.text = "Delete"
	delete_move.pressed.connect(_delete_move)
	editor_panel.add_child(delete_move)
	preview_button = Button.new()
	preview_button.position = Vector2(579, 10)
	preview_button.size = Vector2(68, 34)
	preview_button.text = "Preview"
	preview_button.pressed.connect(_toggle_preview)
	editor_panel.add_child(preview_button)
	ghosts_input = CheckBox.new()
	ghosts_input.position = Vector2(655, 10)
	ghosts_input.size = Vector2(68, 34)
	ghosts_input.text = "Ghosts"
	ghosts_input.button_pressed = true
	ghosts_input.toggled.connect(_on_ghosts_toggled)
	editor_panel.add_child(ghosts_input)
	var save_button := Button.new()
	save_button.position = Vector2(731, 10)
	save_button.size = Vector2(251, 34)
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

	keyframe_select = OptionButton.new()
	keyframe_select.position = Vector2(18, 96)
	keyframe_select.size = Vector2(180, 34)
	keyframe_select.item_selected.connect(_on_keyframe_selected)
	editor_panel.add_child(keyframe_select)
	_add_editor_button(editor_panel, "Add keyframe", Vector2(208, 96), _add_keyframe, 105)
	_add_editor_button(editor_panel, "Delete keyframe", Vector2(323, 96), _delete_keyframe, 125)
	_add_editor_button(editor_panel, "Copy previous", Vector2(458, 96), _copy_previous_keyframe, 120)
	move_class_input = OptionButton.new()
	move_class_input.position = Vector2(588, 96)
	move_class_input.size = Vector2(130, 34)
	move_class_input.add_item("Mount")
	move_class_input.add_item("Swing")
	move_class_input.add_item("Release")
	move_class_input.add_item("Dismount")
	move_class_input.tooltip_text = "Move class"
	move_class_input.item_selected.connect(_on_move_class_changed)
	editor_panel.add_child(move_class_input)
	duration_input = SpinBox.new()
	duration_input.position = Vector2(728, 96)
	duration_input.size = Vector2(110, 34)
	duration_input.min_value = 0.1
	duration_input.max_value = 30.0
	duration_input.step = 0.05
	duration_input.prefix = "Move "
	duration_input.suffix = " s"
	duration_input.tooltip_text = "Whole-move duration. Changing this proportionally retimes every keyframe."
	duration_input.value_changed.connect(_on_duration_changed)
	editor_panel.add_child(duration_input)
	loop_input = CheckBox.new()
	loop_input.position = Vector2(848, 96)
	loop_input.size = Vector2(134, 34)
	loop_input.text = "Loop move"
	loop_input.toggled.connect(_on_loop_changed)
	editor_panel.add_child(loop_input)

	editor_panel.visible = false
	_build_play_panel(layer)
	_build_routine_panel(layer)
	_build_game_interface(layer)
	_build_routine_library(layer)
	_build_transition_editor_panel(layer)
	_update_history_buttons()

func _build_score_panel(layer: CanvasLayer) -> void:
	score_panel = Control.new()
	score_panel.position = Vector2(0, 560)
	score_panel.size = Vector2(1000, 200)
	layer.add_child(score_panel)
	var background: ColorRect = ColorRect.new()
	background.size = score_panel.size
	background.color = Color("#12243d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_panel.add_child(background)
	score_total_label = Label.new()
	score_total_label.position = Vector2(18, 10)
	score_total_label.size = Vector2(150, 38)
	score_total_label.text = "D  0.00"
	score_total_label.add_theme_font_size_override("font_size", 28)
	score_total_label.add_theme_color_override("font_color", Color("#ffdc8a"))
	score_panel.add_child(score_total_label)
	score_current_label = Label.new()
	score_current_label.position = Vector2(180, 12)
	score_current_label.size = Vector2(430, 30)
	score_current_label.add_theme_font_size_override("font_size", 14)
	score_current_label.add_theme_color_override("font_color", Color("#72ddf7"))
	score_panel.add_child(score_current_label)
	score_groups_label = Label.new()
	score_groups_label.position = Vector2(620, 12)
	score_groups_label.size = Vector2(362, 30)
	score_groups_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_groups_label.add_theme_font_size_override("font_size", 14)
	score_groups_label.add_theme_color_override("font_color", Color("#72f1b8"))
	score_panel.add_child(score_groups_label)
	score_group_legend_label = Label.new()
	score_group_legend_label.position = Vector2(180, 36)
	score_group_legend_label.size = Vector2(802, 20)
	score_group_legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_group_legend_label.text = "I  LONG HANG / TURNS   ·   II  FLIGHT   ·   III  IN-BAR / ADLER   ·   IV  DISMOUNTS"
	score_group_legend_label.add_theme_font_size_override("font_size", 12)
	score_group_legend_label.add_theme_color_override("font_color", Color("#b5c4d8"))
	score_panel.add_child(score_group_legend_label)
	for index in range(StickScoring.MAX_COUNTING_ELEMENTS):
		var label: Label = Label.new()
		var column: int = floori(float(index) / 5.0)
		var row: int = index % 5
		label.position = Vector2(18 + column * 490, 58 + row * 26)
		label.size = Vector2(472, 25)
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color("#fff5d6"))
		score_panel.add_child(label)
		score_element_labels.append(label)
	_refresh_score_panel()

func _on_skill_completed(completed_skill: Dictionary) -> void:
	if edit_mode:
		return
	if current_mode == "game" and game_phase == "perform":
		if performance_stage == "mount":
			gymnast.suppress_next_automatic_follow()
			gymnast.queued_skill = {}
			call_deferred("_advance_to_next_complex")
			return
		if performance_stage in ["complex_execution", "complex_active", "dismount_landing"]:
			gymnast.suppress_next_automatic_follow()
			_finalize_execution(completed_skill)
			if release_failed:
				gymnast.queued_skill = {}
				failed_routine_index = maxi(0, performance_next_index - 1)
				call_deferred("_begin_release_fall")
				return
			if str(completed_skill.get("move_class", "")) == "dismount":
				performance_stage = "finished"
				game_phase = "results"
				timing_button.text = "LANDED"
				performance_feedback_label.text = "ROUTINE COMPLETE"
				status.text = "ROUTINE COMPLETE"
				repeat_routine_button.visible = true
			else:
				call_deferred("_advance_to_next_complex")
			return
		# Connecting giants are deliberately automatic and deduction-free.
		return
	if scoring.record_completed_skill(completed_skill):
		_refresh_score_panel()

func _reset_live_score() -> void:
	scoring.reset()
	displayed_d_score = 0.0
	_refresh_score_panel()

func _refresh_score_panel() -> void:
	if score_panel == null:
		return
	for index in range(score_element_labels.size()):
		var label: Label = score_element_labels[index]
		if index < scoring.counting_elements.size():
			var element: Dictionary = scoring.counting_elements[index]
			var difficulty: float = float(element.difficulty)
			var group: String = str(element.group)
			label.text = "%02d  %s %0.1f   %s %-18s  %s" % [index + 1,
				StickScoring.difficulty_letter(difficulty), difficulty, group,
				StickScoring.group_name(group), str(element.name).to_upper()]
		else:
			label.text = "%02d   —" % (index + 1)
	var groups: Array[String] = scoring.represented_groups()
	if groups.is_empty():
		score_groups_label.text = "GROUP BONUSES  —"
	else:
		score_groups_label.text = "GROUPS %s   +%0.1f" % [", ".join(groups), scoring.group_bonus_total()]
	score_total_label.text = "D  %0.2f" % displayed_d_score

func _panel_background(panel: Control) -> void:
	var background := ColorRect.new()
	background.size = panel.size
	background.color = Color("#12243d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(background)

func _make_class_filter(parent: Control, position: Vector2) -> OptionButton:
	var filter := OptionButton.new()
	filter.position = position
	filter.size = Vector2(130, 34)
	for label in ["All classes", "Mount", "Swing", "Release", "Dismount"]:
		filter.add_item(label)
	parent.add_child(filter)
	return filter

func _build_play_panel(layer: CanvasLayer) -> void:
	play_panel = Control.new()
	play_panel.position = Vector2(1000, 110)
	play_panel.size = Vector2(280, 650)
	layer.add_child(play_panel)
	_panel_background(play_panel)
	play_search = LineEdit.new()
	play_search.position = Vector2(12, 10)
	play_search.size = Vector2(166, 34)
	play_search.placeholder_text = "Search 15+ moves…"
	play_search.text_changed.connect(func(_text): _refresh_move_browsers())
	play_panel.add_child(play_search)
	play_code = LineEdit.new()
	play_code.position = Vector2(188, 10)
	play_code.size = Vector2(80, 34)
	play_code.placeholder_text = "Code"
	play_code.text_submitted.connect(_perform_move_code)
	play_panel.add_child(play_code)
	play_class_filter = _make_class_filter(play_panel, Vector2(12, 54))
	play_class_filter.size.x = 256
	play_class_filter.item_selected.connect(func(_index): _refresh_move_browsers())
	play_move_list = ItemList.new()
	play_move_list.position = Vector2(12, 98)
	play_move_list.size = Vector2(256, 540)
	play_move_list.select_mode = ItemList.SELECT_SINGLE
	play_move_list.allow_reselect = true
	play_move_list.add_theme_font_size_override("font_size", 16)
	play_move_list.item_selected.connect(_perform_play_list_item)
	play_panel.add_child(play_move_list)

func _build_routine_panel(layer: CanvasLayer) -> void:
	routine_panel = Control.new()
	routine_panel.position = Vector2(1000, 110)
	routine_panel.size = Vector2(280, 650)
	layer.add_child(routine_panel)
	_panel_background(routine_panel)
	routine_search = LineEdit.new()
	routine_search.position = Vector2(12, 10)
	routine_search.size = Vector2(166, 34)
	routine_search.placeholder_text = "Search moves…"
	routine_search.text_changed.connect(func(_text): _refresh_move_browsers())
	routine_panel.add_child(routine_search)
	routine_code = LineEdit.new()
	routine_code.position = Vector2(188, 10)
	routine_code.size = Vector2(80, 34)
	routine_code.placeholder_text = "Code"
	routine_code.text_submitted.connect(_add_routine_move_code)
	routine_panel.add_child(routine_code)
	routine_class_filter = _make_class_filter(routine_panel, Vector2(12, 54))
	routine_class_filter.size.x = 256
	routine_class_filter.item_selected.connect(func(_index): _refresh_move_browsers())
	routine_move_list = ItemList.new()
	routine_move_list.position = Vector2(12, 98)
	routine_move_list.size = Vector2(256, 270)
	routine_move_list.select_mode = ItemList.SELECT_SINGLE
	routine_move_list.allow_reselect = true
	routine_move_list.add_theme_font_size_override("font_size", 15)
	routine_move_list.item_selected.connect(func(_index): _add_to_routine())
	routine_panel.add_child(routine_move_list)
	_add_editor_button(routine_panel, "Remove last", Vector2(12, 378), _remove_routine_last, 122)
	_add_editor_button(routine_panel, "Clear", Vector2(146, 378), _clear_routine, 122)
	_add_editor_button(routine_panel, "Play routine", Vector2(12, 422), _play_routine, 256)
	routine_sequence_label = Label.new()
	routine_sequence_label.position = Vector2(12, 470)
	routine_sequence_label.size = Vector2(256, 168)
	routine_sequence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	routine_sequence_label.add_theme_font_size_override("font_size", 16)
	routine_sequence_label.add_theme_color_override("font_color", Color("#ffdc8a"))
	routine_panel.add_child(routine_sequence_label)
	_refresh_routine_display()

func _build_game_interface(layer: CanvasLayer) -> void:
	game_panel = Control.new()
	game_panel.position = Vector2(0, 0)
	game_panel.size = Vector2(1000, 550)
	layer.add_child(game_panel)
	_panel_background(game_panel)
	var heading := Label.new()
	heading.position = Vector2(12, 8)
	heading.size = Vector2(170, 30)
	heading.text = "COMPOSE ROUTINE"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color("#ffdc8a"))
	game_panel.add_child(heading)
	var back_to_routines := Button.new()
	back_to_routines.position = Vector2(190, 10)
	back_to_routines.size = Vector2(128, 38)
	back_to_routines.text = "← Routines"
	back_to_routines.pressed.connect(_show_routine_library)
	game_panel.add_child(back_to_routines)
	routine_name_input = LineEdit.new()
	routine_name_input.position = Vector2(12, 496)
	routine_name_input.size = Vector2(280, 40)
	routine_name_input.placeholder_text = "Routine name"
	game_panel.add_child(routine_name_input)
	game_search = LineEdit.new()
	game_search.position = Vector2(330, 10)
	game_search.size = Vector2(390, 38)
	game_search.placeholder_text = "Search moves…"
	game_search.text_changed.connect(func(_text): _refresh_skill_grid())
	game_panel.add_child(game_search)
	game_class_filter = _make_class_filter(game_panel, Vector2(730, 10))
	game_class_filter.size = Vector2(258, 38)
	game_class_filter.item_selected.connect(func(_index): _refresh_skill_grid())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 62)
	scroll.size = Vector2(976, 420)
	game_panel.add_child(scroll)
	skill_grid = GridContainer.new()
	skill_grid.columns = 5
	skill_grid.add_theme_constant_override("h_separation", 18)
	skill_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(skill_grid)
	compose_d_label = Label.new()
	compose_d_label.position = Vector2(310, 496)
	compose_d_label.size = Vector2(132, 42)
	compose_d_label.text = "D  0.00"
	compose_d_label.add_theme_font_size_override("font_size", 25)
	compose_d_label.add_theme_color_override("font_color", Color("#ffdc8a"))
	game_panel.add_child(compose_d_label)
	var details_button := Button.new()
	details_button.position = Vector2(450, 500)
	details_button.size = Vector2(118, 34)
	details_button.text = "D details"
	details_button.pressed.connect(_toggle_compose_details)
	game_panel.add_child(details_button)
	var perform_button := Button.new()
	perform_button.position = Vector2(730, 492)
	perform_button.size = Vector2(258, 48)
	perform_button.text = "PERFORM ROUTINE"
	perform_button.pressed.connect(_prepare_performance)
	game_panel.add_child(perform_button)
	var save_routine_button := Button.new()
	save_routine_button.position = Vector2(574, 500)
	save_routine_button.size = Vector2(142, 40)
	save_routine_button.text = "Save routine"
	save_routine_button.pressed.connect(_save_current_routine)
	game_panel.add_child(save_routine_button)

	compose_panel = Control.new()
	compose_panel.position = Vector2(0, 560)
	compose_panel.size = Vector2(1000, 200)
	layer.add_child(compose_panel)
	_panel_background(compose_panel)
	var instruction := Label.new()
	instruction.position = Vector2(18, 8)
	instruction.size = Vector2(964, 25)
	instruction.text = "DRAG MOVES INTO A VALID SLOT  ·  DRAG ROUTINE CARDS TO REORDER  ·  × TO DELETE"
	instruction.add_theme_color_override("font_color", Color("#b5c4d8"))
	compose_panel.add_child(instruction)
	var routine_scroll := ScrollContainer.new()
	routine_scroll.position = Vector2(12, 38)
	routine_scroll.size = Vector2(976, 120)
	routine_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	routine_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	compose_panel.add_child(routine_scroll)
	routine_cards = HBoxContainer.new()
	routine_cards.add_theme_constant_override("separation", 2)
	routine_scroll.add_child(routine_cards)
	compose_details = Label.new()
	compose_details.position = Vector2(18, 163)
	compose_details.size = Vector2(964, 28)
	compose_details.visible = false
	compose_details.add_theme_color_override("font_color", Color("#72f1b8"))
	compose_panel.add_child(compose_details)

	perform_controls = Control.new()
	perform_controls.position = Vector2(1000, 110)
	perform_controls.size = Vector2(280, 650)
	layer.add_child(perform_controls)
	_panel_background(perform_controls)
	performance_score_label = Label.new()
	performance_score_label.position = Vector2(12, 20)
	performance_score_label.size = Vector2(256, 110)
	performance_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	performance_score_label.add_theme_font_size_override("font_size", 24)
	performance_score_label.add_theme_color_override("font_color", Color("#ffdc8a"))
	perform_controls.add_child(performance_score_label)
	performance_feedback_label = Label.new()
	performance_feedback_label.position = Vector2(12, 140)
	performance_feedback_label.size = Vector2(256, 100)
	performance_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	performance_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	performance_feedback_label.add_theme_color_override("font_color", Color("#72ddf7"))
	perform_controls.add_child(performance_feedback_label)
	hints_input = CheckBox.new()
	hints_input.position = Vector2(12, 222)
	hints_input.size = Vector2(256, 32)
	hints_input.text = "Show timing pose hints"
	hints_input.button_pressed = false
	perform_controls.add_child(hints_input)
	timing_button = Button.new()
	timing_button.position = Vector2(12, 260)
	timing_button.size = Vector2(256, 120)
	timing_button.text = "HIT!\n[SPACE]"
	timing_button.add_theme_font_size_override("font_size", 30)
	timing_button.pressed.connect(_attempt_execution)
	perform_controls.add_child(timing_button)
	var abandon := Button.new()
	abandon.position = Vector2(12, 590)
	abandon.size = Vector2(256, 42)
	abandon.text = "Back to routines"
	abandon.pressed.connect(_return_to_compose)
	perform_controls.add_child(abandon)
	repeat_routine_button = Button.new()
	repeat_routine_button.position = Vector2(12, 530)
	repeat_routine_button.size = Vector2(256, 50)
	repeat_routine_button.text = "REPEAT ROUTINE"
	repeat_routine_button.add_theme_font_size_override("font_size", 18)
	repeat_routine_button.pressed.connect(_prepare_performance)
	repeat_routine_button.visible = false
	perform_controls.add_child(repeat_routine_button)
	recovery_controls = Control.new()
	recovery_controls.position = Vector2(12, 400)
	recovery_controls.size = Vector2(256, 174)
	perform_controls.add_child(recovery_controls)
	_add_editor_button(recovery_controls, "Remount + retry", Vector2(0, 0), _retry_failed_move, 256)
	_add_editor_button(recovery_controls, "Remount + next", Vector2(0, 46), _resume_after_failed_move, 256)
	_add_editor_button(recovery_controls, "Restart routine", Vector2(0, 92), _prepare_performance, 256)
	recovery_controls.visible = false
	perform_controls.visible = false
	_refresh_skill_grid()
	_refresh_composed_routine()

func _build_routine_library(layer: CanvasLayer) -> void:
	routine_library_panel = Control.new()
	routine_library_panel.position = Vector2(0, 0)
	routine_library_panel.size = Vector2(1000, 760)
	layer.add_child(routine_library_panel)
	_panel_background(routine_library_panel)
	var title := Label.new()
	title.position = Vector2(42, 28)
	title.size = Vector2(700, 54)
	title.text = "CHOOSE A ROUTINE"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#ffdc8a"))
	routine_library_panel.add_child(title)
	var subtitle := Label.new()
	subtitle.position = Vector2(44, 78)
	subtitle.size = Vector2(700, 30)
	subtitle.text = "Perform immediately, or create your own routine."
	subtitle.add_theme_color_override("font_color", Color("#b5c4d8"))
	routine_library_panel.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 126)
	scroll.size = Vector2(920, 520)
	routine_library_panel.add_child(scroll)
	routine_library_list = VBoxContainer.new()
	routine_library_list.custom_minimum_size.x = 900
	routine_library_list.add_theme_constant_override("separation", 12)
	scroll.add_child(routine_library_list)
	var add_button := Button.new()
	add_button.position = Vector2(40, 674)
	add_button.size = Vector2(920, 56)
	add_button.text = "+  ADD A ROUTINE"
	add_button.add_theme_font_size_override("font_size", 20)
	add_button.pressed.connect(_begin_new_routine)
	routine_library_panel.add_child(add_button)
	_load_saved_routines()
	_refresh_routine_library()

func _default_routines() -> Array[Dictionary]:
	return [
		{"name":"First Flight", "skills":["start_swing", "normal_giant", "kovacs", "normal_giant", "layout_back"]},
		{"name":"Turn and Fly", "skills":["start_swing", "normal_giant", "blind_change", "forward_giant", "pirouette", "normal_giant", "layout_back"]},
		{"name":"Tkatchev Challenge", "skills":["start_swing", "tap_giant", "tkatchev", "normal_giant", "layout_back"]},
	]

func _refresh_routine_library() -> void:
	if routine_library_list == null:
		return
	for child in routine_library_list.get_children():
		child.queue_free()
	for definition in _default_routines():
		_add_routine_library_row(definition, -1)
	for saved_index in range(saved_routines.size()):
		_add_routine_library_row(saved_routines[saved_index], saved_index)

func _add_routine_library_row(definition: Dictionary, saved_index: int) -> void:
	if routine_library_list == null:
		return
	var ids: Array = definition.get("skills", [])
	var valid_ids: Array[String] = []
	for id in ids:
		if _find_skill(str(id)) != null:
			valid_ids.append(str(id))
	if valid_ids.is_empty():
		return
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(900, 92)
	row.add_theme_constant_override("separation", 8)
	var perform := Button.new()
	perform.custom_minimum_size = Vector2(900 if saved_index < 0 else 650, 92)
	perform.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perform.text = "%s%s\n%s" % [str(definition.get("name", "Routine")), "" if saved_index < 0 else "  ·  CUSTOM", _routine_summary(valid_ids)]
	perform.alignment = HORIZONTAL_ALIGNMENT_LEFT
	perform.add_theme_font_size_override("font_size", 18)
	perform.pressed.connect(_choose_library_routine.bind(str(definition.get("name", "Routine")), valid_ids))
	row.add_child(perform)
	if saved_index >= 0:
		var edit := Button.new()
		edit.custom_minimum_size = Vector2(112, 92)
		edit.text = "EDIT"
		edit.pressed.connect(_edit_saved_routine.bind(saved_index))
		row.add_child(edit)
		var delete := Button.new()
		delete.custom_minimum_size = Vector2(112, 92)
		delete.text = "DELETE"
		delete.pressed.connect(_delete_saved_routine.bind(saved_index))
		row.add_child(delete)
	routine_library_list.add_child(row)

func _routine_summary(ids: Array[String]) -> String:
	var names: Array[String] = []
	for id in ids:
		var move = _find_skill(id)
		if move != null:
			names.append(str(move.get("name", id)))
	return "  →  ".join(names)

func _choose_library_routine(name: String, ids: Array[String]) -> void:
	routine.clear()
	for id in ids:
		var move = _find_skill(id)
		if move != null:
			routine.append(move)
	routine_name_input.text = name
	_refresh_composed_routine()
	_prepare_performance()

func _begin_new_routine() -> void:
	routine.clear()
	editing_saved_routine_index = -1
	routine_name_input.text = ""
	game_phase = "compose"
	routine_library_panel.visible = false
	game_panel.visible = true
	compose_panel.visible = true
	perform_controls.visible = false
	gymnast.visible = false
	_refresh_composed_routine()
	status.text = "COMPOSE A NEW ROUTINE"

func _edit_saved_routine(saved_index: int) -> void:
	if saved_index < 0 or saved_index >= saved_routines.size():
		return
	var definition: Dictionary = saved_routines[saved_index]
	editing_saved_routine_index = saved_index
	routine.clear()
	for id in definition.get("skills", []):
		var move = _find_skill(str(id))
		if move != null:
			routine.append(move)
	routine_name_input.text = str(definition.get("name", "Routine"))
	game_phase = "compose"
	routine_library_panel.visible = false
	game_panel.visible = true
	compose_panel.visible = true
	perform_controls.visible = false
	gymnast.visible = false
	_refresh_composed_routine()
	status.text = "EDITING CUSTOM ROUTINE"

func _delete_saved_routine(saved_index: int) -> void:
	if saved_index < 0 or saved_index >= saved_routines.size():
		return
	var deleted_name: String = str(saved_routines[saved_index].get("name", "Routine"))
	saved_routines.remove_at(saved_index)
	editing_saved_routine_index = -1
	if _write_saved_routines():
		status.text = "DELETED CUSTOM ROUTINE: %s" % deleted_name.to_upper()
	_refresh_routine_library()

func _show_routine_library() -> void:
	routine_playing = false
	_clear_queued_move_popup()
	game_phase = "home"
	gymnast.clear_execution_preview()
	gymnast.set_idle_hang()
	gymnast.visible = false
	game_panel.visible = false
	compose_panel.visible = false
	perform_controls.visible = false
	routine_library_panel.visible = true
	_refresh_routine_library()
	status.text = "CHOOSE A ROUTINE"

func _save_current_routine() -> void:
	if routine.is_empty():
		status.text = "ADD MOVES BEFORE SAVING"
		return
	var routine_name: String = routine_name_input.text.strip_edges()
	if routine_name.is_empty():
		status.text = "GIVE THE ROUTINE A NAME"
		return
	var ids: Array[String] = []
	for move in routine:
		ids.append(str(move.get("id", "")))
	var replaced := false
	if editing_saved_routine_index >= 0 and editing_saved_routine_index < saved_routines.size():
		saved_routines[editing_saved_routine_index] = {"name":routine_name, "skills":ids}
		replaced = true
	else:
		for index in range(saved_routines.size()):
			if str(saved_routines[index].get("name", "")) == routine_name:
				saved_routines[index] = {"name":routine_name, "skills":ids}
				editing_saved_routine_index = index
				replaced = true
				break
	if not replaced:
		saved_routines.append({"name":routine_name, "skills":ids})
		editing_saved_routine_index = saved_routines.size() - 1
	if not _write_saved_routines():
		status.text = "COULD NOT SAVE ROUTINE"
		return
	status.text = "SAVED TO %s" % ROUTINE_SAVE_PATH

func _write_saved_routines() -> bool:
	var file := FileAccess.open(ROUTINE_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"routines":saved_routines}, "  "))
	return true

func _load_saved_routines() -> void:
	saved_routines.clear()
	if not FileAccess.file_exists(ROUTINE_SAVE_PATH):
		return
	var file := FileAccess.open(ROUTINE_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	for source in parsed.get("routines", []):
		if source is Dictionary:
			saved_routines.append(source)

func _build_transition_editor_panel(layer: CanvasLayer) -> void:
	transition_editor_panel = Control.new()
	transition_editor_panel.position = Vector2(1000, 110)
	transition_editor_panel.size = Vector2(280, 650)
	layer.add_child(transition_editor_panel)
	_panel_background(transition_editor_panel)
	_add_transition_heading("START / ENTRY", 16, Color("#72f1b8"))
	_add_transition_fields("entry", 58)
	_add_transition_heading("END / EXIT", 190, Color("#ff7b72"))
	_add_transition_fields("exit", 232)
	var note := Label.new()
	note.position = Vector2(14, 340)
	note.size = Vector2(252, 45)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Transition signatures filter which moves can follow."
	note.add_theme_color_override("font_color", Color("#b5c4d8"))
	transition_editor_panel.add_child(note)
	_add_transition_heading("KEYFRAME TURN / DEPTH", 388, Color("#72ddf7"))
	_add_pose_depth_input("body_yaw", "Turn", 428, 180.0)
	_add_pose_depth_input("arm_depth", "Arms out", 474, 90.0)
	_add_pose_depth_input("leg_depth", "Legs out", 520, 90.0)
	_add_pose_grip_input("left_grip", "Left grip", 566, 14)
	_add_pose_grip_input("right_grip", "Right grip", 566, 142)
	execution_keyframe_button = Button.new()
	execution_keyframe_button.position = Vector2(14, 610)
	execution_keyframe_button.size = Vector2(252, 34)
	execution_keyframe_button.pressed.connect(_set_execution_keyframe)
	transition_editor_panel.add_child(execution_keyframe_button)

func _add_transition_heading(text: String, y: float, color: Color) -> void:
	var label := Label.new()
	label.position = Vector2(14, y)
	label.size = Vector2(252, 30)
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	transition_editor_panel.add_child(label)

func _add_transition_fields(endpoint: String, y: float) -> void:
	var definitions := [
		["state", AuthoredSkills.TRANSITION_STATES, "Position / phase"],
		["grip", AuthoredSkills.GRIPS, "Grip"],
	]
	for row in range(definitions.size()):
		var definition: Array = definitions[row]
		var input := OptionButton.new()
		input.position = Vector2(14, y + row * 56)
		input.size = Vector2(252, 42)
		input.tooltip_text = str(definition[2])
		for value in definition[1]:
			input.add_item(str(value).replace("_", " ").capitalize())
		input.item_selected.connect(_on_transition_field_changed.bind(endpoint, str(definition[0]), input))
		transition_editor_panel.add_child(input)
		transition_inputs["%s_%s" % [endpoint, definition[0]]] = input

func _add_pose_depth_input(field: String, label: String, y: float, maximum: float) -> void:
	var input: SpinBox = SpinBox.new()
	input.position = Vector2(14, y)
	input.size = Vector2(252, 36)
	input.min_value = 0.0
	input.max_value = maximum
	input.step = 1.0
	input.prefix = "%s " % label
	input.suffix = "°"
	input.tooltip_text = "Optional 2.5D projection on the selected keyframe; true bone lengths do not change."
	input.value_changed.connect(_on_pose_depth_changed.bind(field, maximum))
	transition_editor_panel.add_child(input)
	pose_depth_inputs[field] = input

func _add_pose_grip_input(field: String, tooltip: String, y: float, x: float) -> void:
	var input: OptionButton = OptionButton.new()
	input.position = Vector2(x, y)
	input.size = Vector2(124, 38)
	input.tooltip_text = tooltip
	for grip in AuthoredSkills.GRIPS:
		if grip != "either":
			input.add_item(grip.replace("_", " ").capitalize())
	input.item_selected.connect(_on_pose_grip_changed.bind(field))
	transition_editor_panel.add_child(input)
	pose_depth_inputs[field] = input

func _add_editor_button(parent: Control, text: String, position: Vector2, callback: Callable, width := 112) -> void:
	var button := Button.new()
	button.position = position
	button.size = Vector2(width, 34)
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_to_routine() -> void:
	var index := _selected_list_skill_index(routine_move_list, routine_move_indices)
	if index < 0:
		return
	_add_skill_index_to_routine(index)

func _refresh_skill_grid() -> void:
	if skill_grid == null:
		return
	for child in skill_grid.get_children():
		child.queue_free()
	var query: String = game_search.text.strip_edges().to_lower() if game_search != null else ""
	var wanted_class := ""
	if game_class_filter != null and game_class_filter.selected > 0:
		wanted_class = game_class_filter.get_item_text(game_class_filter.selected).to_lower()
	for index in range(skills.size()):
		var move: Dictionary = skills[index]
		var move_class: String = str(move.get("move_class", "swing"))
		var name_text: String = str(move.get("name", "Move"))
		if move_class == "fall" or bool(move.get("hidden", false)):
			continue
		if not wanted_class.is_empty() and move_class != wanted_class:
			continue
		if not query.is_empty() and not name_text.to_lower().contains(query) and not move_class.contains(query):
			continue
		var card: Control = SkillCardScript.new()
		card.setup(move, index)
		card.set_selected(selected_compose_source == "library" and selected_compose_skill_id == str(move.get("id", "")))
		card.clicked.connect(_select_library_card)
		card.preview_finished.connect(_on_card_preview_finished)
		skill_grid.add_child(card)

func _select_library_card(skill_index: int) -> void:
	if skill_index < 0 or skill_index >= skills.size():
		return
	var clicked_id: String = str(skills[skill_index].get("id", ""))
	if selected_compose_source == "library" and selected_compose_skill_id == clicked_id:
		selected_compose_skill_id = ""
		selected_compose_source = ""
		status.text = "PREVIEW CLOSED"
	else:
		selected_compose_skill_id = clicked_id
		selected_compose_source = "library"
		status.text = "%s PREVIEW" % str(skills[skill_index].get("name", "Move")).to_upper()
	selected_compose_routine_index = -1
	_refresh_skill_grid()
	_refresh_composed_routine()

func _select_routine_card(_skill_index: int, routine_index: int) -> void:
	if routine_index < 0 or routine_index >= routine.size():
		return
	if selected_compose_source == "routine" and selected_compose_routine_index == routine_index:
		selected_compose_skill_id = ""
		selected_compose_source = ""
		selected_compose_routine_index = -1
		status.text = "PREVIEW CLOSED"
	else:
		selected_compose_skill_id = str(routine[routine_index].get("id", ""))
		selected_compose_source = "routine"
		selected_compose_routine_index = routine_index
		status.text = "%s ROUTINE PREVIEW" % str(routine[routine_index].get("name", "Move")).to_upper()
	_refresh_skill_grid()
	_refresh_composed_routine()

func _on_card_preview_finished(_skill_index: int, routine_index: int, from_routine: bool) -> void:
	if from_routine:
		if selected_compose_source != "routine" or selected_compose_routine_index != routine_index:
			return
	elif selected_compose_source != "library":
		return
	selected_compose_skill_id = ""
	selected_compose_source = ""
	selected_compose_routine_index = -1
	call_deferred("_refresh_skill_grid")
	call_deferred("_refresh_composed_routine")

func _refresh_composed_routine() -> void:
	if routine_cards == null:
		return
	for child in routine_cards.get_children():
		child.queue_free()
	for insertion_index in range(routine.size() + 1):
		var zone: Control = RoutineDropZoneScript.new()
		zone.setup(insertion_index, _can_drop_routine_skill)
		zone.skill_dropped.connect(_drop_routine_skill)
		routine_cards.add_child(zone)
		if insertion_index < routine.size():
			var move: Dictionary = routine[insertion_index]
			var card: Control = SkillCardScript.new()
			card.setup(move, _skill_index_by_id(str(move.get("id", ""))), true, insertion_index)
			card.set_selected(selected_compose_source == "routine" and selected_compose_routine_index == insertion_index)
			card.clicked.connect(_select_routine_card.bind(insertion_index))
			card.remove_clicked.connect(_remove_routine_index)
			card.preview_finished.connect(_on_card_preview_finished)
			routine_cards.add_child(card)
	var potential := StickScoring.new()
	for move in routine:
		potential.record_completed_skill(move)
	performance_d_score = potential.d_score()
	if compose_d_label != null:
		compose_d_label.text = "D  %0.2f" % performance_d_score
	if compose_details != null:
		var parts: Array[String] = []
		for element in potential.counting_elements:
			parts.append("%s %s %0.1f" % [str(element.name), StickScoring.difficulty_letter(float(element.difficulty)), float(element.difficulty)])
		compose_details.text = "  ·  ".join(parts) if not parts.is_empty() else "No scoring elements yet."
	_refresh_routine_display()

func _skill_index_by_id(id: String) -> int:
	for index in range(skills.size()):
		if str(skills[index].get("id", "")) == id:
			return index
	return -1

func _candidate_after_drop(payload: Dictionary, insertion_index: int) -> Array[Dictionary]:
	var candidate: Array[Dictionary] = []
	for move in routine:
		candidate.append(move)
	var source_index: int = int(payload.get("routine_index", -1))
	var target_index := insertion_index
	if bool(payload.get("from_routine", false)) and source_index >= 0 and source_index < candidate.size():
		candidate.remove_at(source_index)
		if source_index < target_index:
			target_index -= 1
	var library_index: int = int(payload.get("skill_index", -1))
	if library_index >= 0 and library_index < skills.size():
		candidate.insert(clampi(target_index, 0, candidate.size()), skills[library_index])
	return candidate

func _can_drop_routine_skill(payload: Dictionary, insertion_index: int) -> bool:
	return _routine_sequence_valid(_candidate_after_drop(payload, insertion_index))

func _drop_routine_skill(payload: Dictionary, insertion_index: int) -> void:
	var candidate := _candidate_after_drop(payload, insertion_index)
	if not _routine_sequence_valid(candidate):
		status.text = "INVALID TRANSITION"
		return
	routine = candidate
	selected_compose_source = ""
	selected_compose_routine_index = -1
	status.text = "ROUTINE UPDATED"
	_refresh_composed_routine()

func _routine_sequence_valid(sequence: Array[Dictionary]) -> bool:
	var signature: Dictionary = AuthoredSkills.make_signature("static_hang", "regular")
	var mount_count := 0
	var dismount_count := 0
	for index in range(sequence.size()):
		var move: Dictionary = sequence[index]
		var move_class: String = str(move.get("move_class", "swing"))
		if move_class == "mount":
			mount_count += 1
			if index != 0 or mount_count > 1:
				return false
		if move_class == "dismount":
			dismount_count += 1
			if index != sequence.size() - 1 or dismount_count > 1:
				return false
		if not AuthoredSkills.can_follow(signature, move.get("entry_signature", {})):
			return false
		signature = move.get("exit_signature", {})
	return true

func _remove_routine_index(index: int) -> void:
	if index >= 0 and index < routine.size():
		routine.remove_at(index)
		selected_compose_source = ""
		selected_compose_routine_index = -1
		_refresh_composed_routine()

func _toggle_compose_details() -> void:
	compose_details.visible = not compose_details.visible

func _prepare_performance() -> void:
	if routine.is_empty():
		status.text = "COMPOSE A ROUTINE FIRST"
		return
	if str(routine[0].get("move_class", "")) != "mount":
		status.text = "START WITH A MOUNT"
		return
	if str(routine[-1].get("move_class", "")) != "dismount":
		status.text = "FINISH WITH A DISMOUNT"
		return
	game_phase = "perform"
	_clear_queued_move_popup()
	performance_stage = "awaiting_start"
	gymnast.visible = true
	routine_library_panel.visible = false
	game_panel.visible = false
	compose_panel.visible = false
	perform_controls.visible = true
	recovery_controls.visible = false
	repeat_routine_button.visible = false
	timing_button.visible = true
	execution_score = 10.0
	stick_bonus = 0.0
	execution_attempted = false
	execution_deductions.clear()
	release_failed = false
	failed_routine_index = -1
	routine_playing = false
	performance_elapsed = 0.0
	performance_next_index = 0
	performance_resume_index = 1
	performance_connector = {}
	performance_complex = {}
	gymnast.set_idle_hang()
	performance_d_score = 0.0
	_reset_live_score()
	_update_performance_score()
	timing_button.text = "START\n[SPACE]"
	performance_feedback_label.text = "Press START when you are ready.\nTime limit: 60 seconds"
	status.text = "READY TO PERFORM"

func _update_execution_prompt() -> void:
	var target: Dictionary = _execution_target(gymnast.skill)
	if target.is_empty():
		return
	var target_time: float = float(target.time)
	var anticipation: float = maxf(0.55, float(gymnast.skill.duration) * 0.28)
	var local_time: float = gymnast.skill_time
	if bool(gymnast.skill.get("loop", false)):
		local_time = fposmod(local_time, float(gymnast.skill.duration))
	var show_preview: bool = hints_input != null and hints_input.button_pressed and not execution_attempted and local_time >= target_time - anticipation and local_time <= target_time + anticipation
	gymnast.set_execution_preview(target.pose, show_preview)
	if not execution_attempted and local_time > target_time + _execution_window(gymnast.skill) * 3.0:
		_apply_missed_input()
	var action_name := "RELEASE NOW!" if str(gymnast.skill.get("move_class", "")) in ["release", "dismount"] else "EXECUTE NOW!"
	timing_button.text = "⚠  %s\n[SPACE]" % action_name

func _update_landing_prompt() -> void:
	var target: Dictionary = _landing_target(gymnast.skill)
	if target.is_empty():
		return
	var target_time: float = float(target.time)
	var local_time: float = gymnast.skill_time
	var anticipation: float = maxf(0.55, float(gymnast.skill.duration) * 0.28)
	var show_preview: bool = hints_input != null and hints_input.button_pressed and local_time >= target_time - anticipation
	gymnast.set_execution_preview(target.pose, show_preview)
	if not execution_attempted and local_time > target_time + _execution_window(gymnast.skill) * 3.0:
		_apply_missed_input()
	timing_button.text = "STICK!\n[SPACE]"

func _execution_window(move: Dictionary) -> float:
	var difficulty: float = clampf(float(move.get("difficulty", 0.1)), 0.1, 1.0)
	return lerpf(0.22, 0.065, difficulty)

func _execution_target(move: Dictionary) -> Dictionary:
	var frames: Array = move.get("keyframes", [])
	if frames.is_empty():
		return {}
	var frame_index: int = clampi(int(move.get("execution_keyframe", frames.size() / 2)), 0, frames.size() - 1)
	return {"time":float(frames[frame_index].get("time", 0.0)), "pose":frames[frame_index].pose}

func _landing_target(move: Dictionary) -> Dictionary:
	var frames: Array = move.get("keyframes", [])
	if frames.is_empty():
		return {}
	var frame_index: int = clampi(int(move.get("landing_keyframe", frames.size() - 1)), 0, frames.size() - 1)
	return {"time":float(frames[frame_index].get("time", move.get("duration", 1.0))), "pose":frames[frame_index].pose}

func _attempt_execution() -> void:
	if game_phase != "perform":
		return
	if performance_stage == "awaiting_start":
		_begin_performance()
		return
	if performance_stage == "waiting_trigger":
		_arm_complex_move()
		return
	if performance_stage not in ["complex_execution", "dismount_landing"] or execution_attempted or not gymnast.playing:
		return
	var judging_landing: bool = performance_stage == "dismount_landing"
	var target: Dictionary = _landing_target(gymnast.skill) if judging_landing else _execution_target(gymnast.skill)
	if target.is_empty():
		return
	var target_time: float = float(target.time)
	var local_time: float = fposmod(gymnast.skill_time, float(gymnast.skill.duration)) if bool(gymnast.skill.get("loop", false)) else gymnast.skill_time
	var error: float = absf(local_time - target_time)
	var window: float = _execution_window(gymnast.skill)
	var deduction := 0.0
	var judgement := "PERFECT"
	if error > window * 3.0:
		deduction = 0.5
		judgement = "MISS  −0.5"
	elif error > window * 2.0:
		deduction = 0.3
		judgement = "LATE/EARLY  −0.3"
	elif error > window:
		deduction = 0.1
		judgement = "SMALL ERROR  −0.1"
	execution_attempted = true
	execution_score = maxf(0.0, execution_score - deduction)
	if deduction > 0.0:
		execution_deductions.append("%s %s" % [str(gymnast.skill.get("name", "Move")), judgement])
		_show_deduction_popup(deduction)
	var move_class: String = str(gymnast.skill.get("move_class", "swing"))
	if judging_landing and error <= window:
		stick_bonus = 0.1
		judgement = "STUCK!  +0.1"
	if not judging_landing and move_class == "release" and error > window * 3.0:
		release_failed = true
		judgement = "MISSED RELEASE — FALL!"
		failed_routine_index = routine_position
		gymnast.queued_skill = {}
		call_deferred("_begin_release_fall")
	gymnast.clear_execution_preview()
	_clear_queued_move_popup()
	performance_feedback_label.text = judgement
	if not judging_landing and move_class == "dismount":
		performance_stage = "dismount_landing"
		execution_attempted = false
		timing_button.text = "STICK!\n[SPACE]"
	elif not judging_landing:
		performance_stage = "complex_active"
	_update_performance_score()

func _begin_performance() -> void:
	if routine.is_empty():
		return
	performance_elapsed = 0.0
	performance_next_index = performance_resume_index
	performance_resume_index = 1
	performance_stage = "mount"
	execution_attempted = true
	gymnast.set_skill(routine[0], true)
	performance_feedback_label.text = str(routine[0].get("name", "Mount")).to_upper()
	timing_button.text = "MOUNTING…"
	status.text = "ROUTINE STARTED"

func _advance_to_next_complex() -> void:
	var previous_move: Dictionary = performance_complex if not performance_complex.is_empty() else (routine[maxi(0, performance_next_index - 1)] if not routine.is_empty() else {})
	performance_complex = {}
	if performance_next_index >= routine.size():
		performance_stage = "finished"
		gymnast.playing = false
		timing_button.text = "COMPLETE"
		performance_feedback_label.text = "ROUTINE COMPLETE"
		status.text = "ROUTINE COMPLETE"
		repeat_routine_button.visible = true
		return
	var next_move: Dictionary = routine[performance_next_index]
	# A routine-authored giant is a holding instruction. Consecutive ordinary
	# swings collapse to the last one, then wait there until the player initiates
	# the following complex skill.
	if not _is_complex_move(next_move) and str(next_move.get("move_class", "")) == "swing":
		while performance_next_index < routine.size():
			var candidate: Dictionary = routine[performance_next_index]
			if _is_complex_move(candidate) or str(candidate.get("move_class", "")) != "swing":
				break
			performance_connector = candidate
			performance_next_index += 1
		if performance_next_index >= routine.size():
			performance_stage = "finished"
			gymnast.playing = false
			timing_button.text = "COMPLETE"
			performance_feedback_label.text = "ROUTINE ENDS IN A HOLDING GIANT"
			repeat_routine_button.visible = true
			return
		performance_complex = routine[performance_next_index]
		performance_next_index += 1
		if not _transition_is_valid(previous_move, performance_connector) or not _transition_is_valid(performance_connector, performance_complex):
			_stop_for_invalid_transition(previous_move, performance_complex)
			return
		gymnast.set_skill(performance_connector, true)
		performance_stage = "waiting_trigger"
		execution_attempted = false
		performance_transition_serial = gymnast.transition_serial
		timing_button.text = "QUEUE: %s\n[SPACE]" % str(performance_complex.get("name", "MOVE")).to_upper()
		performance_feedback_label.text = "%s HOLD — queue the next move when ready\nNext: %s" % [str(performance_connector.get("name", "Giant")).to_upper(), str(performance_complex.get("name", "Move"))]
		return
	# No giant was authored between the skills: continue directly. The next
	# complex animation starts automatically and only its execution click is due.
	performance_complex = next_move
	performance_next_index += 1
	if not _transition_is_valid(previous_move, performance_complex):
		_stop_for_invalid_transition(previous_move, performance_complex)
		return
	_start_implied_complex()

func _start_implied_complex() -> void:
	performance_stage = "complex_execution"
	execution_attempted = false
	release_failed = false
	gymnast.set_skill(performance_complex, true)
	var move_class: String = str(performance_complex.get("move_class", "swing"))
	var action_name := "RELEASE!" if move_class == "release" else ("DISMOUNT!" if move_class == "dismount" else "TURN!")
	_show_queued_move_popup(action_name)
	timing_button.text = "⚠  %s NOW!\n[SPACE]" % ("RELEASE" if move_class in ["release", "dismount"] else "EXECUTE")
	performance_feedback_label.text = "%s STARTED AUTOMATICALLY\nTIMED INPUT REQUIRED" % str(performance_complex.get("name", "Move")).to_upper()
	status.text = "ADJACENT SKILL — EXECUTE NOW"

func _transition_is_valid(from_move: Dictionary, to_move: Dictionary) -> bool:
	return not from_move.is_empty() and not to_move.is_empty() and AuthoredSkills.can_follow(from_move.get("exit_signature", {}), to_move.get("entry_signature", {}))

func _stop_for_invalid_transition(from_move: Dictionary, to_move: Dictionary) -> void:
	performance_stage = "finished"
	gymnast.playing = false
	timing_button.text = "INVALID TRANSITION"
	performance_feedback_label.text = "%s CANNOT FLOW DIRECTLY INTO %s" % [str(from_move.get("name", "Move")).to_upper(), str(to_move.get("name", "Move")).to_upper()]
	status.text = "ROUTINE TRANSITION IS NOT PLAYABLE"
	repeat_routine_button.visible = true

func _arm_complex_move() -> void:
	if performance_complex.is_empty():
		return
	release_failed = false
	performance_stage = "queued_complex"
	execution_attempted = false
	gymnast.clear_execution_preview()
	performance_transition_serial = gymnast.transition_serial
	var queue_message: String = gymnast.queue_skill_for_next_bottom(performance_complex)
	var action_name := "RELEASE!" if str(performance_complex.get("move_class", "")) in ["release", "dismount"] else "EXECUTE!"
	var callout_text := "EXECUTE!"
	var move_class: String = str(performance_complex.get("move_class", "swing"))
	if move_class == "release":
		callout_text = "RELEASE!"
	elif move_class == "dismount":
		callout_text = "DISMOUNT!"
	elif _is_complex_move(performance_complex):
		callout_text = "TURN!"
	_show_queued_move_popup(callout_text)
	timing_button.text = "⚠  %s\n[SPACE]" % action_name
	timing_button.add_theme_color_override("font_color", Color("#fff5d6"))
	timing_button.add_theme_color_override("font_hover_color", Color.WHITE)
	performance_feedback_label.text = "%s\nSECOND CLICK WILL BE TIMED" % queue_message.to_upper()
	status.text = "MOVE INITIATED — TIMED INPUT COMING"

func _show_queued_move_popup(text: String) -> void:
	_clear_queued_move_popup()
	queued_move_popup = Label.new()
	queued_move_popup.size = Vector2(180, 48)
	queued_move_popup.text = text
	queued_move_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queued_move_popup.add_theme_font_size_override("font_size", 27)
	queued_move_popup.add_theme_color_override("font_color", Color("#ffdc8a"))
	queued_move_popup.add_theme_color_override("font_shadow_color", Color("#08111f"))
	queued_move_popup.add_theme_constant_override("shadow_offset_x", 3)
	queued_move_popup.add_theme_constant_override("shadow_offset_y", 3)
	queued_move_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(queued_move_popup)
	queued_move_popup.position = Vector2(410.0, 22.0)
	var tween := queued_move_popup.create_tween().set_loops()
	tween.tween_property(queued_move_popup, "modulate:a", 0.48, 0.32)
	tween.tween_property(queued_move_popup, "modulate:a", 1.0, 0.32)

func _clear_queued_move_popup() -> void:
	if queued_move_popup != null and is_instance_valid(queued_move_popup):
		queued_move_popup.queue_free()
	queued_move_popup = null

func _is_complex_move(move: Dictionary) -> bool:
	var move_class: String = str(move.get("move_class", "swing"))
	if move_class == "release" or move_class == "dismount":
		return true
	var id: String = str(move.get("id", "")).to_lower()
	if id.contains("blind") or id.contains("pirouette") or id.contains("turn"):
		return true
	var frames: Array = move.get("keyframes", [])
	return frames.size() > 1 and absf(float(frames[-1].pose.get("body_yaw", 0.0)) - float(frames[0].pose.get("body_yaw", 0.0))) > 0.25

func _time_up() -> void:
	_clear_queued_move_popup()
	game_phase = "results"
	performance_stage = "finished"
	gymnast.playing = false
	gymnast.clear_execution_preview()
	timing_button.text = "TIME IS UP!"
	performance_feedback_label.text = "TIME IS UP!\nThe routine was not landed within 60 seconds."
	status.text = "TIME IS UP!"
	repeat_routine_button.visible = true

func _apply_missed_input() -> void:
	if execution_attempted or game_phase != "perform":
		return
	execution_attempted = true
	execution_score = maxf(0.0, execution_score - 0.5)
	execution_deductions.append("%s NO INPUT −0.5" % str(gymnast.skill.get("name", "Move")))
	_show_deduction_popup(0.5)
	performance_feedback_label.text = "NO INPUT  −0.5"
	var move_class: String = str(gymnast.skill.get("move_class", "swing"))
	if performance_stage == "complex_execution" and move_class == "release":
		release_failed = true
		failed_routine_index = maxi(0, performance_next_index - 1)
		gymnast.queued_skill = {}
		call_deferred("_begin_release_fall")
	elif performance_stage == "complex_execution" and move_class == "dismount":
		performance_stage = "dismount_landing"
		execution_attempted = false
		timing_button.text = "STICK!\n[SPACE]"
	elif performance_stage == "complex_execution":
		performance_stage = "complex_active"
	gymnast.clear_execution_preview()
	_update_performance_score()

func _show_deduction_popup(deduction: float) -> void:
	if ui_layer == null or deduction <= 0.0:
		return
	var popup := Label.new()
	var anchor: Vector2 = Vector2(gymnast.pose.get("hip", Vector2(500, 360)))
	popup.position = anchor + Vector2(-42.0, -38.0)
	popup.size = Vector2(100, 42)
	popup.text = "− %0.1f" % deduction
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 28)
	popup.add_theme_color_override("font_color", Color("#ff5f6d"))
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(popup)
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 54.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.75).set_delay(0.18)
	tween.chain().tween_callback(popup.queue_free)

func _finalize_execution(completed_skill: Dictionary) -> void:
	if not execution_attempted:
		execution_score = maxf(0.0, execution_score - 0.5)
		execution_deductions.append("%s NO INPUT −0.5" % str(completed_skill.get("name", "Move")))
		_show_deduction_popup(0.5)
		performance_feedback_label.text = "NO INPUT  −0.5"
		if str(completed_skill.get("move_class", "swing")) == "release":
			release_failed = true
	if not release_failed:
		scoring.record_completed_skill(completed_skill)
	performance_d_score = scoring.d_score()
	_update_performance_score()

func _update_performance_score() -> void:
	if performance_score_label == null:
		return
	var remaining: float = maxf(0.0, PERFORMANCE_LIMIT - performance_elapsed)
	performance_score_label.text = "D  %0.2f   E  %0.2f\nTOTAL  %0.2f\nTIME  %02d:%02d" % [performance_d_score, execution_score,
		performance_d_score + execution_score + stick_bonus, floori(remaining / 60.0), floori(fposmod(remaining, 60.0))]

func _begin_release_fall() -> void:
	if game_phase != "perform":
		return
	routine_playing = false
	_clear_queued_move_popup()
	game_phase = "fall"
	gymnast.clear_execution_preview()
	gymnast.set_skill(AuthoredSkills.create_fall_skill(gymnast.current_pose_copy()), true)
	timing_button.visible = false
	recovery_controls.visible = true
	performance_feedback_label.text = "FALL — choose where to rejoin the routine"
	status.text = "RELEASE MISSED"

func _retry_failed_move() -> void:
	_resume_performance_from(maxi(0, failed_routine_index))

func _resume_after_failed_move() -> void:
	_resume_performance_from(mini(routine.size() - 1, failed_routine_index + 1))

func _resume_performance_from(index: int) -> void:
	game_phase = "perform"
	performance_stage = "awaiting_start"
	performance_resume_index = clampi(index, 1, maxi(1, routine.size() - 1))
	recovery_controls.visible = false
	timing_button.visible = true
	execution_attempted = false
	release_failed = false
	gymnast.set_idle_hang()
	timing_button.text = "REMOUNT\n[SPACE]"
	performance_feedback_label.text = "Press when ready to remount"
	status.text = "READY TO REMOUNT"

func _first_move_of_class(move_class: String):
	for move in skills:
		if str(move.get("move_class", "")) == move_class:
			return move
	return null

func _return_to_compose() -> void:
	_show_routine_library()

func _add_skill_index_to_routine(index: int) -> void:
	var move := skills[index]
	var move_class := str(move.get("move_class", "swing"))
	if move_class == "mount":
		if not routine.is_empty():
			status.text = "A MOUNT MUST BE THE FIRST MOVE"
			return
		if _routine_has_class("mount"):
			status.text = "A ROUTINE CAN ONLY HAVE ONE MOUNT"
			return
	elif move_class == "dismount":
		if _routine_has_class("dismount"):
			status.text = "A ROUTINE CAN ONLY HAVE ONE DISMOUNT"
			return
	elif _routine_has_class("dismount"):
		status.text = "THE DISMOUNT MUST BE THE LAST MOVE"
		return
	routine.append(move)
	_refresh_routine_display()
	_refresh_move_browsers()
	_refresh_composed_routine()
	status.text = "%s ADDED TO ROUTINE" % str(move.name).to_upper()

func _add_routine_move_code(code: String) -> void:
	var index := _skill_index_from_code(code)
	if index < 0:
		status.text = "UNKNOWN MOVE CODE"
		return
	routine_code.clear()
	_add_skill_index_to_routine(index)

func _perform_play_list_item(item_index: int) -> void:
	if item_index < 0 or item_index >= play_move_indices.size():
		return
	_cancel_routine_playback()
	status.text = gymnast.queue_skill(skills[play_move_indices[item_index]]).to_upper()
	_refresh_move_browsers()

func _perform_move_code(code: String) -> void:
	var index := _skill_index_from_code(code)
	if index < 0:
		status.text = "UNKNOWN MOVE CODE"
		return
	play_code.clear()
	_cancel_routine_playback()
	status.text = gymnast.queue_skill(skills[index]).to_upper()
	_refresh_move_browsers()

func _skill_index_from_code(code: String) -> int:
	var cleaned := code.strip_edges()
	if not cleaned.is_valid_int():
		return -1
	var index := int(cleaned) - 1
	return index if index >= 0 and index < skills.size() else -1

func _selected_list_skill_index(list: ItemList, indices: Array[int]) -> int:
	var selected := list.get_selected_items()
	if selected.is_empty() or selected[0] < 0 or selected[0] >= indices.size():
		return -1
	return indices[selected[0]]

func _routine_has_class(move_class: String) -> bool:
	for move in routine:
		if str(move.get("move_class", "swing")) == move_class:
			return true
	return false

func _remove_routine_last() -> void:
	if routine.is_empty():
		return
	routine.pop_back()
	if routine_position >= routine.size():
		routine_position = maxi(0, routine.size() - 1)
	_refresh_routine_display()
	_refresh_move_browsers()
	_refresh_composed_routine()

func _clear_routine() -> void:
	routine.clear()
	routine_playing = false
	routine_position = 0
	_refresh_routine_display()
	_refresh_move_browsers()
	_refresh_composed_routine()
	status.text = "ROUTINE CLEARED"

func _play_routine() -> void:
	if routine.is_empty():
		status.text = "ADD AT LEAST ONE MOVE TO THE ROUTINE"
		return
	routine_playing = true
	_reset_live_score()
	routine_position = 0
	playback_routine = _expanded_routine()
	# Every watched routine begins from the same neutral context, including the
	# fallback swing used if its first release precedes any explicit swing.
	gymnast.set_idle_hang()
	gymnast.set_skill(playback_routine[0], true)
	observed_transition_serial = gymnast.transition_serial
	_queue_next_routine_move()
	_refresh_routine_display()
	status.text = "PLAYING ROUTINE"

func _queue_next_routine_move() -> void:
	var next_index := routine_position + 1
	if next_index < playback_routine.size():
		gymnast.queue_skill(playback_routine[next_index])
	_refresh_routine_display()

func _expanded_routine() -> Array[Dictionary]:
	var expanded: Array[Dictionary] = []
	for move in routine:
		expanded.append(move)
	return expanded

func _refresh_routine_display() -> void:
	if routine_sequence_label == null:
		return
	if routine.is_empty():
		routine_sequence_label.text = "Routine is empty — choose a move and add it."
		return
	var entries: Array[String] = []
	var displayed := playback_routine if routine_playing else routine
	for index in range(displayed.size()):
		var name := "%s: %s" % [str(displayed[index].get("move_class", "swing")).capitalize(), str(displayed[index].name)]
		entries.append("[%s]" % name if routine_playing and index == routine_position else name)
	routine_sequence_label.text = "  →  ".join(entries)

func _cancel_routine_playback() -> void:
	if routine_playing:
		routine_playing = false
		_refresh_routine_display()

func _on_mode_menu_selected(id: int) -> void:
	var modes: Array[String] = ["game", "edit"]
	_set_mode(modes[clampi(id, 0, 1)])

func _set_mode(mode: String) -> void:
	_cancel_routine_playback()
	current_mode = mode
	edit_mode = mode == "edit"
	play_panel.visible = false
	editor_panel.visible = edit_mode
	transition_editor_panel.visible = edit_mode
	routine_panel.visible = false
	game_panel.visible = false
	compose_panel.visible = false
	perform_controls.visible = false
	routine_library_panel.visible = mode == "game"
	score_panel.visible = false
	gymnast.set_editor_enabled(edit_mode)
	if edit_mode:
		routine_library_panel.visible = false
		gymnast.visible = true
		gymnast.set_skill(skills[selected_move], false)
		status.text = "EDIT MODE"
		_refresh_keyframes()
		_refresh_transition_editor()
	else:
		game_phase = "home"
		gymnast.visible = false
		_reset_live_score()
		gymnast.set_idle_hang()
		status.text = "CHOOSE A ROUTINE"
		_refresh_routine_library()

func _on_move_selected(index: int) -> void:
	if updating_ui:
		return
	selected_move = index
	selected_keyframe = -1
	gymnast.set_skill(skills[index], not edit_mode)
	_refresh_keyframes()

func _refresh_moves() -> void:
	_ensure_skill_shortcuts()
	updating_ui = true
	move_select.clear()
	for index in range(skills.size()):
		var shortcut := "%s  " % SKILL_SHORTCUT_LABELS[index] if index < SKILL_SHORTCUT_LABELS.size() else ""
		move_select.add_item("%s%s" % [shortcut, str(skills[index].name)])
	move_select.select(clampi(selected_move, 0, skills.size() - 1))
	_refresh_move_browsers()
	updating_ui = false

func _refresh_move_browsers() -> void:
	_populate_move_browser(play_move_list, play_move_indices, play_search, play_class_filter)
	_populate_move_browser(routine_move_list, routine_move_indices, routine_search, routine_class_filter)

func _populate_move_browser(list: ItemList, indices: Array[int], search: LineEdit, class_filter: OptionButton) -> void:
	if list == null:
		return
	var query := search.text.strip_edges().to_lower() if search != null else ""
	var wanted_class := ""
	if class_filter != null and class_filter.selected > 0:
		wanted_class = class_filter.get_item_text(class_filter.selected).to_lower()
	var outgoing_signature := gymnast.current_exit_signature()
	if list == routine_move_list:
		outgoing_signature = AuthoredSkills.make_signature("static_hang", "regular") if routine.is_empty() else routine[-1].exit_signature
	list.clear()
	indices.clear()
	for index in range(skills.size()):
		var move_name_text := str(skills[index].name)
		var move_class := str(skills[index].get("move_class", "swing"))
		if not AuthoredSkills.can_follow(outgoing_signature, skills[index].entry_signature):
			continue
		if not wanted_class.is_empty() and move_class != wanted_class:
			continue
		var code := "%02d" % (index + 1)
		if not query.is_empty() and not move_name_text.to_lower().contains(query) and not move_class.contains(query) and not code.contains(query):
			continue
		list.add_item("%s   %s\n      %s" % [code, move_name_text, move_class.capitalize()])
		indices.append(index)

func _refresh_transition_editor() -> void:
	if transition_editor_panel == null:
		return
	updating_ui = true
	for endpoint in ["entry", "exit"]:
		var signature: Dictionary = gymnast.skill["%s_signature" % endpoint]
		_select_transition_value(transition_inputs["%s_state" % endpoint], AuthoredSkills.TRANSITION_STATES, str(signature.state))
		_select_transition_value(transition_inputs["%s_grip" % endpoint], AuthoredSkills.GRIPS, str(signature.grip))
	var selected_pose: Dictionary = gymnast.pose
	pose_depth_inputs.body_yaw.value = float(selected_pose.get("body_yaw", 0.0)) * 180.0
	pose_depth_inputs.arm_depth.value = float(selected_pose.get("arm_depth", 0.0)) * 90.0
	pose_depth_inputs.leg_depth.value = float(selected_pose.get("leg_depth", 0.0)) * 90.0
	var editable: bool = selected_keyframe >= 0
	for field in ["body_yaw", "arm_depth", "leg_depth"]:
		pose_depth_inputs[field].editable = editable
	for field in ["left_grip", "right_grip"]:
		pose_depth_inputs[field].disabled = not editable
	for field in ["left_grip", "right_grip"]:
		var grip_values: Array[String] = ["regular", "reverse", "mixed", "el_grip"]
		pose_depth_inputs[field].select(maxi(0, grip_values.find(str(selected_pose.get(field, "regular")))))
	var execution_index: int = clampi(int(gymnast.skill.get("execution_keyframe", 0)), 0, maxi(0, gymnast.skill.keyframes.size() - 1))
	execution_keyframe_button.text = "Execution: %02d %s" % [execution_index + 1, str(gymnast.skill.keyframes[execution_index].get("label", "Keyframe"))]
	execution_keyframe_button.disabled = selected_keyframe < 0
	updating_ui = false

func _set_execution_keyframe() -> void:
	if selected_keyframe < 0 or selected_keyframe >= gymnast.skill.keyframes.size():
		status.text = "SELECT A KEYFRAME FIRST"
		return
	_record_change()
	gymnast.skill.execution_keyframe = selected_keyframe
	_refresh_transition_editor()
	gymnast.queue_redraw()
	status.text = "EXECUTION KEYFRAME SET — SAVE WHEN READY"

func _on_pose_depth_changed(value: float, field: String, maximum: float) -> void:
	if updating_ui or selected_keyframe < 0:
		return
	_record_change()
	gymnast.pose[field] = value / maximum
	gymnast.skill.keyframes[selected_keyframe].pose = gymnast.pose.duplicate(true)
	gymnast.queue_redraw()
	status.text = "KEYFRAME %s UPDATED — SAVE WHEN READY" % field.replace("_", " ").to_upper()

func _on_pose_grip_changed(index: int, field: String) -> void:
	if updating_ui or selected_keyframe < 0:
		return
	var grip_values: Array[String] = ["regular", "reverse", "mixed", "el_grip"]
	_record_change()
	gymnast.pose[field] = grip_values[clampi(index, 0, grip_values.size() - 1)]
	gymnast.skill.keyframes[selected_keyframe].pose = gymnast.pose.duplicate(true)
	gymnast.queue_redraw()
	status.text = "KEYFRAME %s UPDATED — SAVE WHEN READY" % field.replace("_", " ").to_upper()

func _select_transition_value(input: OptionButton, values: Array[String], value: String) -> void:
	input.select(maxi(0, values.find(value)))

func _on_transition_field_changed(index: int, endpoint: String, field: String, _input: OptionButton) -> void:
	if updating_ui:
		return
	var values: Array[String]
	if field == "state":
		values = AuthoredSkills.TRANSITION_STATES
	else:
		values = AuthoredSkills.GRIPS
	_record_change()
	var signature: Dictionary = gymnast.skill["%s_signature" % endpoint]
	signature[field] = values[clampi(index, 0, values.size() - 1)]
	gymnast.skill["%s_signature" % endpoint] = signature
	if field == "state":
		gymnast.skill["%s_state" % endpoint] = signature.state
	gymnast.queue_redraw()
	_refresh_move_browsers()
	status.text = "%s %s UPDATED — SAVE WHEN READY" % [endpoint.to_upper(), field.to_upper()]

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
	move_class_input.select(_move_class_index(str(gymnast.skill.get("move_class", "swing"))))
	updating_ui = false
	if edit_mode:
		_refresh_transition_editor()

func _move_class_index(move_class: String) -> int:
	if move_class == "mount":
		return 0
	if move_class == "dismount":
		return 3
	if move_class == "release":
		return 2
	return 1

func _on_move_class_changed(index: int) -> void:
	if updating_ui:
		return
	var classes: Array[String] = ["mount", "swing", "release", "dismount"]
	var next_class: String = classes[clampi(index, 0, classes.size() - 1)]
	if str(gymnast.skill.get("move_class", "swing")) == next_class:
		return
	_record_change()
	gymnast.skill.move_class = next_class
	if next_class == "release":
		gymnast.skill.loop = false
	_refresh_moves()
	_refresh_keyframes()
	status.text = "MOVE CLASS SET TO %s — SAVE WHEN READY" % next_class.to_upper()

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
	if edit_mode:
		_refresh_transition_editor()

func _on_duration_changed(value: float) -> void:
	if updating_ui:
		return
	var old_duration: float = gymnast.skill.duration
	if old_duration <= 0.0001 or is_equal_approx(value, old_duration):
		return
	_record_change()
	var ratio := value / old_duration
	for frame in gymnast.skill.keyframes:
		frame.time = float(frame.time) * ratio
	gymnast.skill.duration = value
	gymnast.seek(gymnast.skill_time * ratio)
	_refresh_keyframes()
	status.text = "MOVE RETIMED TO %0.2f SECONDS — SAVE WHEN READY" % value

func _on_loop_changed(enabled: bool) -> void:
	if not updating_ui and bool(gymnast.skill.loop) != enabled:
		_record_change()
		gymnast.skill.loop = enabled

func _on_ghosts_toggled(enabled: bool) -> void:
	gymnast.set_ghosts_visible(enabled)

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
	if edit_mode:
		_refresh_transition_editor()

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
		marker.mouse_default_cursor_shape = Control.CURSOR_HSIZE if index > 0 else Control.CURSOR_POINTING_HAND
		marker.gui_input.connect(_on_keyframe_marker_input.bind(index))
		keyframe_markers.add_child(marker)
	_update_marker_selection()

func _on_keyframe_marker_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_select_keyframe(index)
			# The first pose defines time zero and remains anchored there.
			if index > 0:
				dragging_keyframe_time = index
				keyframe_time_drag_recorded = false
		else:
			if dragging_keyframe_time == index and keyframe_time_drag_recorded:
				status.text = "KEYFRAME TIME UPDATED — SAVE WHEN READY"
				_refresh_keyframes()
			dragging_keyframe_time = -1
			keyframe_time_drag_recorded = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging_keyframe_time == index:
		var duration: float = gymnast.skill.duration
		var time := clampf(keyframe_markers.get_local_mouse_position().x / keyframe_markers.size.x * duration, 0.0, duration)
		# Frames cannot cross one another; this keeps interpolation well-defined
		# and lets the selected frame retain its identity throughout the drag.
		var minimum := float(gymnast.skill.keyframes[index - 1].time) + 0.001
		var maximum := duration
		if index + 1 < gymnast.skill.keyframes.size():
			maximum = float(gymnast.skill.keyframes[index + 1].time) - 0.001
		time = clampf(snappedf(time, 0.001), minimum, maximum)
		if is_equal_approx(time, float(gymnast.skill.keyframes[index].time)):
			return
		if not keyframe_time_drag_recorded:
			_record_change()
			keyframe_time_drag_recorded = true
		gymnast.skill.keyframes[index].time = time
		gymnast.seek(time)
		updating_ui = true
		timeline.value = time / duration * 1000.0
		keyframe_select.set_item_text(index, "%02d  %0.3fs  %s" % [index + 1, time, gymnast.skill.keyframes[index].get("label", "")])
		updating_ui = false
		time_label.text = "%0.3f / %0.2fs" % [time, duration]
		var marker: Control = keyframe_markers.get_child(index)
		marker.position.x = time / duration * keyframe_markers.size.x - 7.0
		marker.tooltip_text = "%s — %0.3fs" % [gymnast.skill.keyframes[index].get("label", "Keyframe"), time]
		get_viewport().set_input_as_handled()

func _update_marker_selection() -> void:
	for marker in keyframe_markers.get_children():
		var index := int(marker.get_meta("keyframe_index"))
		var selected := index == selected_keyframe
		var style := StyleBoxFlat.new()
		if selected:
			style.bg_color = Color("#72ddf7")
		elif index == 0:
			style.bg_color = Color("#72f1b8")
		elif index == gymnast.skill.keyframes.size() - 1:
			style.bg_color = Color("#ff7b72")
		else:
			style.bg_color = Color("#ffbc42")
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
	_record_change()
	selected_keyframe = gymnast.add_keyframe(gymnast.skill_time)
	_refresh_keyframes()
	status.text = "KEYFRAME ADDED"

func _delete_keyframe() -> void:
	if selected_keyframe < 0 or gymnast.skill.keyframes.size() <= 2:
		status.text = "SELECT A KEYFRAME; KEEP AT LEAST TWO"
		return
	_record_change()
	if not gymnast.delete_keyframe(selected_keyframe):
		status.text = "KEEP AT LEAST TWO KEYFRAMES"
		return
	selected_keyframe = -1
	_refresh_keyframes()
	status.text = "KEYFRAME DELETED"

func _copy_previous_keyframe() -> void:
	if selected_keyframe <= 0:
		status.text = "SELECT ANY KEYFRAME EXCEPT THE FIRST"
		return
	_record_change()
	if not gymnast.copy_previous_keyframe(selected_keyframe):
		status.text = "SELECT ANY KEYFRAME EXCEPT THE FIRST"
		return
	status.text = "COPIED THE PREVIOUS POSE INTO THIS KEYFRAME"
	_refresh_keyframe_markers()

func _add_move() -> void:
	var requested_name := move_name.text.strip_edges()
	if requested_name.is_empty():
		status.text = "ENTER A NAME FOR THE NEW MOVE"
		return
	_record_change()
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

func _rename_move() -> void:
	var requested_name := move_name.text.strip_edges()
	if requested_name.is_empty():
		status.text = "ENTER THE MOVE'S NEW NAME"
		return
	if str(gymnast.skill.name) == requested_name:
		return
	_record_change()
	gymnast.skill.name = requested_name
	move_name.clear()
	_refresh_moves()
	_refresh_routine_display()
	status.text = "MOVE RENAMED — SAVE WHEN READY"

func _copy_move() -> void:
	_record_change()
	var source: Dictionary = gymnast.skill
	var copy: Dictionary = source.duplicate(true)
	var base_id := "%s_copy" % str(source.id)
	var next_id := base_id
	var suffix := 2
	while _find_skill(next_id) != null:
		next_id = "%s_%d" % [base_id, suffix]
		suffix += 1
	copy.id = next_id
	copy.name = "%s copy" % str(source.name)
	skills.append(copy)
	selected_move = skills.size() - 1
	selected_keyframe = -1
	gymnast.set_skill(copy, false)
	_refresh_moves()
	_refresh_keyframes()
	status.text = "MOVE COPIED — RENAME, MODIFY, THEN SAVE IT"

func _delete_move() -> void:
	if skills.size() <= 1:
		status.text = "KEEP AT LEAST ONE MOVE"
		return
	_record_change()
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

func _find_skill(id: String):
	for move in skills:
		if move.id == id:
			return move
	return null

func _snapshot() -> Dictionary:
	var skill_copies: Array[Dictionary] = []
	for move in skills:
		skill_copies.append(move.duplicate(true))
	return {"skills":skill_copies, "selected_move":selected_move,
		"selected_keyframe":selected_keyframe, "time":gymnast.skill_time}

func _record_change() -> void:
	if not edit_mode:
		return
	undo_stack.append(_snapshot())
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_history_buttons()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(_snapshot())
	var previous: Dictionary = undo_stack.pop_back()
	_restore_snapshot(previous)
	status.text = "UNDONE — SAVE WHEN READY"
	_update_history_buttons()

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(_snapshot())
	var next: Dictionary = redo_stack.pop_back()
	_restore_snapshot(next)
	status.text = "REDONE — SAVE WHEN READY"
	_update_history_buttons()

func _restore_snapshot(snapshot: Dictionary) -> void:
	var restored: Array[Dictionary] = []
	for move in snapshot.skills:
		restored.append(move.duplicate(true))
	skills = restored
	selected_move = clampi(int(snapshot.selected_move), 0, skills.size() - 1)
	selected_keyframe = int(snapshot.selected_keyframe)
	gymnast.set_skill(skills[selected_move], false)
	gymnast.set_editor_enabled(true)
	gymnast.seek(clampf(float(snapshot.time), 0.0, float(gymnast.skill.duration)))
	gymnast.set_selected_keyframe(selected_keyframe)
	_refresh_moves()
	_refresh_keyframes()

func _update_history_buttons() -> void:
	if undo_button != null:
		undo_button.disabled = undo_stack.is_empty()
	if redo_button != null:
		redo_button.disabled = redo_stack.is_empty()

func _input(event: InputEvent) -> void:
	# Gameplay timing must win even when a UI control currently has keyboard
	# focus; relying on _unhandled_input lets focused buttons consume Space.
	if current_mode == "game" and game_phase == "perform" and event.is_action_pressed("release_catch"):
		_attempt_execution()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if edit_mode and event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_Z and event.shift_pressed:
			_redo()
		elif event.keycode == KEY_Z:
			_undo()
		elif event.keycode == KEY_Y:
			_redo()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if edit_mode:
		return
	if current_mode == "game":
		if event.is_action_pressed("restart"):
			_return_to_compose()
		return
	if current_mode == "routine":
		if event.is_action_pressed("release_catch"):
			gymnast.playing = not gymnast.playing
		elif event.is_action_pressed("restart"):
			_cancel_routine_playback()
			_reset_live_score()
			gymnast.set_idle_hang()
			status.text = "ROUTINE RESET"
			_refresh_move_browsers()
		return
	for index in range(mini(skills.size(), SKILL_SHORTCUT_KEYS.size())):
		if event.is_action_pressed(_skill_action(index)):
			_cancel_routine_playback()
			status.text = gymnast.queue_skill(skills[index]).to_upper()
			_refresh_move_browsers()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("move_tap"):
		_cancel_routine_playback()
		var tap = _find_skill("tap_giant")
		if tap != null:
			status.text = gymnast.queue_skill(tap).to_upper()
			_refresh_move_browsers()
	elif event.is_action_pressed("move_normal"):
		_cancel_routine_playback()
		var normal = _find_skill("normal_giant")
		if normal != null:
			status.text = gymnast.queue_skill(normal).to_upper()
			_refresh_move_browsers()
	elif event.is_action_pressed("move_dismount"):
		_cancel_routine_playback()
		_queue_dismount()
	elif event.is_action_pressed("release_catch"):
		gymnast.playing = not gymnast.playing
	elif event.is_action_pressed("restart"):
		_cancel_routine_playback()
		_reset_live_score()
		gymnast.set_idle_hang()
		status.text = "STATIC HANG — SELECT A MOVE"
		_refresh_move_browsers()

func _queue_dismount() -> void:
	if edit_mode:
		return
	_cancel_routine_playback()
	var dismount = _find_skill("layout_back")
	if dismount != null:
		status.text = gymnast.queue_skill(dismount).to_upper()
		_refresh_move_browsers()

func _ensure_move_inputs() -> void:
	_add_key_action("move_normal", KEY_G)
	_add_key_action("move_tap", KEY_T)
	_add_key_action("move_dismount", KEY_D)

func _ensure_skill_shortcuts() -> void:
	# Rebuild our numbered actions whenever the in-memory move list changes.
	# Consequently every JSON skill discovered at launch automatically becomes
	# playable without adding a bespoke action or editing this script.
	for index in range(SKILL_SHORTCUT_KEYS.size()):
		var action := _skill_action(index)
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		if index < skills.size():
			_add_key_action(action, SKILL_SHORTCUT_KEYS[index])

func _skill_action(index: int) -> StringName:
	return StringName("move_slot_%d" % (index + 1))

func _play_shortcut_legend() -> String:
	var entries: Array[String] = []
	for index in range(mini(skills.size(), SKILL_SHORTCUT_LABELS.size())):
		entries.append("%s %s" % [SKILL_SHORTCUT_LABELS[index], str(skills[index].name).to_upper()])
	return "  ·  ".join(entries)

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
	draw_rect(Rect2(0, 0, 1280, 760), Color("#0e1a2b"))
