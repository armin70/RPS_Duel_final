class_name DealerCardBehavior
extends Resource


func on_enter_board(
	_state: MatchState,
	_dealer_card: CardInstance,
	_dealer_slot_id: int
) -> void:
	pass


# اگر true باشد، کارت‌های بازنده‌ی بازیکن‌ها در لاین این Dealer card
# بعد از تمام مبارزه‌های همان Turn از زمین خارج می‌شوند.
func discards_lane_losers_after_combat() -> bool:
	return false


# کارت‌هایی مثل Gladiator Div برای حضور در لاین وسط باید هر دو جایگاه
# MIDDLE_0 و MIDDLE_1 را با دو CardInstance مستقل پر کنند.
func requires_matching_middle_pair() -> bool:
	return false
