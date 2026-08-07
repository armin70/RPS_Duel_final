class_name CardDefinition
extends Resource


@export_category("Identity")

@export var card_id: StringName
@export var display_name: String


@export_category("Gameplay")

@export var gesture: CardGesture.Type = CardGesture.Type.ROCK

@export_range(0, 20, 1)
var mana_cost: int = 1


@export_category("Presentation")

@export var visual_id: StringName

@export_category("Visual")
@export var front_texture: Texture2D

@export_category("Special Behavior")
@export var behavior: CardBehavior


@export_category("Dealer Behavior")
@export var dealer_behavior: DealerCardBehavior
