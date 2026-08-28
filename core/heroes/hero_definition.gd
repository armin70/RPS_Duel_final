class_name HeroDefinition
extends CardDefinition


enum HeroKind {
	ROSTAM,
	TAHMINEH,
	AFRASIAB
}


@export_category("Hero")
@export var hero_kind: HeroKind = HeroKind.ROSTAM
@export_range(1, 20, 1) var starting_health: int = 5
@export_range(0, 20, 1) var starting_shields: int = 0
@export_range(0, 20, 1) var active_mana_cost: int = 0
@export var passive_title: String = ""
@export_multiline var passive_description: String = ""
@export var active_title: String = ""
@export_multiline var active_description: String = ""

# Tahmineh's passive reward card. Other heroes leave this empty.
@export var passive_reward_card: CardDefinition


func kind_name() -> String:
	match hero_kind:
		HeroKind.ROSTAM:
			return "Rostam"
		HeroKind.TAHMINEH:
			return "Tahmineh"
		HeroKind.AFRASIAB:
			return "Afrasiab"
	return "Hero"
