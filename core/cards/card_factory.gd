class_name CardFactory
extends RefCounted


var next_instance_id: int = 1


func create_card(
	definition: CardDefinition,
	owner_id: int
) -> CardInstance:
	var card := CardInstance.new(
		next_instance_id,
		definition,
		owner_id
	)

	next_instance_id += 1
	return card


func build_deck(
	deck_definition: DeckDefinition,
	owner_id: int
) -> Array[CardInstance]:
	var deck: Array[CardInstance] = []

	if deck_definition == null:
		push_error("DeckDefinition is null.")
		return deck

	for entry: DeckEntry in deck_definition.entries:
		if entry == null or entry.card == null:
			continue

		for index: int in range(entry.copies):
			var card: CardInstance = create_card(
				entry.card,
				owner_id
			)

			deck.append(card)

	deck.shuffle()

	return deck
