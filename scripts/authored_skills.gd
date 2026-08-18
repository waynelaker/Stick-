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
const CHAIN := [["hand", "shoulder"], ["shoulder", "hip"], ["hip", "knee"], ["knee", "ankle"]]
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
		"duration":skill.duration, "loop":skill.loop, "entry_state":skill.entry_state,
		"exit_state":skill.exit_state, "playback_profile":skill.get("playback_profile", "linear"), "keyframes":frames}
	return JSON.stringify(data, "  ")

static func new_skill(name: String, base_pose: Dictionary) -> Dictionary:
	var safe_id := name.to_lower().strip_edges().replace(" ", "_")
	return {"id":safe_id, "name":name, "duration":1.0, "loop":false,
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
		frames.append({"time":float(source_frame.time), "label":str(source_frame.get("label", "")), "pose":pose})
	frames.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var inferred_profile := "tap_giant" if str(data.id).begins_with("tap_giant") else ("giant" if str(data.id).begins_with("normal_giant") else "linear")
	return {"id":str(data.id), "name":str(data.name), "duration":float(data.duration),
		"loop":bool(data.loop), "entry_state":str(data.get("entry_state", "custom")),
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
	return {"id":"layout_back", "name":"Layout back dismount", "duration":2.18, "loop":false,
		"entry_state":"long_hang_forward", "exit_state":"landed", "playback_profile":"linear", "keyframes":frames}

static func _create_giant_skill(id: String, name: String, is_tap: bool) -> Dictionary:
	var frames: Array[Dictionary] = []
	var labels := ["Bottom", "Rising low", "Rising", "Quarter", "Approaching handstand", "Handstand approach", "Handstand", "Descending high", "Descending", "Quarter", "Descending low", "Bottom approach"]
	for index in range(12):
		var time := GIANT_DURATION * float(index) / 12.0
		frames.append({"time": time, "label": labels[index], "pose": _reference_giant_pose(time, is_tap)})
	return {"id":id, "name":name, "duration":GIANT_DURATION, "loop":true,
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
	var result := {"hand": Vector2(from.hand).lerp(Vector2(to.hand), amount)}
	for bone in CHAIN:
		var parent: String = bone[0]
		var child: String = bone[1]
		var from_vector: Vector2 = from[child] - from[parent]
		var to_vector: Vector2 = to[child] - to[parent]
		var angle := from_vector.angle() + _shortest_angle_delta(from_vector.angle(), to_vector.angle()) * amount
		var length := lerpf(from_vector.length(), to_vector.length(), amount)
		result[child] = result[parent] + Vector2.from_angle(angle) * length
	var from_head: Vector2 = from.head - from.shoulder
	var to_head: Vector2 = to.head - to.shoulder
	var head_angle := from_head.angle() + _shortest_angle_delta(from_head.angle(), to_head.angle()) * amount
	var head_length := lerpf(from_head.length(), to_head.length(), amount)
	result.head = result.shoulder + Vector2.from_angle(head_angle) * head_length
	return result

static func _shortest_angle_delta(from: float, to: float) -> float:
	var delta := to - from
	while delta > PI:
		delta -= TAU
	while delta < -PI:
		delta += TAU
	return delta
