extends "res://tests/battle_kit/bk_test_case.gd"
## 1.1: elemental affinities, the AI and the damage preview, the level curve, timed hits.


func element_hit(element: StringName, power: float = 0.0, target := BKAction.Target.ONE_ENEMY) -> BKAction:
	var action := BKAction.make(StringName("hit_" + element), "Hit", BKAction.Kind.DAMAGE, target, power)
	action.accuracy = 1.0
	action.can_crit = false
	action.element = element
	return action


func test_weak_resist_immune_absorb() -> void:
	var foe := fighter(&"slime", {&"max_hp": 200, &"speed": 1})
	foe.affinities = {&"fire": BKBattlerData.WEAK, &"ice": BKBattlerData.RESIST, &"earth": BKBattlerData.IMMUNE, &"water": BKBattlerData.ABSORB}
	var battle := make_battle([fighter(&"mage", {&"attack": 20, &"speed": 50})], [foe])
	var mage := battle.party[0]
	var slime := battle.enemies[0]
	assert_eq(battle.compute_damage(mage, element_hit(&""), slime), 20, "neutral")
	assert_eq(battle.compute_damage(mage, element_hit(&"fire"), slime), 40, "weak: x2")
	assert_eq(battle.compute_damage(mage, element_hit(&"ice"), slime), 10, "resist: x0.5")
	assert_eq(battle.compute_damage(mage, element_hit(&"earth"), slime), 0, "immune")
	assert_eq(battle.compute_damage(mage, element_hit(&"water"), slime), -20, "absorb: negative")
	assert_eq(battle.compute_damage(mage, element_hit(&"wind"), slime), 20, "unlisted element: normal")
	var poison := BKStatus.make(&"poison", "Poison", 3)
	var mud := element_hit(&"earth")
	mud.statuses = [poison]
	var result := battle.perform(mud, one(slime))
	var hit: Dictionary = result.events_of("damage")[0]
	assert_eq(hit.amount, 0)
	assert_eq(hit.affinity, BKBattler.Affinity.IMMUNE)
	assert_false(slime.has_status(&"poison"), "no status through an immunity")
	assert_true(BKText.describe(hit).contains("(immune)"), BKText.describe(hit))
	slime.hp = 150
	while battle.current != mage:
		battle.perform(BKAction.make(&"defend", "Defend", BKAction.Kind.DEFEND, BKAction.Target.SELF))
	result = battle.perform(element_hit(&"water"), one(slime))
	assert_eq(result.events_of("absorb")[0].amount, 20)
	assert_eq(slime.hp, 170, "absorbed: healed")
	assert_eq(result.events_of("damage").size(), 0)
	assert_eq(BKText.affinity_tag(BKBattler.Affinity.WEAK), "Weak!")
	assert_eq(BKText.affinity_tag(BKBattler.Affinity.RESIST), "Resist")
	assert_eq(BKBattler.affinity_kind(1.0), BKBattler.Affinity.NORMAL)
	assert_eq(BKBattler.affinity_kind(1.5), BKBattler.Affinity.WEAK)


func test_sides_learn_affinities_by_hitting() -> void:
	var foe := fighter(&"golem", {&"max_hp": 500, &"speed": 1})
	foe.affinities = {&"ice": 2.0}
	var battle := make_battle([fighter(&"mage", {&"speed": 50})], [foe])
	var golem := battle.enemies[0]
	assert_false(battle.knows_affinity(BKBattler.PARTY, golem, &"ice"))
	assert_true(battle.knows_affinity(BKBattler.PARTY, golem, &""), "neutral is always known")
	var guess := battle.preview_damage(battle.party[0], element_hit(&"ice"), golem)
	assert_false(guess.known)
	assert_eq(guess.max, 20, "unknown: the preview assumes normal damage")
	battle.perform(element_hit(&"ice"), one(golem))
	assert_true(battle.knows_affinity(BKBattler.PARTY, golem, &"ice"), "learned by hitting")
	assert_false(battle.knows_affinity(BKBattler.ENEMIES, golem, &"ice"), "each side has its own knowledge")
	guess = battle.preview_damage(battle.party[0], element_hit(&"ice"), golem)
	assert_true(guess.known)
	assert_eq(guess.affinity, BKBattler.Affinity.WEAK)
	assert_eq([guess.min, guess.max], [40, 40], "no variance in the fixture")
	battle.start([fighter(&"mage")], [foe], 1)
	assert_false(battle.knows_affinity(BKBattler.PARTY, battle.enemies[0], &"ice"), "a new battle starts unknown")


func test_preview_rolls_nothing() -> void:
	var battle := make_battle([fighter(&"hero", {&"attack": 20, &"speed": 50})], [fighter(&"foe", {&"defense": 60})])
	battle.variance = 0.1
	var state := battle.rng.state
	var guess := battle.preview_damage(battle.party[0], element_hit(&""), battle.enemies[0])
	assert_eq(battle.rng.state, state, "same battle with or without previews")
	assert_eq([guess.min, guess.max], [9, 11])
	assert_eq(battle.preview_damage(battle.party[0], element_hit(&""), battle.enemies[0], true).max, 14, "a timed hit: +30 %")


func test_ai_prefers_known_weaknesses() -> void:
	var caster := fighter(&"imp", {&"speed": 50})
	var fire := element_hit(&"fire")
	caster.actions.append(fire)
	var tough := fighter(&"knight", {&"speed": 1})
	tough.affinities = {&"fire": 0.0}
	var frail := fighter(&"archer", {&"speed": 1})
	frail.affinities = {&"fire": 2.0}
	var battle := make_battle([tough, frail], [caster])
	battle.ai_focus_weakest = 0.0
	var imp := battle.enemies[0]
	# Nothing known: fire is as likely as the plain attack.
	assert_eq(battle._ai_weight(imp, fire), 1.0)
	battle.reveal_affinity(BKBattler.ENEMIES, battle.party[0], &"fire")
	var picks := {}
	for i in 30:
		var targets := battle._ai_targets(imp, fire, null)
		picks[targets[0].data.id] = true
	assert_eq(picks.keys(), [&"archer"], "never a target known to be immune")
	battle.reveal_affinity(BKBattler.ENEMIES, battle.party[1], &"fire")
	assert_eq(battle._ai_weight(imp, fire), 4.0, "a known weakness, focus 2: x4")
	var fire_count := 0
	for i in 200:
		var choice := battle.choose_ai_action(imp)
		if choice.action == fire:
			fire_count += 1
			assert_eq(choice.targets, [battle.party[1]], "the weak one")
	assert_true(fire_count > 130, "fire picked %d times out of 200 (expected about 160)" % fire_count)
	battle.ai_affinity_focus = 0.0
	assert_eq(battle._ai_weight(imp, fire), 1.0, "focus 0: affinities ignored")
	battle.ai_affinity_focus = 2.0
	var cheat := make_battle([tough, frail], [caster])
	cheat.ai_knows_affinities = true
	assert_eq(cheat._ai_weight(cheat.enemies[0], fire), 4.0, "an AI that knows everything from the start")


func test_level_curve() -> void:
	var curve := BKLevelCurve.make(100, 1.5, {&"max_hp": 10, &"attack": 2}, 10)
	assert_eq(curve.xp_to_reach(1), 0)
	assert_eq(curve.xp_to_reach(2), 100)
	assert_eq(curve.xp_to_reach(3), 283)
	assert_eq(curve.level_for_xp(99), 1)
	assert_eq(curve.level_for_xp(300), 3)
	assert_eq(curve.level_for_xp(999999), 10, "capped at max_level")
	curve.xp_table = PackedInt32Array([50, 120])
	assert_eq(curve.xp_to_reach(3), 120, "the table wins")
	assert_eq(curve.xp_to_reach(4), roundi(100 * pow(3, 1.5)), "then the formula")
	assert_eq(curve.validate(), PackedStringArray())
	curve.xp_table = PackedInt32Array([50, 40])
	assert_eq(curve.validate().size(), 1)
	curve.xp_table = PackedInt32Array()
	var hero := BKBattler.from_data(fighter(&"hero", {&"max_hp": 100, &"attack": 20}))
	hero.bonuses = {&"attack": 5.0}  # equipment or Skill Tree Kit
	hero.hp = 60
	var info := hero.gain_xp(300, curve)
	assert_eq([info.from, info.to], [1, 3])
	assert_eq(info.gains, {&"max_hp": 20.0, &"attack": 4.0})
	assert_eq(hero.get_max_hp(), 120)
	assert_eq(hero.get_stat(&"attack"), 29.0, "base 20 + bonuses 5 + levels 4")
	assert_eq(hero.hp, 80, "HP rise with the max")
	assert_eq(hero.get_xp_to_next(), curve.xp_to_reach(4) - 300)
	var copy := BKBattler.from_data(hero.data)
	copy.curve = curve
	copy.load_data(JSON.parse_string(JSON.stringify(hero.to_data())))
	assert_eq([copy.level, copy.xp, copy.hp, copy.get_max_hp()], [3, 300, 80, 120])
	var own := fighter(&"veteran")
	own.level = 5
	own.growth = {&"defense": 3.0}
	var veteran := BKBattler.from_data(own)
	assert_eq(veteran.level, 5)
	veteran.gain_xp(1, curve)
	assert_eq(veteran.level, 5, "starts with the XP of its level")
	assert_eq(veteran.xp, curve.xp_to_reach(5) + 1)


func test_victory_levels_up_the_survivors() -> void:
	var foe := fighter(&"foe", {&"max_hp": 1, &"speed": 1})
	foe.xp = 120
	var battle := make_battle([fighter(&"hero"), fighter(&"fallen")], [foe], 1, false)
	battle.level_curve = BKLevelCurve.make(100, 1.0, {&"max_hp": 10})
	var party: Array[BKBattler] = [BKBattler.from_data(fighter(&"hero", {&"speed": 50})), BKBattler.from_data(fighter(&"fallen"))]
	party[1].hp = 0
	var ups := []
	battle.level_up.connect(func(b: BKBattler, from: int, to: int, _gains: Dictionary) -> void: ups.append([b.data.id, from, to]))
	battle.start(party, [foe], 1)
	var sweep := element_hit(&"", 0, BKAction.Target.ALL_ENEMIES)
	battle.perform(sweep)
	assert_eq(battle.outcome, BKBattle.Outcome.VICTORY)
	assert_eq(ups, [[&"hero", 1, 2]], "fallen heroes get no XP")
	assert_eq(battle.rewards.level_ups.size(), 1)
	assert_eq(battle.rewards.xp_each, 120)
	assert_eq(party[0].xp, 120)
	assert_eq(party[0].get_max_hp(), 110)
	assert_true(BKText.level_up_line(battle.rewards.level_ups[0]).begins_with("Hero reaches level 2!"))
	party[1].hp = 50
	battle.share_xp = true
	battle.start(party, [foe], 1)
	battle.perform(sweep)
	assert_eq(battle.rewards.xp_each, 60, "shared between the two survivors")
	assert_eq(party[1].xp, 60)
	disconnect_all([battle])
	var plain := make_battle([fighter(&"hero", {&"speed": 50})], [foe])
	plain.perform(sweep)
	assert_eq(plain.rewards.level_ups, [], "no curve: no levels (1.0 behaviour)")
	assert_eq(plain.party[0].level, 1)


func test_timed_hits() -> void:
	var brute := fighter(&"brute", {&"attack": 20, &"speed": 20, &"max_hp": 500})
	var strike := element_hit(&"")
	brute.basic_attack = strike  # always hits, never crits
	var battle := make_battle([fighter(&"hero", {&"attack": 20, &"speed": 50, &"max_hp": 500})], [brute])
	var result := battle.perform(strike, one(battle.enemies[0]), true)
	assert_eq(result.events_of("damage")[0].amount, 26, "a timed attack: +30 %")
	assert_true(result.events_of("damage")[0].timed)
	result = battle.perform(strike, one(battle.enemies[0]))
	assert_eq(result.events_of("damage")[0].amount, 20, "not timed")
	while battle.current != battle.enemies[0]:
		battle.perform(BKAction.make(&"wait", "Wait", BKAction.Kind.SUPPORT, BKAction.Target.SELF))
	result = battle.run_ai_turn(true)
	assert_eq(result.events_of("damage")[0].amount, 12, "a timed guard: -40 %")
