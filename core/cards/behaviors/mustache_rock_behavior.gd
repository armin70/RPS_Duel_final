class_name MustacheRockBehavior
extends CardBehavior

func get_dealer_attack_type(
	state: MatchState,
	source_card: CardInstance
) -> int:
	if state == null:
		return DealerAttackType.NORMAL

	if source_card == null:
		return DealerAttackType.NORMAL

	# قدرت قبلاً در اولین Attack بررسی و مصرف شده است.
	if source_card.ability_used:
		return DealerAttackType.NORMAL

	var owner: PlayerState = state.get_player(
		source_card.owner_id
	)

	if owner == null:
		return DealerAttackType.NORMAL

	# مهم:
	# اولین Attack قدرت را مصرف می‌کند،
	# حتی اگر شرط دو Rock برقرار نباشد.
	source_card.ability_used = true

	var source_gesture: CardGesture.Type = source_card.get_gesture()
	var other_matching_count: int = 0

	for slot_id: int in SlotID.all_slots():
		var friend_card: CardInstance = \
			owner.board.get_card(slot_id)

		if friend_card == null:
			continue

		# خود کارت ویژه حساب نمی‌شود.
		if friend_card == source_card:
			continue

		if friend_card.definition == null:
			continue

		if friend_card.get_gesture() != source_gesture:
			continue

		other_matching_count += 1

	# در اولین Attack شرط برقرار نبود:
	# حمله معمولی انجام می‌شود و قدرت برای همیشه از بین می‌رود.
	if other_matching_count < 2:
		print(
			"MUSTACHE SWEEP FAILED | matching_friends=",
			other_matching_count,
			" | gesture=",
			source_gesture,
			" | ability consumed"
		)

		return DealerAttackType.NORMAL

	# در اولین Attack شرط برقرار بود:
	# حمله معمولی با چهار برد جایگزین می‌شود.
	print(
		"MUSTACHE SWEEP ACTIVATED | matching_friends=",
		other_matching_count,
		" | gesture=",
		source_gesture
	)

	return DealerAttackType.SWEEP_WIN
