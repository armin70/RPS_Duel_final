class_name  CardGesture
extends RefCounted

enum Type {
	ROCK,
	PAPER,
	SCISSORS,
	DIV
}


static func can_cover(
	new_gesture: Type,
	old_gesture: Type
) -> bool:
	match new_gesture:
		Type.ROCK:
			return old_gesture == Type.SCISSORS

		Type.PAPER:
			return old_gesture == Type.ROCK

		Type.SCISSORS:
			return old_gesture == Type.PAPER

	return false
