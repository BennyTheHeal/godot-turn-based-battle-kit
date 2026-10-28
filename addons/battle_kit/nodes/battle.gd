class_name BKBattle
extends Node
## A turn-based battle: two sides, a turn order driven by speed (fast fighters act more
## often), actions that cost MP or use items from an Inventory Kit bag, statuses, an
## enemy AI, and rewards (XP, gold, drops) paid into the bag at the end.
##
## [codeblock]
## battle.bag = bag.container
## battle.start([knight, mage], [wolf_data, wolf_data])   # BKBattler or BKBattlerData
## # on turn_started(actor): heroes pick an action, enemies call run_ai_turn()
## var result := battle.perform(fireball, [battle.enemies[0]])
## [/codeblock]
##
## Event types in [member BKResult.events] and [signal action_resolved]: "used" (timed),
## "damage" (amount, critical, element, affinity, timed), "absorb" (amount healed by an
## element it absorbs), "heal", "mp", "miss", "status", "immune", "cured", "defend",
## "revived", "defeated", "fled", "flee_failed", and at the start of a turn "tick" (status
## damage, negative = heal), "expired", "stunned". Each has "target" and, for actions, "actor".
##
## Elements: an action's [member BKAction.element] meets the target's
## [member BKBattlerData.affinities] (weak, resist, immune, absorb). Each side learns an
## affinity by hitting it; the AI prefers the weaknesses it knows.
## Levels: with a [member level_curve], victories level the surviving heroes up.
## Timed hits: [method perform] with [code]timed = true[/code] (the player pressed at the
## right moment) adds [member timed_attack_bonus] to a hero's damage, or removes
## [member timed_guard_reduction] from an enemy's damage on a hero.

signal battle_started
## A battler's turn begins (after its statuses ticked). Heroes: wait for the player.
## Enemies: call [method run_ai_turn] (now, or after a short pause for readability).
signal turn_started(actor: BKBattler)
## Status damage, expiries and stuns at the start of a turn, before [signal turn_started].
signal turn_events(actor: BKBattler, events: Array[Dictionary])
signal action_resolved(actor: BKBattler, action: BKAction, events: Array[Dictionary])
signal battler_defeated(battler: BKBattler)
## [param rewards]: {"xp": int, "gold": int, "items": {id: amount}, "left_behind": {id: amount},
## "level_ups": [{"battler", "from", "to", "gains"}], "xp_each": int}.
signal battle_ended(outcome: Outcome, rewards: Dictionary)
## A hero gained levels after a victory (before [signal battle_ended]). [param gains]:
## {stat: amount} added by the new levels.
signal level_up(battler: BKBattler, from_level: int, to_level: int, gains: Dictionary)

enum Outcome { NONE, VICTORY, DEFEAT, FLED }

## Rewards and item actions use this container (the party's bag).
var bag: IKContainer
## Gold rewards are added as this item. Empty = gold is only reported in the rewards.
@export var gold_item: StringName = &"gold_coins"
@export var can_flee := true
@export_range(0.0, 1.0, 0.01) var flee_chance: float = 0.6
## Item actions the party may use (potions...). Only those with at least one item in the
## bag are offered by [method get_item_actions].
@export var item_actions: Array[BKAction] = []
## Damage multiplier on critical hits.
@export var critical_multiplier := 1.5
## Damage is multiplied by a random value in [1 - variance, 1 + variance].
@export_range(0.0, 0.5, 0.01) var variance := 0.1
## Defense reduces damage by defense / (defense + armor_scale): 60 defense with a scale of
## 60 halves the damage.
@export var armor_scale := 60.0
## AI: chance to aim at the weakest target instead of a random one.
@export_range(0.0, 1.0, 0.01) var ai_focus_weakest := 0.5
## AI: heals an ally below this part of its max HP when it can.
@export_range(0.0, 1.0, 0.01) var ai_heal_below := 0.4
@export_group("Elements")
## AI: knows every affinity from the start. Off = it learns them by hitting, like the player.
@export var ai_knows_affinities := false
## AI: how much known affinities weigh in its choices (an action's weight is multiplied by
## the multiplier to this power: 2 = a weakness is 4× more likely). 0 = ignores them.
@export_range(0.0, 4.0, 0.1) var ai_affinity_focus := 2.0
@export_group("Levels")
## XP curve of the party. Empty = no levels: the rewards still report the XP.
## A hero's own [member BKBattlerData.level_curve] wins.
@export var level_curve: BKLevelCurve
## On: the XP is split between the surviving heroes. Off: each survivor gets all of it.
@export var share_xp := false
@export_group("Timed hits")
## A hero's timed attack ([code]perform(..., true)[/code]): damage × (1 + this).
@export_range(0.0, 2.0, 0.05) var timed_attack_bonus := 0.3
## A timed guard against an enemy's attack: damage to heroes × (1 - this).
@export_range(0.0, 1.0, 0.05) var timed_guard_reduction := 0.4

var party: Array[BKBattler] = []
var enemies: Array[BKBattler] = []
var current: BKBattler
var outcome: Outcome = Outcome.NONE
var rewards: Dictionary = {}
var turn_count: int = 0
var rng := RandomNumberGenerator.new()
var _known: Dictionary = {}  # side -> {BKBattler: {element: true}}


## Starts a battle. [param p_party] and [param p_enemies] hold [BKBattler] (kept, with their
## HP) or [BKBattlerData] (a fresh battler is made). [param seed_value] makes rolls
## reproducible (-1 = random).
func start(p_party: Array, p_enemies: Array, seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	party = _make_side(p_party, BKBattler.PARTY)
	enemies = _make_side(p_enemies, BKBattler.ENEMIES)
	outcome = Outcome.NONE
	rewards = {}
	turn_count = 0
	current = null
	_known = {BKBattler.PARTY: {}, BKBattler.ENEMIES: {}}
	for battler in get_all():
		battler.defending = false
		battler.ready_at = _turn_time(battler) * rng.randf_range(0.9, 1.0)
	battle_started.emit()
	_check_end()
	if outcome == Outcome.NONE:
		_next_turn()


func get_all() -> Array[BKBattler]:
	var all: Array[BKBattler] = []
	all.append_array(party)
	all.append_array(enemies)
	return all


func get_side(side: int) -> Array[BKBattler]:
	return party if side == BKBattler.PARTY else enemies


func get_opponents(battler: BKBattler) -> Array[BKBattler]:
	return get_side(1 - battler.side)


func get_alive(side: int) -> Array[BKBattler]:
	var alive: Array[BKBattler] = []
	for battler in get_side(side):
		if battler.is_alive():
			alive.append(battler)
	return alive


func is_over() -> bool:
	return outcome != Outcome.NONE


## The next [param count] turns, current one first (statuses and future speed changes
## are not predicted).
func get_turn_order(count: int = 8) -> Array[BKBattler]:
	var order: Array[BKBattler] = []
	var clock := {}
	for battler in get_all():
		if battler.is_alive():
			clock[battler] = battler.ready_at
	if current != null and current.is_alive():
		order.append(current)
		clock[current] = current.ready_at + _turn_time(current)
	while order.size() < count and not clock.is_empty():
		var next: BKBattler = null
		for battler: BKBattler in clock:
			if next == null or _before(battler, clock[battler], next, clock[next]):
				next = battler
		order.append(next)
		clock[next] += _turn_time(next)
	return order


## Item actions with at least one item left in the bag.
func get_item_actions() -> Array[BKAction]:
	var list: Array[BKAction] = []
	for action in item_actions:
		if action != null and bag != null and bag.has(action.item_id):
			list.append(action)
	return list


## Targets [param action] may be aimed at by [param actor] (alive or fallen as needed).
func get_valid_targets(actor: BKBattler, action: BKAction) -> Array[BKBattler]:
	var targets: Array[BKBattler] = []
	match action.target:
		BKAction.Target.SELF:
			targets.append(actor)
		BKAction.Target.ONE_ENEMY, BKAction.Target.ALL_ENEMIES:
			targets = get_alive(1 - actor.side)
		BKAction.Target.ONE_ALLY, BKAction.Target.ALL_ALLIES:
			targets = get_alive(actor.side)
		BKAction.Target.ONE_FALLEN_ALLY:
			for battler in get_side(actor.side):
				if not battler.is_alive():
					targets.append(battler)
	return targets


## Checks [param action] for the current battler without doing it.
func can_perform(action: BKAction, targets: Array[BKBattler] = []) -> BKResult:
	if is_over():
		return BKResult.failure(BKResult.Code.BATTLE_OVER, "The battle is over.")
	if action == null or current == null:
		return BKResult.failure(BKResult.Code.INVALID_ARGUMENT, "No action or no current battler.")
	if action.kind == BKAction.Kind.FLEE and not can_flee:
		return BKResult.failure(BKResult.Code.CANNOT_FLEE, "Fleeing is disabled.")
	if not current.can_pay(action):
		return BKResult.failure(BKResult.Code.NOT_ENOUGH_MP, "%d MP needed." % action.mp_cost)
	if action.is_item():
		if bag == null or not bag.has(action.item_id):
			var missing := BKResult.failure(BKResult.Code.NO_ITEM, "No '%s' in the bag." % action.item_id)
			return missing
	if action.targets_one():
		var valid := get_valid_targets(current, action)
		if targets.size() != 1 or not valid.has(targets[0]):
			return BKResult.failure(BKResult.Code.INVALID_TARGET, "Pick one valid target.")
	return BKResult.success()


## The current battler does [param action]. Single-target actions need [param targets]
## with one battler; the others pick their targets themselves. [param timed]: the player
## hit the timing (see [member timed_attack_bonus] and [member timed_guard_reduction]).
func perform(action: BKAction, targets: Array[BKBattler] = [], timed: bool = false) -> BKResult:
	var check := can_perform(action, targets)
	if not check.ok:
		return check
	var actor := current
	if action.is_item():
		var used := bag.remove(action.item_id, 1)
		if not used.ok:
			var refused := BKResult.failure(BKResult.Code.NO_ITEM, used.message)
			refused.inventory_result = used
			return refused
	actor.mp -= action.mp_cost
	var events: Array[Dictionary] = [{"type": "used", "actor": actor, "target": actor, "action": action, "timed": timed}]
	var resolved := targets if action.targets_one() else get_valid_targets(actor, action)
	match action.kind:
		BKAction.Kind.DEFEND:
			actor.defending = true
			events.append({"type": "defend", "actor": actor, "target": actor})
		BKAction.Kind.FLEE:
			if rng.randf() < flee_chance:
				events.append({"type": "fled", "actor": actor, "target": actor})
				outcome = Outcome.FLED
			else:
				events.append({"type": "flee_failed", "actor": actor, "target": actor})
		_:
			for target in resolved:
				_apply(actor, action, target, events, timed)
	turn_count += 1
	actor.ready_at += _turn_time(actor) * action.delay
	action_resolved.emit(actor, action, events)
	_check_end()
	if outcome == Outcome.NONE:
		_next_turn()
	elif outcome == Outcome.FLED:
		battle_ended.emit(outcome, rewards)
	return BKResult.success(events)


## Picks an action and targets for [param actor] the way an enemy would:
## {"action": BKAction, "targets": Array[BKBattler]}.
func choose_ai_action(actor: BKBattler) -> Dictionary:
	var usable: Array[BKAction] = []
	for action in actor.get_actions():
		if actor.can_pay(action) and action.kind != BKAction.Kind.FLEE and not get_valid_targets(actor, action).is_empty():
			usable.append(action)
	# An ally in danger comes first.
	var hurt: BKBattler = null
	for ally in get_alive(actor.side):
		if float(ally.hp) / ally.get_max_hp() < ai_heal_below and (hurt == null or ally.hp < hurt.hp):
			hurt = ally
	if hurt != null:
		for action in usable:
			if action.kind == BKAction.Kind.HEAL:
				return {"action": action, "targets": _ai_targets(actor, action, hurt)}
	var pool: Array[BKAction] = []
	for action in usable:
		if action.kind == BKAction.Kind.HEAL or action.kind == BKAction.Kind.REVIVE:
			continue
		# Do not cast a buff the target already has.
		if action.kind == BKAction.Kind.SUPPORT and action.target == BKAction.Target.SELF and _has_all(actor, action):
			continue
		if _ai_weight(actor, action) > 0.0:
			pool.append(action)
	if pool.is_empty():
		var attack := actor.get_attack()
		return {"action": attack, "targets": _ai_targets(actor, attack, null)}
	var total := 0.0
	for action in pool:
		total += _ai_weight(actor, action)
	var roll := rng.randf() * total
	var chosen: BKAction = pool.back()
	for action in pool:
		roll -= _ai_weight(actor, action)
		if roll < 0.0:
			chosen = action
			break
	return {"action": chosen, "targets": _ai_targets(actor, chosen, null)}


## The current battler acts on its own (enemies; heroes too, for an "auto" button).
## [param timed]: the player guarded in time against this enemy action.
func run_ai_turn(timed: bool = false) -> BKResult:
	if is_over() or current == null:
		return BKResult.failure(BKResult.Code.BATTLE_OVER, "Nothing to do.")
	var choice := choose_ai_action(current)
	var targets: Array[BKBattler] = []
	targets.assign(choice.targets)
	return perform(choice.action, targets, timed)


# --- Elements ----------------------------------------------------------------

## True when [param side] has seen what [param element] does to [param target] (neutral
## attacks are always known).
func knows_affinity(side: int, target: BKBattler, element: StringName) -> bool:
	if element.is_empty() or target == null:
		return true
	return _known.get(side, {}).get(target, {}).has(element)


## Tells [param side] what [param element] does to [param target] (a scan, a bestiary).
func reveal_affinity(side: int, target: BKBattler, element: StringName) -> void:
	if element.is_empty() or target == null:
		return
	if not _known.has(side):
		_known[side] = {}
	if not _known[side].has(target):
		_known[side][target] = {}
	_known[side][target][element] = true


## Expected damage of one hit, without rolling anything: {"min": int, "max": int,
## "multiplier": float, "affinity": BKBattler.Affinity, "known": bool}. The affinity counts
## only once [param actor]'s side knows it ("known"); until then the preview assumes normal
## damage. "min" and "max" are negative when the target absorbs the element.
func preview_damage(actor: BKBattler, action: BKAction, target: BKBattler, timed: bool = false) -> Dictionary:
	var known := knows_affinity(actor.side, target, action.element)
	var multiplier := target.get_affinity(action.element) if known else 1.0
	var base := _base_damage(actor, action, target) * _timing_factor(actor, target, timed)
	var low := _finish_damage(base * (1.0 - variance), multiplier)
	var high := _finish_damage(base * (1.0 + variance), multiplier)
	return {"min": mini(low, high), "max": maxi(low, high), "multiplier": multiplier,
		"affinity": BKBattler.affinity_kind(multiplier), "known": known}


## Lets every enemy turn play until a hero must choose or the battle ends.
func run_enemy_turns(limit: int = 100) -> void:
	while not is_over() and current != null and current.side == BKBattler.ENEMIES and limit > 0:
		run_ai_turn()
		limit -= 1


# --- Rules -------------------------------------------------------------------

func _apply(actor: BKBattler, action: BKAction, target: BKBattler, events: Array[Dictionary], timed: bool = false) -> void:
	var hostile := target.side != actor.side
	match action.kind:
		BKAction.Kind.DAMAGE:
			var landed := false
			for i in action.hits:
				if not target.is_alive():
					break
				if rng.randf() > action.accuracy - target.get_stat(&"evasion"):
					events.append({"type": "miss", "actor": actor, "target": target})
					continue
				var critical := action.can_crit and rng.randf() < actor.get_stat(&"crit_chance")
				var amount := compute_damage(actor, action, target, critical, timed)
				var affinity := BKBattler.affinity_kind(target.get_affinity(action.element))
				reveal_affinity(actor.side, target, action.element)
				if amount < 0:
					var healed := mini(-amount, target.get_max_hp() - target.hp)
					target.hp += healed
					events.append({"type": "absorb", "actor": actor, "target": target, "amount": healed,
						"element": action.element, "affinity": affinity})
					continue
				target.hp = maxi(0, target.hp - amount)
				landed = landed or amount > 0
				events.append({"type": "damage", "actor": actor, "target": target, "amount": amount, "critical": critical and amount > 0,
					"element": action.element, "affinity": affinity, "timed": timed})
			if landed:
				_apply_statuses(actor, action, target, events)
		BKAction.Kind.HEAL:
			var amount := roundi(action.power + actor.get_stat(&"magic") * 0.5)
			amount = mini(amount, target.get_max_hp() - target.hp)
			target.hp += amount
			events.append({"type": "heal", "actor": actor, "target": target, "amount": amount})
			_apply_statuses(actor, action, target, events)
		BKAction.Kind.RESTORE_MP:
			var amount := mini(roundi(action.power), target.get_max_mp() - target.mp)
			target.mp += amount
			events.append({"type": "mp", "actor": actor, "target": target, "amount": amount})
		BKAction.Kind.REVIVE:
			target.hp = maxi(1, roundi(target.get_max_hp() * action.power / 100.0))
			target.statuses.clear()
			target.ready_at = maxf(target.ready_at, actor.ready_at)
			events.append({"type": "revived", "actor": actor, "target": target, "amount": target.hp})
		BKAction.Kind.SUPPORT:
			if hostile and rng.randf() > action.accuracy - target.get_stat(&"evasion"):
				events.append({"type": "miss", "actor": actor, "target": target})
				return
			_apply_statuses(actor, action, target, events)
	for status_id in action.cures:
		var at := target.statuses.map(func(e: Dictionary) -> StringName: return e.status.id).find(status_id)
		if at >= 0:
			var status: BKStatus = target.statuses[at].status
			target.remove_status(status_id)
			events.append({"type": "cured", "actor": actor, "target": target, "status": status})
	if hostile and not target.is_alive():
		_defeat(target, events)


## Damage of one hit, without rolling accuracy. [param critical] is decided by the caller.
## The target's affinity to [member BKAction.element] applies: 0 when immune, negative
## when it absorbs the element (the amount it heals).
func compute_damage(actor: BKBattler, action: BKAction, target: BKBattler, critical: bool = false, timed: bool = false) -> int:
	var amount := _base_damage(actor, action, target)
	amount *= rng.randf_range(1.0 - variance, 1.0 + variance)
	if critical:
		amount *= critical_multiplier
	amount *= _timing_factor(actor, target, timed)
	return _finish_damage(amount, target.get_affinity(action.element))


## Power and attack (or magic) against defense (or resistance), defending included.
func _base_damage(actor: BKBattler, action: BKAction, target: BKBattler) -> float:
	var magic := action.scaling == BKAction.Scaling.MAGIC
	var raw := action.power + actor.get_stat(&"magic" if magic else &"attack")
	var armor := target.get_stat(&"resistance" if magic else &"defense")
	var amount := raw * armor_scale / (armor_scale + armor)
	if target.defending:
		amount *= 0.5
	return amount


func _finish_damage(amount: float, multiplier: float) -> int:
	if is_zero_approx(multiplier):
		return 0
	if multiplier < 0.0:
		return mini(-1, roundi(absf(amount) * multiplier))
	return maxi(1, roundi(amount * multiplier))


func _timing_factor(actor: BKBattler, target: BKBattler, timed: bool) -> float:
	if not timed or target.side == actor.side:
		return 1.0
	if actor.side == BKBattler.PARTY:
		return 1.0 + timed_attack_bonus
	return maxf(0.0, 1.0 - timed_guard_reduction)


func _apply_statuses(actor: BKBattler, action: BKAction, target: BKBattler, events: Array[Dictionary]) -> void:
	for status in action.statuses:
		if status == null or not target.is_alive():
			continue
		if action.status_chance < 1.0 and rng.randf() >= action.status_chance:
			continue
		if target.apply_status(status):
			events.append({"type": "status", "actor": actor, "target": target, "status": status})
		else:
			events.append({"type": "immune", "actor": actor, "target": target, "status": status})


func _defeat(target: BKBattler, events: Array[Dictionary]) -> void:
	target.hp = 0
	target.statuses.clear()
	target.defending = false
	events.append({"type": "defeated", "target": target})
	battler_defeated.emit(target)


func _next_turn() -> void:
	for _guard in 1000:
		current = _pick_next()
		if current == null:
			return
		current.defending = false
		var events := _tick(current)
		if not events.is_empty():
			turn_events.emit(current, events)
		_check_end()
		if is_over():
			return
		if not current.is_alive():
			continue
		if events.any(func(e: Dictionary) -> bool: return e.type == "stunned"):
			current.ready_at += _turn_time(current)
			continue
		turn_started.emit(current)
		return


func _pick_next() -> BKBattler:
	var next: BKBattler = null
	for battler in get_all():
		if battler.is_alive() and (next == null or _before(battler, battler.ready_at, next, next.ready_at)):
			next = battler
	return next


## Statuses of [param battler] at the start of its turn: damage, then durations.
func _tick(battler: BKBattler) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var expired: Array[Dictionary] = []
	var stunned := false
	for entry in battler.statuses.duplicate():
		var status: BKStatus = entry.status
		var amount := (status.damage_per_turn + roundi(status.damage_percent_per_turn * battler.get_max_hp())) * int(entry.stacks)
		if amount != 0 and battler.is_alive():
			battler.hp = clampi(battler.hp - amount, 0, battler.get_max_hp())
			events.append({"type": "tick", "target": battler, "status": status, "amount": amount})
			if not battler.is_alive():
				_defeat(battler, events)
				return events
		if status.skips_turn:
			stunned = true
		entry.turns -= 1
		if entry.turns <= 0:
			battler.remove_status(status.id)
			expired.append({"type": "expired", "target": battler, "status": status})
	if stunned:
		events.append({"type": "stunned", "target": battler})
	events.append_array(expired)
	return events


func _check_end() -> void:
	if is_over() and outcome != Outcome.FLED:
		return
	if outcome == Outcome.FLED:
		current = null
		return
	if get_alive(BKBattler.ENEMIES).is_empty():
		outcome = Outcome.VICTORY
		current = null
		rewards = _pay_rewards()
		_give_xp(rewards)
		battle_ended.emit(outcome, rewards)
	elif get_alive(BKBattler.PARTY).is_empty():
		outcome = Outcome.DEFEAT
		current = null
		rewards = {"xp": 0, "gold": 0, "items": {}, "left_behind": {}, "level_ups": [], "xp_each": 0}
		battle_ended.emit(outcome, rewards)


func _pay_rewards() -> Dictionary:
	var xp := 0
	var gold := 0
	var items := {}
	for enemy in enemies:
		xp += enemy.data.xp
		gold += enemy.data.gold
		for drop in enemy.data.drops:
			if drop != null and not drop.item_id.is_empty() and rng.randf() < drop.chance:
				items[drop.item_id] = int(items.get(drop.item_id, 0)) + rng.randi_range(drop.min_amount, maxi(drop.min_amount, drop.max_amount))
	var given := {}
	var left := {}
	var all := items.duplicate()
	if gold > 0 and not gold_item.is_empty():
		all[gold_item] = int(all.get(gold_item, 0)) + gold
	for item_id: StringName in all:
		var amount: int = all[item_id]
		var placed := 0
		if bag != null:
			var result := bag.add(item_id, amount, true)
			placed = amount - result.remainder if result.ok else 0
		if placed > 0:
			given[item_id] = placed
		if placed < amount:
			left[item_id] = amount - placed
	return {"xp": xp, "gold": gold, "items": given, "left_behind": left}


## Victory XP to the surviving heroes that have a curve (theirs or [member level_curve]).
func _give_xp(paid: Dictionary) -> void:
	var level_ups: Array[Dictionary] = []
	var survivors := get_alive(BKBattler.PARTY)
	var total: int = paid.get("xp", 0)
	var each := floori(float(total) / survivors.size()) if share_xp and not survivors.is_empty() else total
	paid["xp_each"] = each
	for hero in survivors:
		if hero.data.level_curve == null and level_curve != null:
			hero.curve = level_curve
		if hero.get_curve() == null:
			continue
		var info := hero.gain_xp(each)
		if info.to > info.from:
			level_ups.append(info)
	paid["level_ups"] = level_ups
	for info in level_ups:
		level_up.emit(info.battler, info.from, info.to, info.gains)


func _make_side(entries: Array, side: int) -> Array[BKBattler]:
	var made: Array[BKBattler] = []
	var counts := {}
	for entry: Variant in entries:
		var battler: BKBattler = null
		if entry is BKBattler:
			battler = entry
		elif entry is BKBattlerData:
			battler = BKBattler.from_data(entry, side)
		if battler == null:
			continue
		battler.side = side
		battler.index = made.size()
		made.append(battler)
		counts[battler.data.get_title()] = int(counts.get(battler.data.get_title(), 0)) + 1
	# Several "Wisp": Wisp A, Wisp B.
	var seen := {}
	for battler in made:
		var title := battler.data.get_title()
		if side == BKBattler.ENEMIES and counts[title] > 1:
			battler.display_name = "%s %s" % [title, char(65 + int(seen.get(title, 0)))]
			seen[title] = int(seen.get(title, 0)) + 1
		elif battler.display_name.is_empty():
			battler.display_name = title
	return made


func _turn_time(battler: BKBattler) -> float:
	return 100.0 / battler.get_stat(&"speed")


func _before(a: BKBattler, a_time: float, b: BKBattler, b_time: float) -> bool:
	if not is_equal_approx(a_time, b_time):
		return a_time < b_time
	if a.side != b.side:
		return a.side < b.side  # heroes win ties
	return a.index < b.index


func _ai_targets(actor: BKBattler, action: BKAction, preferred: BKBattler) -> Array[BKBattler]:
	var valid := get_valid_targets(actor, action)
	if not action.targets_one() or valid.is_empty():
		return valid
	var picked: Array[BKBattler] = []
	if preferred != null and valid.has(preferred):
		picked.append(preferred)
		return picked
	if action.is_elemental() and action.targets_enemies() and ai_affinity_focus > 0.0:
		# A known weakness first; never a target known to be immune or to absorb it.
		var best: BKBattler = null
		var best_multiplier := 1.0
		var usable: Array[BKBattler] = []
		for battler in valid:
			if not _ai_knows(actor, battler, action.element):
				usable.append(battler)
				continue
			var multiplier := battler.get_affinity(action.element)
			if multiplier > 0.0:
				usable.append(battler)
			if multiplier > best_multiplier or (best != null and is_equal_approx(multiplier, best_multiplier) and battler.hp < best.hp):
				best = battler
				best_multiplier = multiplier
		if best != null and best_multiplier > 1.0:
			picked.append(best)
			return picked
		if not usable.is_empty():
			valid = usable
	if action.targets_enemies() and rng.randf() < ai_focus_weakest:
		var weakest := valid[0]
		for battler in valid:
			if battler.hp < weakest.hp:
				weakest = battler
		picked.append(weakest)
		return picked
	picked.append(valid[rng.randi_range(0, valid.size() - 1)])
	return picked


func _ai_knows(actor: BKBattler, target: BKBattler, element: StringName) -> bool:
	return ai_knows_affinities or knows_affinity(actor.side, target, element)


## [member BKAction.ai_weight], scaled by what the AI knows of the targets' affinities.
func _ai_weight(actor: BKBattler, action: BKAction) -> float:
	if not action.is_elemental() or ai_affinity_focus <= 0.0 or not action.targets_enemies():
		return action.ai_weight
	var targets := get_valid_targets(actor, action)
	if targets.is_empty():
		return action.ai_weight
	var score := 0.0
	if action.targets_one():
		score = -INF
		for target in targets:
			score = maxf(score, target.get_affinity(action.element) if _ai_knows(actor, target, action.element) else 1.0)
	else:
		for target in targets:
			score += target.get_affinity(action.element) if _ai_knows(actor, target, action.element) else 1.0
		score /= targets.size()
	if score <= 0.0:
		return 0.0
	return action.ai_weight * pow(score, ai_affinity_focus)


func _has_all(battler: BKBattler, action: BKAction) -> bool:
	for status in action.statuses:
		if status != null and not battler.has_status(status.id):
			return false
	return not action.statuses.is_empty()
