extends Control

const PIXELS_PER_SECOND := 52.0
const STRIP_TOP := 38.0
const STRIP_HEIGHT := 46.0
const PLAYHEAD_COLOR := Color("#fff1b8")

var moves: Array[Dictionary] = []
var current_index := 0
var move_progress := 0.0
var phase := "READY"
var elapsed := 0.0
var limit := 60.0

func set_performance(
	new_moves: Array[Dictionary],
	new_current_index: int,
	new_move_progress: float,
	new_phase: String,
	new_elapsed: float,
	new_limit: float
) -> void:
	moves = new_moves
	current_index = clampi(new_current_index, 0, maxi(0, moves.size() - 1))
	move_progress = clampf(new_move_progress, 0.0, 1.0)
	phase = new_phase
	elapsed = new_elapsed
	limit = new_limit
	queue_redraw()

func _draw() -> void:
	if moves.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var playhead_x := size.x * 0.5
	# Compact opaque strip beneath the apparatus, kept visually separate from
	# the gymnast while retaining the fixed playhead and authored input markers.
	draw_rect(Rect2(0, STRIP_TOP - 9.0, size.x, STRIP_HEIGHT + 18.0), Color("#091523"))
	draw_string(font, Vector2(6, 15), "← ROUTINE", HORIZONTAL_ALIGNMENT_LEFT, 100, 11, Color("#7895ad"))

	# At progress zero, the current move's leading edge sits exactly on NOW.
	# Thereafter the complete strip translates continuously beneath the fixed line.
	var current_time := 0.0
	for index in range(current_index):
		current_time += _move_duration(moves[index])
	current_time += _move_duration(moves[current_index]) * move_progress
	var strip_origin := playhead_x - current_time * PIXELS_PER_SECOND
	var frame_x := strip_origin
	for index in range(moves.size()):
		var frame_width := _move_duration(moves[index]) * PIXELS_PER_SECOND
		_draw_move_frame(index, frame_x, frame_width, font)
		_draw_input_markers(index, frame_x, frame_width, font)
		frame_x += frame_width

	# The playhead is deliberately drawn last and never changes position.
	draw_rect(Rect2(playhead_x - 2.0, STRIP_TOP - 11.0, 4.0, STRIP_HEIGHT + 22.0), Color("#07111d"))
	draw_line(Vector2(playhead_x, STRIP_TOP - 13.0), Vector2(playhead_x, STRIP_TOP + STRIP_HEIGHT + 13.0), PLAYHEAD_COLOR, 2.0, true)
	var marker := PackedVector2Array([
		Vector2(playhead_x - 7.0, STRIP_TOP - 13.0),
		Vector2(playhead_x + 7.0, STRIP_TOP - 13.0),
		Vector2(playhead_x, STRIP_TOP - 5.0),
	])
	draw_colored_polygon(marker, PLAYHEAD_COLOR)
	draw_string(font, Vector2(playhead_x - 34.0, size.y - 5.0), "NOW", HORIZONTAL_ALIGNMENT_CENTER, 68, 12, PLAYHEAD_COLOR)

func _draw_move_frame(index: int, x: float, frame_width: float, font: Font) -> void:
	if x + frame_width < 0.0 or x > size.x:
		return
	var move: Dictionary = moves[index]
	var fill := Color("#14263a")
	var border := Color("#52718a")
	var frame_rect := Rect2(x + 2.0, STRIP_TOP, maxf(1.0, frame_width - 4.0), STRIP_HEIGHT)
	draw_rect(frame_rect, fill)
	draw_rect(frame_rect, border, false, 1.0)
	var text_width := maxf(1.0, frame_width - 18.0)
	var name := str(move.get("name", "Move")).to_upper()
	_draw_move_name(font, name, x + 9.0, text_width)

func _draw_move_name(font: Font, name: String, x: float, available_width: float) -> void:
	var font_size := 12
	var lines: Array[String] = [name]
	var words := name.split(" ", false)
	if words.size() > 1:
		var best_split := 1
		var best_width := INF
		for split in range(1, words.size()):
			var left := " ".join(words.slice(0, split))
			var right := " ".join(words.slice(split))
			var widest := maxf(font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
			if widest < best_width:
				best_width = widest
				best_split = split
		lines = [" ".join(words.slice(0, best_split)), " ".join(words.slice(best_split))]
	while font_size > 7:
		var widest_line := 0.0
		for line in lines:
			widest_line = maxf(widest_line, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		if widest_line <= available_width:
			break
		font_size -= 1
	if lines.size() == 1:
		draw_string(font, Vector2(x, STRIP_TOP + 29.0), lines[0], HORIZONTAL_ALIGNMENT_CENTER, available_width, font_size, Color("#dcecff"))
	else:
		draw_string(font, Vector2(x, STRIP_TOP + 21.0), lines[0], HORIZONTAL_ALIGNMENT_CENTER, available_width, font_size, Color("#dcecff"))
		draw_string(font, Vector2(x, STRIP_TOP + 35.0), lines[1], HORIZONTAL_ALIGNMENT_CENTER, available_width, font_size, Color("#dcecff"))

func _draw_input_markers(index: int, x: float, _frame_width: float, font: Font) -> void:
	var move: Dictionary = moves[index]
	var points: Array = move.get("judgement_points", [])
	var frames: Array = move.get("keyframes", [])
	if points.is_empty() or frames.is_empty():
		return
	var duration := _move_duration(move)
	var local_time := duration * move_progress if index == current_index else (duration if index < current_index else 0.0)
	var first_unpassed := -1
	for point_index in range(points.size()):
		var point: Dictionary = points[point_index]
		var keyframe_index := clampi(int(point.get("keyframe", 0)), 0, frames.size() - 1)
		var target_time := clampf(float(frames[keyframe_index].get("time", 0.0)), 0.0, duration)
		if first_unpassed < 0 and index == current_index and target_time >= local_time - 0.02:
			first_unpassed = point_index
	for point_index in range(points.size()):
		var point: Dictionary = points[point_index]
		var keyframe_index := clampi(int(point.get("keyframe", 0)), 0, frames.size() - 1)
		var target_time := clampf(float(frames[keyframe_index].get("time", 0.0)), 0.0, duration)
		var marker_x := x + target_time * PIXELS_PER_SECOND
		if marker_x < -45.0 or marker_x > size.x + 45.0:
			continue
		var passed := index < current_index or (index == current_index and local_time > target_time + 0.02)
		var active := index == current_index and point_index == first_unpassed and phase == "ACTION NOW"
		var marker_color := Color("#526d82") if passed else Color("#ffdc8a")
		var radius := 4.5
		if active:
			marker_color = Color("#ff6f6f")
			radius = 6.0 + sin(elapsed * 9.0) * 1.2
		draw_line(Vector2(marker_x, STRIP_TOP - 4.0), Vector2(marker_x, STRIP_TOP + 7.0), marker_color, 1.5, true)
		draw_circle(Vector2(marker_x, STRIP_TOP - 8.0), radius, marker_color)
		draw_circle(Vector2(marker_x, STRIP_TOP - 8.0), maxf(1.5, radius - 2.5), Color("#091523"))
		var role := str(point.get("role", "INPUT")).to_upper()
		if role == "LAND":
			role = "STICK"
		draw_string(font, Vector2(marker_x - 38.0, STRIP_TOP - 17.0), role, HORIZONTAL_ALIGNMENT_CENTER, 76.0, 10, marker_color)

func _move_duration(move: Dictionary) -> float:
	return maxf(0.01, float(move.get("duration", 1.0)))
