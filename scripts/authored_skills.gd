class_name AuthoredSkills
extends RefCounted

# Faithful port of the TypeScript GME movement representation. A pose is six
# joint positions; playback interpolates articulated bone angles, not raw XY.
const GIANT_DURATION := TAU
const HIGH_BAR := Vector2(500.0, 255.0)
const ARM := 65.0
const TORSO := 80.0
const THIGH := 65.0
const SHIN := 65.0
const HEAD_OFFSET := 20.0
const HEAD_LENGTH := 21.1896201 # sqrt(HEAD_OFFSET² + the renderer's 7px side offset²)
const FLOOR_Y := 545.0
const CHAIN := [["hand", "shoulder"], ["shoulder", "hip"], ["hip", "knee"], ["knee", "ankle"]]
const REVERSE_CHAIN := [["ankle", "knee"], ["knee", "hip"], ["hip", "shoulder"], ["shoulder", "hand"]]
const BUILTIN_PATHS := [
	"res://skills/normal_giant.stick.json",
	"res://skills/tap_giant.stick.json",
	"res://skills/layout_back.stick.json",
]

static func normal_giant() -> Dictionary:
	return load_skill(BUILTIN_PATHS[0])

static func tap_giant() -> Dictionary:
	return load_skill(BUILTIN_PATHS[1])

static func layout_back_dismount() -> Dictionary:
	return load_skill(BUILTIN_PATHS[2])

static func builtin_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var loaded_paths: Array[String] = []
	for path in BUILTIN_PATHS:
		result.append(load_skill(path))
		loaded_paths.append(path)
	var discovered := DirAccess.get_files_at("res://skills")
	discovered.sort()
	for file_name in discovered:
		if not file_name.ends_with(".stick.json"):
			continue
		var path := "res://skills/%s" % file_name
		if path not in loaded_paths:
			var move := load_skill(path)
			if not move.is_empty():
				result.append(move)
	return result

static func load_skill(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open skill: %s" % path)
		return _create_giant_skill("normal_giant", "Normal giant", false)
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("format", "") != "stick-skill":
		push_error("Invalid Stick! skill: %s" % path)
		return _create_giant_skill("normal_giant", "Normal giant", false)
	if parsed.has("generator"):
		var generator: Dictionary = parsed.generator
		if generator.type == "giant":
			return _create_giant_skill(str(parsed.id), str(parsed.name), generator.get("variant", "normal") == "tap")
		if generator.type == "layout_back":
			return _create_layout_back()
	return _skill_from_file_data(parsed)

static func skill_to_json(skill: Dictionary) -> String:
	var frames: Array[Dictionary] = []
	for frame in skill.keyframes:
		var joints := {}
		for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
			var point: Vector2 = frame.pose[joint]
			joints[joint] = {"x":point.x, "y":point.y}
		frames.append({"time":frame.time, "label":frame.get("label", ""), "pose":{"joints":joints}})
	var data := {"format":"stick-skill", "version":1, "id":skill.id, "name":skill.name,
		"move_class":skill.get("move_class", "swing"), "duration":skill.duration, "loop":skill.loop, "entry_state":skill.entry_state,
		"exit_state":skill.exit_state, "playback_profile":skill.get("playback_profile", "linear"), "keyframes":frames}
	return JSON.stringify(data, "  ")

static func new_skill(name: String, base_pose: Dictionary) -> Dictionary:
	var safe_id := name.to_lower().strip_edges().replace(" ", "_")
	return {"id":safe_id, "name":name, "move_class":"swing", "duration":1.0, "loop":false,
		"entry_state":"custom", "exit_state":"custom", "playback_profile":"linear",
		"keyframes":[{"time":0.0, "label":"Start", "pose":base_pose.duplicate(true)},
			{"time":1.0, "label":"Finish", "pose":base_pose.duplicate(true)}]}

static func _skill_from_file_data(data: Dictionary) -> Dictionary:
	var frames: Array[Dictionary] = []
	for source_frame in data.get("keyframes", []):
		var pose := {}
		var joint_names := ["hand", "shoulder", "hip", "knee", "ankle", "head"]
		if source_frame.has("joints"):
			for index in range(joint_names.size()):
				var point: Array = source_frame.joints[index]
				pose[joint_names[index]] = Vector2(float(point[0]), float(point[1]))
		else:
			var joints: Dictionary = source_frame.pose.joints
			for joint in joint_names:
				pose[joint] = Vector2(float(joints[joint].x), float(joints[joint].y))
		frames.append({"time":float(source_frame.time), "label":str(source_frame.get("label", "")), "pose":normalize_pose(pose)})
	frames.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var inferred_profile := "tap_giant" if str(data.id).begins_with("tap_giant") else ("giant" if str(data.id).begins_with("normal_giant") else "linear")
	var inferred_class := "dismount" if str(data.id) == "layout_back" or str(data.get("exit_state", "")) == "landed" else ("release" if str(data.id) == "kovacs" else "swing")
	var move_class := str(data.get("move_class", inferred_class))
	return {"id":str(data.id), "name":str(data.name), "move_class":move_class, "duration":float(data.duration),
		"loop":bool(data.loop) and move_class != "release", "entry_state":str(data.get("entry_state", "custom")),
		"exit_state":str(data.get("exit_state", "custom")),
		"playback_profile":str(data.get("playback_profile", inferred_profile)), "keyframes":frames}

static func _create_layout_back() -> Dictionary:
	var frames: Array[Dictionary] = []
	frames.append({"time":0.0, "label":"Bottom", "pose":_reference_giant_pose(0.0, false)})
	frames.append({"time":0.28, "label":"Dismount swing", "pose":_reference_giant_pose(0.55, false)})
	var release_pose := _reference_giant_pose(1.05, false)
	frames.append({"time":0.52, "label":"Release", "pose":release_pose})
	var start_hip: Vector2 = release_pose.hip
	var finish_hip := Vector2(280.0, 415.0)
	var start_angle := (Vector2(release_pose.shoulder) - Vector2(release_pose.hand)).angle()
	var finish_angle := PI / 2.0 - TAU
	for index in range(1, 8):
		var progress := float(index) / 7.0
		var travel := smoothstep(0.0, 1.0, progress)
		var hip := _bezier(start_hip, start_hip + Vector2(-125, -165), finish_hip + Vector2(105, -205), finish_hip, travel)
		var body_angle := lerpf(start_angle, finish_angle, travel)
		frames.append({"time":0.52 + progress * 1.45, "label":"Layout flight", "pose":_layout_pose(hip, body_angle)})
	# A short held landing makes completion readable before later Stick! timing.
	frames.append({"time":2.18, "label":"Landing", "pose":_layout_pose(finish_hip, PI / 2.0)})
	return {"id":"layout_back", "name":"Layout back dismount", "move_class":"dismount", "duration":2.18, "loop":false,
		"entry_state":"long_hang_forward", "exit_state":"landed", "playback_profile":"linear", "keyframes":frames}

static func _create_giant_skill(id: String, name: String, is_tap: bool) -> Dictionary:
	var frames: Array[Dictionary] = []
	var labels := ["Bottom", "Rising low", "Rising", "Quarter", "Approaching handstand", "Handstand approach", "Handstand", "Descending high", "Descending", "Quarter", "Descending low", "Bottom approach"]
	for index in range(12):
		var time := GIANT_DURATION * float(index) / 12.0
		frames.append({"time": time, "label": labels[index], "pose": _reference_giant_pose(time, is_tap)})
	return {"id":id, "name":name, "move_class":"swing", "duration":GIANT_DURATION, "loop":true,
		"entry_state":"long_hang_forward", "exit_state":"long_hang_forward",
		"playback_profile":"tap_giant" if is_tap else "giant", "keyframes":frames}

static func sample_skill(skill: Dictionary, time: float) -> Dictionary:
	var duration: float = skill.duration
	var local_time := fposmod(time, duration) if skill.loop else clampf(time, 0.0, duration)
	var frames: Array = skill.keyframes
	var next_index := -1
	for index in range(frames.size()):
		if float(frames[index].time) > local_time:
			next_index = index
			break
	if not skill.loop and next_index == -1:
		return interpolate_pose(frames[-1].pose, frames[-1].pose, 0.0)
	var wraps_after_last := next_index == -1
	var wraps_before_first := next_index == 0
	var wraps := wraps_after_last or wraps_before_first
	var previous: Dictionary = frames[-1] if wraps else frames[next_index - 1]
	var next: Dictionary = frames[0] if wraps else frames[next_index]
	# The TypeScript prototype offset both ends of the final→first interval,
	# making interpolation jump to ~92% at the last keyframe. Represent the
	# wrap as one ordinary keyframe span so it begins at 0% and reaches 100%.
	var previous_time := float(previous.time) - duration if wraps_before_first else float(previous.time)
	var next_time := float(next.time) + duration if wraps_after_last else float(next.time)
	var evaluation_time := local_time + duration if wraps_before_first else local_time
	var span := next_time - previous_time
	return interpolate_pose(previous.pose, next.pose, 0.0 if span == 0.0 else (evaluation_time - previous_time) / span)

static func _reference_giant_pose(time: float, is_tap: bool) -> Dictionary:
	var phase := -time
	var radial := Vector2(sin(phase), cos(phase))
	var tangent := Vector2(cos(phase), -sin(phase))
	var tap_phase := fposmod(time, GIANT_DURATION)
	var upswing := maxf(0.0, sin(tap_phase)) if is_tap else 0.0
	var downswing := maxf(0.0, -sin(tap_phase)) if is_tap else 0.0
	var arch_amount := (1.0 + cos(tap_phase)) / 2.0 if is_tap else 0.0
	var shoulder_flex := -(downswing * 0.42 + upswing * 0.6)
	var hip_flex := -(downswing * 0.38 + upswing * 0.95 - arch_amount * 0.26)
	var torso_direction := radial * cos(shoulder_flex) + tangent * sin(shoulder_flex)
	var shape := 9.0 * sin(phase - 0.35) - arch_amount * 22.0
	var shoulder := HIGH_BAR + radial * ARM
	var hip := shoulder + torso_direction * TORSO + tangent * shape
	var knee_bend := shoulder_flex + hip_flex + (0.0 if is_tap else sin(phase + 0.7) * 0.12)
	var ankle_bend := shoulder_flex + hip_flex * 0.82 + (0.0 if is_tap else sin(phase + 0.2) * 0.05)
	var knee_direction := radial * cos(knee_bend) + tangent * sin(knee_bend)
	var ankle_direction := radial * cos(ankle_bend) + tangent * sin(ankle_bend)
	var knee := hip + knee_direction * THIGH
	return {"hand":HIGH_BAR, "shoulder":shoulder, "hip":hip, "knee":knee,
		"ankle":knee + ankle_direction * SHIN, "head":shoulder - radial * HEAD_OFFSET + tangent * 7.0}

static func _layout_pose(hip: Vector2, body_angle: float) -> Dictionary:
	var direction := Vector2.from_angle(body_angle)
	var normal := Vector2(-direction.y, direction.x)
	var shoulder := hip - direction * TORSO
	var hand := shoulder - direction * ARM
	var knee := hip + direction * THIGH
	return {"hand":hand, "shoulder":shoulder, "hip":hip, "knee":knee,
		"ankle":knee + direction * SHIN, "head":shoulder - direction * HEAD_OFFSET + normal * 7.0}

static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, amount: float) -> Vector2:
	var inverse := 1.0 - amount
	return a * inverse * inverse * inverse + b * 3.0 * inverse * inverse * amount + c * 3.0 * inverse * amount * amount + d * amount * amount * amount

static func interpolate_pose(from: Dictionary, to: Dictionary, amount: float) -> Dictionary:
	var from_attached: bool = Vector2(from.hand).distance_to(HIGH_BAR) <= 6.0
	var to_attached: bool = Vector2(to.hand).distance_to(HIGH_BAR) <= 6.0
	var from_grounded: bool = not from_attached and absf(float(from.ankle.y) - FLOOR_Y) <= 6.0
	var to_grounded: bool = not to_attached and absf(float(to.ankle.y) - FLOOR_Y) <= 6.0
	if from_attached and to_attached:
		return _interpolate_chain(from, to, amount, CHAIN, "hand")
	if from_grounded and to_grounded:
		return _interpolate_chain(from, to, amount, REVERSE_CHAIN, "ankle")
	return _interpolate_from_hip(from, to, amount)

static func normalize_pose(source: Dictionary) -> Dictionary:
	# Sampling a pose against itself preserves all authored joint angles and its
	# appropriate hand/foot/hip anchor while restoring canonical bone lengths.
	return interpolate_pose(source, source, 0.0)

static func _interpolate_chain(from: Dictionary, to: Dictionary, amount: float, chain: Array, root: String) -> Dictionary:
	var result := {root: Vector2(from[root]).lerp(Vector2(to[root]), amount)}
	for bone in chain:
		var parent: String = bone[0]
		var child: String = bone[1]
		result[child] = _interpolated_child(result[parent], from[parent], from[child], to[parent], to[child], amount, _bone_length(parent, child))
	_interpolate_head(result, from, to, amount)
	return result

static func _interpolate_from_hip(from: Dictionary, to: Dictionary, amount: float) -> Dictionary:
	var result := {"hip":Vector2(from.hip).lerp(Vector2(to.hip), amount)}
	result.knee = _interpolated_child(result.hip, from.hip, from.knee, to.hip, to.knee, amount, THIGH)
	result.ankle = _interpolated_child(result.knee, from.knee, from.ankle, to.knee, to.ankle, amount, SHIN)
	result.shoulder = _interpolated_child(result.hip, from.hip, from.shoulder, to.hip, to.shoulder, amount, TORSO)
	result.hand = _interpolated_child(result.shoulder, from.shoulder, from.hand, to.shoulder, to.hand, amount, ARM)
	_interpolate_head(result, from, to, amount)
	return result

static func _interpolated_child(parent_result: Vector2, from_parent: Vector2, from_child: Vector2, to_parent: Vector2, to_child: Vector2, amount: float, fixed_length: float) -> Vector2:
	var from_vector := from_child - from_parent
	var to_vector := to_child - to_parent
	var angle := from_vector.angle() + _shortest_angle_delta(from_vector.angle(), to_vector.angle()) * amount
	return parent_result + Vector2.from_angle(angle) * fixed_length

static func _interpolate_head(result: Dictionary, from: Dictionary, to: Dictionary, amount: float) -> void:
	var from_head: Vector2 = from.head - from.shoulder
	var to_head: Vector2 = to.head - to.shoulder
	var head_angle := from_head.angle() + _shortest_angle_delta(from_head.angle(), to_head.angle()) * amount
	result.head = result.shoulder + Vector2.from_angle(head_angle) * HEAD_LENGTH

static func _bone_length(parent: String, child: String) -> float:
	if (parent == "hand" and child == "shoulder") or (parent == "shoulder" and child == "hand"):
		return ARM
	if (parent == "shoulder" and child == "hip") or (parent == "hip" and child == "shoulder"):
		return TORSO
	if (parent == "hip" and child == "knee") or (parent == "knee" and child == "hip"):
		return THIGH
	return SHIN

static func _shortest_angle_delta(from: float, to: float) -> float:
	var delta := to - from
	while delta > PI:
		delta -= TAU
	while delta < -PI:
		delta += TAU
	return delta
