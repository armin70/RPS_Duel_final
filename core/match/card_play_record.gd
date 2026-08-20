class_name CardPlayRecord
extends RefCounted


enum Type {
	PLAY_CARD,
	MOVE_BOARD_CARD
}


var type: Type = Type.PLAY_CARD
var card: CardInstance
var owner_id: int = -1
# Destination slot for both PLAY_CARD and MOVE_BOARD_CARD.
var slot_id: int = -1
# Only used by MOVE_BOARD_CARD.
var from_slot_id: int = -1

# Cards that left the board exactly because of this action.
var removed_cards: Array[CardInstance] = []

# Public visual board state immediately after this action.
# This is captured when the action happens so reveal can replay one action
# at a time without exposing later hidden Bot moves.
# Key: CardInstance.instance_id, Value: SlotID.Type
var board_slots_after: Dictionary = {}
