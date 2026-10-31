## Global enums + team helpers shared by every CALLOFBRAWL system.
##
## Loaded by scripts that need it (class_name => globally available).
class_name CBTeam
extends RefCounted

enum Id { NONE = -1, ALPHA = 0, BRAVO = 1 }

const NONE := Id.NONE
const ALPHA := Id.ALPHA
const BRAVO := Id.BRAVO

const NAMES := {
	Id.ALPHA: "TEAM ALPHA",
	Id.BRAVO: "TEAM BRAVO",
}

const SHORT_NAMES := {
	Id.ALPHA: "ALPHA",
	Id.BRAVO: "BRAVO",
}

## Comma-separated (StringName) friendly team tags used to pick the team-coloured
## fallback materials on the army character model.
const FRIENDLY_TAGS := "army, soldier, uniform, helmet, camo, olive, green, shirt, pants, glove"
const ENEMY_TAGS := "army, soldier, uniform, helmet, camo, tan, brown, desert, shirt, pants, glove"


static func name_of(team: int) -> String:
	return NAMES.get(team, "NONE")


static func short_name(team: int) -> String:
	return SHORT_NAMES.get(team, "NONE")


static func opponents(team: int) -> int:
	if team == Id.ALPHA:
		return Id.BRAVO
	if team == Id.BRAVO:
		return Id.ALPHA
	return Id.NONE


static func is_friendly(a: int, b: int) -> bool:
	return a == b and a != Id.NONE


## Chat/UI colour for a team.
static func color_of(team: int) -> Color:
	if team == Id.ALPHA:
		return Color(0.36, 0.68, 1.0)
	return Color(1.0, 0.42, 0.36)


## Uniform tint applied to the fallback character materials.
static func uniform_of(team: int) -> Color:
	if team == Id.ALPHA:
		return Color(0.30, 0.46, 0.32)
	return Color(0.52, 0.42, 0.30)
