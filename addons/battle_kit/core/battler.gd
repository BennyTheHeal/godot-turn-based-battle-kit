class_name BKBattler
extends RefCounted
## A fighter during a battle: HP, MP, statuses, and its stats with every bonus applied.
## Heroes can keep the same BKBattler from fight to fight (HP and MP carry over).

const PARTY := 0
const ENEMIES := 1

## What an element does to a battler, from its multiplier ([method get_affinity]).
enum Affinity { NORMAL, WEAK, RESIST, IMMUNE, ABSORB }

var data: BKBattlerData
## [constant PARTY] or [constant ENEMIES].
var side: int = PARTY
## Place in its side (0 = first).
var index: int = 0
var hp: int = 0
var mp: int = 0
## Flat bonuses from outside the battle, {stat: amount}: equipment, Skill Tree Kit's
## [code]skills.get_bonuses()[/code], set bonuses... Added before status percentages.
var bonuses: Dictionary = {}
## Live statuses: [{"status": BKStatus, "turns": int, "stacks": int}].
var statuses: Array[Dictionary] = []
var defending := false
## Battle clock: the battler with the lowest value acts next.
var ready_at: float = 0.0
## Name shown in battle ("Haunted Armor B" when several share a name).
var display_name: String = ""
## Current level: starts at [member BKBattlerData.level], grows with [method gain_xp].
var level: int = 1
## Total XP earned.
var xp: int = 0
## XP curve when [member BKBattlerData.level_curve] is empty (set by the battle).
var curve: BKLevelCurve


static func from_data(p_data: BKBattlerData, p_side: int = PARTY) -> BKBattler:
	var battler := BKBattler.new()
	battler.data = p_data
	battler.side = p_side
	battler.display_name = p_data.get_title()
	battler.level = p_data.level
	battler.hp = battler.get_max_hp()
	battler.mp = int(battler.get_stat(&"max_mp"))
	return battler


func is_alive() -> bool:
	return hp > 0


func get_max_hp() -> int:
	return maxi(1, roundi(get_stat(&"max_hp")))


func get_max_mp() -> int:
	return maxi(0, roundi(get_stat(&"max_mp")))


## Base stat + [member bonuses] + flat status changes, times (1 + status percentages).
func get_stat(stat: StringName) -> float:
	var value: float = float(data.stats.get(stat, 0.0)) + float(bonuses.get(stat, 0.0)) + get_level_bonus(stat)
	var percent := 0.0
	for entry in statuses:
		var status: BKStatus = entry.status
		value += float(status.stat_flat.get(stat, 0.0)) * entry.stacks
		percent += float(status.stat_percent.get(stat, 0.0)) * entry.stacks
	value *= maxf(0.0, 1.0 + percent)
	if stat == &"speed":
		return maxf(1.0, value)
	if stat in [&"crit_chance", &"evasion"]:
		return clampf(value, 0.0, 0.95)
	return maxf(0.0, value)


# --- Levels ------------------------------------------------------------------

## The curve used for its levels: its data's own, else [member curve].
func get_curve() -> BKLevelCurve:
	return data.level_curve if data.level_curve != null else curve


## What its levels above [member BKBattlerData.level] add to [param stat].
func get_level_bonus(stat: StringName) -> float:
	var gained := level - data.level
	if gained <= 0:
		return 0.0
	var growth: Dictionary = data.growth
	if growth.is_empty():
		var used := get_curve()
		if used == null:
			return 0.0
		growth = used.stat_growth
	return float(growth.get(stat, 0.0)) * gained


## Adds XP and levels up along [param p_curve] (default: [method get_curve]). HP and MP
## rise with the max values. Returns {"battler", "from", "to", "gains": {stat: amount}};
## "from" == "to" when no level was gained.
func gain_xp(amount: int, p_curve: BKLevelCurve = null) -> Dictionary:
	var used := p_curve if p_curve != null else get_curve()
	var before := level
	if used != null:
		xp = maxi(xp, used.xp_to_reach(level))  # a fighter that starts at level 5 has its XP
	xp += maxi(0, amount)
	var gains := {}
	if used != null:
		var target := clampi(used.level_for_xp(xp), level, used.max_level)
		if target > level:
			var old_stats := {}
			for stat in BKBattlerData.STATS:
				old_stats[stat] = get_stat(stat)
			var old_max_hp := get_max_hp()
			var old_max_mp := get_max_mp()
			if curve == null and data.level_curve == null:
				curve = used
			level = target
			for stat in BKBattlerData.STATS:
				var delta: float = get_stat(stat) - float(old_stats[stat])
				if not is_zero_approx(delta):
					gains[stat] = delta
			if is_alive():
				hp += get_max_hp() - old_max_hp
				mp += get_max_mp() - old_max_mp
			_clamp_pools()
	return {"battler": self, "from": before, "to": level, "gains": gains}


## XP still needed for the next level (0 without a curve or at the max level).
func get_xp_to_next() -> int:
	var used := get_curve()
	return used.xp_to_next(level, xp) if used != null else 0


# --- Elements ----------------------------------------------------------------

## Damage multiplier for [param element] (1 = normal, also for neutral attacks).
func get_affinity(element: StringName) -> float:
	if element.is_empty():
		return 1.0
	return float(data.affinities.get(element, 1.0))


static func affinity_kind(multiplier: float) -> Affinity:
	if multiplier < 0.0:
		return Affinity.ABSORB
	if is_zero_approx(multiplier):
		return Affinity.IMMUNE
	if multiplier > 1.0 and not is_equal_approx(multiplier, 1.0):
		return Affinity.WEAK
	if multiplier < 1.0 and not is_equal_approx(multiplier, 1.0):
		return Affinity.RESIST
	return Affinity.NORMAL


# --- Saving --------------------------------------------------------------------

## HP, MP, level and XP of a hero, to keep between sessions (statuses are not saved).
func to_data() -> Dictionary:
	return {"hp": hp, "mp": mp, "level": level, "xp": xp}


## Restores [method to_data]. Missing keys keep their value.
func load_data(saved: Dictionary) -> void:
	level = maxi(1, int(saved.get("level", level)))
	xp = maxi(0, int(saved.get("xp", xp)))
	hp = clampi(int(saved.get("hp", hp)), 0, get_max_hp())
	mp = clampi(int(saved.get("mp", mp)), 0, get_max_mp())


func has_status(status_id: StringName) -> bool:
	return _find(status_id) >= 0


func get_stacks(status_id: StringName) -> int:
	var at := _find(status_id)
	return statuses[at].stacks if at >= 0 else 0


func is_stunned() -> bool:
	for entry in statuses:
		if entry.status.skips_turn:
			return true
	return false


## Adds or refreshes [param status]. Returns false when immune or dead.
func apply_status(status: BKStatus) -> bool:
	if status == null or not is_alive() or data.immunities.has(status.id):
		return false
	var at := _find(status.id)
	if at >= 0:
		statuses[at].turns = status.duration
		statuses[at].stacks = mini(statuses[at].stacks + 1, status.max_stacks)
	else:
		statuses.append({"status": status, "turns": status.duration, "stacks": 1})
	_clamp_pools()
	return true


func remove_status(status_id: StringName) -> bool:
	var at := _find(status_id)
	if at < 0:
		return false
	statuses.remove_at(at)
	_clamp_pools()
	return true


## Every action it may use now: its own actions, its basic attack and Defend. Items are
## offered by the battle (they come from the bag).
func get_actions() -> Array[BKAction]:
	var list: Array[BKAction] = []
	list.append(get_attack())
	list.append_array(data.actions)
	return list


func get_attack() -> BKAction:
	if data.basic_attack != null:
		return data.basic_attack
	return BKAction.make(&"attack", "Attack", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 0.0)


func can_pay(action: BKAction) -> bool:
	return mp >= action.mp_cost


func get_title() -> String:
	return display_name if not display_name.is_empty() else data.get_title()


## HP and MP back to full, statuses cleared (an inn, a rest).
func restore() -> void:
	statuses.clear()
	defending = false
	hp = get_max_hp()
	mp = get_max_mp()


func _find(status_id: StringName) -> int:
	for i in statuses.size():
		if statuses[i].status.id == status_id:
			return i
	return -1


func _clamp_pools() -> void:
	hp = mini(hp, get_max_hp())
	mp = mini(mp, get_max_mp())


func _to_string() -> String:
	return "BKBattler(%s %d/%d HP)" % [get_title(), hp, get_max_hp()]
