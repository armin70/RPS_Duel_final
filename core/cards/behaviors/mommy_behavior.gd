class_name MommyBehavior
extends CardBehavior

@export var spawned_card: CardDefinition

# When this card wins during battle, MatchEngine queues one FREE normal card of
# the matching type for the owner's next hand. If that reward is not played in
# that turn, it is permanently removed before the following hand refresh.
