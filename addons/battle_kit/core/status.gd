@tool
class_name BKStatus
extends Resource
## A buff or a debuff: poison, burn, stun, guard, haste... Lasts a number of the bearer's
## turns, can stack, changes stats, hurts or heals each turn, or skips turns.

## Stable id: cures and immunities refer to it.
@export var id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
## Turns of the bearer it lasts. Applying it again refreshes the duration.
@export_range(1, 99) var duration: int = 3
## Applying it again adds a stack, up to this many (damage and modifiers multiply).
@export_range(1, 9) var max_stacks: int = 1
## Debuffs are red in the UI and are what "cure all" removes; buffs are green.
@export var is_debuff: bool = true
@export_group("Effects")
## Stat changes in percent per stack: {&"defense": 0.5} = +50 % defense, -0.3 = -30 %.
@export var stat_percent: Dictionary[StringName, float] = {}
## Flat stat changes per stack: {&"speed": 5.0}.
@export var stat_flat: Dictionary[StringName, float] = {}
## At the start of each of the bearer's turns, per stack: damage (negative heals).
@export var damage_per_turn: int = 0
## Same, as a fraction of max HP: 0.05 = 5 % of max HP per turn.
@export_range(-1.0, 1.0, 0.01) var damage_percent_per_turn: float = 0.0
## The bearer skips its turns while it lasts (stun, sleep, freeze).
@export var skips_turn: bool = false
@export_group("Look")
@export var icon: Texture2D
## Empty icon = the icon of this item in the item database.
@export var icon_item: StringName
@export var color := Color(1, 1, 1)


static func make(p_id: StringName, p_title: String, p_duration: int = 3, p_debuff: bool = true,
		p_icon_item: StringName = &"") -> BKStatus:
	var status := BKStatus.new()
	status.id = p_id
	status.title = p_title
	status.duration = p_duration
	status.is_debuff = p_debuff
	status.icon_item = p_icon_item
	status.color = Color(1.0, 0.45, 0.4) if p_debuff else Color(0.5, 0.95, 0.55)
	return status


func get_title() -> String:
	return BKText.t(title) if not title.is_empty() else String(id).capitalize()


func get_icon(database: IKItemDatabase) -> Texture2D:
	if icon != null:
		return icon
	var definition := database.get_item(icon_item) if database != null and not icon_item.is_empty() else null
	return definition.icon if definition != null else null
