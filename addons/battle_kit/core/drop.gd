@tool
class_name BKDrop
extends Resource
## One possible reward of a defeated enemy: an item with a chance and an amount.

@export var item_id: StringName
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
@export_range(1, 9999) var min_amount: int = 1
@export_range(1, 9999) var max_amount: int = 1


static func make(p_item_id: StringName, p_chance: float = 1.0, p_min: int = 1, p_max: int = -1) -> BKDrop:
	var drop := BKDrop.new()
	drop.item_id = p_item_id
	drop.chance = p_chance
	drop.min_amount = p_min
	drop.max_amount = p_max if p_max >= p_min else p_min
	return drop
