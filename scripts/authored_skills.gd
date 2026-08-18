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

static func normal_giant() -> Dictionary:
	return _create_giant_skill("normal_giant", "Normal giant", false)

static func tap_giant() -> Dictionary:
	return _create_giant_skill("tap_giant", "Tap giant", true)

static func _create_giant_skill(id: String, name: String, is_tap: bool) -> Dictionary:
	var frames: Array[Dictionary] = []
	var labels := ["Bottom", "Rising low", "Rising", "Quarter", "Approaching handstand", "Handstand approach", "Handstand", "Descending high", "Descending", "Quarter", "Descending low", "Bottom approach"]
	for index in range(12):
		var time := GIANT_DURATION * float(index) / 12.0
		frames.append({"time": time, "label": labels[index], "pose": _reference_giant_pose(time, is_tap)})
	return {"id":id, "name":name, "duration":GIANT_DURATION, "loop":true,
		"entry_state":"long_hang_forward", "exit_state":"long_hang_forward", "keyframes":frames}

static func sample_skill(skill: Dictionary, time: float) -> Dictionary:
	var duration: float = skill.duration
	var local_time := fposmod(time, duration) if skill.loop else clampf(time, 0.0, duration)
	var frames: Array = skill.keyframes
	var next_index := -1
	for index in range(frames.size()):
		if float(frames[index].time) > local_time:
			next_index = index
			break
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
