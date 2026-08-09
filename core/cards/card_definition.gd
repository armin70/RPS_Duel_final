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


@export_category("VFX")

# Played when the card itself is placed/revealed.
@export var placed_vfx: CardVFXDefinition

# Played on cards affected by this card (for example Disabler hits).
@export var target_vfx: CardVFXDefinition

# Played when the card ability resolves later (Collector, Chainsaw, Mustache).
@export var ability_vfx: CardVFXDefinition


@export_category("Special Behavior")
@export var behavior: CardBehavior


@export_category("Dealer Behavior")
@export var dealer_behavior: DealerCardBehavior
