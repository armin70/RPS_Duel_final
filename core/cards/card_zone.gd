class_name CardZone
extends RefCounted


enum Type {
	DRAW,
	HAND,
	BOARD,
	DISCARD,
	DEALER_BOARD,
	RESERVE,
	# Rush-only terminal zone. Cards in this zone are not stored in any pile
	# and can never be shuffled back into the match.
	REMOVED
}
