class_name CardPlayRecord
extends RefCounted


var card: CardInstance
var owner_id: int = -1
var slot_id: int = -1

# کارت‌هایی که دقیقاً به‌خاطر این Play
# از Board خارج شدند.
var removed_cards: Array[CardInstance] = []
