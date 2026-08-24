class_name StickScoring
extends RefCounted

# Prototype D-score model. The policy is intentionally small and data-driven:
# up to ten distinct completed elements count, plus one 0.5 requirement bonus
# for each represented element group. Skill JSON can override both fields.
const MAX_COUNTING_ELEMENTS := 10
const GROUP_BONUS := 0.5
const DIFFICULTY_LETTERS := "ABCDEFGHIJ"
const GROUP_NAMES := {
	"I":"LONG HANG SWINGS / TURNS",
	"II":"FLIGHT",
	"III":"IN-BAR / ADLER",
	"IV":"DISMOUNTS",
}

var completed_ids: Dictionary = {}
var counting_elements: Array[Dictionary] = []

func reset() -> void:
	completed_ids.clear()
	counting_elements.clear()

func record_completed_skill(skill: Dictionary) -> bool:
	var id: String = str(skill.get("id", ""))
	var difficulty: float = float(skill.get("difficulty", 0.0))
	if id.is_empty() or difficulty <= 0.0 or completed_ids.has(id):
		return false
	completed_ids[id] = true
	counting_elements.append({
		"id":id,
		"name":str(skill.get("name", id)),
		"difficulty":difficulty,
		"group":str(skill.get("element_group", "—")),
	})
	if counting_elements.size() > MAX_COUNTING_ELEMENTS:
		var lowest_index := 0
		for index in range(1, counting_elements.size()):
			if float(counting_elements[index].difficulty) < float(counting_elements[lowest_index].difficulty):
				lowest_index = index
		counting_elements.remove_at(lowest_index)
	return true

func difficulty_total() -> float:
	var total := 0.0
	for element in counting_elements:
		total += float(element.difficulty)
	return total

func represented_groups() -> Array[String]:
	var result: Array[String] = []
	for element in counting_elements:
		var group: String = str(element.group)
		if group != "—" and not result.has(group):
			result.append(group)
	result.sort()
	return result

func group_bonus_total() -> float:
	return float(represented_groups().size()) * GROUP_BONUS

func d_score() -> float:
	return difficulty_total() + group_bonus_total()

static func difficulty_letter(difficulty: float) -> String:
	if difficulty <= 0.0:
		return "—"
	var index: int = clampi(roundi(difficulty * 10.0) - 1, 0, DIFFICULTY_LETTERS.length() - 1)
	return DIFFICULTY_LETTERS.substr(index, 1)

static func group_name(group: String) -> String:
	return str(GROUP_NAMES.get(group, "UNASSIGNED"))
