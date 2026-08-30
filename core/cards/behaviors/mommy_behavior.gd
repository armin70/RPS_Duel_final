class_name MommyBehavior
extends CardBehavior

@export var spawned_card: CardDefinition

# MatchEngine spawns one temporary same-type card after this card wins a PvP
# clash. The spawn lives for the following turn/combat and then disappears.
