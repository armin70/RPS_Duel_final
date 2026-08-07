class_name CardMover
extends RefCounted


# تمام کارت‌های باقی‌مانده در Hand را به Discard می‌فرستد.
static func discard_hand(
	player: PlayerState
) -> int:
	if player == null:
		return 0

	var discarded_count: int = 0

	while not player.hand.is_empty():
		var card: CardInstance = \
			player.hand.pop_back()

		if card == null:
			continue

		card.zone = CardZone.Type.DISCARD
		card.current_slot = CardInstance.NO_SLOT

		player.discard_pile.append(card)
		discarded_count += 1

	return discarded_count


# فقط وقتی Draw خالی شده باشد اجرا می‌شود.
#
# ترتیب بسیار مهم است:
# 1. Discard وارد Draw می‌شود.
# 2. Draw به‌هم می‌خورد.
# 3. Reserve وارد Discard می‌شود.
#
# بنابراین کارت‌های Reserve در همین Shuffle وارد Draw نمی‌شوند.
static func recycle_empty_draw(
	player: PlayerState
) -> bool:
	if player == null:
		return false

	if not player.draw_pile.is_empty():
		return false

	var created_new_draw_pile: bool = false

	# اول Discard فعلی وارد Draw می‌شود.
	if not player.discard_pile.is_empty():
		for card: CardInstance in player.discard_pile:
			if card == null:
				continue

			card.zone = CardZone.Type.DRAW
			card.current_slot = CardInstance.NO_SLOT

			player.draw_pile.append(card)

		player.discard_pile.clear()
		player.draw_pile.shuffle()

		created_new_draw_pile = true

	# بعد از ساخته‌شدن Draw جدید،
	# کارت‌های حذف‌شده از Board وارد Discard می‌شوند.
	if not player.reserve_pile.is_empty():
		for card: CardInstance in player.reserve_pile:
			if card == null:
				continue

			card.zone = CardZone.Type.DISCARD
			card.current_slot = CardInstance.NO_SLOT

			player.discard_pile.append(card)

		player.reserve_pile.clear()

	return created_new_draw_pile


# چند کارت را به‌صورت یک Batch می‌کشد.
#
# در هر Batch فقط یک بار اجازه‌ی Recycle دارد.
# این موضوع باعث می‌شود کارت‌های Reserve نتوانند در همان
# Turn دوباره Shuffle شده و Draw شوند.
static func draw_cards_to_hand(
	player: PlayerState,
	card_count: int
) -> Array[CardInstance]:
	var drawn_cards: Array[CardInstance] = []

	if player == null:
		return drawn_cards

	if card_count <= 0:
		return drawn_cards

	var recycled_during_this_draw: bool = false

	for index: int in range(card_count):
		if player.draw_pile.is_empty():
			# در یک Draw Batch فقط یک بار Shuffle انجام می‌شود.
			if recycled_during_this_draw:
				break

			recycle_empty_draw(player)
			recycled_during_this_draw = true

			# ممکن است Discard خالی بوده باشد و فقط
			# Reserve وارد Discard شده باشد.
			# در این حالت کارت‌های Reserve تا Batch بعدی
			# قابل Draw نیستند.
			if player.draw_pile.is_empty():
				break

		var card: CardInstance = \
			player.draw_pile.pop_back()

		if card == null:
			continue

		card.zone = CardZone.Type.HAND
		card.current_slot = CardInstance.NO_SLOT

		player.hand.append(card)
		drawn_cards.append(card)

	return drawn_cards


# برای سازگاری با کدهای قدیمی که فقط یک کارت Draw می‌کنند.
static func draw_to_hand(
	player: PlayerState
) -> CardInstance:
	var drawn_cards: Array[CardInstance] = \
		draw_cards_to_hand(
			player,
			1
		)

	if drawn_cards.is_empty():
		return null

	return drawn_cards[0]


# برای سازگاری با نام قبلی.
static func discard_to_draw(
	player: PlayerState
) -> bool:
	return recycle_empty_draw(player)


static func hand_to_board(
	player: PlayerState,
	card: CardInstance,
	slot_id: int
) -> bool:
	if player == null or card == null:
		return false

	if not player.hand.has(card):
		return false

	if not player.board.is_slot_empty(slot_id):
		return false

	player.hand.erase(card)

	if not player.board.place_card(
		slot_id,
		card
	):
		player.hand.append(card)
		return false

	return true


# تمام کارت‌هایی که از Board حذف می‌شوند،
# ابتدا وارد Reserve می‌شوند.
static func board_to_reserve(
	player: PlayerState,
	slot_id: int
) -> CardInstance:
	if player == null:
		return null

	var card: CardInstance = \
		player.board.remove_card(slot_id)

	if card == null:
		return null

	card.zone = CardZone.Type.RESERVE
	card.current_slot = CardInstance.NO_SLOT

	player.reserve_pile.append(card)

	return card


# Wrapper سازگاری:
# Collector، کارت Dealer و سیستم Cover ممکن است هنوز
# board_to_discard را صدا بزنند.
#
# با این Wrapper همه‌ی آن‌ها خودکار وارد Reserve می‌شوند.
static func board_to_discard(
	player: PlayerState,
	slot_id: int
) -> CardInstance:
	return board_to_reserve(
		player,
		slot_id
	)
