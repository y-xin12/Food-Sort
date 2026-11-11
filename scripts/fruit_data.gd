## Registry of fruit types. Matching works on these IDs only; the colors
## here are placeholder visuals, so the circles can be replaced with real
## artwork later without touching the board rules.
class_name FruitData
extends RefCounted

const APPLE := "apple"
const ORANGE := "orange"
const BANANA := "banana"

const ALL := [APPLE, ORANGE, BANANA]

const COLORS := {
	APPLE: Color(0.85, 0.18, 0.15),
	ORANGE: Color(0.95, 0.53, 0.13),
	BANANA: Color(0.96, 0.81, 0.22),
}

const OUTLINE_COLORS := {
	APPLE: Color(0.62, 0.09, 0.07),
	ORANGE: Color(0.72, 0.36, 0.05),
	BANANA: Color(0.76, 0.60, 0.08),
}


static func is_valid(fruit_id: String) -> bool:
	return COLORS.has(fruit_id)


static func color_of(fruit_id: String) -> Color:
	return COLORS.get(fruit_id, Color.MAGENTA)


static func outline_color_of(fruit_id: String) -> Color:
	return OUTLINE_COLORS.get(fruit_id, Color.MAGENTA)
