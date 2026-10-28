extends "res://tests/battle_kit/bk_test_case.gd"
## Battle rules: stats, turn order, damage, costs, statuses, rewards, AI.


func hit(power: float = 0.0, target := BKAction.Target.ONE_ENEMY) -> BKAction:
	var action := BKAction.make(&"hit", "Hit", BKAction.Kind.DAMAGE, target, power)
	action.accuracy = 1.0
	action.can_crit = false
	return action


func test_stats_add_bonuses_then_status_percentages() -> void:
	var battler := BKBattler.from_data(fighter(&"a", {&"attack": 10}))
	battler.bonuses = {&"attack": 5.0}
	assert_eq(battler.get_stat(&"attack"), 15.0)
	var valor := BKStatus.make(&"valor", "Valor", 3, false)
	valor.stat_percent = {&"attack": 0.5}
	battler.apply_status(valor)
	assert_eq(battler.get_stat(&"attack"), 22.5)
	assert_eq(battler.get_stat(&"speed"), 10.0)
	battler.remove_status(&"valor")
	assert_eq(battler.get_stat(&"attack"), 15.0)


func test_faster_fighters_act_more_often() -> void:
	var battle := make_battle([fighter(&"fast", {&"speed": 20})], [fighter(&"slow", {&"speed": 10})])
	assert_eq(battle.current.data.id, &"fast")
	var order := battle.get_turn_order(6)
	var fast := order.filter(func(b: BKBattler) -> bool: return b.data.id == &"fast").size()
	assert_eq(fast, 4, "twice as fast: 4 of the next 6 turns")
	var defend := BKAction.make(&"defend", "Defend", BKAction.Kind.DEFEND, BKAction.Target.SELF)
	var seen := []
	for i in 6:
		seen.append(battle.current.data.id)
		assert_ok_battle(battle.perform(defend))
	assert_eq(seen, order.map(func(b: BKBattler) -> StringName: return b.data.id), "the preview matched the real order")


func test_damage_formula_defense_crit_and_defend() -> void:
	var battle := make_battle([fighter(&"a", {&"attack": 20})], [fighter(&"b", {&"defense": 60})])
	var a := battle.party[0]
	var b := battle.enemies[0]
	assert_eq(battle.compute_damage(a, hit(), b), 10, "60 defense with the default 60 scale halves the damage")
	assert_eq(battle.compute_damage(a, hit(), b, true), 15, "critical x1.5")
	b.defending = true
	assert_eq(battle.compute_damage(a, hit(), b), 5, "defending halves again")
	assert_eq(battle.compute_damage(a, hit(-100), b), 1, "at least 1")


func test_mp_cost_and_items_from_the_bag() -> void:
	var battle := make_battle([fighter(&"hero", {&"max_mp": 3, &"speed": 50})], [fighter(&"foe", {&"speed": 1})])
	var spell := hit(5)
	spell.mp_cost = 4
	assert_battle(battle.perform(spell, one(battle.enemies[0])), BKResult.Code.NOT_ENOUGH_MP)
	var potion := BKAction.make_item(&"health_potion", "Potion", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 30)
	battle.item_actions = [potion]
	assert_eq(battle.get_item_actions().size(), 0, "no potion in the bag: not offered")
	assert_battle(battle.perform(potion, one(battle.party[0])), BKResult.Code.NO_ITEM)
	battle.bag.add(&"health_potion", 2)
	battle.party[0].hp = 50
	var result := battle.perform(potion, one(battle.party[0]))
	assert_ok_battle(result)
	assert_eq(battle.party[0].hp, 85, "30 + half of 10 magic")
	assert_eq(battle.bag.count(&"health_potion"), 1, "one potion used")
	assert_eq(result.events_of("heal")[0].amount, 35)


func test_heal_is_capped_and_targets_are_checked() -> void:
	var battle := make_battle([fighter(&"hero"), fighter(&"friend", {&"speed": 1})], [fighter(&"foe", {&"speed": 1})])
	var heal := BKAction.make(&"heal", "Heal", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 50)
	battle.party[1].hp = 90
	assert_battle(battle.perform(heal, one(battle.enemies[0])), BKResult.Code.INVALID_TARGET, "not an ally")
	assert_battle(battle.perform(heal, []), BKResult.Code.INVALID_TARGET, "no target")
	var result := battle.perform(heal, one(battle.party[1]))
	assert_eq(battle.party[1].hp, 100)
	assert_eq(result.events_of("heal")[0].amount, 10, "only what was missing")


func test_poison_stacks_ticks_and_wears_off() -> void:
	var battle := make_battle([fighter(&"hero", {&"speed": 100})], [fighter(&"foe", {&"speed": 1, &"max_hp": 500})])
	var poison := BKStatus.make(&"poison", "Poison", 2)
	poison.damage_per_turn = 5
	poison.max_stacks = 3
	var sting := hit(0)
	sting.statuses = [poison]
	var foe := battle.enemies[0]
	foe.apply_status(poison)
	foe.apply_status(poison)
	assert_eq(foe.get_stacks(&"poison"), 2)
	# Let the foe's turn come: it takes 2 stacks x 5.
	var ticks: Array = []
	battle.turn_events.connect(func(_a: BKBattler, events: Array[Dictionary]) -> void: ticks.append_array(events))
	while battle.current != foe:
		battle.perform(BKAction.make(&"defend", "Defend", BKAction.Kind.DEFEND, BKAction.Target.SELF))
	assert_eq(ticks[0].type, "tick")
	assert_eq(ticks[0].amount, 10)
	assert_eq(foe.hp, foe.get_max_hp() - 10)
	disconnect_all([battle])


func test_stun_skips_the_turn() -> void:
	var battle := make_battle([fighter(&"hero", {&"speed": 10})], [fighter(&"foe", {&"speed": 9})])
	var stun := BKStatus.make(&"stun", "Stun", 1)
	stun.skips_turn = true
	var bash := hit(0)
	bash.statuses = [stun]
	battle.perform(bash, one(battle.enemies[0]))
	assert_eq(battle.current, battle.party[0], "the stunned foe lost its turn")
	assert_false(battle.enemies[0].has_status(&"stun"), "and the stun wore off")


func test_immunity_and_cures() -> void:
	var golem := fighter(&"golem")
	golem.immunities.assign([&"poison"])
	var battle := make_battle([fighter(&"hero", {&"speed": 30}), fighter(&"medic", {&"speed": 29})], [golem, fighter(&"foe", {&"speed": 1})])
	var poison := BKStatus.make(&"poison", "Poison", 3)
	var sting := hit(0)
	sting.statuses = [poison]
	var result := battle.perform(sting, one(battle.enemies[0]))
	assert_eq(result.events_of("immune").size(), 1)
	assert_false(battle.enemies[0].has_status(&"poison"))
	battle.party[0].apply_status(poison)
	var antidote := BKAction.make(&"antidote", "Antidote", BKAction.Kind.SUPPORT, BKAction.Target.ONE_ALLY)
	antidote.cures.assign([&"poison"])
	assert_eq(battle.current, battle.party[1])
	result = battle.perform(antidote, one(battle.party[0]))
	assert_eq(result.events_of("cured").size(), 1)
	assert_false(battle.party[0].has_status(&"poison"))


func test_victory_pays_xp_gold_and_drops_into_the_bag() -> void:
	var foe := fighter(&"foe", {&"max_hp": 1})
	foe.xp = 30
	foe.gold = 12
	foe.drops.assign([BKDrop.make(&"bone", 1.0, 2, 2)])
	var battle := make_battle([fighter(&"hero", {&"speed": 50})], [foe, foe])
	var ended := []
	battle.battle_ended.connect(func(outcome: BKBattle.Outcome, rewards: Dictionary) -> void: ended.append([outcome, rewards]))
	var sweep := hit(0, BKAction.Target.ALL_ENEMIES)
	var result := battle.perform(sweep)
	assert_eq(result.events_of("defeated").size(), 2)
	assert_eq(battle.outcome, BKBattle.Outcome.VICTORY)
	assert_eq(ended.size(), 1)
	assert_eq(battle.rewards.xp, 60)
	assert_eq(battle.bag.count(&"gold_coins"), 24)
	assert_eq(battle.bag.count(&"bone"), 4)
	assert_battle(battle.perform(sweep), BKResult.Code.BATTLE_OVER)
	disconnect_all([battle])


func test_full_bag_reports_what_was_left_behind() -> void:
	var foe := fighter(&"foe", {&"max_hp": 1})
	foe.drops.assign([BKDrop.make(&"bone", 1.0, 5, 5)])
	var battle := make_battle([fighter(&"hero")], [foe], 1, false)
	battle.bag = IKContainer.new(&"tiny", 1, make_db())
	battle.bag.add(&"health_potion", 1)
	battle.start([fighter(&"hero", {&"speed": 50})], [foe], 1)
	battle.perform(hit(), one(battle.enemies[0]))
	assert_eq(battle.rewards.left_behind, {&"bone": 5})
	assert_eq(battle.bag.count(&"health_potion"), 1, "nothing was lost")


func test_defeat_and_fleeing() -> void:
	var battle := make_battle([fighter(&"hero", {&"max_hp": 1, &"speed": 1})], [fighter(&"brute", {&"speed": 50})])
	battle.run_enemy_turns()
	assert_eq(battle.outcome, BKBattle.Outcome.DEFEAT)
	var flee := BKAction.make(&"flee", "Flee", BKAction.Kind.FLEE, BKAction.Target.SELF)
	battle = make_battle([fighter(&"hero", {&"speed": 50})], [fighter(&"foe")])
	battle.can_flee = false
	assert_battle(battle.perform(flee), BKResult.Code.CANNOT_FLEE)
	battle.can_flee = true
	battle.flee_chance = 1.0
	assert_ok_battle(battle.perform(flee))
	assert_eq(battle.outcome, BKBattle.Outcome.FLED)
	assert_eq(battle.current, null)


func test_revive_brings_a_fallen_ally_back() -> void:
	var battle := make_battle([fighter(&"cleric", {&"speed": 30}), fighter(&"knight", {&"speed": 1})], [fighter(&"foe", {&"speed": 1})])
	battle.party[1].hp = 0
	var raise := BKAction.make(&"raise", "Raise", BKAction.Kind.REVIVE, BKAction.Target.ONE_FALLEN_ALLY, 50)
	assert_battle(battle.perform(raise, one(battle.party[0])), BKResult.Code.INVALID_TARGET, "alive: cannot be revived")
	assert_ok_battle(battle.perform(raise, one(battle.party[1])))
	assert_eq(battle.party[1].hp, 50)


func test_ai_heals_a_hurt_ally_then_focuses_the_weakest() -> void:
	var healer := fighter(&"healer", {&"speed": 50})
	healer.actions.append(BKAction.make(&"mend", "Mend", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 30))
	var battle := make_battle([fighter(&"a", {&"speed": 1}), fighter(&"b", {&"speed": 1})], [healer, fighter(&"brute", {&"speed": 1})])
	battle.enemies[1].hp = 20
	var choice := battle.choose_ai_action(battle.enemies[0])
	assert_eq(choice.action.id, &"mend")
	assert_eq(choice.targets, [battle.enemies[1]])
	battle.enemies[1].hp = 100
	battle.ai_focus_weakest = 1.0
	battle.party[1].hp = 5
	choice = battle.choose_ai_action(battle.enemies[0])
	assert_eq(choice.action.id, &"attack")
	assert_eq(choice.targets, [battle.party[1]])


func test_same_seed_same_battle() -> void:
	var outcomes := []
	for run in 2:
		var hero := fighter(&"hero", {&"crit_chance": 0.3, &"evasion": 0.2})
		var battle := make_battle([hero, fighter(&"mage")], [fighter(&"foe", {&"crit_chance": 0.3}), fighter(&"foe")], 42)
		battle.variance = 0.1
		for i in 200:
			if battle.is_over():
				break
			battle.run_ai_turn()
		outcomes.append([battle.outcome, battle.turn_count, battle.party[0].hp, battle.party[1].hp])
	assert_eq(outcomes[0], outcomes[1])
	assert_true(outcomes[0][0] != BKBattle.Outcome.NONE, "the battle ended")


func assert_ok_battle(result: BKResult, message: String = "") -> void:
	if result == null or not result.ok:
		fail("%sexpected OK, got %s" % [message + ": " if message else "", result])
