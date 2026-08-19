class_name MatchController3D
extends Node3D


signal overlap_combat_step_finished
signal combat_result_vfx_finished


const SLOT_COLLISION_MASK: int = 2
const CARD_DETAIL_OVERLAY_SCRIPT: Script = preload(
	"res://game/ui/card_detail_overlay.gd"
)
const DECK_SELECTION_SCREEN_SCRIPT: Script = preload(
	"res://game/deck_builder/deck_selection_screen.gd"
)
const DEFAULT_DECK_BUILDER_SETTINGS: DeckBuilderSettings = preload(
	"res://data/deck_builder/default_deck_builder_settings.tres"
)
const COMBAT_RESULT_VFX_SCRIPT: Script = preload(
	"res://game/vfx/combat_result_vfx_3d.gd"
)
const DEFAULT_WIN_RESULT_FRAMES: SpriteFrames = preload(
	"res://data/vfx/combat_result_win_frames.tres"
)
const DEFAULT_LOSS_RESULT_FRAMES: SpriteFrames = preload(
	"res://data/vfx/combat_result_loss_frames.tres"
)
const DEFAULT_DRAW_RESULT_FRAMES: SpriteFrames = preload(
	"res://data/vfx/combat_result_draw_frames.tres"
)


@export_category("VFX")

@export var vfx_manager: CardVFXManager3D

# Kept temporarily so the current binary main_game.scn can still deserialize
# its old inspector fields safely. The new VFX system does not use them.
@export_category("Legacy VFX References")
@export var saw_vfx_spawn: Node3D
@export var mustache_vfx_spawn: Node3D
@export var MUSTACHE_VFX_SCENE: PackedScene
@export var SAW_DIRT_SCENE: PackedScene
@export var saw_sound_volume_db: float = 0.0
@export var mustache_vfx_lifetime: float = 5.0

@export_category("VFX Timing")
@export_range(0.0, 1.0, 0.01)
var collector_pull_delay: float = 0.20
@export_category("Match Resources")
@export var rules: MatchRules
@export var player_one_deck: DeckDefinition
@export var player_two_deck: DeckDefinition
@export var dealer_deck: DeckDefinition

@export_category("Player Deck Choice")
@export var player_one_deck_2: DeckDefinition
@export var player_one_deck_3: DeckDefinition

# Optional. When empty, the first card inside each deck is used as its cover.
@export var deck_one_preview_card: CardDefinition
@export var deck_two_preview_card: CardDefinition
@export var deck_three_preview_card: CardDefinition
@export var deck_builder_settings: DeckBuilderSettings = \
	DEFAULT_DECK_BUILDER_SETTINGS

@export_range(1.0, 6.0, 0.1)
var deck_choice_distance: float = 2.6

@export_range(0.4, 2.0, 0.05)
var deck_choice_spacing: float = 0.45

@export_range(0.5, 4.0, 0.1)
var deck_choice_scale: float = 1

@export_range(-2.0, 2.0, 0.05)
var deck_choice_vertical_offset: float = 0.0

@export_range(0.05, 1.0, 0.05)
var deck_choice_animation_time: float = 0.30


@export_category("Scene References")
@export var game_layout: GameLayout3D
@export var card_scene: PackedScene
@export var runtime_cards: Node3D
@export var camera_3d: Camera3D
@export var hud: GameHUD
@export var balance_scale: GameBalanceScale3D

@export_category("Tutorial")
@export var tutorial_enabled: bool = false
# Optional portrait shown inside the tutorial speech panel. If left empty,
# the tutorial uses its built-in RPS GUIDE fallback badge.
@export var tutorial_guide_texture: Texture2D


@export_category("Drag")
@export_range(1, 2, 1)
var local_player_id: int = 1

@export var drag_plane_height: float = 0.25


@export_category("Bot and Reveal")
@export var bot_think_time: float = 0.3
@export var reveal_step_time: float = 0.3
@export_range(0.0, 2.0, 0.05)
var bot_action_pause: float = 0.45
@export var reveal_drop_height: float = 0.4

@export_category("Combat Animation")
@export_range(0.0, 1.0, 0.01)
var combat_lift_height: float = 0.38
@export_range(0.05, 1.0, 0.01)
var combat_lift_time: float = 0.16
@export_range(0.05, 1.0, 0.01)
var combat_attack_time: float = 0.12
@export_range(0.05, 1.0, 0.01)
var combat_return_time: float = 0.10
@export_range(0.0, 0.5, 0.01)
var combat_hit_pause: float = 0.03
@export_range(0.0, 0.5, 0.01)
var combat_attack_gap: float = 0.04
@export_range(0.0, 1.0, 0.01)
var combat_phase_pause: float = 0.08

# Dealer combat intentionally uses a different visual language than PvP:
# attackers travel almost all the way to the Dealer card, and the Dealer
# card reacts to the impact. PvP still meets around the midpoint.
@export_range(0.0, 0.3, 0.01)
var dealer_attack_stop_ratio: float = 0.05
@export_range(0.0, 0.5, 0.01)
var dealer_recoil_distance: float = 0.10
@export_range(0.0, 0.5, 0.01)
var dealer_recoil_height: float = 0.08
@export_range(0.01, 0.5, 0.01)
var dealer_recoil_out_time: float = 0.06
@export_range(0.01, 0.5, 0.01)
var dealer_recoil_return_time: float = 0.08

@export_category("Combat Result VFX")
@export var win_result_frames: SpriteFrames = DEFAULT_WIN_RESULT_FRAMES
@export var loss_result_frames: SpriteFrames = DEFAULT_LOSS_RESULT_FRAMES
@export var draw_result_frames: SpriteFrames = DEFAULT_DRAW_RESULT_FRAMES
@export var result_animation_name: StringName = &"default"
@export var result_local_offset: Vector3 = Vector3(0.0, 0.58, 0.0)
@export_range(0.0001, 0.01, 0.0001)
var result_pixel_size: float = 0.0012
@export_range(0.05, 2.0, 0.05)
var result_loop_fallback_duration: float = 0.35

const MAX_KEPT_HAND_CARDS: int = 3
const MAX_HAND_CARDS: int = 6
const TAP_DRAG_THRESHOLD: float = 18.0
var engine: MatchEngine
var state: MatchState
var kept_hand_card_ids: Dictionary = {}

var pointer_start_position: Vector2 = Vector2.ZERO
var pointer_has_dragged: bool = false
var bot_controller: BotController = BotController.new()
var bot_player_id: int = 2

var interaction_locked: bool = false

var card_views: Dictionary = {}
var opponent_hand_views: Dictionary = {}
var dragged_card: Card3D

var pending_local_cards: Array[CardInstance] = []
var pending_bot_plays: Array[CardPlayRecord] = []

var deck_selection_active: bool = false
var deck_choice_cards: Array[Card3D] = []
var deck_selection_screen: DeckSelectionScreen
var tutorial_controller: TutorialController
var card_detail_overlay: CardDetailOverlay


func _ready() -> void:
	# The transparent menu finds this controller through the group.
	add_to_group(&"match_controller")

	_ensure_vfx_manager()
	_remove_legacy_resident_vfx()

	if not _resources_are_valid():
		return

	_ensure_card_detail_overlay()

	bot_player_id = 2 if local_player_id == 1 else 1

	# Do not build MatchState yet. The player must choose a deck first.
	interaction_locked = true
	hud.visible = false
	hud.set_interaction_enabled(false)

	hud.end_turn_pressed.connect(
		Callable(self, "_on_end_turn_pressed")
	)

	print("Waiting for player deck selection.")


func _ensure_card_detail_overlay() -> void:
	if is_instance_valid(card_detail_overlay):
		return

	if not is_instance_valid(hud):
		return

	card_detail_overlay = \
		CARD_DETAIL_OVERLAY_SCRIPT.new() as CardDetailOverlay

	if card_detail_overlay == null:
		push_error(
			"Could not create CardDetailOverlay."
		)
		return

	card_detail_overlay.name = "CardDetailOverlay"
	hud.add_child(card_detail_overlay)


func _ensure_vfx_manager() -> void:
	if is_instance_valid(vfx_manager):
		return

	var scene_root := get_parent() as Node3D

	if scene_root == null:
		push_error(
			"MatchController3D needs a Node3D parent for RuntimeVFX."
		)
		return

	var runtime_root := scene_root.get_node_or_null(
		"RuntimeVFX"
	) as Node3D

	if runtime_root == null:
		runtime_root = Node3D.new()
		runtime_root.name = "RuntimeVFX"
		scene_root.add_child(runtime_root)

	var anchors := scene_root.get_node_or_null(
		"VFXAnchors"
	) as Node3D

	if anchors == null:
		anchors = Node3D.new()
		anchors.name = "VFXAnchors"
		scene_root.add_child(anchors)

	var dealer_anchor := anchors.get_node_or_null(
		"DealerVFXAnchor"
	) as Node3D

	if dealer_anchor == null:
		dealer_anchor = Node3D.new()
		dealer_anchor.name = "DealerVFXAnchor"
		anchors.add_child(dealer_anchor)

	var board_anchor := anchors.get_node_or_null(
		"BoardVFXAnchor"
	) as Node3D

	if board_anchor == null:
		board_anchor = Node3D.new()
		board_anchor.name = "BoardVFXAnchor"
		anchors.add_child(board_anchor)

	vfx_manager = CardVFXManager3D.new()
	vfx_manager.name = "CardVFXManager3D"
	scene_root.add_child(vfx_manager)

	vfx_manager.runtime_root = runtime_root
	vfx_manager.dealer_anchor = dealer_anchor
	vfx_manager.board_anchor = board_anchor

	print("Runtime VFX manager created.")


func _remove_legacy_resident_vfx() -> void:
	# The active project scene is saved as binary, so old dealer VFX/markers
	# may still be serialized there. Remove them immediately at runtime.
	var legacy_nodes: Array[Node] = []

	if is_instance_valid(saw_vfx_spawn):
		legacy_nodes.append(saw_vfx_spawn)

	if (
		is_instance_valid(mustache_vfx_spawn)
		and not legacy_nodes.has(mustache_vfx_spawn)
	):
		legacy_nodes.append(mustache_vfx_spawn)

	var scene_root: Node = get_parent()

	if scene_root != null:
		for legacy_name: String in [
			"SawVFXSpawn",
			"sibilVFXSpawn"
		]:
			var legacy_node: Node = scene_root.find_child(
				legacy_name,
				true,
				false
			)

			if (
				is_instance_valid(legacy_node)
				and not legacy_nodes.has(legacy_node)
			):
				legacy_nodes.append(legacy_node)

	for legacy_node: Node in legacy_nodes:
		if is_instance_valid(legacy_node):
			legacy_node.queue_free()

	saw_vfx_spawn = null
	mustache_vfx_spawn = null
	MUSTACHE_VFX_SCENE = null
	SAW_DIRT_SCENE = null
func begin_tutorial_match() -> void:
	if state != null:
		return

	tutorial_enabled = true

	await _start_match_with_selected_deck(
		player_one_deck
	)

func begin_deck_selection() -> void:
	if deck_selection_active:
		return

	if state != null:
		return

	deck_selection_active = true
	interaction_locked = true
	hud.visible = false
	hud.set_interaction_enabled(false)

	_show_deck_selection_screen()


func _show_deck_selection_screen() -> void:
	if is_instance_valid(deck_selection_screen):
		return

	var decks: Array[DeckDefinition] = [
		player_one_deck,
		player_one_deck_2,
		player_one_deck_3
	]

	var preview_overrides: Array[CardDefinition] = [
		deck_one_preview_card,
		deck_two_preview_card,
		deck_three_preview_card
	]

	deck_selection_screen = \
		DECK_SELECTION_SCREEN_SCRIPT.new() as DeckSelectionScreen

	if deck_selection_screen == null:
		push_error("Could not create DeckSelectionScreen.")
		return

	deck_selection_screen.configure(
		deck_builder_settings,
		decks,
		preview_overrides
	)
	deck_selection_screen.deck_selected.connect(
		Callable(self, "_on_deck_definition_selected")
	)
	add_child(deck_selection_screen)


func _on_deck_definition_selected(
	selected_deck: DeckDefinition
) -> void:
	if not deck_selection_active:
		return

	if selected_deck == null:
		return

	deck_selection_active = false
	interaction_locked = true

	if is_instance_valid(deck_selection_screen):
		deck_selection_screen.queue_free()
		deck_selection_screen = null

	_clear_deck_choice_cards()
	await get_tree().process_frame

	await _start_match_with_selected_deck(
		selected_deck
	)


func _spawn_deck_choice_cards() -> void:
	_clear_deck_choice_cards()

	var decks: Array[DeckDefinition] = [
		player_one_deck,
		player_one_deck_2,
		player_one_deck_3
	]

	var preview_overrides: Array[CardDefinition] = [
		deck_one_preview_card,
		deck_two_preview_card,
		deck_three_preview_card
	]

	for index: int in range(decks.size()):
		var selected_deck: DeckDefinition = decks[index]
		var preview_definition: CardDefinition = \
			_get_deck_preview_definition(
				selected_deck,
				preview_overrides[index]
			)

		if preview_definition == null:
			push_error(
				"Deck %d has no preview card." % (index + 1)
			)
			continue

		var card_view := card_scene.instantiate() as Card3D

		if card_view == null:
			push_error("Card scene root must be Card3D.")
			continue

		runtime_cards.add_child(card_view)

		var preview_instance := CardInstance.new(
			-1000 - index,
			preview_definition,
			local_player_id
		)

		var target_transform: Transform3D = \
			_get_deck_choice_transform(index)

		card_view.setup(
			preview_instance,
			target_transform,
			false,
			true
		)

		card_view.drag_requested.connect(
			Callable(
				self,
				"_on_deck_choice_selected"
			).bind(selected_deck)
		)

		deck_choice_cards.append(card_view)

	# Small entrance animation.
	for index: int in range(deck_choice_cards.size()):
		var card_view: Card3D = deck_choice_cards[index]
		var target_scale: Vector3 = card_view.scale
		card_view.scale = target_scale * 0.02

		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(
			card_view,
			"scale",
			target_scale,
			deck_choice_animation_time
		)

		await get_tree().create_timer(0.07).timeout

	for card_view: Card3D in deck_choice_cards:
		card_view.is_draggable = true

	print("Choose one of the three deck cards.")


func _get_deck_preview_definition(
	deck: DeckDefinition,
	override_definition: CardDefinition
) -> CardDefinition:
	if override_definition != null:
		return override_definition

	if deck == null:
		return null

	for entry: DeckEntry in deck.entries:
		if entry == null:
			continue

		if entry.card != null:
			return entry.card

	return null


func _get_deck_choice_transform(
	index: int
) -> Transform3D:
	var camera_transform: Transform3D = camera_3d.global_transform

	var camera_right: Vector3 = \
		camera_transform.basis.x.normalized()
	var camera_up: Vector3 = \
		camera_transform.basis.y.normalized()
	var camera_forward: Vector3 = \
		-camera_transform.basis.z.normalized()

	var horizontal_offset: float = \
		(float(index) - 1.0) * deck_choice_spacing

	var target_position: Vector3 = (
		camera_transform.origin
		+ camera_forward * deck_choice_distance
		+ camera_right * horizontal_offset
		+ camera_up * deck_choice_vertical_offset
	)

	# Card3D's front normal is its local +Y axis.
	# Point +Y back toward the camera and keep the card upright.
	var facing_basis := Basis(
		camera_right,
		-camera_forward,
		-camera_up
	)

	facing_basis = facing_basis.scaled(
		Vector3.ONE * deck_choice_scale
	)

	return Transform3D(
		facing_basis,
		target_position
	)


func _on_deck_choice_selected(
	selected_card_view: Card3D,
	selected_deck: DeckDefinition
) -> void:
	if not deck_selection_active:
		return

	if selected_card_view == null:
		return

	if selected_deck == null:
		return

	deck_selection_active = false

	for card_view: Card3D in deck_choice_cards:
		card_view.is_draggable = false

	var selection_tween: Tween = create_tween()
	selection_tween.set_parallel(true)
	selection_tween.set_trans(Tween.TRANS_BACK)
	selection_tween.set_ease(Tween.EASE_IN_OUT)

	for card_view: Card3D in deck_choice_cards:
		if card_view == selected_card_view:
			var toward_camera: Vector3 = (
				camera_3d.global_position
				- card_view.global_position
			).normalized()

			selection_tween.tween_property(
				card_view,
				"global_position",
				card_view.global_position + toward_camera * 0.35,
				deck_choice_animation_time
			)
			selection_tween.tween_property(
				card_view,
				"scale",
				card_view.scale * 1.15,
				deck_choice_animation_time
			)
		else:
			selection_tween.tween_property(
				card_view,
				"scale",
				Vector3.ZERO,
				deck_choice_animation_time
			)

	await selection_tween.finished

	_clear_deck_choice_cards()
	await get_tree().process_frame

	await _start_match_with_selected_deck(
		selected_deck
	)


func _clear_deck_choice_cards() -> void:
	for card_view: Card3D in deck_choice_cards:
		if is_instance_valid(card_view):
			card_view.queue_free()

	deck_choice_cards.clear()


func _start_match_with_selected_deck(
	selected_deck: DeckDefinition
) -> void:
	player_one_deck = selected_deck

	engine = MatchEngine.new()
	state = engine.start_match(
		rules,
		player_one_deck,
		player_two_deck,
		dealer_deck
	)

	if tutorial_enabled:
		_ensure_tutorial_controller()
		if tutorial_controller != null:
			tutorial_controller.prepare_match_state()

	# FAIR Bot فقط وضعیت عمومی ابتدای Turn را به خاطر می‌سپارد.
	# هر Play یا Move مخفی بعد از این نقطه برای Fair قابل مشاهده نیست.
	_capture_fair_bot_knowledge()

	await _sync_visual_state()

	hud.visible = true
	hud.refresh(
		state,
		local_player_id
	)
	hud.set_interaction_enabled(true)

	interaction_locked = false
	_refresh_balance_scale()

	if tutorial_enabled and tutorial_controller != null:
		tutorial_controller.start()

	print("Match started with selected player deck.")


func _ensure_tutorial_controller() -> void:
	if is_instance_valid(tutorial_controller):
		return

	tutorial_controller = TutorialController.new()
	tutorial_controller.name = "TutorialController"
	add_child(tutorial_controller)
	tutorial_controller.setup(self)


func refresh_tutorial_visual_state() -> void:
	# Public tutorial-only bridge: rebuild the 3D card views after the
	# deterministic tutorial changes hands / boards directly.
	await _sync_visual_state()

	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.sync_visual_visibility()

	if hud != null:
		hud.refresh(
			state,
			local_player_id
		)

	_refresh_balance_scale()


func play_tutorial_collector_vfx_now() -> void:
	# The reference tutorial shows Collector pulling Rock cards immediately
	# after it is placed. Reuse the project's existing Collector VFX sequence;
	# TutorialController performs the tutorial-only state change afterwards.
	await _play_collector_vfx_before_combat()


func _capture_fair_bot_knowledge() -> void:
	if bot_controller == null:
		return

	if state == null:
		return

	bot_controller.capture_fair_opponent_snapshot(
		state,
		local_player_id
	)


func _prepare_bot_turn() -> void:
	if state == null:
		return

	if state.phase != MatchPhase.Type.MAIN:
		return

	var bot: PlayerState = state.get_player(
		bot_player_id
	)

	if bot == null:
		return

	if bot.is_ready:
		return

	pending_bot_plays.clear()

	engine.clear_play_records(
		bot_player_id
	)

	var used_tutorial_script: bool = false
	if tutorial_controller != null and tutorial_controller.is_active():
		used_tutorial_script = tutorial_controller.execute_scripted_bot_turn()

	if not used_tutorial_script:
		bot_controller.play_turn(
			engine,
			bot_player_id
		)

	pending_bot_plays = engine.consume_play_records(
		bot_player_id
	)

	engine.set_player_ready(
		bot_player_id
	)

	print(
		"Bot completed hidden planning with ",
		pending_bot_plays.size(),
		" plays."
	)

func _get_board_card_ids(
	player_id: int
) -> Dictionary:
	var result: Dictionary = {}

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return result

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = player.board.get_card(
			slot_id
		)

		if card != null:
			result[card.instance_id] = true

	return result


func _get_cards_not_in_snapshot(
	player_id: int,
	previous_card_ids: Dictionary
) -> Array[CardInstance]:
	var result: Array[CardInstance] = []

	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return result

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = player.board.get_card(
			slot_id
		)

		if card == null:
			continue

		if not previous_card_ids.has(card.instance_id):
			result.append(card)

	return result


func _on_end_turn_pressed() -> void:
	if interaction_locked:
		return

	if (
		tutorial_controller != null
		and tutorial_controller.is_active()
		and not tutorial_controller.can_press_end_turn()
	):
		tutorial_controller.notify_wrong_action()
		return

	if state == null:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	if player.is_ready:
		return

	# Bot بعد از قفل‌شدن Turn تصمیم می‌گیرد.
	# FAIR فقط Snapshot عمومی ابتدای Turn را می‌بیند؛
	# کارت جدید و Move مخفی همین Turn برایش قابل شناسایی نیست.
	_prepare_bot_turn()

	var success: bool = engine.set_player_ready(
		local_player_id
	)

	if not success:
		return

	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.notify_end_turn_pressed()

	interaction_locked = true

	hud.set_interaction_enabled(false)

	hud.refresh(
		state,
		local_player_id
	)

	if _are_both_players_ready():
		await _run_reveal_and_battle()


func _are_both_players_ready() -> bool:
	if state == null:
		return false

	var player_one: PlayerState = state.get_player(1)
	var player_two: PlayerState = state.get_player(2)

	if player_one == null or player_two == null:
		return false

	return (
		player_one.is_ready
		and player_two.is_ready
	)


func _run_reveal_and_battle() -> void:
	await get_tree().create_timer(
		bot_think_time
	).timeout

	# مهم: اینجا دیگر همه کارت‌های Discardشده را یک‌جا حذف نمی‌کنیم.
	# هر Play حریف مسئول نمایش و حذف کارت‌های مربوط به همان اکت است؛
	# بنابراین اکت‌ها واقعاً یکی‌یکی دیده می‌شوند.
	await _reveal_cards_one_by_one(
		pending_local_cards,
		pending_bot_plays
	)

	# Cleanup نهایی فقط برای Viewهایی که به هر دلیلی رکورد Reveal نداشتند.
	_remove_discarded_card_views()

	pending_local_cards.clear()
	pending_bot_plays.clear()

	# Tutorial can pause here, after reveal but before score/combat animation,
	# so every explanation beat from the reference tutorial is shown.
	if tutorial_controller != null and tutorial_controller.is_active():
		await tutorial_controller.wait_before_combat()

	await _start_animated_combat()


func _reveal_cards_one_by_one(
	player_cards: Array[CardInstance],
	bot_plays: Array[CardPlayRecord]
) -> void:
	var maximum_count: int = max(
		player_cards.size(),
		bot_plays.size()
	)

	for index: int in range(maximum_count):
		if index < player_cards.size():
			await _pulse_existing_card(
				player_cards[index]
			)

		if index < bot_plays.size():
			await _reveal_bot_play(
				bot_plays[index]
			)

			# اکت بعدی Bot تا وقتی اکت فعلی کامل نشده شروع نمی‌شود.
			# این مکث باعث می‌شود چند Play پشت سر هم یک‌جا به نظر نرسند.
			if bot_action_pause > 0.0:
				await get_tree().create_timer(
					bot_action_pause
				).timeout

	await _refresh_opponent_hand_positions()

func _reveal_bot_play(
	play_record: CardPlayRecord
) -> void:
	if play_record == null:
		return

	if play_record.card == null:
		return

	if (
		play_record.type
		== CardPlayRecord.Type.MOVE_BOARD_CARD
	):
		await _reveal_bot_board_move(
			play_record
		)
		return

	# اول خود کارت Bot وارد زمین می‌شود.
	await _reveal_bot_card(
		play_record.card,
		play_record.slot_id
	)

	# بعد حذف‌ها / Coverهای مربوط به همان Play نمایش داده می‌شوند.
	await _reveal_removed_card_views(
		play_record.removed_cards
	)


func _reveal_bot_board_move(
	play_record: CardPlayRecord
) -> void:
	if play_record == null or play_record.card == null:
		return

	var card_view := card_views.get(
		play_record.card.instance_id,
		null
	) as Card3D

	if card_view == null:
		return

	var target_place: CardPlace3D = \
		game_layout.get_board_place(
			bot_player_id,
			play_record.slot_id
		)

	if target_place == null:
		return

	# اگر Move روی یک کارت دیگر Cover شده، اول همان کارت کنار می‌رود.
	await _reveal_removed_card_views(
		play_record.removed_cards
	)

	var target_transform: Transform3D = \
		target_place.card_anchor.global_transform
	var start_position: Vector3 = \
		card_view.global_position
	var target_position: Vector3 = \
		target_transform.origin
	var middle_position: Vector3 = (
		(start_position + target_position) / 2.0
		+ Vector3.UP * reveal_drop_height
	)

	var tween: Tween = create_tween()
	tween.tween_property(
		card_view,
		"global_position",
		middle_position,
		reveal_step_time * 0.45
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	tween.tween_property(
		card_view,
		"global_transform",
		target_transform,
		reveal_step_time * 0.55
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	await tween.finished
	card_view.move_home(target_transform)

func _pulse_existing_card(
	card: CardInstance
) -> void:
	var card_view := card_views.get(
		card.instance_id,
		null
	) as Card3D

	if card_view == null:
		return

	var original_position: Vector3 = \
		card_view.global_position

	var lifted_position: Vector3 = (
		original_position
		+ Vector3.UP * 0.12
	)

	var tween: Tween = create_tween()

	tween.tween_property(
		card_view,
		"global_position",
		lifted_position,
		reveal_step_time * 0.5
	)

	tween.tween_property(
		card_view,
		"global_position",
		original_position,
		reveal_step_time * 0.5
	)

	await tween.finished


func _reveal_bot_card(
	card: CardInstance,
	slot_id: int
) -> void:
	var place: CardPlace3D = game_layout.get_board_place(
		bot_player_id,
		slot_id
	)

	if place == null:
		push_error("Missing opponent board place.")
		return

	var target_transform: Transform3D = \
		place.card_anchor.global_transform

	var card_view := opponent_hand_views.get(
		card.instance_id,
		null
	) as Card3D

	if card_view == null:
		var start_transform: Transform3D = \
			target_transform

		start_transform.origin += \
			Vector3.UP * reveal_drop_height

		card_view = _create_card_view(
			card,
			start_transform,
			false,
			false,
			false
		)

	if card_view == null:
		return

	opponent_hand_views.erase(
		card.instance_id
	)

	var start_position: Vector3 = \
		card_view.global_position

	var target_position: Vector3 = \
		target_transform.origin

	var middle_position: Vector3 = (
		(start_position + target_position) / 2.0
		+ Vector3.UP * reveal_drop_height
	)

	var tween: Tween = create_tween()

	tween.tween_property(
		card_view,
		"global_position",
		middle_position,
		reveal_step_time * 0.45
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	tween.tween_callback(
		Callable(
			card_view,
			"set_face_up"
		).bind(true)
	)

	tween.tween_property(
		card_view,
		"global_transform",
		target_transform,
		reveal_step_time * 0.55
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	await tween.finished

	card_view.move_home(
		target_transform
	)

	card_views[
		card.instance_id
	] = card_view

	var placed_vfx_duration: float = \
		_play_card_placed_vfx(
			card_view
		)

	await _play_card_placement_disable_sequence(
		card_view,
		placed_vfx_duration
	)

func _find_card_slot(
	player_id: int,
	target_card: CardInstance
) -> int:
	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return -1

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = player.board.get_card(
			slot_id
		)

		if card == target_card:
			return slot_id

	return -1


func _sync_visual_state() -> void:
	dragged_card = null

	for child: Node in runtime_cards.get_children():
		child.queue_free()

	card_views.clear()
	opponent_hand_views.clear()

	await get_tree().process_frame

	_spawn_dealer_cards()

	_spawn_board_cards(1)
	_spawn_board_cards(2)

	_spawn_hand_cards()
	_spawn_opponent_hand_cards()
	_refresh_board_disabled_visuals(false)
	_refresh_pile_entities()
	_restore_local_board_dragging()


func _restore_local_board_dragging() -> void:
	if state == null:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	var drag_callable := Callable(
		self,
		"_start_card_drag"
	)

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = player.board.get_card(
			slot_id
		)

		if card == null:
			continue

		var card_view := card_views.get(
			card.instance_id,
			null
		) as Card3D

		if card_view == null:
			continue

		card_view.is_draggable = true
		card_view.input_ray_pickable = true

		if not card_view.drag_requested.is_connected(
			drag_callable
		):
			card_view.drag_requested.connect(
				drag_callable
			)

func _get_dealer_card_ids() -> Dictionary:
	var result: Dictionary = {}

	if state == null:
		return result

	if state.dealer == null:
		return result

	for slot_id: int in DealerSlotID.all_slots():
		var card: CardInstance = state.dealer.slots.get(
			slot_id,
			null
		) as CardInstance

		if card == null:
			continue

		result[card.instance_id] = true

	return result


func _play_new_dealer_placed_vfx(
	previous_card_ids: Dictionary
) -> void:
	if state == null:
		return

	if state.dealer == null:
		return

	var longest_duration: float = 0.0

	for slot_id: int in DealerSlotID.all_slots():
		var card: CardInstance = state.dealer.slots.get(
			slot_id,
			null
		) as CardInstance

		if card == null:
			continue

		# این کارت قبلاً روی زمین بوده.
		if previous_card_ids.has(card.instance_id):
			continue

		if card.definition == null:
			continue
		if (
			card.definition.dealer_notice_texture
			!= null
		):
			hud.show_dealer_notice(
				card.definition.dealer_notice_texture,
				card.definition.dealer_notice_duration
			)
		# این کارت اصلاً Placed VFX ندارد.
		if card.definition.placed_vfx == null:
			continue

		var card_view: Card3D = card_views.get(
			card.instance_id,
			null
		) as Card3D

		if card_view == null:
			continue

		print(
			"DEALER PLACED VFX | ",
			card.definition.display_name
		)

		var duration: float = _play_card_placed_vfx(
			card_view
		)

		longest_duration = maxf(
			longest_duration,
			duration
		)

	if longest_duration > 0.0:
		await get_tree().create_timer(
			longest_duration
		).timeout

func _spawn_dealer_cards() -> void:
	for slot_id: int in DealerSlotID.all_slots():
		var card: CardInstance = state.dealer.slots.get(
			slot_id,
			null
		)

		if card == null:
			continue

		var anchor: Marker3D = \
			game_layout.get_dealer_anchor(
				slot_id
			)

		if anchor == null:
			push_error(
				"Missing dealer anchor: %s"
				% slot_id
			)
			continue

		_create_card_view(
			card,
			anchor.global_transform,
			false
		)

func _spawn_board_cards(
	player_id: int
) -> void:
	var player: PlayerState = state.get_player(
		player_id
	)

	if player == null:
		return

	for slot_id: int in SlotID.all_slots():
		var card: CardInstance = \
			player.board.get_card(
				slot_id
			)

		if card == null:
			continue

		var place: CardPlace3D = \
			game_layout.get_board_place(
				player_id,
				slot_id
			)

		if place == null:
			continue

		var draggable: bool = (
			player_id == local_player_id
		)

		var card_view: Card3D = \
			_create_card_view(
				card,
				place.card_anchor.global_transform,
				draggable
			)

		if card_view == null:
			continue

		if draggable:
			card_view.drag_requested.connect(
				Callable(
					self,
					"_start_card_drag"
				)
			)


func _spawn_hand_cards() -> void:
	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	for index: int in range(player.hand.size()):
		var card: CardInstance = player.hand[index]

		var target_transform: Transform3D = \
			game_layout.get_hand_transform(
				local_player_id,
				index,
				player.hand.size()
			)

		var card_view: Card3D = _create_card_view(
			card,
			target_transform,
			true
		)

		if card_view == null:
			continue

		card_view.set_keep_selected(
			kept_hand_card_ids.has(
				card.instance_id
			)
		)

		card_view.drag_requested.connect(
			Callable(
				self,
				"_start_card_drag"
			)
		)

func _create_card_view(
	card: CardInstance,
	target_transform: Transform3D,
	draggable: bool,
	face_up: bool = true,
	register_as_main_view: bool = true
) -> Card3D:
	var card_view := \
		card_scene.instantiate() as Card3D

	if card_view == null:
		push_error(
			"Card scene root must be Card3D."
		)
		return null

	runtime_cards.add_child(card_view)

	card_view.setup(
		card,
		target_transform,
		draggable,
		face_up
	)

	card_view.inspect_requested.connect(
		Callable(
			self,
			"_on_card_inspect_requested"
		)
	)

	if register_as_main_view:
		card_views[card.instance_id] = card_view

	return card_view

func _on_card_inspect_requested(
	card_view: Card3D
) -> void:
	if card_view == null:
		return

	if not is_instance_valid(card_view):
		return

	# Never expose a face-down opponent card.
	if not card_view.is_face_up:
		return

	if card_view.card_instance == null:
		return

	# A hold starts from the same press as a possible drag.
	# If the hold wins before the drag threshold, cancel the drag cleanly.
	if dragged_card == card_view:
		card_view.return_home()
		dragged_card = null
		pointer_has_dragged = false

	_ensure_card_detail_overlay()

	if not is_instance_valid(card_detail_overlay):
		return

	card_detail_overlay.show_card(
		card_view.card_instance,
		card_view.is_disabled
	)


func _start_card_drag(
	card_view: Card3D,
	screen_position: Vector2
) -> void:
	if dragged_card != null:
		return

	if interaction_locked:
		return

	if state == null:
		return

	if state.phase != MatchPhase.Type.MAIN:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	if player.is_ready:
		return

	if card_view == null:
		return

	var card: CardInstance = \
		card_view.card_instance

	if card == null:
		return

	if card.owner_id != local_player_id:
		return

	if (
		card.zone != CardZone.Type.HAND
		and card.zone != CardZone.Type.BOARD
	):
		return

	if (
		tutorial_controller != null
		and tutorial_controller.is_active()
		and not tutorial_controller.can_start_drag(card)
	):
		tutorial_controller.notify_wrong_action()
		return

	dragged_card = card_view
	pointer_start_position = screen_position
	pointer_has_dragged = false

	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.notify_drag_started(card)

func _input(event: InputEvent) -> void:
	# Deck selection is handled directly by screen position.
	# This does not depend on Card3D's collider or drag signal.
	if deck_selection_active:
		# The new deck screen uses normal Control input. Do not consume the
		# event here or its buttons will never receive it. The old 3D picker is
		# kept below as a safe fallback for older serialized scenes.
		if is_instance_valid(deck_selection_screen):
			return

		if event is InputEventMouseButton:
			if (
				event.button_index == MOUSE_BUTTON_LEFT
				and event.pressed
			):
				_try_select_deck_at_screen_position(
					event.position
				)
				get_viewport().set_input_as_handled()

		elif event is InputEventScreenTouch:
			if event.pressed:
				_try_select_deck_at_screen_position(
					event.position
				)
				get_viewport().set_input_as_handled()

		return

	if dragged_card == null:
		return

	if event is InputEventScreenDrag:
		_update_pointer_drag(
			event.position
		)

	elif event is InputEventMouseMotion:
		_update_pointer_drag(
			event.position
		)

	elif event is InputEventScreenTouch:
		if not event.pressed:
			_finish_pointer_interaction(
				event.position
			)

	elif event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed
		):
			_finish_pointer_interaction(
				event.position
			)

func _try_select_deck_at_screen_position(
	screen_position: Vector2
) -> void:
	if not deck_selection_active:
		return

	if camera_3d == null:
		return

	if deck_choice_cards.is_empty():
		return

	var closest_index: int = -1
	var closest_distance: float = INF

	for index: int in range(deck_choice_cards.size()):
		var card_view: Card3D = deck_choice_cards[index]

		if not is_instance_valid(card_view):
			continue

		if camera_3d.is_position_behind(
			card_view.global_position
		):
			continue

		var card_screen_position: Vector2 = \
			camera_3d.unproject_position(
				card_view.global_position
			)

		var distance: float = \
			card_screen_position.distance_to(
				screen_position
			)

		if distance < closest_distance:
			closest_distance = distance
			closest_index = index

	if closest_index < 0:
		return

	var viewport_height: float = \
		get_viewport().get_visible_rect().size.y

	var selection_radius: float = clampf(
		viewport_height * 0.24,
		120.0,
		320.0
	)

	if closest_distance > selection_radius:
		return

	var decks: Array[DeckDefinition] = [
		player_one_deck,
		player_one_deck_2,
		player_one_deck_3
	]

	if closest_index >= decks.size():
		return

	var selected_deck: DeckDefinition = \
		decks[closest_index]

	if selected_deck == null:
		push_error(
			"Selected deck %d is missing."
			% (closest_index + 1)
		)
		return

	print(
		"DECK CHOICE CLICK | deck=",
		closest_index + 1
	)

	_on_deck_choice_selected(
		deck_choice_cards[closest_index],
		selected_deck
	)


func _update_pointer_drag(
	screen_position: Vector2
) -> void:
	if not pointer_has_dragged:
		var drag_distance: float = \
			screen_position.distance_to(
				pointer_start_position
			)

		if drag_distance < TAP_DRAG_THRESHOLD:
			return

		pointer_has_dragged = true

	_move_dragged_card(
		screen_position
	)


func _finish_pointer_interaction(
	screen_position: Vector2
) -> void:
	if dragged_card == null:
		return

	if not pointer_has_dragged:
		var tapped_card: Card3D = dragged_card
		dragged_card = null

		_toggle_keep_card(
			tapped_card
		)
		return

	_finish_card_drag(
		screen_position
	)

func _toggle_keep_card(
	card_view: Card3D
) -> void:
	if card_view == null:
		return

	var card: CardInstance = \
		card_view.card_instance

	if tutorial_controller != null and tutorial_controller.is_active():
		if tutorial_controller.try_handle_card_tap(card):
			return
		if not tutorial_controller.can_toggle_keep_card():
			tutorial_controller.notify_wrong_action()
			return

	if card == null:
		return

	if card.owner_id != local_player_id:
		return

	if card.zone != CardZone.Type.HAND:
		return

	if kept_hand_card_ids.has(
		card.instance_id
	):
		kept_hand_card_ids.erase(
			card.instance_id
		)

		card_view.set_keep_selected(false)
		return

	if (
		kept_hand_card_ids.size()
		>= MAX_KEPT_HAND_CARDS
	):
		return

	kept_hand_card_ids[
		card.instance_id
	] = true

	card_view.set_keep_selected(true)


func _move_dragged_card(
	screen_position: Vector2
) -> void:
	var ray_origin: Vector3 = \
		camera_3d.project_ray_origin(
			screen_position
		)

	var ray_direction: Vector3 = \
		camera_3d.project_ray_normal(
			screen_position
		)

	var drag_plane := Plane(
		Vector3.UP,
		drag_plane_height
	)

	var intersection: Variant = \
		drag_plane.intersects_ray(
			ray_origin,
			ray_direction
		)

	if intersection == null:
		return

	dragged_card.global_position = intersection

func _finish_card_drag(
	screen_position: Vector2
) -> void:
	var card_view: Card3D = dragged_card
	dragged_card = null

	if card_view == null:
		return

	var place: CardPlace3D = _get_place_under_mouse(
		screen_position
	)

	if place == null:
		card_view.return_home()
		if tutorial_controller != null and tutorial_controller.is_active():
			tutorial_controller.notify_wrong_action()
		return

	if place.kind != CardPlace3D.Kind.PLAYER_BOARD:
		card_view.return_home()
		if tutorial_controller != null and tutorial_controller.is_active():
			tutorial_controller.notify_wrong_action()
		return

	if place.owner_id != local_player_id:
		card_view.return_home()
		if tutorial_controller != null and tutorial_controller.is_active():
			tutorial_controller.notify_wrong_action()
		return

	var card: CardInstance = card_view.card_instance

	if card == null:
		card_view.return_home()
		return

	if (
		tutorial_controller != null
		and tutorial_controller.is_active()
		and not tutorial_controller.can_drop(card, place)
	):
		card_view.return_home()
		tutorial_controller.notify_wrong_action()
		return

	var original_zone: CardZone.Type = card.zone

	if original_zone == CardZone.Type.HAND:
		var was_played: bool = engine.play_card(
			local_player_id,
			card,
			place.logical_id
		)

		if not was_played:
			card_view.return_home()
			return

		kept_hand_card_ids.erase(
			card.instance_id
		)
		card_view.set_keep_selected(false)

		_remove_pile_card_views(
			local_player_id
		)
		_remove_discarded_card_views()
		_spawn_missing_local_hand_cards()
		_refresh_pile_entities()

		pending_local_cards.append(
			card
		)

		card_view.is_draggable = true
		card_view.move_home(
			place.card_anchor.global_transform
		)

		var placed_vfx_duration: float = \
			_play_card_placed_vfx(
				card_view
			)

		await _play_card_placement_disable_sequence(
			card_view,
			placed_vfx_duration
		)

		hud.refresh(
			state,
			local_player_id
		)

		await _refresh_hand_positions()

		if tutorial_controller != null and tutorial_controller.is_active():
			tutorial_controller.notify_successful_drop(
				card,
				original_zone,
				place.logical_id
			)
		return

	if original_zone == CardZone.Type.BOARD:
		var from_slot_id: int = card.current_slot
		var to_slot_id: int = place.logical_id

		var was_moved: bool = engine.move_board_card(
			local_player_id,
			from_slot_id,
			to_slot_id
		)

		if not was_moved:
			card_view.return_home()
			return

		_remove_pile_card_views(
			local_player_id
		)
		_refresh_pile_entities()

		card_view.move_home(
			place.card_anchor.global_transform
		)
		_refresh_board_disabled_visuals(true)

		hud.refresh(
			state,
			local_player_id
		)

		if tutorial_controller != null and tutorial_controller.is_active():
			tutorial_controller.notify_successful_drop(
				card,
				original_zone,
				place.logical_id
			)
		return

	card_view.return_home()

func _get_place_under_mouse(
	screen_position: Vector2
) -> CardPlace3D:
	var ray_origin: Vector3 = \
		camera_3d.project_ray_origin(
			screen_position
		)

	var ray_direction: Vector3 = \
		camera_3d.project_ray_normal(
			screen_position
		)

	var query := \
		PhysicsRayQueryParameters3D.create(
			ray_origin,
			ray_origin + ray_direction * 1000.0
		)

	query.collision_mask = SLOT_COLLISION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result: Dictionary = \
		get_world_3d().direct_space_state.intersect_ray(
			query
		)

	if result.is_empty():
		return null

	return result.get(
		"collider",
		null
	) as CardPlace3D


func _refresh_hand_positions() -> void:
	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	for index: int in range(player.hand.size()):
		var card: CardInstance = player.hand[index]

		var card_view := card_views.get(
			card.instance_id,
			null
		) as Card3D

		if card_view == null:
			continue

		var target_transform: Transform3D = \
			game_layout.get_hand_transform(
				local_player_id,
				index,
				player.hand.size()
			)

		card_view.move_home(
			target_transform
		)


func _resources_are_valid() -> bool:
	if rules == null:
		push_error("Rules are missing.")
		return false

	if player_one_deck == null:
		push_error("Player one deck is missing.")
		return false

	if player_one_deck_2 == null:
		push_error("Player deck choice 2 is missing.")
		return false

	if player_one_deck_3 == null:
		push_error("Player deck choice 3 is missing.")
		return false

	if deck_builder_settings == null:
		push_error("Deck builder settings are missing.")
		return false

	if player_two_deck == null:
		push_error("Player two deck is missing.")
		return false

	if dealer_deck == null:
		push_error("Dealer deck is missing.")
		return false

	if game_layout == null:
		push_error("GameLayout is missing.")
		return false

	if card_scene == null:
		push_error("Card scene is missing.")
		return false

	if runtime_cards == null:
		push_error("RuntimeCards is missing.")
		return false

	if vfx_manager == null:
		push_error("CardVFXManager3D is missing.")
		return false

	if camera_3d == null:
		push_error("Camera3D is missing.")
		return false

	if hud == null:
		push_error("HUD is missing.")
		return false

	return true


func _spawn_opponent_hand_cards() -> void:
	var opponent: PlayerState = state.get_player(
		bot_player_id
	)

	if opponent == null:
		return

	for index: int in range(
		opponent.hand.size()
	):
		var card: CardInstance = \
			opponent.hand[index]

		var target_transform: Transform3D = \
			game_layout.get_hand_transform(
				bot_player_id,
				index,
				opponent.hand.size()
			)

		var card_view: Card3D = \
			_create_card_view(
				card,
				target_transform,
				false,
				false,
				false
			)

		if card_view == null:
			continue

		opponent_hand_views[
			card.instance_id
		] = card_view


func _refresh_opponent_hand_positions() -> void:
	var opponent: PlayerState = state.get_player(
		bot_player_id
	)

	if opponent == null:
		return

	for index: int in range(
		opponent.hand.size()
	):
		var card: CardInstance = \
			opponent.hand[index]

		var card_view := \
			opponent_hand_views.get(
				card.instance_id,
				null
			) as Card3D

		if card_view == null:
			continue

		var target_transform: Transform3D = \
			game_layout.get_hand_transform(
				bot_player_id,
				index,
				opponent.hand.size()
			)

		card_view.move_home(
			target_transform
		)

func _refresh_board_disabled_visuals(
	animate_changes: bool = true
) -> float:
	if engine == null:
		return 0.0

	if engine.state == null:
		return 0.0

	var longest_hit_duration: float = 0.0

	for player_id: int in [1, 2]:
		var player: PlayerState = engine.state.get_player(
			player_id
		)

		if player == null:
			continue

		for slot_id: int in SlotID.all_slots():
			var card: CardInstance = player.board.get_card(
				slot_id
			)

			if card == null:
				continue

			var card_view := card_views.get(
				card.instance_id,
				null
			) as Card3D

			if card_view == null:
				continue

			var source_card: CardInstance = (
				_find_disabler_source_for_target(
					player_id,
					slot_id,
					card
				)
			)

			var disabled: bool = source_card != null

			var was_disabled: bool = card_view.is_disabled

			card_view.set_disabled(
				disabled,
				false
			)

			var became_disabled: bool = (
				disabled
				and not was_disabled
			)

			if (
				animate_changes
				and became_disabled
				and source_card != null
				and source_card.definition != null
				and vfx_manager != null
			):
				var source_view := card_views.get(
					source_card.instance_id,
					null
				) as Card3D

				var hit_duration: float = vfx_manager.play_vfx(
					source_card.definition.target_vfx,
					source_view,
					card_view
				)

				longest_hit_duration = maxf(
					longest_hit_duration,
					hit_duration
				)

	return longest_hit_duration

func _is_card_visually_disabled(
	target_owner_id: int,
	target_slot_id: int,
	target_card: CardInstance
) -> bool:
	return (
		_find_disabler_source_for_target(
			target_owner_id,
			target_slot_id,
			target_card
		)
		!= null
	)

func _find_disabler_source_for_target(
	target_owner_id: int,
	target_slot_id: int,
	target_card: CardInstance
) -> CardInstance:
	if state == null:
		return null

	if target_card == null:
		return null

	var source_owner_id: int = (
		2 if target_owner_id == 1 else 1
	)

	var source_player: PlayerState = state.get_player(
		source_owner_id
	)

	if source_player == null:
		return null

	for source_slot_id: int in SlotID.all_slots():
		var source_card: CardInstance = source_player.board.get_card(
			source_slot_id
		)

		if source_card == null:
			continue

		if source_card.definition == null:
			continue

		var behavior := (
			source_card.definition.behavior
			as DisableGestureBehavior
		)

		if behavior == null:
			continue

		var source_view := card_views.get(
			source_card.instance_id,
			null
		) as Card3D

		if source_view == null:
			continue

		if not source_view.visible:
			continue

		if behavior.disables_target(
			source_slot_id,
			target_slot_id,
			target_card
		):
			return source_card

	return null


func _start_animated_combat() -> void:
	interaction_locked = true

	await _play_collector_vfx_before_combat()

	var sequence: BattleSequence = engine.begin_combat()

	if sequence == null:
		push_error("Could not begin battle sequence.")
		interaction_locked = false
		hud.set_interaction_enabled(true)
		return

	await _sync_visual_state()

	_refresh_board_disabled_visuals(false)
	_refresh_battle_scores()

	print(
		"ANIMATED COMBAT STARTED | acts=",
		sequence.acts.size()
	)

	# Combat is presented in three fast visual phases:
	# 1) Both players attack the Dealer together.
	# 2) Front-row PvP clashes.
	# 3) Back-row PvP clashes.
	#
	# BattleResolver still owns all combat rules. This controller only groups
	# the already-created BattleActs so the animation is faster and clearer.
	await _play_grouped_combat_sequence(sequence)

	# تمام Clashهای هر دو بازیکن کامل محاسبه شده‌اند.
	# حالا برای اولین بار اختلاف نهایی را بررسی می‌کنیم.
	var game_ended: bool = \
		engine.finalize_combat_score()

	_refresh_battle_scores()

	if game_ended:
		_finish_game()
		return

	var retained_cards: Array[CardInstance] = \
		_take_selected_cards_from_local_hand()

	# یادمان باشد الان چه کارت‌هایی روی زمین Dealer هستند.
	var previous_dealer_card_ids: Dictionary = \
		_get_dealer_card_ids()

	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.prepare_next_dealer_before_finish_combat()

	engine.finish_combat()

	_restore_retained_cards_to_local_hand(
		retained_cards
	)

	_return_excess_local_hand_cards_to_draw_pile()

	kept_hand_card_ids.clear()

	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.prepare_new_turn_state()

	# Turn جدید کامل ساخته شده ولی Player هنوز حرکت مخفی انجام نداده.
	# این وضعیت، حافظه عمومی Fair Bot برای کل این Turn است.
	_capture_fair_bot_knowledge()

	await _sync_visual_state()
	# هر Dealer card جدیدی که Placed VFX دارد، الان افکتش را پخش کن.
	await _play_new_dealer_placed_vfx(
		previous_dealer_card_ids
	)
	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.sync_visual_visibility()

	hud.refresh(
		state,
		local_player_id
	)

	_refresh_battle_scores()
	_refresh_board_disabled_visuals(false)

	interaction_locked = false
	hud.set_interaction_enabled(true)

	if tutorial_controller != null and tutorial_controller.is_active():
		tutorial_controller.notify_combat_finished()


func _play_grouped_combat_sequence(
	sequence: BattleSequence
) -> void:
	if sequence == null:
		return

	var acts: Array[BattleAct] = sequence.acts

	# Dealer combat is now split by row:
	# FRONT rises/attacks/returns first, then BACK does the same.
	await _play_dealer_row_combat_phase(
		acts,
		SlotID.Row.FRONT
	)

	if combat_phase_pause > 0.0:
		await get_tree().create_timer(
			combat_phase_pause
		).timeout

	await _play_dealer_row_combat_phase(
		acts,
		SlotID.Row.BACK
	)

	if combat_phase_pause > 0.0:
		await get_tree().create_timer(
			combat_phase_pause
		).timeout

	# PvP follows the same front-then-back presentation.
	await _play_pvp_row_combat_phase(
		acts,
		SlotID.Row.FRONT
	)

	if combat_phase_pause > 0.0:
		await get_tree().create_timer(
			combat_phase_pause
		).timeout

	await _play_pvp_row_combat_phase(
		acts,
		SlotID.Row.BACK
	)

	# Safety net for future BattleAct types.
	for act: BattleAct in acts:
		if act == null:
			continue

		if act.resolved:
			continue

		await _animate_battle_act(act)
		engine.apply_battle_act(act)
		_refresh_board_shield_visuals()
		_refresh_battle_scores()


func _play_dealer_row_combat_phase(
	acts: Array[BattleAct],
	row: int
) -> void:
	var row_dealer_acts: Array[BattleAct] = []

	for act: BattleAct in acts:
		if act == null:
			continue

		if not (
			act.type in [
				BattleAct.Type.PLAYER_VS_DEALER,
				BattleAct.Type.MUSTACHE_SWEEP,
				BattleAct.Type.CHAINSAW_SWEEP
			]
		):
			continue

		if not SlotID.is_valid(act.attacker_slot_id):
			continue

		if SlotID.get_row(act.attacker_slot_id) != row:
			continue

		row_dealer_acts.append(act)

	if row_dealer_acts.is_empty():
		return

	# All participating cards in THIS row rise together.
	var original_positions: Dictionary = await _lift_cards_for_acts(
		row_dealer_acts,
		false
	)

	var regular_waves: Array = \
		_build_dealer_regular_waves_for_row(
			row_dealer_acts,
			row
		)

	# Schedule regular attacks with real overlap.
	# Different cards can start before the previous attack has returned.
	# A card that is used again (important in the middle lane) is locked until
	# its previous attack cycle has finished.
	await _play_overlapped_dealer_waves(
		regular_waves
	)

	# Special sweep acts keep their dedicated VFX sequence. They are still
	# row-scoped, but are not mixed into overlapping position tweens because
	# they can move several cards at once.
	for special_act: BattleAct in row_dealer_acts:
		if special_act == null or special_act.resolved:
			continue

		if (
			special_act.type != BattleAct.Type.MUSTACHE_SWEEP
			and special_act.type != BattleAct.Type.CHAINSAW_SWEEP
		):
			continue

		await _animate_battle_act(special_act)
		engine.apply_battle_act(special_act)
		_refresh_board_shield_visuals()
		_refresh_battle_scores()

	await _restore_lifted_cards(original_positions)


func _build_dealer_regular_waves_for_row(
	acts: Array[BattleAct],
	row: int
) -> Array:
	var waves: Array = []
	var row_slots: Array[int] = _get_board_slots_for_row(row)

	# First pass: one target per card. This lets LEFT, MIDDLE and RIGHT attacks
	# overlap visibly instead of waiting for a complete attack-return cycle.
	for slot_id: int in row_slots:
		var targets: Array[int] = \
			_get_dealer_targets_for_board_slot(slot_id)

		if targets.is_empty():
			continue

		var first_wave: Array[BattleAct] = \
			_collect_dealer_wave(
				acts,
				slot_id,
				targets[0]
			)

		if not first_wave.is_empty():
			waves.append(first_wave)

	# Second pass: only middle cards have a second Dealer target.
	# The overlap scheduler below knows these cards are reused and waits just
	# long enough for that specific card to be free again.
	for slot_id: int in row_slots:
		var targets: Array[int] = \
			_get_dealer_targets_for_board_slot(slot_id)

		if targets.size() < 2:
			continue

		var second_wave: Array[BattleAct] = \
			_collect_dealer_wave(
				acts,
				slot_id,
				targets[1]
			)

		if not second_wave.is_empty():
			waves.append(second_wave)

	return waves


func _collect_dealer_wave(
	acts: Array[BattleAct],
	slot_id: int,
	dealer_slot_id: int
) -> Array[BattleAct]:
	var wave: Array[BattleAct] = []

	for act: BattleAct in acts:
		if act == null or act.resolved:
			continue

		if act.type != BattleAct.Type.PLAYER_VS_DEALER:
			continue

		if act.attacker_slot_id != slot_id:
			continue

		if act.dealer_slot_id != dealer_slot_id:
			continue

		# Same board slot + same Dealer target means P1 and P2 can attack
		# together in the same visual wave.
		wave.append(act)

	return wave


func _play_overlapped_dealer_waves(
	waves: Array
) -> void:
	if waves.is_empty():
		return

	var available_at: Dictionary = {}
	var schedules: Array[Dictionary] = []
	var base_start: float = 0.0
	var cycle_time: float = _get_regular_attack_cycle_time()

	for wave_variant: Array in waves:
		var wave: Array[BattleAct] = []
		wave.assign(wave_variant)

		if wave.is_empty():
			continue

		var start_at: float = base_start

		for act: BattleAct in wave:
			if act == null or act.attacker == null:
				continue

			var attacker_id: int = act.attacker.instance_id
			start_at = maxf(
				start_at,
				float(available_at.get(attacker_id, 0.0))
			)

			# A Dealer card may be targeted by several middle-lane attacks.
			# Do not start a second impact on that exact Dealer until its short
			# recoil has recovered; attacks on other Dealer cards still overlap.
			if act.defender != null:
				var dealer_id: int = act.defender.instance_id
				start_at = maxf(
					start_at,
					float(available_at.get(dealer_id, 0.0))
				)

		for act: BattleAct in wave:
			if act == null or act.attacker == null:
				continue

			var attacker_lock_time: float = cycle_time

			if act.attacker_owner_id == local_player_id:
				attacker_lock_time = maxf(
					attacker_lock_time,
					combat_attack_time
					+ _get_result_vfx_duration(
						act.attacker_outcome
					)
				)

			available_at[act.attacker.instance_id] = \
				start_at + attacker_lock_time

			if act.defender != null:
				available_at[act.defender.instance_id] = maxf(
					float(available_at.get(
						act.defender.instance_id,
						0.0
					)),
					start_at
					+ dealer_recoil_out_time
					+ dealer_recoil_return_time
				)

		schedules.append({
			"wave": wave,
			"delay": start_at
		})

		# This is a START gap, not a "wait until animation finished" gap.
		base_start += combat_attack_gap

	if schedules.is_empty():
		return

	var tracker: Dictionary = {
		"remaining": schedules.size()
	}

	for schedule: Dictionary in schedules:
		var scheduled_wave: Array[BattleAct] = []
		scheduled_wave.assign(
			schedule.get("wave", [])
		)

		var delay: float = float(
			schedule.get("delay", 0.0)
		)

		_run_dealer_wave_overlapped(
			scheduled_wave,
			delay,
			tracker
		)

	await _wait_for_overlap_tracker(tracker)


func _run_dealer_wave_overlapped(
	wave: Array[BattleAct],
	delay: float,
	tracker: Dictionary
) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	await _animate_player_vs_dealer_wave(wave)

	for act: BattleAct in wave:
		if act == null or act.resolved:
			continue

		engine.apply_battle_act(act)

	_refresh_board_shield_visuals()
	_refresh_battle_scores()
	_finish_overlap_tracker_step(tracker)


func _play_pvp_row_combat_phase(
	acts: Array[BattleAct],
	row: int
) -> void:
	var row_acts: Array[BattleAct] = []

	for act: BattleAct in acts:
		if act == null:
			continue

		if act.type != BattleAct.Type.PLAYER_VS_PLAYER:
			continue

		if not SlotID.is_valid(act.attacker_slot_id):
			continue

		if SlotID.get_row(act.attacker_slot_id) != row:
			continue

		row_acts.append(act)

	if row_acts.is_empty():
		return

	# All cards involved in this PvP row rise together first.
	var original_positions: Dictionary = await _lift_cards_for_acts(
		row_acts,
		true
	)

	# Real overlap with collision-safe scheduling:
	# independent clashes are staggered by combat_attack_gap, but if a middle
	# card appears in another clash, that specific clash waits for the card.
	await _play_overlapped_pvp_acts(row_acts)

	await _restore_lifted_cards(original_positions)


func _play_overlapped_pvp_acts(
	acts: Array[BattleAct]
) -> void:
	if acts.is_empty():
		return

	var available_at: Dictionary = {}
	var schedules: Array[Dictionary] = []
	var base_start: float = 0.0
	var cycle_time: float = _get_regular_attack_cycle_time()

	for act: BattleAct in acts:
		if act == null or act.resolved:
			continue

		if act.attacker == null or act.defender == null:
			continue

		var start_at: float = base_start
		var attacker_id: int = act.attacker.instance_id
		var defender_id: int = act.defender.instance_id

		start_at = maxf(
			start_at,
			float(available_at.get(attacker_id, 0.0))
		)
		start_at = maxf(
			start_at,
			float(available_at.get(defender_id, 0.0))
		)

		var attacker_lock_time: float = cycle_time
		var defender_lock_time: float = cycle_time

		if act.attacker_owner_id == local_player_id:
			attacker_lock_time = maxf(
				attacker_lock_time,
				combat_attack_time
				+ _get_result_vfx_duration(
					act.attacker_outcome
				)
			)

		if act.defender_owner_id == local_player_id:
			defender_lock_time = maxf(
				defender_lock_time,
				combat_attack_time
				+ _get_result_vfx_duration(
					act.defender_outcome
				)
			)

		available_at[attacker_id] = \
			start_at + attacker_lock_time
		available_at[defender_id] = \
			start_at + defender_lock_time

		schedules.append({
			"act": act,
			"delay": start_at
		})

		base_start += combat_attack_gap

	if schedules.is_empty():
		return

	var tracker: Dictionary = {
		"remaining": schedules.size()
	}

	for schedule: Dictionary in schedules:
		var scheduled_act := schedule.get(
			"act",
			null
		) as BattleAct

		if scheduled_act == null:
			_finish_overlap_tracker_step(tracker)
			continue

		var delay: float = float(
			schedule.get("delay", 0.0)
		)

		_run_pvp_act_overlapped(
			scheduled_act,
			delay,
			tracker
		)

	await _wait_for_overlap_tracker(tracker)


func _run_pvp_act_overlapped(
	act: BattleAct,
	delay: float,
	tracker: Dictionary
) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	await _animate_player_clash(act)

	if not act.resolved:
		engine.apply_battle_act(act)

	_refresh_board_shield_visuals()
	_refresh_battle_scores()
	_finish_overlap_tracker_step(tracker)


func _wait_for_overlap_tracker(
	tracker: Dictionary
) -> void:
	while int(tracker.get("remaining", 0)) > 0:
		await overlap_combat_step_finished


func _finish_overlap_tracker_step(
	tracker: Dictionary
) -> void:
	var remaining: int = max(
		0,
		int(tracker.get("remaining", 0)) - 1
	)

	tracker["remaining"] = remaining
	overlap_combat_step_finished.emit()


func _get_regular_attack_cycle_time() -> float:
	return (
		combat_attack_time
		+ combat_hit_pause
		+ combat_return_time
	)


func _get_board_slots_for_row(
	row: int
) -> Array[int]:
	if row == SlotID.Row.FRONT:
		return [
			SlotID.Type.FRONT_LEFT,
			SlotID.Type.FRONT_MIDDLE_0,
			SlotID.Type.FRONT_MIDDLE_1,
			SlotID.Type.FRONT_RIGHT
		]

	return [
		SlotID.Type.BACK_LEFT,
		SlotID.Type.BACK_MIDDLE_0,
		SlotID.Type.BACK_MIDDLE_1,
		SlotID.Type.BACK_RIGHT
	]


func _get_dealer_targets_for_board_slot(
	slot_id: int
) -> Array[int]:
	match slot_id:
		SlotID.Type.FRONT_LEFT, SlotID.Type.BACK_LEFT:
			return [DealerSlotID.Type.LEFT]

		SlotID.Type.FRONT_RIGHT, SlotID.Type.BACK_RIGHT:
			return [DealerSlotID.Type.RIGHT]

		SlotID.Type.FRONT_MIDDLE_0, \
		SlotID.Type.FRONT_MIDDLE_1, \
		SlotID.Type.BACK_MIDDLE_0, \
		SlotID.Type.BACK_MIDDLE_1:
			# Middle is intentionally different: each player middle card
			# attacks both Dealer middle cards.
			return [
				DealerSlotID.Type.MIDDLE_0,
				DealerSlotID.Type.MIDDLE_1
			]

	return []


func _lift_cards_for_acts(
	acts: Array[BattleAct],
	include_defenders: bool
) -> Dictionary:
	var original_positions: Dictionary = {}
	var views_to_lift: Array[Card3D] = []

	for act: BattleAct in acts:
		if act == null:
			continue

		var cards: Array[CardInstance] = []

		if act.attacker != null:
			cards.append(act.attacker)

		if include_defenders and act.defender != null:
			cards.append(act.defender)

		for card: CardInstance in cards:
			if card == null:
				continue

			if original_positions.has(card.instance_id):
				continue

			var card_view := card_views.get(
				card.instance_id,
				null
			) as Card3D

			if card_view == null:
				continue

			if not is_instance_valid(card_view):
				continue

			original_positions[card.instance_id] = \
				card_view.global_position
			views_to_lift.append(card_view)

	if views_to_lift.is_empty():
		return original_positions

	var lift_tween: Tween = create_tween()
	lift_tween.set_parallel(true)

	for card_view: Card3D in views_to_lift:
		if not is_instance_valid(card_view):
			continue

		var lifted_position: Vector3 = \
			card_view.global_position + Vector3.UP * combat_lift_height

		lift_tween.tween_property(
			card_view,
			"global_position",
			lifted_position,
			combat_lift_time
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)

	await lift_tween.finished
	return original_positions


func _restore_lifted_cards(
	original_positions: Dictionary
) -> void:
	if original_positions.is_empty():
		return

	var return_tween: Tween = create_tween()
	return_tween.set_parallel(true)
	var has_valid_view: bool = false

	for raw_instance_id: Variant in original_positions.keys():
		var instance_id: int = int(raw_instance_id)
		var card_view := card_views.get(
			instance_id,
			null
		) as Card3D

		if card_view == null:
			continue

		if not is_instance_valid(card_view):
			continue

		has_valid_view = true
		return_tween.tween_property(
			card_view,
			"global_position",
			original_positions[raw_instance_id],
			combat_lift_time
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_IN
		)

	if has_valid_view:
		await return_tween.finished


func _animate_player_vs_dealer_wave(
	wave: Array[BattleAct]
) -> void:
	if wave.is_empty():
		return

	var start_positions: Dictionary = {}
	var valid_acts: Array[BattleAct] = []
	var attack_tween: Tween = create_tween()
	attack_tween.set_parallel(true)

	for act: BattleAct in wave:
		if act == null:
			continue

		if act.attacker == null or act.defender == null:
			continue

		var attacker_view := card_views.get(
			act.attacker.instance_id,
			null
		) as Card3D

		var dealer_view := card_views.get(
			act.defender.instance_id,
			null
		) as Card3D

		if attacker_view == null or dealer_view == null:
			continue

		if not is_instance_valid(attacker_view):
			continue

		if not is_instance_valid(dealer_view):
			continue

		var attacker_start: Vector3 = \
			attacker_view.global_position
		var dealer_position: Vector3 = \
			dealer_view.global_position

		# Dealer combat must read as an attack ON the Dealer, not as a PvP
		# midpoint clash. Stop almost on top of the Dealer card.
		var hit_position: Vector3 = dealer_position.lerp(
			attacker_start,
			dealer_attack_stop_ratio
		)
		hit_position.y += 0.10

		start_positions[act.attacker.instance_id] = attacker_start
		valid_acts.append(act)

		attack_tween.tween_property(
			attacker_view,
			"global_position",
			hit_position,
			combat_attack_time
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_IN
		)

	if valid_acts.is_empty():
		return

	await attack_tween.finished

	# Make the Dealer visibly absorb the hit. This is the key visual
	# distinction from PvP, where both player cards travel to a midpoint.
	_start_dealer_hit_reactions(valid_acts, start_positions)

	# The local player's WIN / LOSS / DRAW pops at the hit moment.
	# It keeps playing while the card returns, so combat stays fast.
	var result_tracker: Dictionary = \
		_start_local_result_vfx_for_acts(valid_acts)

	if combat_hit_pause > 0.0:
		await get_tree().create_timer(
			combat_hit_pause
		).timeout

	var return_tween: Tween = create_tween()
	return_tween.set_parallel(true)

	for act: BattleAct in valid_acts:
		var attacker_view := card_views.get(
			act.attacker.instance_id,
			null
		) as Card3D

		if attacker_view == null:
			continue

		if not is_instance_valid(attacker_view):
			continue

		return_tween.tween_property(
			attacker_view,
			"global_position",
			start_positions[act.attacker.instance_id],
			combat_return_time
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)

	await return_tween.finished

	# If the Dealer recoil is a hair longer than the attacker return, finish
	# that impact before this wave reports itself complete.
	var dealer_reaction_remaining: float = maxf(
		0.0,
		dealer_recoil_out_time
		+ dealer_recoil_return_time
		- combat_hit_pause
		- combat_return_time
	)
	if dealer_reaction_remaining > 0.0:
		await get_tree().create_timer(dealer_reaction_remaining).timeout

	await _wait_for_result_vfx_tracker(result_tracker)


func _start_dealer_hit_reactions(
	acts: Array[BattleAct],
	attacker_start_positions: Dictionary
) -> void:
	var processed_dealers: Dictionary = {}

	for act: BattleAct in acts:
		if act == null or act.defender == null:
			continue

		var dealer_id: int = act.defender.instance_id
		if processed_dealers.has(dealer_id):
			continue
		processed_dealers[dealer_id] = true

		var dealer_view := card_views.get(
			dealer_id,
			null
		) as Card3D
		if dealer_view == null or not is_instance_valid(dealer_view):
			continue

		var dealer_start: Vector3 = dealer_view.global_position
		var away_vector: Vector3 = Vector3.ZERO

		# Average the incoming attack directions. If P1 and P2 hit the same
		# Dealer from opposite sides, horizontal recoil cancels naturally but
		# the upward pop still makes the impact obvious.
		for source_act: BattleAct in acts:
			if source_act == null or source_act.defender == null:
				continue
			if source_act.defender.instance_id != dealer_id:
				continue
			if source_act.attacker == null:
				continue

			var attacker_start_variant: Variant = attacker_start_positions.get(
				source_act.attacker.instance_id,
				null
			)
			if attacker_start_variant == null:
				continue

			var attacker_start: Vector3 = attacker_start_variant
			var incoming_away: Vector3 = dealer_start - attacker_start
			incoming_away.y = 0.0
			if incoming_away.length_squared() > 0.0001:
				away_vector += incoming_away.normalized()

		if away_vector.length_squared() > 0.0001:
			away_vector = away_vector.normalized()

		var recoil_target: Vector3 = dealer_start
		recoil_target += away_vector * dealer_recoil_distance
		recoil_target += Vector3.UP * dealer_recoil_height

		var reaction_tween: Tween = create_tween()
		reaction_tween.tween_property(
			dealer_view,
			"global_position",
			recoil_target,
			dealer_recoil_out_time
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)

		reaction_tween.tween_property(
			dealer_view,
			"global_position",
			dealer_start,
			dealer_recoil_return_time
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_IN
		)




func _take_selected_cards_from_local_hand() -> Array[CardInstance]:
	var retained_cards: Array[CardInstance] = []

	if state == null:
		return retained_cards

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return retained_cards

	for index: int in range(
		player.hand.size() - 1,
		-1,
		-1
	):
		var card: CardInstance = player.hand[index]

		if card == null:
			continue

		if not kept_hand_card_ids.has(
			card.instance_id
		):
			continue

		player.hand.remove_at(index)
		retained_cards.push_front(card)

	return retained_cards


func _restore_retained_cards_to_local_hand(
	retained_cards: Array[CardInstance]
) -> void:
	if state == null:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	for index: int in range(retained_cards.size()):
		var card: CardInstance = retained_cards[index]

		if card == null:
			continue

		card.zone = CardZone.Type.HAND
		player.hand.insert(index, card)


func _return_excess_local_hand_cards_to_draw_pile() -> void:
	if state == null:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	while player.hand.size() > MAX_HAND_CARDS:
		var card: CardInstance = player.hand.pop_back()

		if card == null:
			continue

		card.zone = CardZone.Type.DRAW
		card.current_slot = CardInstance.NO_SLOT
		player.draw_pile.append(card)

func _animate_battle_act(
	act: BattleAct
) -> void:
	if act == null:
		return

	match act.type:
		BattleAct.Type.PLAYER_VS_DEALER:
			await _animate_player_vs_dealer(
				act
			)

		BattleAct.Type.PLAYER_VS_PLAYER:
			await _animate_player_clash(
				act
			)

		BattleAct.Type.MUSTACHE_SWEEP:
			await _play_mustache_card_sequence(
				act
			)
			await _play_local_result_vfx_for_act(act)

		BattleAct.Type.CHAINSAW_SWEEP:
			await _play_card_ability_vfx_for_act(
				act
			)
			await _play_local_result_vfx_for_act(act)


func _play_mustache_card_sequence(
	act: BattleAct
) -> void:
	if act == null:
		return

	if act.attacker == null:
		return

	if act.attacker.definition == null:
		return

	if vfx_manager == null:
		push_error("CardVFXManager3D is missing.")
		return

	var mustache_view := card_views.get(
		act.attacker.instance_id,
		null
	) as Card3D

	var vfx_definition: CardVFXDefinition = (
		act.attacker.definition.ability_vfx
	)

	if vfx_definition == null:
		push_warning(
			"Mustache card has no ability VFX resource."
		)
		return

	var affected_views: Array[Card3D] = []
	var start_positions: Array[Vector3] = []

	if mustache_view != null:
		affected_views.append(mustache_view)
		start_positions.append(
			mustache_view.global_position
		)

	var owner: PlayerState = state.get_player(
		act.attacker_owner_id
	)

	if owner != null:
		for slot_id: int in SlotID.all_slots():
			var rock_card: CardInstance = owner.board.get_card(
				slot_id
			)

			if rock_card == null:
				continue

			if rock_card == act.attacker:
				continue

			if rock_card.definition == null:
				continue

			if (
				rock_card.definition.gesture
				!= CardGesture.Type.ROCK
			):
				continue

			var rock_view := card_views.get(
				rock_card.instance_id,
				null
			) as Card3D

			if rock_view == null:
				continue

			if affected_views.has(rock_view):
				continue

			affected_views.append(rock_view)
			start_positions.append(
				rock_view.global_position
			)

	var center_position: Vector3 = (
		vfx_manager.get_spawn_transform(
			vfx_definition,
			mustache_view
		).origin
	)

	if not affected_views.is_empty():
		var gather_tween: Tween = create_tween()
		gather_tween.set_parallel(true)

		for card_view: Card3D in affected_views:
			gather_tween.tween_property(
				card_view,
				"global_position",
				center_position,
				0.28
			).set_trans(
				Tween.TRANS_QUAD
			).set_ease(
				Tween.EASE_IN
			)

		await gather_tween.finished

		for card_view: Card3D in affected_views:
			if is_instance_valid(card_view):
				card_view.visible = false

	var effect_duration: float = _play_card_ability_vfx(
		act.attacker,
		mustache_view
	)

	if effect_duration > 0.0:
		await get_tree().create_timer(
			effect_duration
		).timeout

	if affected_views.is_empty():
		return

	for card_view: Card3D in affected_views:
		if not is_instance_valid(card_view):
			continue

		card_view.global_position = center_position
		card_view.visible = true

	var return_tween: Tween = create_tween()
	return_tween.set_parallel(true)

	for index: int in range(affected_views.size()):
		var card_view: Card3D = affected_views[index]

		if not is_instance_valid(card_view):
			continue

		return_tween.tween_property(
			card_view,
			"global_position",
			start_positions[index],
			0.32
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)

	await return_tween.finished


func _play_card_ability_vfx_for_act(
	act: BattleAct
) -> void:
	if act == null:
		return

	if act.attacker == null:
		return

	var source_view := card_views.get(
		act.attacker.instance_id,
		null
	) as Card3D

	var effect_duration: float = _play_card_ability_vfx(
		act.attacker,
		source_view
	)

	if effect_duration > 0.0:
		await get_tree().create_timer(
			effect_duration
		).timeout


func _play_card_ability_vfx(
	card: CardInstance,
	source_view: Card3D
) -> float:
	if card == null:
		return 0.0

	if card.definition == null:
		return 0.0

	if vfx_manager == null:
		return 0.0

	return vfx_manager.play_vfx(
		card.definition.ability_vfx,
		source_view
	)

func _animate_player_vs_dealer(
	act: BattleAct
) -> void:
	if act == null:
		return

	if act.attacker == null:
		return

	if act.defender == null:
		return



	var attacker_view := card_views.get(
		act.attacker.instance_id,
		null
	) as Card3D

	var dealer_view := card_views.get(
		act.defender.instance_id,
		null
	) as Card3D

	if attacker_view == null:
		push_error(
			"Missing attacker view: %s | id=%s"
			% [
				act.attacker.definition.display_name,
				act.attacker.instance_id
			]
		)
		return

	if dealer_view == null:
		push_error(
			"Missing dealer view: %s | id=%s"
			% [
				act.defender.definition.display_name,
				act.defender.instance_id
			]
		)
		return

	var attacker_start: Vector3 = \
		attacker_view.global_position

	var dealer_position: Vector3 = \
		dealer_view.global_position

	var hit_position: Vector3 = dealer_position.lerp(
		attacker_start,
		dealer_attack_stop_ratio
	)

	hit_position.y += 0.10

	var attack_tween: Tween = create_tween()

	attack_tween.tween_property(
		attacker_view,
		"global_position",
		hit_position,
		combat_attack_time
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	await attack_tween.finished

	var fallback_positions: Dictionary = {
		act.attacker.instance_id: attacker_start
	}
	_start_dealer_hit_reactions([act], fallback_positions)

	var result_tracker: Dictionary = \
		_start_local_result_vfx_for_act(act)

	await get_tree().create_timer(
		combat_hit_pause
	).timeout

	var return_tween: Tween = create_tween()

	return_tween.tween_property(
		attacker_view,
		"global_position",
		attacker_start,
		combat_return_time
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	await return_tween.finished

	var dealer_reaction_remaining: float = maxf(
		0.0,
		dealer_recoil_out_time
		+ dealer_recoil_return_time
		- combat_hit_pause
		- combat_return_time
	)
	if dealer_reaction_remaining > 0.0:
		await get_tree().create_timer(dealer_reaction_remaining).timeout

	await _wait_for_result_vfx_tracker(result_tracker)

func _animate_player_clash(
	act: BattleAct
) -> void:
	if act == null:
		return

	if act.attacker == null:
		return

	if act.defender == null:
		return

	var first_view := card_views.get(
		act.attacker.instance_id,
		null
	) as Card3D

	var second_view := card_views.get(
		act.defender.instance_id,
		null
	) as Card3D

	if first_view == null:
		push_error(
			"Missing first clash view: %s"
			% act.attacker.definition.display_name
		)
		return

	if second_view == null:
		push_error(
			"Missing second clash view: %s"
			% act.defender.definition.display_name
		)
		return

	var first_start: Vector3 = \
		first_view.global_position

	var second_start: Vector3 = \
		second_view.global_position

	var clash_center: Vector3 = (
		first_start + second_start
	) * 0.5

	# Cards are already lifted before the PvP phase, so the clash only needs
	# a small extra rise instead of the old large jump.
	clash_center.y += 0.12

	var direction: Vector3 = \
		second_start - first_start

	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()

	var first_target: Vector3 = \
		clash_center - direction * 0.08

	var second_target: Vector3 = \
		clash_center + direction * 0.08

	var clash_tween: Tween = create_tween()
	clash_tween.set_parallel(true)

	clash_tween.tween_property(
		first_view,
		"global_position",
		first_target,
		combat_attack_time
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	clash_tween.tween_property(
		second_view,
		"global_position",
		second_target,
		combat_attack_time
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	await clash_tween.finished

	var result_tracker: Dictionary = \
		_start_local_result_vfx_for_act(act)

	await get_tree().create_timer(
		combat_hit_pause
	).timeout

	var return_tween: Tween = create_tween()
	return_tween.set_parallel(true)

	return_tween.tween_property(
		first_view,
		"global_position",
		first_start,
		combat_return_time
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	return_tween.tween_property(
		second_view,
		"global_position",
		second_start,
		combat_return_time
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	await return_tween.finished
	await _wait_for_result_vfx_tracker(result_tracker)

func _start_local_result_vfx_for_act(
	act: BattleAct
) -> Dictionary:
	var acts: Array[BattleAct] = []
	acts.append(act)
	return _start_local_result_vfx_for_acts(acts)


func _start_local_result_vfx_for_acts(
	acts: Array[BattleAct]
) -> Dictionary:
	var tracker: Dictionary = {
		"remaining": 0
	}

	for act: BattleAct in acts:
		var result_data: Dictionary = \
			_get_local_result_data(act)

		if result_data.is_empty():
			continue

		var card := result_data.get(
			"card",
			null
		) as CardInstance
		var outcome: int = int(
			result_data.get(
				"outcome",
				BattleAct.Outcome.TIE
			)
		)

		if card == null:
			continue

		var frames: SpriteFrames = \
			_get_result_frames(outcome)

		if frames == null:
			continue

		var card_view := card_views.get(
			card.instance_id,
			null
		) as Card3D

		if card_view == null:
			continue

		if not is_instance_valid(card_view):
			continue

		tracker["remaining"] = \
			int(tracker.get("remaining", 0)) + 1

		_run_local_result_vfx(
			card_view,
			frames,
			tracker
		)

	return tracker


func _play_local_result_vfx_for_act(
	act: BattleAct
) -> void:
	var tracker: Dictionary = \
		_start_local_result_vfx_for_act(act)

	await _wait_for_result_vfx_tracker(tracker)


func _run_local_result_vfx(
	card_view: Card3D,
	frames: SpriteFrames,
	tracker: Dictionary
) -> void:
	if card_view == null or not is_instance_valid(card_view):
		_finish_result_vfx_tracker_step(tracker)
		return

	var result_vfx := COMBAT_RESULT_VFX_SCRIPT.new() \
		as CombatResultVFX3D

	if result_vfx == null:
		_finish_result_vfx_tracker_step(tracker)
		return

	card_view.add_child(result_vfx)
	result_vfx.position = result_local_offset

	await result_vfx.play_and_wait(
		frames,
		result_animation_name,
		result_pixel_size,
		result_loop_fallback_duration
	)

	_finish_result_vfx_tracker_step(tracker)


func _wait_for_result_vfx_tracker(
	tracker: Dictionary
) -> void:
	while int(tracker.get("remaining", 0)) > 0:
		await combat_result_vfx_finished


func _finish_result_vfx_tracker_step(
	tracker: Dictionary
) -> void:
	tracker["remaining"] = max(
		0,
		int(tracker.get("remaining", 0)) - 1
	)
	combat_result_vfx_finished.emit()


func _get_local_result_data(
	act: BattleAct
) -> Dictionary:
	if act == null:
		return {}

	if (
		act.attacker_owner_id == local_player_id
		and act.attacker != null
	):
		return {
			"card": act.attacker,
			"outcome": act.attacker_outcome
		}

	if (
		act.defender_owner_id == local_player_id
		and act.defender != null
	):
		return {
			"card": act.defender,
			"outcome": act.defender_outcome
		}

	return {}


func _get_result_frames(
	outcome: int
) -> SpriteFrames:
	match outcome:
		BattleAct.Outcome.WIN:
			return win_result_frames

		BattleAct.Outcome.LOSS:
			return loss_result_frames

		_:
			return draw_result_frames


func _get_result_vfx_duration(
	outcome: int
) -> float:
	var frames: SpriteFrames = _get_result_frames(outcome)

	if frames == null:
		return 0.0

	var animation_name: StringName = \
		_resolve_result_animation_name(frames)

	if animation_name == &"":
		return 0.0

	var fps: float = frames.get_animation_speed(
		animation_name
	)

	if fps <= 0.0:
		return result_loop_fallback_duration

	var total_relative_duration: float = 0.0
	var frame_count: int = frames.get_frame_count(
		animation_name
	)

	for frame_index: int in range(frame_count):
		total_relative_duration += \
			frames.get_frame_duration(
				animation_name,
				frame_index
			)

	return total_relative_duration / fps


func _resolve_result_animation_name(
	frames: SpriteFrames
) -> StringName:
	if frames == null:
		return &""

	if frames.has_animation(result_animation_name):
		return result_animation_name

	if frames.has_animation(&"default"):
		return &"default"

	var names: PackedStringArray = \
		frames.get_animation_names()

	if names.is_empty():
		return &""

	return StringName(names[0])


func _refresh_battle_scores() -> void:
	if engine == null:
		return

	if engine.state == null:
		return

	if hud == null:
		return

	hud.set_scores(
		engine.state.player_one.score,
		engine.state.player_two.score
	)
	_refresh_balance_scale()

func _remove_discarded_card_views() -> void:
	for instance_id: Variant in card_views.keys():
		var card_view := card_views.get(
			instance_id,
			null
		) as Card3D

		if card_view == null:
			continue

		if card_view.card_instance == null:
			continue

		if (
			card_view.card_instance.zone
			!= CardZone.Type.DISCARD
		):
			continue

		card_views.erase(instance_id)
		card_view.queue_free()


func _refresh_pile_entities() -> void:
	if state == null:
		return

	if not is_instance_valid(game_layout):
		return

	for player_id: int in [1, 2]:
		var player: PlayerState = \
			state.get_player(player_id)

		if player == null:
			continue

		for pile_type: int in \
			CardPile3D.Type.values():

			var pile_entity: CardPile3D = \
				game_layout.get_pile_entity(
					player_id,
					pile_type
				)

			if pile_entity == null:
				continue

			pile_entity.refresh_from_player(
				player
			)

func _remove_pile_card_views(
	owner_filter: int = -1
) -> void:
	var card_ids: Array = card_views.keys()

	for raw_id: Variant in card_ids:
		var card_view: Card3D = \
			card_views.get(
				raw_id,
				null
			) as Card3D

		if card_view == null:
			continue

		var card: CardInstance = \
			card_view.card_instance

		if card == null:
			continue

		if (
			owner_filter != -1
			and card.owner_id != owner_filter
		):
			continue

		var is_in_pile: bool = (
			card.zone == CardZone.Type.DRAW
			or card.zone == CardZone.Type.DISCARD
			or card.zone == CardZone.Type.RESERVE
		)

		if not is_in_pile:
			continue

		card_views.erase(raw_id)
		card_view.queue_free()


func _spawn_missing_local_hand_cards() -> void:
	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	for index: int in range(player.hand.size()):
		var card: CardInstance = \
			player.hand[index]

		if card == null:
			continue

		if card_views.has(card.instance_id):
			continue

		var target_transform: Transform3D = \
			game_layout.get_hand_transform(
				local_player_id,
				index,
				player.hand.size()
			)

		var card_view: Card3D = \
			_create_card_view(
				card,
				target_transform,
				true
			)

		if card_view == null:
			continue
		card_view.set_keep_selected(
			kept_hand_card_ids.has(
				card.instance_id
			)
		)
		card_view.drag_requested.connect(
			Callable(
				self,
				"_start_card_drag"
			)
		)


func _reveal_removed_card_views(
	removed_cards: Array[CardInstance]
) -> void:
	if removed_cards.is_empty():
		return

	await get_tree().create_timer(
		0.12
	).timeout

	for removed_card: CardInstance in removed_cards:
		if removed_card == null:
			continue

		var card_view: Card3D = \
			card_views.get(
				removed_card.instance_id,
				null
			) as Card3D

		if card_view == null:
			continue

		card_views.erase(
			removed_card.instance_id
		)

		var tween: Tween = create_tween()

		tween.tween_property(
			card_view,
			"scale",
			Vector3.ZERO,
			reveal_step_time * 0.35
		)

		tween.tween_callback(
			Callable(
				card_view,
				"queue_free"
			)
		)

	await get_tree().create_timer(
		reveal_step_time * 0.35
	).timeout
func _finish_game() -> void:
	interaction_locked = true

	hud.set_interaction_enabled(false)

	hud.refresh(
		state,
		local_player_id
	)

	pending_local_cards.clear()
	pending_bot_plays.clear()

	var local_won: bool = (
		state.winner_id
		== local_player_id
	)

	var local_score: int

	var opponent_score: int

	if local_player_id == 1:
		local_score = state.player_one.score
		opponent_score = state.player_two.score
	else:
		local_score = state.player_two.score
		opponent_score = state.player_one.score

	var score_difference: int = abs(
		local_score
		- opponent_score
	)

	hud.show_game_over(
		local_won,
		local_score,
		opponent_score,
		score_difference
	)

	if local_won:
		print(
			"YOU WIN | difference=",
			score_difference
		)
	else:
		print(
			"YOU LOSE | difference=",
			score_difference
		)
func _refresh_balance_scale() -> void:
	if balance_scale == null:
		return

	if state == null:
		return

	if state.rules == null:
		return

	balance_scale.set_balance(
		state.player_one.score,
		state.player_two.score,
		state.rules.winning_score_difference
	)


func _refresh_board_shield_visuals(
	animate_change: bool = true
) -> void:
	for card_instance_id: int in card_views:
		var card_view: Card3D = card_views[
			card_instance_id
		]

		if card_view == null:
			continue

		var card: CardInstance = (
			_find_board_card_by_instance_id(
				card_instance_id
			)
		)

		if card == null:
			card_view.set_shield_count(
				0,
				false
			)
			continue

		card_view.set_shield_count(
			card.shield_count,
			animate_change
		)


func _find_board_card_by_instance_id(
	instance_id: int
) -> CardInstance:
	if state == null:
		return null

	for player_id: int in [1, 2]:
		var player: PlayerState = state.get_player(
			player_id
		)

		if player == null:
			continue

		for slot_id: int in SlotID.all_slots():
			var card: CardInstance = \
				player.board.get_card(
					slot_id
				)

			if card == null:
				continue

			if card.instance_id == instance_id:
				return card

	return null

func _play_card_placed_vfx(
	card_view: Card3D
) -> float:
	if card_view == null:
		return 0.0

	if card_view.card_instance == null:
		return 0.0

	if card_view.card_instance.definition == null:
		return 0.0

	if vfx_manager == null:
		return 0.0

	return vfx_manager.play_vfx(
		card_view.card_instance.definition.placed_vfx,
		card_view
	)


func _play_card_placement_disable_sequence(
	card_view: Card3D,
	placed_vfx_duration: float = 0.0
) -> void:
	if card_view == null:
		return

	if card_view.card_instance == null:
		return

	if card_view.card_instance.definition == null:
		return

	var disabler_behavior := (
		card_view.card_instance.definition.behavior
		as DisableGestureBehavior
	)

	if disabler_behavior == null:
		return

	if placed_vfx_duration > 0.0:
		await get_tree().create_timer(
			placed_vfx_duration
		).timeout

	var hit_duration: float = _refresh_board_disabled_visuals(
		true
	)

	if hit_duration > 0.0:
		await get_tree().create_timer(
			hit_duration
		).timeout

func _play_collector_vfx_before_combat() -> void:
	if state == null:
		return

	var claimed_target_ids: Dictionary = {}

	for collector_owner_id: int in [1, 2]:
		var collector_owner: PlayerState = \
			state.get_player(collector_owner_id)

		if collector_owner == null:
			continue

		for collector_slot_id: int in SlotID.all_slots():
			var collector_card: CardInstance = \
				collector_owner.board.get_card(
					collector_slot_id
				)

			if collector_card == null:
				continue

			if collector_card.definition == null:
				continue

			var collector_behavior := (
				collector_card.definition.behavior
				as CollectorBehavior
			)

			if collector_behavior == null:
				continue

			# Collector فقط یک بار استفاده می‌شود.
			if collector_card.ability_used:
				continue

			var collector_view := card_views.get(
				collector_card.instance_id,
				null
			) as Card3D

			if collector_view == null:
				continue

			var target_views: Array[Card3D] = []

			# Collector فقط Board صاحب خودش را بررسی می‌کند.
			for target_owner_id: int in [1, 2]:
				if target_owner_id != collector_owner_id:
					continue

				var target_owner: PlayerState = \
					state.get_player(target_owner_id)

				if target_owner == null:
					continue

				for target_slot_id: int in SlotID.all_slots():
					var target_card: CardInstance = \
						target_owner.board.get_card(
							target_slot_id
						)

					if target_card == null:
						continue

					if target_card.definition == null:
						continue

					# خود Collector جمع نمی‌شود.
					if target_card == collector_card:
						continue

					# کارت‌های همین Turn جمع نمی‌شوند.
					if (
						target_card.turn_played
						>= state.turn_number
					):
						continue

					# فقط Gesture مربوط به همین Collector.
					if (
						target_card.definition.gesture
						!= collector_behavior.collected_gesture
					):
						continue

					# یک کارت توسط دو Collector انتخاب نشود.
					if claimed_target_ids.has(
						target_card.instance_id
					):
						continue

					var target_view := card_views.get(
						target_card.instance_id,
						null
					) as Card3D

					if target_view == null:
						continue

					claimed_target_ids[
						target_card.instance_id
					] = true

					target_views.append(target_view)

			print(
				"COLLECTOR START | card=",
				collector_card.definition.display_name,
				" | targets=",
				target_views.size()
			)

			# Collector VFX is instantiated only while this ability is running.
			var effect_duration: float = 0.0

			if vfx_manager != null:
				effect_duration = vfx_manager.play_vfx(
					collector_card.definition.ability_vfx,
					collector_view
				)

			# A short delay lets the effect establish before cards move.
			var pull_delay: float = collector_pull_delay
			var pull_duration: float = 0.55
			var elapsed_time: float = 0.0

			if not target_views.is_empty():
				if pull_delay > 0.0:
					await get_tree().create_timer(
						pull_delay
					).timeout

					elapsed_time += pull_delay

				var pull_tween: Tween = create_tween()

				pull_tween.set_parallel(true)

				pull_tween.set_trans(
					Tween.TRANS_QUAD
				)

				pull_tween.set_ease(
					Tween.EASE_IN
				)

				for target_view: Card3D in target_views:
					if target_view == null:
						continue


					# همه کارت‌ها هم‌زمان به Collector می‌روند.
					pull_tween.tween_property(
						target_view,
						"global_position",
						collector_view.global_position,
						pull_duration
					)

					# همه کارت‌ها هم‌زمان کوچک می‌شوند.
					pull_tween.tween_property(
						target_view,
						"scale",
						Vector3.ZERO,
						pull_duration
					)

				await pull_tween.finished

				elapsed_time += pull_duration

				# حذف واقعی بعداً توسط begin_combat انجام می‌شود.
				for target_view: Card3D in target_views:
					if is_instance_valid(target_view):
						target_view.visible = false

			# اگر انیمیشن Collector هنوز تمام نشده، صبر می‌کنیم.
			var remaining_effect_time: float = (
				effect_duration
				- elapsed_time
			)

			if remaining_effect_time > 0.0:
				await get_tree().create_timer(
					remaining_effect_time
				).timeout
