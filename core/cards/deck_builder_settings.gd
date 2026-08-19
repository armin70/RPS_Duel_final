class_name DeckBuilderSettings
extends Resource


@export_category("Deck Size")

@export_range(1, 60, 1)
var deck_size: int = 18


@export_category("Copy Limits")

@export_range(1, 20, 1)
var common_copy_limit: int = 4

@export_range(1, 20, 1)
var rare_copy_limit: int = 2


@export_category("Card Pool")

@export var available_cards: Array[CardDefinition] = []


func get_copy_limit(card: CardDefinition) -> int:
	if card == null:
		return 0

	if card.rarity == CardDefinition.Rarity.RARE:
		return rare_copy_limit

	return common_copy_limit


func is_card_available(card: CardDefinition) -> bool:
	return card != null and available_cards.has(card)
