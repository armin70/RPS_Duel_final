class_name GladiatorDealerBehavior
extends DealerCardBehavior


func discards_lane_losers_after_combat() -> bool:
	return true


func requires_matching_middle_pair() -> bool:
	return true
