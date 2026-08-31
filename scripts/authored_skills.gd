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
const TRANSITION_STATES: Array[String] = ["static_hang", "swing_bottom", "handstand", "airborne", "landed", "custom"]
const GRIPS: Array[String] = ["either", "regular", "reverse", "mixed", "el_grip"]
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
			if generator.get("variant", "normal") == "forward":
				return _create_forward_giant(str(parsed.id), str(parsed.name))
			return _create_giant_skill(str(parsed.id), str(parsed.name), generator.get("variant", "normal") == "tap")
		if generator.type == "blind_change":
			return _create_blind_change(str(parsed.id), str(parsed.name))
		if generator.type == "pirouette":
			return _create_pirouette(str(parsed.id), str(parsed.name))
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
		var pose_data: Dictionary = {"joints":joints}
		for field in ["body_yaw", "arm_depth", "leg_depth", "left_hand_attached", "right_hand_attached", "left_grip", "right_grip"]:
			if frame.pose.has(field):
				pose_data[field] = frame.pose[field]
		frames.append({"time":frame.time, "label":frame.get("label", ""), "pose":pose_data})
	var data: Dictionary = {"format":"stick-skill", "version":2, "id":skill.id, "name":skill.name,
		"move_class":skill.get("move_class", "swing"), "duration":skill.duration, "loop":skill.loop, "entry_state":skill.entry_state,
		"exit_state":skill.exit_state, "entry_signature":skill.entry_signature,
		"exit_signature":skill.exit_signature, "playback_profile":skill.get("playback_profile", "linear"),
		"difficulty":float(skill.get("difficulty", 0.0)), "element_group":str(skill.get("element_group", "-")), "keyframes":frames}
	data.entry_signatures = skill.get("entry_signatures", [skill.entry_signature])
	data.execution_keyframe = clampi(int(skill.get("execution_keyframe", 0)), 0, maxi(0, frames.size() - 1))
	data.judgement_points = skill.get("judgement_points", [])
	if str(skill.get("move_class", "")) == "dismount":
		data.landing_keyframe = clampi(int(skill.get("landing_keyframe", frames.size() - 1)), 0, maxi(0, frames.size() - 1))
	if skill.has("default_follow"):
		data.default_follow = skill.default_follow
	return JSON.stringify(data, "  ")

static func new_skill(name: String, base_pose: Dictionary) -> Dictionary:
	var safe_id := name.to_lower().strip_edges().replace(" ", "_")
	return {"id":safe_id, "name":name, "move_class":"swing", "duration":1.0, "loop":false,
		"entry_state":"custom", "exit_state":"custom", "entry_signature":make_signature("custom"),
		"exit_signature":make_signature("custom"), "playback_profile":"linear", "difficulty":0.1, "element_group":"I", "execution_keyframe":1,
		"keyframes":[{"time":0.0, "label":"Start", "pose":base_pose.duplicate(true)},
			{"time":1.0, "label":"Finish", "pose":base_pose.duplicate(true)}]}

static func create_fall_skill(start_pose: Dictionary) -> Dictionary:
	var released: Dictionary = start_pose.duplicate(true)
	released.left_hand_attached = false
	released.right_hand_attached = false
	var middle: Dictionary = _fall_pose(released, 0.48, Vector2(72.0, 105.0))
	var landed: Dictionary = _fall_pose(released, 1.25, Vector2(145.0, 0.0))
	var floor_shift: float = FLOOR_Y - float(landed.ankle.y)
	for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
		landed[joint] = Vector2(landed[joint]) + Vector2(0.0, floor_shift)
	return {
		"id":"fall", "name":"Fall", "move_class":"fall", "hidden":true,
		"duration":1.15, "loop":false, "playback_profile":"linear",
		"entry_state":"airborne", "exit_state":"landed",
		"entry_signature":make_signature("airborne", "either"),
		"exit_signature":make_signature("landed", "either"),
		"difficulty":0.0, "element_group":"-", "execution_keyframe":2,
		"keyframes":[
			{"time":0.0, "label":"Miss", "pose":released},
			{"time":0.55, "label":"Falling", "pose":middle},
			{"time":1.15, "label":"Floor", "pose":landed},
		]
	}

static func create_landing_reaction(start_pose: Dictionary, deduction: float, salute_pose: Dictionary = {}) -> Dictionary:
	if deduction >= 0.99:
		var fall: Dictionary = create_fall_skill(start_pose)
		fall.id = "landing_reaction"
		fall.name = "Landing fall"
		return fall
	var base: Dictionary = start_pose.duplicate(true)
	base.left_hand_attached = false
	base.right_hand_attached = false
	var frames: Array[Dictionary] = [{"time":0.0, "label":"Contact", "pose":base}]
	var duration := 0.72
	var landing_offset := Vector2.ZERO
	if deduction >= 0.5:
		frames.append({"time":0.24, "label":"Large step", "pose":_translated_pose(base, Vector2(62.0, 0.0))})
		frames.append({"time":0.82, "label":"Settle", "pose":_translated_pose(base, Vector2(42.0, 0.0))})
		landing_offset = Vector2(42.0, 0.0)
		duration = 0.82
	elif deduction >= 0.3:
		frames.append({"time":0.2, "label":"Step", "pose":_translated_pose(base, Vector2(28.0, 0.0))})
		frames.append({"time":0.72, "label":"Return", "pose":base.duplicate(true)})
	elif deduction >= 0.1:
		var apart: Dictionary = base.duplicate(true)
		apart.body_yaw = 0.04
		apart.leg_depth = 0.12
		frames.append({"time":0.16, "label":"Feet apart", "pose":apart})
		frames.append({"time":0.62, "label":"Together", "pose":base.duplicate(true)})
		duration = 0.62
	else:
		frames.append({"time":0.55, "label":"Stick", "pose":base.duplicate(true)})
		duration = 0.55
	# Ground contact happens before the end of an authored dismount. Preserve its
	# final presentation pose (normally arms raised to the judges) after the
	# deduction-specific landing response instead of cutting those frames off.
	if not salute_pose.is_empty():
		var salute: Dictionary = salute_pose.duplicate(true)
		salute.left_hand_attached = false
		salute.right_hand_attached = false
		if landing_offset != Vector2.ZERO:
			salute = _translated_pose(salute, landing_offset)
		frames.append({"time":duration + 0.34, "label":"Salute", "pose":salute})
		frames.append({"time":duration + 0.82, "label":"Present", "pose":salute.duplicate(true)})
		duration += 0.82
	return {"id":"landing_reaction", "name":"Landing reaction", "move_class":"landing_reaction",
		"duration":duration, "loop":false, "playback_profile":"linear", "entry_state":"landed", "exit_state":"landed",
		"entry_signature":make_signature("landed", "either"), "exit_signature":make_signature("landed", "either"),
		"difficulty":0.0, "element_group":"-", "execution_keyframe":0, "judgement_points":[], "keyframes":frames}

static func _translated_pose(source: Dictionary, offset: Vector2) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
		result[joint] = Vector2(source[joint]) + offset
	return result

static func _fall_pose(source: Dictionary, rotation: float, translation: Vector2) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var pivot: Vector2 = Vector2(source.hip)
	for joint in ["hand", "shoulder", "hip", "knee", "ankle", "head"]:
		var point: Vector2 = Vector2(source[joint])
		result[joint] = pivot + (point - pivot).rotated(rotation) + translation
	result.left_hand_attached = false
	result.right_hand_attached = false
	return result

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
			for field in ["body_yaw", "arm_depth", "leg_depth", "left_hand_attached", "right_hand_attached", "left_grip", "right_grip"]:
				if source_frame.pose.has(field):
					pose[field] = source_frame.pose[field]
		frames.append({"time":float(source_frame.time), "label":str(source_frame.get("label", "")), "pose":normalize_pose(pose)})
	frames.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var inferred_profile := "tap_giant" if str(data.id).begins_with("tap_giant") else ("giant" if str(data.id).begins_with("normal_giant") else "linear")
	var inferred_class := "dismount" if str(data.id) == "layout_back" or str(data.get("exit_state", "")) == "landed" else ("release" if str(data.id) == "kovacs" else "swing")
	var move_class := str(data.get("move_class", inferred_class))
	var scoring: Dictionary = _inferred_scoring(str(data.id), move_class)
	var execution_keyframe: int = clampi(int(data.get("execution_keyframe", _inferred_execution_keyframe(frames, move_class))), 0, maxi(0, frames.size() - 1))
	var landing_keyframe: int = clampi(int(data.get("landing_keyframe", _inferred_landing_keyframe(frames))), 0, maxi(0, frames.size() - 1))
	var judgement_points: Array[Dictionary] = _judgement_points_from_data(data.get("judgement_points", []), frames, move_class, execution_keyframe, landing_keyframe)
	var entry_signature := _signature_from_data(data.get("entry_signature", {}), _inferred_transition_state(str(data.id), move_class, true))
	var entry_signatures: Array[Dictionary] = _signatures_from_data(data.get("entry_signatures", []), entry_signature)
	var exit_signature := _signature_from_data(data.get("exit_signature", {}), _inferred_transition_state(str(data.id), move_class, false))
	return {"id":str(data.id), "name":str(data.name), "move_class":move_class, "duration":float(data.duration),
		"loop":bool(data.loop) and move_class != "release", "entry_state":entry_signature.state,
		"exit_state":exit_signature.state, "entry_signature":entry_signature, "entry_signatures":entry_signatures, "exit_signature":exit_signature,
		"playback_profile":str(data.get("playback_profile", inferred_profile)),
		"default_follow":str(data.get("default_follow", "")),
		"difficulty":float(data.get("difficulty", scoring.difficulty)),
		"element_group":str(data.get("element_group", scoring.element_group)),
		"execution_keyframe":execution_keyframe, "landing_keyframe":landing_keyframe,
		"judgement_points":judgement_points, "keyframes":frames}

static func _judgement_points_from_data(source: Array, frames: Array[Dictionary], move_class: String, execution_index: int, landing_index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# A release is visually self-evident once its authored animation begins. Its
	# single gameplay input is the regrasp, so legacy RELEASE+CATCH files are
	# normalised to CATCH without requiring every skill file to be hand-edited.
	if move_class == "release":
		for point in source:
			if point is Dictionary and str(point.get("role", "")).to_upper() == "CATCH":
				result.append({"role":"CATCH", "keyframe":clampi(int(point.get("keyframe", execution_index)), 0, maxi(0, frames.size() - 1))})
				break
		if result.is_empty():
			var catch_index: int = _inferred_catch_keyframe(frames, execution_index)
			result.append({"role":"CATCH", "keyframe":catch_index if catch_index >= 0 else maxi(0, frames.size() - 1)})
		return result
	if move_class == "dismount":
		for point in source:
			if point is Dictionary and str(point.get("role", "")).to_upper() == "LAND":
				result.append({"role":"LAND", "keyframe":clampi(int(point.get("keyframe", landing_index)), 0, maxi(0, frames.size() - 1))})
				break
		if result.is_empty():
			result.append({"role":"LAND", "keyframe":landing_index})
		return result
	for point in source:
		if point is Dictionary:
			result.append({"role":str(point.get("role", "EXECUTE")).to_upper(),
				"keyframe":clampi(int(point.get("keyframe", execution_index)), 0, maxi(0, frames.size() - 1))})
	if not result.is_empty():
		result.sort_custom(func(a, b): return int(a.keyframe) < int(b.keyframe))
		return result
	if move_class == "in_bar":
		result.append({"role":"EXECUTE", "keyframe":execution_index})
	elif move_class == "swing" and _frames_contain_turn(frames):
		result.append({"role":"TURN", "keyframe":execution_index})
	return result

static func _inferred_catch_keyframe(frames: Array[Dictionary], release_index: int) -> int:
	for index in range(release_index + 1, frames.size()):
		var pose: Dictionary = frames[index].pose
		var attached: bool = bool(pose.get("left_hand_attached", Vector2(pose.hand).distance_to(HIGH_BAR) <= 6.0)) or bool(pose.get("right_hand_attached", Vector2(pose.hand).distance_to(HIGH_BAR) <= 6.0))
		if attached:
			return index
	return -1

static func _frames_contain_turn(frames: Array[Dictionary]) -> bool:
	if frames.size() < 2:
		return false
	return absf(float(frames[-1].pose.get("body_yaw", 0.0)) - float(frames[0].pose.get("body_yaw", 0.0))) > 0.25

static func _inferred_execution_keyframe(frames: Array[Dictionary], move_class: String) -> int:
	if frames.is_empty():
		return 0
	if move_class == "mount":
		return frames.size() - 1
	if move_class == "release" or move_class == "dismount":
		for index in range(frames.size()):
			var attached: bool = Vector2(frames[index].pose.hand).distance_to(HIGH_BAR) <= 6.0
			if not attached:
				return index
	return floori(float(frames.size()) / 2.0)

static func _inferred_landing_keyframe(frames: Array[Dictionary]) -> int:
	if frames.is_empty():
		return 0
	for index in range(frames.size()):
		if absf(float(frames[index].pose.ankle.y) - FLOOR_Y) <= 6.0:
			return index
	return frames.size() - 1

static func _inferred_scoring(id: String, move_class: String) -> Dictionary:
	if move_class == "mount":
		return {"difficulty":0.0, "element_group":"I"}
	if move_class == "release":
		if id == "kovacs":
			return {"difficulty":0.5, "element_group":"II"}
		if id == "tkatchev":
			return {"difficulty":0.4, "element_group":"II"}
		return {"difficulty":0.4, "element_group":"II"}
	if move_class == "in_bar":
		return {"difficulty":0.3, "element_group":"III"}
	if move_class == "dismount":
		return {"difficulty":0.3, "element_group":"IV"}
	return {"difficulty":0.1, "element_group":"I"}

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
	var release_index: int = _inferred_execution_keyframe(frames, "dismount")
	var land_index: int = _inferred_landing_keyframe(frames)
	return {"id":"layout_back", "name":"Layout back dismount", "move_class":"dismount", "duration":2.18, "loop":false,
		"entry_state":"swing_bottom", "exit_state":"landed", "entry_signature":make_signature("swing_bottom", "regular"),
		"exit_signature":make_signature("landed", "either"), "playback_profile":"linear",
		"difficulty":0.3, "element_group":"IV", "execution_keyframe":release_index,
		"landing_keyframe":land_index, "judgement_points":[{"role":"RELEASE", "keyframe":release_index}, {"role":"LAND", "keyframe":land_index}], "keyframes":frames}

static func _create_giant_skill(id: String, name: String, is_tap: bool) -> Dictionary:
	var frames: Array[Dictionary] = []
	var labels := ["Bottom", "Rising low", "Rising", "Quarter", "Approaching handstand", "Handstand approach", "Handstand", "Descending high", "Descending", "Quarter", "Descending low", "Bottom approach"]
	for index in range(12):
		var time := GIANT_DURATION * float(index) / 12.0
		frames.append({"time": time, "label": labels[index], "pose": _reference_giant_pose(time, is_tap)})
	return {"id":id, "name":name, "move_class":"swing", "duration":GIANT_DURATION, "loop":true,
		"entry_state":"swing_bottom", "exit_state":"swing_bottom", "entry_signature":make_signature("swing_bottom", "regular"),
		"exit_signature":make_signature("swing_bottom", "regular"),
		"playback_profile":"tap_giant" if is_tap else "giant", "difficulty":0.1, "element_group":"I", "execution_keyframe":6, "keyframes":frames}

static func _create_forward_giant(id: String, name: String) -> Dictionary:
	var result: Dictionary = load_skill("res://skills/normal_giant.stick.json").duplicate(true)
	result.id = id
	result.name = name
	result.loop = true
	result.entry_signature = make_signature("swing_bottom", "reverse")
	result.exit_signature = make_signature("swing_bottom", "reverse")
	result.entry_state = "swing_bottom"
	result.exit_state = "swing_bottom"
	for frame in result.keyframes:
		frame.pose.body_yaw = 1.0
		frame.pose.left_grip = "reverse"
		frame.pose.right_grip = "reverse"
	return result

static func _create_blind_change(id: String, name: String) -> Dictionary:
	# The established giant supplies the exact swing and body shapes. Only the
	# authored turn layer changes, beginning as the gymnast approaches handstand
	# and settling before the following bottom.
	var result: Dictionary = load_skill("res://skills/normal_giant.stick.json").duplicate(true)
	result.id = id
	result.name = name
	result.loop = false
	# It shares the giant's authored clock, so entry and exit retain the exact
	# established giant cadence instead of receiving release/dismount time-warp.
	result.playback_profile = "giant_authored"
	result.entry_signature = make_signature("swing_bottom", "regular")
	result.exit_signature = make_signature("swing_bottom", "reverse")
	result.entry_state = "swing_bottom"
	result.exit_state = "swing_bottom"
	result.default_follow = "forward_giant"
	var count: int = result.keyframes.size()
	for index in range(count):
		var progress: float = float(index) / float(maxi(1, count - 1))
		# Turn around the upper part of the circle, then retain the new facing.
		var yaw: float = smoothstep(0.28, 0.64, progress)
		var pose: Dictionary = result.keyframes[index].pose
		pose.body_yaw = yaw
		pose.left_grip = "reverse" if yaw >= 0.72 else "regular"
		pose.right_grip = "reverse" if yaw >= 0.38 else "regular"
		# Briefly show the turning hand leave and regrasp the edge-on bar.
		pose.right_hand_attached = not (yaw > 0.2 and yaw < 0.58)
	result.execution_keyframe = clampi(ceili(float(count - 1) * 0.28), 0, count - 1)
	result.judgement_points = [{"role":"TURN", "keyframe":result.execution_keyframe}]
	return result

static func _create_pirouette(id: String, name: String) -> Dictionary:
	# Inverse of the blind change: retain the successful giant shapes and turn
	# from the reverse-grip side silhouette back to the regular-grip silhouette.
	var result: Dictionary = load_skill("res://skills/normal_giant.stick.json").duplicate(true)
	result.id = id
	result.name = name
	result.loop = false
	result.playback_profile = "giant_authored"
	result.entry_signature = make_signature("swing_bottom", "reverse")
	result.exit_signature = make_signature("swing_bottom", "regular")
	result.entry_state = "swing_bottom"
	result.exit_state = "swing_bottom"
	result.default_follow = "normal_giant"
	var count: int = result.keyframes.size()
	for index in range(count):
		var progress: float = float(index) / float(maxi(1, count - 1))
		var turn_progress: float = smoothstep(0.28, 0.64, progress)
		var yaw: float = 1.0 - turn_progress
		var pose: Dictionary = result.keyframes[index].pose
		pose.body_yaw = yaw
		pose.left_grip = "regular" if turn_progress >= 0.72 else "reverse"
		pose.right_grip = "regular" if turn_progress >= 0.38 else "reverse"
		pose.right_hand_attached = not (turn_progress > 0.2 and turn_progress < 0.58)
	result.execution_keyframe = clampi(ceili(float(count - 1) * 0.28), 0, count - 1)
	result.judgement_points = [{"role":"TURN", "keyframe":result.execution_keyframe}]
	return result

static func make_signature(state: String, grip := "regular") -> Dictionary:
	return {"state":state, "grip":grip}

static func can_follow(exit_signature: Dictionary, entry_signature: Dictionary) -> bool:
	var state_matches := _field_matches(str(exit_signature.get("state", "custom")), str(entry_signature.get("state", "custom")))
	var grip_matches := _field_matches(str(exit_signature.get("grip", "either")), str(entry_signature.get("grip", "either")))
	return state_matches and grip_matches

static func can_skill_follow(exit_signature: Dictionary, skill: Dictionary) -> bool:
	for entry in skill.get("entry_signatures", [skill.get("entry_signature", {})]):
		if entry is Dictionary and can_follow(exit_signature, entry):
			return true
	return false

static func _field_matches(outgoing: String, incoming: String) -> bool:
	return outgoing == "either" or incoming == "either" or outgoing == incoming

static func _signature_from_data(source, fallback_state: String) -> Dictionary:
	if source is Dictionary and not source.is_empty():
		return make_signature(str(source.get("state", fallback_state)), str(source.get("grip", "regular")))
	return make_signature(fallback_state, "regular" if fallback_state not in ["landed", "airborne"] else "either")

static func _signatures_from_data(source, fallback: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source is Array:
		for item in source:
			if item is Dictionary and not item.is_empty():
				var signature := make_signature(str(item.get("state", fallback.state)), str(item.get("grip", fallback.grip)))
				if signature not in result:
					result.append(signature)
	if result.is_empty():
		result.append(fallback.duplicate(true))
	return result

static func _inferred_transition_state(id: String, move_class: String, is_entry: bool) -> String:
	if id == "start_swing":
		return "static_hang" if is_entry else "swing_bottom"
	if move_class == "mount":
		return "static_hang" if is_entry else "swing_bottom"
	if move_class == "dismount":
		return "swing_bottom" if is_entry else "landed"
	return "swing_bottom"

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
	var result: Dictionary
	if from_attached and to_attached:
		result = _interpolate_chain(from, to, amount, CHAIN, "hand")
	elif from_grounded and to_grounded:
		result = _interpolate_chain(from, to, amount, REVERSE_CHAIN, "ankle")
	else:
		result = _interpolate_from_hip(from, to, amount)
	_interpolate_pose_metadata(result, from, to, amount)
	return result

static func _interpolate_pose_metadata(result: Dictionary, from: Dictionary, to: Dictionary, amount: float) -> void:
	for field in ["body_yaw", "arm_depth", "leg_depth"]:
		var from_value: float = float(from.get(field, 0.0))
		var to_value: float = float(to.get(field, 0.0))
		if not is_zero_approx(from_value) or not is_zero_approx(to_value):
			result[field] = lerpf(from_value, to_value, amount)
	for field in ["left_hand_attached", "right_hand_attached", "left_grip", "right_grip"]:
		if from.has(field) or to.has(field):
			result[field] = from.get(field, to.get(field)) if amount < 0.5 else to.get(field, from.get(field))

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
