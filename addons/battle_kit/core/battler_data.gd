@tool
class_name BKBattlerData
extends Resource
## A hero or a monster, as a resource: stats, actions, rewards. A battle makes a live
## [BKBattler] from it, so one resource can appear several times in the same fight.

## The stats every battler has. Missing entries count as 0 (max_hp and speed at least 1).
const STATS: Array[StringName] = [&"max_hp", &"max_mp", &"attack", &"defense", &"magic", &"resistance",
	&"speed", &"crit_chance", &"evasion"]
## Affinity shortcuts for [member affinities].
const WEAK := 2.0
const RESIST := 0.5
const IMMUNE := 0.0
const ABSORB := -1.0

@export var id: StringName
@export var title: String = ""
@export_range(1, 99) var level: int = 1
## {&"max_hp": 60, &"attack": 12, &"speed": 10, &"crit_chance": 0.05, &"evasion": 0.05...}
@export var stats: Dictionary[StringName, float] = {}
## Besides these, every battler can Attack (if [member basic_attack] is set), Defend and use items (heroes).
@export var actions: Array[BKAction] = []
## The plain attack. Empty = a 0-power physical attack.
@export var basic_attack: BKAction
## Status ids it never gets ("poison" for a golem).
@export var immunities: Array[StringName] = []
## Damage multiplier per element, {&"fire": 2.0}: 2 = weak, 0.5 = resists, 0 = immune,
## negative = absorbs (-1 heals the full damage). Missing elements count as 1.
## Shortcuts: [constant WEAK], [constant RESIST], [constant IMMUNE], [constant ABSORB].
@export var affinities: Dictionary[StringName, float] = {}
@export_group("Levels")
## Its own XP curve. Empty = [member BKBattle.level_curve].
@export var level_curve: BKLevelCurve
## Stat gains per level above [member level], {&"max_hp": 12, &"attack": 2}. Empty = the
## curve's [member BKLevelCurve.stat_growth].
@export var growth: Dictionary[StringName, float] = {}
@export_group("Rewards")
@export_range(0, 999999) var xp: int = 0
@export_range(0, 999999) var gold: int = 0
@export var drops: Array[BKDrop] = []
@export_group("Look")
@export var icon: Texture2D
@export var icon_item: StringName


static func make(p_id: StringName, p_title: String, p_stats: Dictionary, p_icon_item: StringName = &"") -> BKBattlerData:
	var data := BKBattlerData.new()
	data.id = p_id
	data.title = p_title
	data.stats.assign(p_stats)
	data.icon_item = p_icon_item
	return data


func get_title() -> String:
	return BKText.t(title) if not title.is_empty() else String(id).capitalize()


func get_icon(database: IKItemDatabase) -> Texture2D:
	if icon != null:
		return icon
	var definition := database.get_item(icon_item) if database != null and not icon_item.is_empty() else null
	return definition.icon if definition != null else null
