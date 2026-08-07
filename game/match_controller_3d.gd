class_name MatchController3D
extends Node3D
@export var saw_vfx_spawn: Node3D
@export var saw_sound_volume_db: float = 0.0
const SLOT_COLLISION_MASK: int = 2



@export_range(0.0, 1.0, 0.01)
var collector_pull_delay: float = 0.20
@export_category("Mustache VFX")

@export var MUSTACHE_VFX_SCENE: PackedScene

@export var mustache_vfx_spawn: Node3D

@export_range(0.5, 10.0, 0.1)
var mustache_vfx_lifetime: float = 5.0
@export_category("VFX")
@export var SAW_DIRT_SCENE: PackedScene
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

@export_range(1.0, 6.0, 0.1)
var deck_choice_distance: float = 2.6

@export_range(0.4, 2.0, 0.05)
var deck_choice_spacing: float = 0.90

@export_range(0.5, 4.0, 0.1)
var deck_choice_scale: float = 2.2

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


@export_category("Drag")
@export_range(1, 2, 1)
var local_player_id: int = 1

@export var drag_plane_height: float = 0.25


@export_category("Bot and Reveal")
@export var bot_think_time: float = 0.3
@export var reveal_step_time: float = 0.3
@export var reveal_drop_height: float = 0.4

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


func _ready() -> void:
	# The transparent menu finds this controller through the group.
	add_to_group(&"match_controller")

	if not _resources_are_valid():
		return

	bot_player_id = 2 if local_player_id == 1 else 1

	# Do not build MatchState yet. The player must choose a deck first.
	interaction_locked = true
	hud.visible = false
	hud.set_interaction_enabled(false)

	hud.end_turn_pressed.connect(
		Callable(self, "_on_end_turn_pressed")
	)

	print("Waiting for player deck selection.")


# Called by main_menu_transparent.gd after Single Player or Hardcore.
func begin_deck_selection() -> void:
	if deck_selection_active:
		return

	if state != null:
		return

	deck_selection_active = true
	interaction_locked = true
	hud.visible = false
	hud.set_interaction_enabled(false)

	call_deferred("_spawn_deck_choice_cards")


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

	await _sync_visual_state()

	hud.visible = true
	hud.refresh(
		state,
		local_player_id
	)
	hud.set_interaction_enabled(true)

	interaction_locked = false
	_refresh_balance_scale()

	print("Match started with selected player deck.")


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

	if state == null:
		return

	var player: PlayerState = state.get_player(
		local_player_id
	)

	if player == null:
		return

	if player.is_ready:
		return

	# Bot now plans after the player locks the turn, so it can
	# react to the player cards that were placed this turn.
	_prepare_bot_turn()

	var success: bool = engine.set_player_ready(
		local_player_id
	)

	if not success:
		return

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
	# کارت‌های Coverشده Bot درست هنگام Reveal ناپدید می‌شوند.
	_remove_discarded_card_views()
	await _reveal_cards_one_by_one(
		pending_local_cards,
		pending_bot_plays
	)

	pending_local_cards.clear()
	pending_bot_plays.clear()

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

	await _refresh_opponent_hand_positions()

func _reveal_bot_play(
	play_record: CardPlayRecord
) -> void:
	if play_record == null:
		return

	if play_record.card == null:
		return

	# اول خود کارت Bot وارد زمین می‌شود.
	await _reveal_bot_card(
		play_record.card,
		play_record.slot_id
	)

	# بعد افکت همان کارت نمایش داده می‌شود.
	await _reveal_removed_card_views(
		play_record.removed_cards
	)

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

	card_view.play_killer_placed_effect()
	card_view.play_bomb_placed_effect()

	await _play_card_placement_disable_sequence(
		card_view
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

	if register_as_main_view:
		card_views[card.instance_id] = card_view

	return card_view

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

	dragged_card = card_view
	pointer_start_position = screen_position
	pointer_has_dragged = false

func _input(event: InputEvent) -> void:
	# Deck selection is handled directly by screen position.
	# This does not depend on Card3D's collider or drag signal.
	if deck_selection_active:
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
		return

	if place.kind != CardPlace3D.Kind.PLAYER_BOARD:
		card_view.return_home()
		return

	if place.owner_id != local_player_id:
		card_view.return_home()
		return

	var card: CardInstance = card_view.card_instance

	if card == null:
		card_view.return_home()
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

		card_view.play_killer_placed_effect()
		card_view.play_bomb_placed_effect()

		await _play_card_placement_disable_sequence(
			card_view
		)

		hud.refresh(
			state,
			local_player_id
		)

		await _refresh_hand_positions()
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
		var player: PlayerState = \
			engine.state.get_player(
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

			var card_view := card_views.get(
				card.instance_id,
				null
			) as Card3D

			if card_view == null:
				continue

			var disabled: bool = \
				_is_card_visually_disabled(
					player_id,
					slot_id,
					card
				)

			var hit_duration: float = \
				card_view.set_disabled(
					disabled,
					animate_changes
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
	if state == null:
		return false

	if target_card == null:
		return false

	# Disabler باید متعلق به طرف مقابل باشد.
	var source_owner_id: int = (
		2 if target_owner_id == 1 else 1
	)

	var source_player: PlayerState = \
		state.get_player(
			source_owner_id
		)

	if source_player == null:
		return false

	for source_slot_id: int in SlotID.all_slots():
		var source_card: CardInstance = \
			source_player.board.get_card(
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

		# اگر View کارت Disabler وجود ندارد،
		# یعنی هنوز برای بازیکن Reveal نشده است.
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
			return true

	return false

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

	while sequence.has_next():
		var act: BattleAct = sequence.get_next()

		if act == null:
			continue

		await _animate_battle_act(act)
		engine.apply_battle_act(act)
		_refresh_board_shield_visuals()
		_refresh_battle_scores()

		await get_tree().create_timer(
			0.25
		).timeout

	if state.phase == MatchPhase.Type.GAME_OVER:
		_refresh_battle_scores()
		_finish_game()
		return

	var retained_cards: Array[CardInstance] = \
		_take_selected_cards_from_local_hand()

	engine.finish_combat()

	_restore_retained_cards_to_local_hand(
		retained_cards
	)

	_return_excess_local_hand_cards_to_draw_pile()

	kept_hand_card_ids.clear()

	await _sync_visual_state()

	hud.refresh(
		state,
		local_player_id
	)

	_refresh_battle_scores()
	_refresh_board_disabled_visuals(false)

	interaction_locked = false
	hud.set_interaction_enabled(true)



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
		BattleAct.Type.CHAINSAW_SWEEP:
			if $"../SawVFXSpawn/AnimationPlayer" == null:
				print("animation is null")
			else:
				$"../SawVFXSpawn/AnimationPlayer".play("move")


func _play_mustache_card_sequence(
	act: BattleAct
) -> void:
	if act == null:
		return

	if act.attacker == null:
		return

	if mustache_vfx_spawn == null:
		push_error("Mustache VFX Spawn is missing.")
		return

	var affected_views: Array[Card3D] = []
	var start_positions: Array[Vector3] = []

	# خود کارت سنگ سیبیل
	var mustache_view := card_views.get(
		act.attacker.instance_id,
		null
	) as Card3D

	if mustache_view != null:
		affected_views.append(mustache_view)
		start_positions.append(
			mustache_view.global_position
		)
	# بازیکنی که سنگ سیبیل متعلق به اوست.
	var owner: PlayerState = state.get_player(
		act.attacker_owner_id
	)

	if owner == null:
		await _play_mustache_vfx()
		return

	# تمام کارت‌های ROCK همان بازیکن روی Board
	for slot_id: int in SlotID.all_slots():
		var rock_card: CardInstance = \
			owner.board.get_card(slot_id)

		if rock_card == null:
			continue

		# سنگ سیبیل قبلاً به لیست اضافه شده است.
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

	# حتی اگر View پیدا نشد، خود VFX اجرا شود.
	if affected_views.is_empty():
		await _play_mustache_vfx()
		return

	var center_position: Vector3 = \
		mustache_vfx_spawn.global_position

	# همه کارت‌ها هم‌زمان به وسط می‌روند.
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

	# در وسط غیب می‌شوند.
	for card_view: Card3D in affected_views:
		if is_instance_valid(card_view):
			card_view.visible = false

	# انیمیشن مخصوص فقط یک بار اجرا می‌شود.
	await _play_mustache_vfx()

	# دوباره در همان نقطه ظاهر می‌شوند.
	for card_view: Card3D in affected_views:
		if not is_instance_valid(card_view):
			continue

		card_view.global_position = center_position
		card_view.visible = true

	# هم‌زمان به جای اصلی برمی‌گردند.
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


func _play_mustache_vfx() -> void:
	if MUSTACHE_VFX_SCENE == null:
		push_error("Mustache VFX Scene is missing.")
		return

	if mustache_vfx_spawn == null:
		push_error("Mustache VFX Spawn is missing.")
		return

	var holder := Node3D.new()
	add_child(holder)

	holder.top_level = true
	holder.global_transform = \
		mustache_vfx_spawn.global_transform

	var mustache_vfx := \
		MUSTACHE_VFX_SCENE.instantiate() as Node3D

	if mustache_vfx == null:
		holder.queue_free()
		push_error("Mustache VFX could not be instantiated.")
		return

	holder.add_child(mustache_vfx)

	await get_tree().process_frame

	var animation_player := \
		mustache_vfx.find_child(
			"AnimationPlayer",
			true,
			false
		) as AnimationPlayer

	if animation_player == null:
		holder.queue_free()
		push_error(
			"Mustache VFX AnimationPlayer was not found."
		)
		return

	var animation_name: StringName = \
		animation_player.get_autoplay()

	if animation_name == &"":
		if animation_player.has_animation(&"move"):
			animation_name = &"move"
		else:
			for candidate: StringName in \
					animation_player.get_animation_list():

				if candidate == &"RESET":
					continue

				animation_name = candidate
				break

	if animation_name == &"":
		holder.queue_free()
		push_error(
			"Mustache VFX has no playable animation."
		)
		return

	print(
		"MUSTACHE VFX STARTED | animation=",
		animation_name
	)

	animation_player.play(animation_name)

	await animation_player.animation_finished

	if is_instance_valid(holder):
		holder.queue_free()
func _play_saw_dirt_vfx() -> void:
	if SAW_DIRT_SCENE == null:
		push_error("Saw Dirt Scene is missing.")
		return

	if saw_vfx_spawn == null:
		push_error("Saw VFX Spawn is missing.")
		return

	var holder := Node3D.new()
	add_child(holder)

	holder.top_level = true
	holder.global_transform = saw_vfx_spawn.global_transform

	var saw_vfx := SAW_DIRT_SCENE.instantiate() as Node3D

	if saw_vfx == null:
		holder.queue_free()
		push_error("Saw VFX could not be instantiated.")
		return

	holder.add_child(saw_vfx)

	# صبر می‌کنیم تمام Childها وارد SceneTree شوند.
	await get_tree().process_frame

	# ریشه و تمام فرزندان VFX را جمع می‌کنیم.
	var all_nodes: Array[Node] = [saw_vfx]
	var node_index: int = 0

	while node_index < all_nodes.size():
		var current_node: Node = all_nodes[node_index]

		for child: Node in current_node.get_children():
			all_nodes.append(child)

		node_index += 1

	var maximum_duration: float = 0.0
	var started_component_count: int = 0

	# اول تمام AnimationTreeها فعال می‌شوند.
	for node: Node in all_nodes:
		if node is AnimationTree:
			var animation_tree := node as AnimationTree
			animation_tree.active = true

	# تمام AnimationPlayerها بدون await پشت سر هم شروع می‌شوند.
	for node: Node in all_nodes:
		if not node is AnimationPlayer:
			continue

		var animation_player := node as AnimationPlayer
		var animation_name: StringName = animation_player.autoplay

		if animation_name == &"":
			if animation_player.has_animation(&"move"):
				animation_name = &"move"
			else:
				for candidate: StringName in \
						animation_player.get_animation_list():

					if candidate == &"RESET":
						continue

					animation_name = candidate
					break

		if animation_name == &"":
			continue

		var animation: Animation = \
			animation_player.get_animation(
				animation_name
			)

		if animation != null:
			maximum_duration = maxf(
				maximum_duration,
				animation.length
			)

		animation_player.stop()
		animation_player.play(animation_name)

		# Trackهای زمان صفر، از جمله Audio Track،
		# همین فریم پردازش می‌شوند.
		animation_player.advance(0.0)

		started_component_count += 1

		print(
			"SAW ANIMATION STARTED | ",
			animation_player.get_path(),
			" | animation=",
			animation_name
		)

	# تمام Particleها، Spriteها و صداها هم در همان فریم شروع می‌شوند.
	for node: Node in all_nodes:
		if node is GPUParticles3D:
			var gpu_particles := node as GPUParticles3D

			gpu_particles.restart()
			gpu_particles.emitting = true

			var particle_duration: float = (
				gpu_particles.lifetime
				/ maxf(gpu_particles.speed_scale, 0.01)
			)

			maximum_duration = maxf(
				maximum_duration,
				particle_duration
			)

			started_component_count += 1

		elif node is CPUParticles3D:
			var cpu_particles := node as CPUParticles3D

			cpu_particles.restart()
			cpu_particles.emitting = true

			var particle_duration: float = (
				cpu_particles.lifetime
				/ maxf(cpu_particles.speed_scale, 0.01)
			)

			maximum_duration = maxf(
				maximum_duration,
				particle_duration
			)

			started_component_count += 1

		elif node is AnimatedSprite3D:
			var animated_sprite_3d := node as AnimatedSprite3D
			animated_sprite_3d.play()
			started_component_count += 1

		elif node is AnimatedSprite2D:
			var animated_sprite_2d := node as AnimatedSprite2D
			animated_sprite_2d.play()
			started_component_count += 1

		elif node is AudioStreamPlayer:
			var audio_player := node as AudioStreamPlayer

			if audio_player.stream == null:
				continue

			maximum_duration = maxf(
				maximum_duration,
				audio_player.stream.get_length()
			)

			audio_player.play()
			started_component_count += 1

			print(
				"SAW AUDIO STARTED | ",
				audio_player.get_path()
			)

		elif node is AudioStreamPlayer3D:
			var audio_player_3d := node as AudioStreamPlayer3D

			if audio_player_3d.stream == null:
				continue

			# صدای سه‌بعدی موقتاً از محدودیت فاصله خارج می‌شود.
			audio_player_3d.max_distance = 1000.0

			maximum_duration = maxf(
				maximum_duration,
				audio_player_3d.stream.get_length()
			)

			audio_player_3d.play()
			started_component_count += 1

			print(
				"SAW 3D AUDIO STARTED | ",
				audio_player_3d.get_path()
			)

	if started_component_count == 0:
		holder.queue_free()
		push_error("Saw VFX: nothing was started.")
		return

	if maximum_duration <= 0.0:
		maximum_duration = 2.5

	# زمان اضافه برای تمام‌شدن دنباله ذرات و صدا.
	await get_tree().create_timer(
		maximum_duration + 0.75
	).timeout

	holder.queue_free()
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
		0.15
	)

	hit_position.y += 0.15

	var attack_tween: Tween = create_tween()

	attack_tween.tween_property(
		attacker_view,
		"global_position",
		hit_position,
		0.28
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	await attack_tween.finished

	await get_tree().create_timer(
		0.10
	).timeout

	var return_tween: Tween = create_tween()

	return_tween.tween_property(
		attacker_view,
		"global_position",
		attacker_start,
		0.28
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	await return_tween.finished

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

	clash_center.y += 0.35

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
		0.32
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	clash_tween.tween_property(
		second_view,
		"global_position",
		second_target,
		0.32
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_IN
	)

	await clash_tween.finished

	await get_tree().create_timer(
		0.15
	).timeout

	var return_tween: Tween = create_tween()
	return_tween.set_parallel(true)

	return_tween.tween_property(
		first_view,
		"global_position",
		first_start,
		0.32
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	return_tween.tween_property(
		second_view,
		"global_position",
		second_start,
		0.32
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	await return_tween.finished

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

func _play_card_placement_disable_sequence(
	card_view: Card3D
) -> void:
	if card_view == null:
		return

	# ابتدا فقط انیمیشن خود Disabler.
	var activate_duration: float = \
		card_view.play_on_placed_effect()

	# صبر تا پایان کامل انیمیشن Disabler.
	if activate_duration > 0.0:
		await get_tree().create_timer(
			activate_duration
		).timeout

	# بعد از پایان Disabler، انیمیشن Targetها شروع می‌شود.
	var hit_duration: float = \
		_refresh_board_disabled_visuals(
			true
		)

	# صبر تا انیمیشن Targetها کامل تمام شود.
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

			# افکت Collector همین حالا شروع می‌شود.
			var effect_duration: float = \
				collector_view.play_collector_effect()

			# کمی بعد همه کارت‌ها باهم حرکت می‌کنند.
			var pull_delay: float = 0.20
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
