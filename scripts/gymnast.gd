class_name StickGymnast
extends Node2D

signal ghost_keyframe_clicked(index: int)
signal pose_edit_started

# GME play-mode port. Styling, proportions, framing and draw order match the
# authoritative SVG renderer rather than the previous Stick! redesign.
const BACKGROUND := Color("#14263d")
const UPRIGHT := Color("#7187a0")
const FLOOR := Color("#34516e")
const BONE := Color("#ffbc42")
const JOINT := Color("#fff5d6")
const HAND := Color("#ff7b54")
const ATTACHED_HAND := Color("#72f1b8")
const GROUNDED_FOOT := Color("#a8f07a")
const BAR := Color("#72ddf7")
const BAR_STROKE := Color("#dce7ed")
const SCENE_SCALE := 0.86
const SCENE_CENTER := Vector2(500.0, 275.0)
const BAR_ATTACHED_DISTANCE := 6.0
const BAR_SNAP_DISTANCE := 18.0
const FLOOR_SNAP_DISTANCE := 18.0

var skill := AuthoredSkills.normal_giant()
var queued_skill: Dictionary = {}
var queued_cycle := -1
var skill_time := 0.0
var speed := 1.0
var playing := true
var pose: Dictionary
# A non-looping authored move normally plays at its saved timing. When it is
# entered from a giant, these values briefly time-warp its opening frames so
# angular velocity is continuous through the bottom instead of abruptly
# dropping to the (much slower) authored dismount rate.
var linear_entry_rate := 1.0
var linear_entry_blend_end := 0.0
var transition_serial := 0
var editor_mode := false
var selected_joint := ""
var dragging_joint := false
var dragging_body := false
var body_drag_position := Vector2.ZERO
var transform_mode := false
var dragging_rotation := false
var rotation_center := Vector2.ZERO
var rotation_start_angle := 0.0
var rotation_start_pose: Dictionary = {}
var pose_edit_transaction := false
var selected_keyframe := -1
var show_ghosts := true

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
			var entry_blend := smoothstep(0.0, linear_entry_blend_end, skill_time) if linear_entry_blend_end > 0.0 else 1.0
			var playback_rate := lerpf(linear_entry_rate, 1.0, entry_blend)
			skill_time = minf(skill_time + delta * speed * playback_rate, float(skill.duration))
			pose = AuthoredSkills.sample_skill(skill, skill_time)
			if skill_time >= float(skill.duration):
				if not queued_skill.is_empty():
					_transition_from_completed_skill()
				elif skill.loop:
					skill_time = 0.0
					pose = AuthoredSkills.sample_skill(skill, skill_time)
				else:
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
				# Linear skills use their own clock, so sampling one with the giant's
				# phase would briefly show an arbitrary (often final) release pose.
				# Prepare their entry using a normal giant and begin the authored move
				# from frame zero at the bottom.
				var queued_profile: String = str(queued_skill.get("playback_profile", "linear"))
				var blend_skill := AuthoredSkills.normal_giant() if queued_profile == "linear" else queued_skill
				var target_pose := AuthoredSkills.sample_skill(blend_skill, local_time)
				if queued_profile == "linear" and not queued_skill.keyframes.is_empty():
					# Meet the release's real first pose at the boundary. This also
					# accommodates authored entries that sit just beyond exact bottom.
					target_pose = AuthoredSkills.interpolate_pose(target_pose, queued_skill.keyframes[0].pose, blend)
				pose = AuthoredSkills.interpolate_pose(pose, target_pose, blend)
			var current_cycle := floori(skill_time / float(skill.duration))
			if current_cycle > previous_cycle and current_cycle >= queued_cycle:
				var outgoing_profile: String = str(skill.get("playback_profile", "giant"))
				var phase_overshoot := fposmod(skill_time, float(skill.duration))
				var incoming_skill := queued_skill
				_configure_linear_entry(outgoing_profile, incoming_skill)
				skill = queued_skill
				transition_serial += 1
				queued_skill = {}
				queued_cycle = -1
				# Convert the small giant-phase overshoot into the incoming skill's
				# authored time domain for a release or dismount. Giant transitions
				# already share the same phase clock and retain the overshoot as-is.
				var incoming_angular_rate := _initial_attached_angular_rate(incoming_skill)
				if linear_entry_blend_end > 0.0 and incoming_angular_rate > 0.001:
					skill_time = phase_overshoot / incoming_angular_rate
				else:
					skill_time = phase_overshoot
				pose = AuthoredSkills.sample_skill(skill, skill_time)
		queue_redraw()

func reset() -> void:
	skill = AuthoredSkills.normal_giant()
	skill_time = 0.0
	playing = true
	queued_skill = {}
	queued_cycle = -1
	linear_entry_rate = 1.0
	linear_entry_blend_end = 0.0
	pose = AuthoredSkills.sample_skill(skill, skill_time)
	queue_redraw()

func set_skill(next_skill: Dictionary, should_play := false) -> void:
	skill = next_skill
	skill_time = 0.0
	queued_skill = {}
	queued_cycle = -1
	linear_entry_rate = 1.0
	linear_entry_blend_end = 0.0
	playing = should_play
	selected_keyframe = -1
	pose = AuthoredSkills.sample_skill(skill, skill_time)
	queue_redraw()

func _configure_linear_entry(outgoing_profile: String, incoming_skill: Dictionary) -> void:
	linear_entry_rate = 1.0
	linear_entry_blend_end = 0.0
	if incoming_skill.get("playback_profile", "linear") != "linear":
		return
	var authored_rate := _initial_attached_angular_rate(incoming_skill)
	if authored_rate <= 0.001:
		return
	# Giant playback is fastest at the bottom. A tap giant is slightly checked
	# there by its tap-drive curve, so it gets its own matching entry speed.
	var outgoing_bottom_rate := 5.04 * 1.2
	if outgoing_profile == "tap_giant":
		outgoing_bottom_rate *= 0.85
	linear_entry_rate = clampf(outgoing_bottom_rate / authored_rate, 1.0, 4.0)
	# Return to the move's authored clock at its release frame. Poses remain
	# entirely file-authored; only the transition timing is adapted.
	if incoming_skill.keyframes.size() >= 3:
		linear_entry_blend_end = float(incoming_skill.keyframes[2].time)
	else:
		linear_entry_blend_end = minf(float(incoming_skill.duration) * 0.25, 0.5)

func _initial_attached_angular_rate(incoming_skill: Dictionary) -> float:
	if incoming_skill.keyframes.size() < 2:
		return 0.0
	var first: Dictionary = incoming_skill.keyframes[0]
	var second: Dictionary = incoming_skill.keyframes[1]
	if Vector2(first.pose.hand).distance_to(AuthoredSkills.HIGH_BAR) > BAR_ATTACHED_DISTANCE or Vector2(second.pose.hand).distance_to(AuthoredSkills.HIGH_BAR) > BAR_ATTACHED_DISTANCE:
		return 0.0
	var elapsed := float(second.time) - float(first.time)
	if elapsed <= 0.0001:
		return 0.0
	var first_arm: Vector2 = Vector2(first.pose.shoulder) - Vector2(first.pose.hand)
	var second_arm: Vector2 = Vector2(second.pose.shoulder) - Vector2(second.pose.hand)
	var angle_change := absf(wrapf(second_arm.angle() - first_arm.angle(), -PI, PI))
	return angle_change / elapsed

func _transition_from_completed_skill() -> void:
	var next_skill := queued_skill
	queued_skill = {}
	queued_cycle = -1
	linear_entry_rate = 1.0
	linear_entry_blend_end = 0.0
	var next_time := 0.0
	var next_profile: String = str(next_skill.get("playback_profile", "linear"))
	# A caught release may finish at any point around the bar. Resume a giant at
	# that same arm angle instead of snapping the gymnast back to its bottom.
	if next_profile == "giant" or next_profile == "tap_giant":
		var arm: Vector2 = Vector2(pose.shoulder) - Vector2(pose.hand)
		next_time = fposmod(arm.angle() - PI / 2.0, float(next_skill.duration))
	skill = next_skill
	transition_serial += 1
	skill_time = next_time
	playing = true
	pose = AuthoredSkills.sample_skill(skill, skill_time)

func set_editor_enabled(enabled: bool) -> void:
	editor_mode = enabled
	selected_joint = ""
	dragging_joint = false
	dragging_body = false
	transform_mode = false
	dragging_rotation = false
	if enabled:
		playing = false
	queue_redraw()

func set_selected_keyframe(index: int) -> void:
	selected_keyframe = index
	selected_joint = ""
	queue_redraw()

func set_ghosts_visible(visible: bool) -> void:
	show_ghosts = visible
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

func delete_keyframe(index: int) -> bool:
	if skill.keyframes.size() <= 2 or index < 0 or index >= skill.keyframes.size():
		return false
	skill.keyframes.remove_at(index)
	seek(minf(skill_time, float(skill.duration)))
	return true

func copy_previous_keyframe(index: int) -> bool:
	if index <= 0 or index >= skill.keyframes.size():
		return false
	skill.keyframes[index].pose = skill.keyframes[index - 1].pose.duplicate(true)
	pose = skill.keyframes[index].pose.duplicate(true)
	skill_time = float(skill.keyframes[index].time)
	selected_joint = ""
	queue_redraw()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not editor_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var authored_position := _screen_to_pose(event.position)
			if transform_mode:
				if authored_position.distance_to(_transform_center()) <= 16.0 / SCENE_SCALE:
					dragging_body = true
					body_drag_position = authored_position
					pose_edit_transaction = false
					get_viewport().set_input_as_handled()
					return
				if authored_position.distance_to(_rotation_handle_position()) <= 14.0 / SCENE_SCALE:
					dragging_rotation = true
					rotation_center = _transform_center()
					rotation_start_angle = (authored_position - rotation_center).angle()
					rotation_start_pose = pose.duplicate(true)
					pose_edit_transaction = false
					get_viewport().set_input_as_handled()
					return
				# A click outside either handle closes transform mode and is not
				# reused for another edit action.
				transform_mode = false
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			# Once a keyframe is selected, its editable joints and detached-body
			# spine take priority over overlapping onion-skin poses.
			if selected_keyframe >= 0:
				# Joints win over the spine handle, especially at its shoulder and
				# hip endpoints.
				selected_joint = _joint_at_pose_position(authored_position, 14.0 / SCENE_SCALE)
				if selected_joint != "":
					dragging_joint = true
					get_viewport().set_input_as_handled()
					return
				if _detached_spine_hit(authored_position):
					transform_mode = true
					selected_joint = ""
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
			# With no editable part hit, an onion-skin pose can be selected.
			var ghost_index := _ghost_keyframe_at(authored_position)
			if ghost_index >= 0:
				ghost_keyframe_clicked.emit(ghost_index)
				get_viewport().set_input_as_handled()
				return
			# Joint edits always belong to an explicitly selected keyframe.
			if selected_keyframe < 0:
				return
			selected_joint = ""
			dragging_joint = false
		else:
			dragging_joint = false
			dragging_body = false
			dragging_rotation = false
			pose_edit_transaction = false
		queue_redraw()
		if selected_joint != "":
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging_joint:
		_move_selected_joint(_screen_to_pose(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging_body:
		var authored_position := _screen_to_pose(event.position)
		var change := authored_position - body_drag_position
		if change == Vector2.ZERO:
			return
		_begin_pose_edit()
		if _selected_pose_is_grounded():
			change.y = 0.0
		body_drag_position = authored_position
		for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
			pose[joint] += change
		if _selected_pose_is_grounded():
			pose.ankle.y = AuthoredSkills.FLOOR_Y
		_commit_selected_keyframe()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging_rotation:
		var authored_position := _screen_to_pose(event.position)
		var angle := (authored_position - rotation_center).angle() - rotation_start_angle
		_begin_pose_edit()
		for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
			var original: Vector2 = rotation_start_pose[joint]
			pose[joint] = rotation_center + (original - rotation_center).rotated(angle)
		_commit_selected_keyframe()
		queue_redraw()
		get_viewport().set_input_as_handled()

func _selected_pose_is_detached() -> bool:
	return pose.hand.distance_to(AuthoredSkills.HIGH_BAR) > BAR_ATTACHED_DISTANCE

func _selected_pose_is_grounded() -> bool:
	return absf(float(pose.ankle.y) - AuthoredSkills.FLOOR_Y) <= BAR_ATTACHED_DISTANCE

func _detached_spine_hit(point: Vector2) -> bool:
	if not _selected_pose_is_detached():
		return false
	var endpoint_exclusion := 20.0 / SCENE_SCALE
	if point.distance_to(pose.shoulder) <= endpoint_exclusion or point.distance_to(pose.hip) <= endpoint_exclusion:
		return false
	return _distance_to_segment(point, pose.shoulder, pose.hip) <= 12.0 / SCENE_SCALE

func _transform_center() -> Vector2:
	return (Vector2(pose.shoulder) + Vector2(pose.hip)) * 0.5

func _rotation_handle_position() -> Vector2:
	var spine: Vector2 = pose.hip - pose.shoulder
	var normal := Vector2(-spine.y, spine.x).normalized()
	if normal == Vector2.ZERO:
		normal = Vector2.RIGHT
	return _transform_center() + normal * 58.0

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
	if not show_ghosts:
		return -1
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
		_begin_pose_edit()
		pose.head = target
		_commit_selected_keyframe()
		queue_redraw()
		return
	if selected_joint == "ankle":
		var knee: Vector2 = pose.knee
		var shin_length: float = Vector2(pose.ankle).distance_to(knee)
		if absf(target.y - AuthoredSkills.FLOOR_Y) <= FLOOR_SNAP_DISTANCE:
			_begin_pose_edit()
			pose.ankle = _ankle_on_floor(target, knee, shin_length)
		else:
			var direction := (target - knee).normalized()
			if direction == Vector2.ZERO:
				return
			_begin_pose_edit()
			pose.ankle = knee + direction * shin_length
		_commit_selected_keyframe()
		queue_redraw()
		return
	if selected_joint == "hand":
		var was_attached := not _selected_pose_is_detached()
		# Pulling away beyond the snap zone releases the grip. Small hand motion
		# while attached remains locked, avoiding accidental detachments.
		if was_attached and target.distance_to(AuthoredSkills.HIGH_BAR) <= BAR_SNAP_DISTANCE:
			return
		var shoulder: Vector2 = pose.shoulder
		var arm_length: float = Vector2(pose.hand).distance_to(shoulder)
		var direction := (target - shoulder).normalized()
		if direction == Vector2.ZERO:
			return
		if not was_attached and target.distance_to(AuthoredSkills.HIGH_BAR) <= BAR_SNAP_DISTANCE:
			_begin_pose_edit()
			pose.hand = AuthoredSkills.HIGH_BAR
		else:
			_begin_pose_edit()
			pose.hand = shoulder + direction * arm_length
		_commit_selected_keyframe()
		queue_redraw()
		return
	if _selected_pose_is_grounded():
		_move_joint_from_ground(target)
		return
	var parent_by_joint := {"shoulder":"hand", "hip":"shoulder", "knee":"hip"}
	var parent: String = parent_by_joint[selected_joint]
	var old_position: Vector2 = pose[selected_joint]
	var parent_position: Vector2 = pose[parent]
	var bone_length := old_position.distance_to(parent_position)
	var direction := (target - parent_position).normalized()
	if direction == Vector2.ZERO:
		return
	var constrained := parent_position + direction * bone_length
	var change := constrained - old_position
	if change == Vector2.ZERO:
		return
	_begin_pose_edit()
	pose[selected_joint] = constrained
	var descendants := {"shoulder":["hip","knee","ankle","head"], "hip":["knee","ankle"], "knee":["ankle"], "ankle":[]}
	for joint in descendants[selected_joint]:
		pose[joint] += change
	_commit_selected_keyframe()
	queue_redraw()

func _move_joint_from_ground(target: Vector2) -> void:
	var parent_by_joint := {"knee":"ankle", "hip":"knee", "shoulder":"hip"}
	if not parent_by_joint.has(selected_joint):
		return
	var parent: String = parent_by_joint[selected_joint]
	var old_position: Vector2 = pose[selected_joint]
	var parent_position: Vector2 = pose[parent]
	var bone_length := old_position.distance_to(parent_position)
	var direction := (target - parent_position).normalized()
	if direction == Vector2.ZERO:
		return
	var constrained := parent_position + direction * bone_length
	var change := constrained - old_position
	if change == Vector2.ZERO:
		return
	_begin_pose_edit()
	pose[selected_joint] = constrained
	var descendants := {"knee":["hip","shoulder","hand","head"], "hip":["shoulder","hand","head"], "shoulder":["hand","head"]}
	for joint in descendants[selected_joint]:
		pose[joint] += change
	pose.ankle.y = AuthoredSkills.FLOOR_Y
	_commit_selected_keyframe()
	queue_redraw()

func _ankle_on_floor(target: Vector2, knee: Vector2, shin_length: float) -> Vector2:
	var vertical := AuthoredSkills.FLOOR_Y - knee.y
	var horizontal_squared := shin_length * shin_length - vertical * vertical
	if horizontal_squared <= 0.0:
		return Vector2(target.x, AuthoredSkills.FLOOR_Y)
	var horizontal := sqrt(horizontal_squared)
	var left := knee.x - horizontal
	var right := knee.x + horizontal
	return Vector2(left if absf(target.x - left) < absf(target.x - right) else right, AuthoredSkills.FLOOR_Y)

func _commit_selected_keyframe() -> void:
	if selected_keyframe >= 0 and selected_keyframe < skill.keyframes.size():
		skill.keyframes[selected_keyframe].pose = pose.duplicate(true)

func _begin_pose_edit() -> void:
	if not pose_edit_transaction:
		pose_edit_transaction = true
		pose_edit_started.emit()

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
		if skill.get("playback_profile", "linear") == "linear" and (not playing or skill_time >= float(skill.duration)):
			queued_skill = requested
			_transition_from_completed_skill()
			return "%s restarted" % requested.name
	if skill.get("playback_profile", "linear") == "linear":
		queued_skill = requested
		queued_cycle = -1
		if not playing or skill_time >= float(skill.duration):
			_transition_from_completed_skill()
			return "%s started" % requested.name
		return "%s queued after %s" % [requested.name, skill.name]
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
	if editor_mode and show_ghosts:
		for index in range(skill.keyframes.size()):
			if index != selected_keyframe or playing:
				_draw_pose(skill.keyframes[index].pose, 0.15)
	_draw_pose(pose, 1.0)
	if editor_mode and selected_joint != "":
		draw_circle(pose[selected_joint], 12.0, Color(0.45, 0.87, 0.97, 0.35))
		draw_arc(pose[selected_joint], 12.0, 0.0, TAU, 24, Color("#72ddf7"), 2.5, true)
	if editor_mode and transform_mode:
		_draw_transform_gizmo()
	# Edge-on bar overlay remains in front of the grip, exactly as in renderer.ts.
	_draw_stroked_circle(AuthoredSkills.HIGH_BAR, 9.0, BAR, BAR_STROKE, 3.0)
	# In side view the attached hand and bar occupy the same point, so a small
	# green grip centre communicates attachment without a separate editor flag.
	if pose.hand.distance_to(AuthoredSkills.HIGH_BAR) <= BAR_ATTACHED_DISTANCE:
		draw_circle(AuthoredSkills.HIGH_BAR, 4.0, ATTACHED_HAND)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_pose(draw_pose: Dictionary, opacity: float) -> void:
	var bone_color := _with_opacity(BONE, opacity)
	var joint_color := _with_opacity(JOINT, opacity)
	var attached: bool = Vector2(draw_pose.hand).distance_to(AuthoredSkills.HIGH_BAR) <= BAR_ATTACHED_DISTANCE
	var grounded: bool = absf(float(draw_pose.ankle.y) - AuthoredSkills.FLOOR_Y) <= BAR_ATTACHED_DISTANCE
	var hand_color := _with_opacity(ATTACHED_HAND if attached else HAND, opacity)
	var foot_color := _with_opacity(GROUNDED_FOOT if grounded else JOINT, opacity)
	# Head is behind the articulated chain so the near arm crosses in front.
	_draw_stroked_circle(draw_pose.head, 17.0, joint_color, bone_color, 4.0)
	for bone in AuthoredSkills.CHAIN:
		_draw_round_line(draw_pose[bone[0]], draw_pose[bone[1]], bone_color, 13.0)
	for joint_name in ["hand", "shoulder", "hip", "knee", "ankle"]:
		if joint_name == "hand":
			_draw_stroked_circle(draw_pose[joint_name], 7.0, hand_color, joint_color, 3.0)
		elif joint_name == "ankle":
			_draw_stroked_circle(draw_pose[joint_name], 7.0, foot_color, bone_color, 4.0)
		else:
			_draw_stroked_circle(draw_pose[joint_name], 7.0, joint_color, bone_color, 4.0)

func _draw_transform_gizmo() -> void:
	var center := _transform_center()
	var rotate_handle := _rotation_handle_position()
	var color := Color("#72ddf7")
	draw_line(center, rotate_handle, Color(color.r, color.g, color.b, 0.6), 2.0, true)
	# Four-way move control.
	draw_rect(Rect2(center - Vector2(9, 9), Vector2(18, 18)), Color(0.08, 0.16, 0.25, 0.9), true)
	draw_rect(Rect2(center - Vector2(9, 9), Vector2(18, 18)), color, false, 2.0)
	draw_line(center - Vector2(13, 0), center + Vector2(13, 0), color, 2.0, true)
	draw_line(center - Vector2(0, 13), center + Vector2(0, 13), color, 2.0, true)
	# Circular rotation control with a small tangent arrowhead.
	draw_circle(rotate_handle, 10.0, Color(0.08, 0.16, 0.25, 0.9))
	draw_arc(rotate_handle, 9.0, 0.35, TAU - 0.35, 24, color, 2.5, true)
	draw_colored_polygon(PackedVector2Array([rotate_handle + Vector2(8, -5), rotate_handle + Vector2(13, -2), rotate_handle + Vector2(8, 1)]), color)

func _with_opacity(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * opacity)

func _draw_round_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color)
	draw_circle(to, width * 0.5, color)

func _draw_stroked_circle(center: Vector2, radius: float, fill: Color, stroke: Color, width: float) -> void:
	draw_circle(center, radius + width * 0.5, stroke)
	draw_circle(center, radius - width * 0.5, fill)
