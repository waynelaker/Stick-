class_name StickGymnast
extends Node2D

signal ghost_keyframe_clicked(index: int)

# GME play-mode port. Styling, proportions, framing and draw order match the
# authoritative SVG renderer rather than the previous Stick! redesign.
const BACKGROUND := Color("#14263d")
const UPRIGHT := Color("#7187a0")
const FLOOR := Color("#34516e")
const BONE := Color("#ffbc42")
const JOINT := Color("#fff5d6")
const HAND := Color("#ff7b54")
const BAR := Color("#72ddf7")
const BAR_STROKE := Color("#dce7ed")
const SCENE_SCALE := 0.86
const SCENE_CENTER := Vector2(500.0, 275.0)

var skill := AuthoredSkills.normal_giant()
var queued_skill: Dictionary = {}
var queued_cycle := -1
var skill_time := 0.0
var speed := 1.0
var playing := true
var pose: Dictionary
var editor_mode := false
var selected_joint := ""
var dragging_joint := false
var selected_keyframe := -1

func _ready() -> void:
	pose = AuthoredSkills.sample_skill(skill, 0.0)
	queue_redraw()

func _process(delta: float) -> void:
	if playing:
		if editor_mode:
			skill_time += delta * speed
			if skill.loop:
				skill_time = fposmod(skill_time, float(skill.duration))
			else:
				skill_time = minf(skill_time, float(skill.duration))
				if skill_time >= float(skill.duration):
					playing = false
			pose = AuthoredSkills.sample_skill(skill, skill_time)
			queue_redraw()
			return
		if skill.get("playback_profile", "linear") == "linear":
			skill_time = minf(skill_time + delta * speed, float(skill.duration))
			if skill.loop:
				skill_time = fposmod(skill_time, float(skill.duration))
			pose = AuthoredSkills.sample_skill(skill, skill_time)
			if skill_time >= float(skill.duration):
				playing = false
			queue_redraw()
			return
		# Direct port: fast through bottom, slow and measured near handstand.
		var bottom_speed_bias := 0.38 + 0.82 * ((1.0 + cos(skill_time)) / 2.0)
		var tap_drive := 0.85 + 0.45 * maxf(0.0, sin(skill_time)) if skill.get("playback_profile", "") == "tap_giant" else 1.0
		var previous_cycle := floori(skill_time / float(skill.duration))
		# Calibrated so the former 1.2× playback is now the natural 1.0× rate.
		skill_time += delta * 5.04 * speed * bottom_speed_bias * tap_drive
		pose = AuthoredSkills.sample_skill(skill, skill_time)
		if not queued_skill.is_empty():
			var local_time := fposmod(skill_time, float(skill.duration))
			var blend_start := float(skill.duration) * 0.78
			var active_cycle := floori(skill_time / float(skill.duration))
			if active_cycle == queued_cycle - 1 and local_time >= blend_start:
				var blend := smoothstep(blend_start, float(skill.duration), local_time)
				# A dismount normalises the outgoing body shape before release.
				var blend_skill := AuthoredSkills.normal_giant() if queued_skill.exit_state == "landed" else queued_skill
				var target_pose := AuthoredSkills.sample_skill(blend_skill, local_time)
				pose = AuthoredSkills.interpolate_pose(pose, target_pose, blend)
			var current_cycle := floori(skill_time / float(skill.duration))
			if current_cycle > previous_cycle and current_cycle >= queued_cycle:
				skill = queued_skill
				queued_skill = {}
				queued_cycle = -1
				skill_time = fposmod(skill_time, float(skill.duration))
				pose = AuthoredSkills.sample_skill(skill, skill_time)
		queue_redraw()

func reset() -> void:
	skill = AuthoredSkills.normal_giant()
	skill_time = 0.0
	playing = true
	queued_skill = {}
	queued_cycle = -1
	pose = AuthoredSkills.sample_skill(skill, skill_time)
	queue_redraw()

func set_skill(next_skill: Dictionary, should_play := false) -> void:
	skill = next_skill
	skill_time = 0.0
	queued_skill = {}
	queued_cycle = -1
	playing = should_play
	selected_keyframe = -1
	pose = AuthoredSkills.sample_skill(skill, skill_time)
	queue_redraw()

func set_editor_enabled(enabled: bool) -> void:
	editor_mode = enabled
	selected_joint = ""
	dragging_joint = false
	if enabled:
		playing = false
	queue_redraw()

func set_selected_keyframe(index: int) -> void:
	selected_keyframe = index
	selected_joint = ""
	queue_redraw()

func seek(time: float) -> void:
	skill_time = clampf(time, 0.0, float(skill.duration))
	pose = AuthoredSkills.sample_skill(skill, skill_time)
	queue_redraw()

func current_pose_copy() -> Dictionary:
	return pose.duplicate(true)

func add_keyframe(time: float) -> int:
	for index in range(skill.keyframes.size()):
		if absf(float(skill.keyframes[index].time) - time) < 0.0005:
			skill.keyframes[index].pose = current_pose_copy()
			return index
	skill.keyframes.append({"time":time, "label":"Keyframe", "pose":current_pose_copy()})
	skill.keyframes.sort_custom(func(a, b): return float(a.time) < float(b.time))
	for index in range(skill.keyframes.size()):
		if is_equal_approx(float(skill.keyframes[index].time), time):
			return index
	return -1

func update_keyframe(index: int) -> void:
	if index >= 0 and index < skill.keyframes.size():
		skill.keyframes[index].pose = current_pose_copy()

func delete_keyframe(index: int) -> bool:
	if skill.keyframes.size() <= 2 or index < 0 or index >= skill.keyframes.size():
		return false
	skill.keyframes.remove_at(index)
	seek(minf(skill_time, float(skill.duration)))
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not editor_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var authored_position := _screen_to_pose(event.position)
			# Ghosts get first pick. The selected ghost is excluded from this hit
			# test, so clicking it again reaches the joint-dragging path below.
			var ghost_index := _ghost_keyframe_at(authored_position)
			if ghost_index >= 0:
				ghost_keyframe_clicked.emit(ghost_index)
				get_viewport().set_input_as_handled()
				return
			selected_joint = _joint_at_pose_position(authored_position, 10.0 / SCENE_SCALE)
			dragging_joint = selected_joint != ""
		else:
			dragging_joint = false
		queue_redraw()
		if selected_joint != "":
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging_joint:
		_move_selected_joint(_screen_to_pose(event.position))
		get_viewport().set_input_as_handled()

func _joint_at_screen_position(screen_position: Vector2) -> String:
	return _joint_at_pose_position(_screen_to_pose(screen_position), 18.0 / SCENE_SCALE)

func _joint_at_pose_position(authored: Vector2, radius: float) -> String:
	var closest := ""
	var closest_distance := radius
	for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
		var distance := authored.distance_to(pose[joint])
		if distance < closest_distance:
			closest = joint
			closest_distance = distance
	return closest

func _ghost_keyframe_at(point: Vector2) -> int:
	var best_index := -1
	var best_distance := 11.0 / SCENE_SCALE
	for index in range(skill.keyframes.size()):
		if index == selected_keyframe:
			continue
		var ghost_pose: Dictionary = skill.keyframes[index].pose
		for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
			var distance := point.distance_to(ghost_pose[joint])
			if distance < best_distance:
				best_distance = distance
				best_index = index
		for bone in AuthoredSkills.CHAIN:
			var distance := _distance_to_segment(point, ghost_pose[bone[0]], ghost_pose[bone[1]])
			if distance < best_distance:
				best_distance = distance
				best_index = index
	return best_index

func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() < 0.001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * amount)

func _screen_to_pose(screen_position: Vector2) -> Vector2:
	var scale_offset := SCENE_CENTER * (1.0 - SCENE_SCALE)
	return (screen_position - scale_offset) / SCENE_SCALE

func _move_selected_joint(target: Vector2) -> void:
	if selected_joint == "head":
		pose.head = target
		queue_redraw()
		return
	if selected_joint == "hand":
		var change: Vector2 = target - pose.hand
		for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
			pose[joint] += change
		queue_redraw()
		return
	var parent_by_joint := {"shoulder":"hand", "hip":"shoulder", "knee":"hip", "ankle":"knee"}
	var parent: String = parent_by_joint[selected_joint]
	var old_position: Vector2 = pose[selected_joint]
	var parent_position: Vector2 = pose[parent]
	var bone_length := old_position.distance_to(parent_position)
	var direction := (target - parent_position).normalized()
	if direction == Vector2.ZERO:
		return
	var constrained := parent_position + direction * bone_length
	var change := constrained - old_position
	pose[selected_joint] = constrained
	var descendants := {"shoulder":["hip","knee","ankle","head"], "hip":["knee","ankle"], "knee":["ankle"], "ankle":[]}
	for joint in descendants[selected_joint]:
		pose[joint] += change
	queue_redraw()

func queue_move(id: String) -> String:
	var requested: Dictionary
	if id == "layout_back":
		requested = AuthoredSkills.layout_back_dismount()
	elif id == "tap_giant":
		requested = AuthoredSkills.tap_giant()
	else:
		requested = AuthoredSkills.normal_giant()
	return queue_skill(requested)

func queue_skill(requested: Dictionary) -> String:
	if skill.exit_state == "landed":
		return "Press R to return to the bar"
	if requested.id == skill.id:
		queued_skill = {}
		queued_cycle = -1
		return "%s continuing" % skill.name
	queued_skill = requested
	var duration: float = skill.duration
	var current_cycle := floori(skill_time / duration)
	var too_late_to_blend := fposmod(skill_time, duration) >= duration * 0.78
	queued_cycle = current_cycle + (2 if too_late_to_blend else 1)
	return "%s queued for %s bottom" % [requested.name, "the following" if too_late_to_blend else "the next"]

func _draw() -> void:
	# The TypeScript scene's SVG viewBox is exactly 1000 x 550.
	draw_rect(Rect2(0, 0, 1000, 550), BACKGROUND)
	# Scale the whole authored composition around the stage centre. Canvas
	# transforms also scale line widths and joint radii, preserving proportions.
	var scale_offset := SCENE_CENTER * (1.0 - SCENE_SCALE)
	draw_set_transform(scale_offset, 0.0, Vector2.ONE * SCENE_SCALE)
	_draw_round_line(AuthoredSkills.HIGH_BAR, Vector2(500, 545), UPRIGHT, 12.0)
	_draw_round_line(Vector2(70, 545), Vector2(930, 545), FLOOR, 8.0)
	if editor_mode:
		for index in range(skill.keyframes.size()):
			if index != selected_keyframe or playing:
				_draw_pose(skill.keyframes[index].pose, 0.15)
	_draw_pose(pose, 1.0)
	if editor_mode and selected_joint != "":
		draw_circle(pose[selected_joint], 12.0, Color(0.45, 0.87, 0.97, 0.35))
		draw_arc(pose[selected_joint], 12.0, 0.0, TAU, 24, Color("#72ddf7"), 2.5, true)
	# Edge-on bar overlay remains in front of the grip, exactly as in renderer.ts.
	_draw_stroked_circle(AuthoredSkills.HIGH_BAR, 9.0, BAR, BAR_STROKE, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_pose(draw_pose: Dictionary, opacity: float) -> void:
	var bone_color := _with_opacity(BONE, opacity)
	var joint_color := _with_opacity(JOINT, opacity)
	var hand_color := _with_opacity(HAND, opacity)
	# Head is behind the articulated chain so the near arm crosses in front.
	_draw_stroked_circle(draw_pose.head, 17.0, joint_color, bone_color, 4.0)
	for bone in AuthoredSkills.CHAIN:
		_draw_round_line(draw_pose[bone[0]], draw_pose[bone[1]], bone_color, 13.0)
	for joint_name in ["hand", "shoulder", "hip", "knee", "ankle"]:
		if joint_name == "hand":
			_draw_stroked_circle(draw_pose[joint_name], 7.0, hand_color, joint_color, 3.0)
		else:
			_draw_stroked_circle(draw_pose[joint_name], 7.0, joint_color, bone_color, 4.0)

func _with_opacity(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * opacity)

func _draw_round_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color)
	draw_circle(to, width * 0.5, color)

func _draw_stroked_circle(center: Vector2, radius: float, fill: Color, stroke: Color, width: float) -> void:
	draw_circle(center, radius + width * 0.5, stroke)
	draw_circle(center, radius - width * 0.5, fill)
