class_name StickGymnast
extends Node2D

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

func _ready() -> void:
	pose = AuthoredSkills.sample_skill(skill, 0.0)
	queue_redraw()

func _process(delta: float) -> void:
	if playing:
		# Direct port: fast through bottom, slow and measured near handstand.
		var bottom_speed_bias := 0.38 + 0.82 * ((1.0 + cos(skill_time)) / 2.0)
		var tap_drive := 0.85 + 0.45 * maxf(0.0, sin(skill_time)) if skill.id == "tap_giant" else 1.0
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
				var target_pose := AuthoredSkills.sample_skill(queued_skill, local_time)
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
	skill_time = 0.0
	playing = true
	queued_skill = {}
	queued_cycle = -1
	pose = AuthoredSkills.sample_skill(skill, skill_time)
	queue_redraw()

func queue_move(id: String) -> String:
	var requested := AuthoredSkills.tap_giant() if id == "tap_giant" else AuthoredSkills.normal_giant()
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
	# Head is behind the articulated chain so the near arm crosses in front.
	_draw_stroked_circle(pose.head, 17.0, JOINT, BONE, 4.0)
	for bone in AuthoredSkills.CHAIN:
		_draw_round_line(pose[bone[0]], pose[bone[1]], BONE, 13.0)
	for joint_name in ["hand", "shoulder", "hip", "knee", "ankle"]:
		var radius := 7.0
		if joint_name == "hand":
			_draw_stroked_circle(pose[joint_name], radius, HAND, JOINT, 3.0)
		else:
			_draw_stroked_circle(pose[joint_name], radius, JOINT, BONE, 4.0)
	# Edge-on bar overlay remains in front of the grip, exactly as in renderer.ts.
	_draw_stroked_circle(AuthoredSkills.HIGH_BAR, 9.0, BAR, BAR_STROKE, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_round_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color)
	draw_circle(to, width * 0.5, color)

func _draw_stroked_circle(center: Vector2, radius: float, fill: Color, stroke: Color, width: float) -> void:
	draw_circle(center, radius + width * 0.5, stroke)
	draw_circle(center, radius - width * 0.5, fill)
