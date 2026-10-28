@tool
class_name BKAction
extends Resource
## Something a battler can do on its turn: an attack, a skill that costs MP, an item from
## the bag, defending or fleeing. Damage, heals, statuses and cures all live here.

enum Target {
	ONE_ENEMY,
	ALL_ENEMIES,
	ONE_ALLY,
	ALL_ALLIES,
	SELF,
	## Revives: a defeated ally.
	ONE_FALLEN_ALLY,
}

enum Kind {
	## Hurts the targets (power + the attacker's attack or magic, minus defense or resistance).
	DAMAGE,
	## Restores HP: power + half the user's magic.
	HEAL,
	## Restores MP by power.
	RESTORE_MP,
	## Only applies statuses and cures.
	SUPPORT,
	## Brings a fallen ally back with power percent of its max HP.
	REVIVE,
	## Halves the damage taken until the user's next turn.
	DEFEND,
	## Ends the battle if it succeeds ([member BKBattle.flee_chance]).
	FLEE,
}

enum Scaling { ATTACK, MAGIC }

## Stable id.
@export var id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.DAMAGE
@export var target: Target = Target.ONE_ENEMY
@export_group("Numbers")
@export var scaling: Scaling = Scaling.ATTACK
@export var power: float = 0.0
## Element of the damage (&"fire", &"ice"...). Empty = neutral: no weakness or resistance
## applies. See [member BKBattlerData.affinities].
@export var element: StringName
@export_range(0, 999) var mp_cost: int = 0
## Chance to hit before the target's evasion (damage and statuses on enemies).
@export_range(0.0, 1.0, 0.01) var accuracy: float = 0.95
@export var can_crit: bool = true
## Hits per target (damage rolls each time).
@export_range(1, 10) var hits: int = 1
## Time until the user acts again: 1 = normal, 0.5 = quick, 1.5 = slow.
@export_range(0.25, 3.0, 0.05) var delay: float = 1.0
@export_group("Statuses")
## Applied to each target that is hit (or each target, for support actions).
@export var statuses: Array[BKStatus] = []
@export_range(0.0, 1.0, 0.01) var status_chance: float = 1.0
## Status ids removed from each target ("antidote" cures &"poison").
@export var cures: Array[StringName] = []
@export_group("Item")
## Uses one of this item from the bag: refused when there is none left.
@export var item_id: StringName
@export_group("AI")
## Relative chance an AI picks it among its usable actions.
@export_range(0.0, 100.0, 0.1) var ai_weight: float = 1.0
@export_group("Look")
@export var icon: Texture2D
## Empty icon = the icon of this item in the item database (the item itself for item actions).
@export var icon_item: StringName


static func make(p_id: StringName, p_title: String, p_kind: Kind = Kind.DAMAGE, p_target: Target = Target.ONE_ENEMY,
		p_power: float = 0.0, p_mp_cost: int = 0, p_icon_item: StringName = &"") -> BKAction:
	var action := BKAction.new()
	action.id = p_id
	action.title = p_title
	action.kind = p_kind
	action.target = p_target
	action.power = p_power
	action.mp_cost = p_mp_cost
	action.icon_item = p_icon_item
	if p_kind in [Kind.HEAL, Kind.RESTORE_MP, Kind.SUPPORT, Kind.REVIVE, Kind.DEFEND, Kind.FLEE]:
		action.accuracy = 1.0
		action.can_crit = false
	return action


## An action that uses one [param p_item_id] from the bag.
static func make_item(p_item_id: StringName, p_title: String, p_kind: Kind, p_target: Target, p_power: float = 0.0) -> BKAction:
	var action := make(StringName("item_" + p_item_id), p_title, p_kind, p_target, p_power)
	action.item_id = p_item_id
	action.icon_item = p_item_id
	return action


func get_title() -> String:
	return BKText.t(title) if not title.is_empty() else String(id).capitalize()


func get_icon(database: IKItemDatabase) -> Texture2D:
	if icon != null:
		return icon
	var key := icon_item if not icon_item.is_empty() else item_id
	var definition := database.get_item(key) if database != null and not key.is_empty() else null
	return definition.icon if definition != null else null


func targets_enemies() -> bool:
	return target in [Target.ONE_ENEMY, Target.ALL_ENEMIES]


func targets_one() -> bool:
	return target in [Target.ONE_ENEMY, Target.ONE_ALLY, Target.ONE_FALLEN_ALLY]


func is_item() -> bool:
	return not item_id.is_empty()


## Damage action with an element ([member element]).
func is_elemental() -> bool:
	return kind == Kind.DAMAGE and not element.is_empty()
