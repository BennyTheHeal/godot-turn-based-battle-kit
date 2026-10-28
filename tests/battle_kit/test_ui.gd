extends "res://tests/battle_kit/bk_test_case.gd"
## The battle screen and the demo.


func _view(party: Array, enemies: Array) -> Dictionary:
	var battle := make_battle(party, enemies, 3, false)
	var view := BKBattleView.new()
	view.enemy_delay = 0.0
	view.battle = battle
	view.size = Vector2(1000, 640)
	add_to_tree(view)
	battle.start(party, enemies, 3)
	return {"battle": battle, "view": view}


func test_view_builds_cards_and_commands() -> void:
	var w := _view([fighter(&"hero", {&"speed": 50}), fighter(&"mage")], [fighter(&"foe"), fighter(&"foe")])
	await wait_frames(2)
	var view: BKBattleView = w.view
	var battle: BKBattle = w.battle
	assert_eq(view._cards.size(), 4)
	assert_eq(battle.enemies[1].get_title(), "Foe B", "two of the same get a letter")
	assert_eq(view.mode, BKBattleView.Mode.COMMAND)
	assert_true(view._command_panel.visible)
	assert_true(view._timeline.get_child_count() > 0)


func test_pick_attack_then_a_target() -> void:
	var w := _view([fighter(&"hero", {&"speed": 50})], [fighter(&"foe", {&"max_hp": 500})])
	await wait_frames(2)
	var view: BKBattleView = w.view
	var battle: BKBattle = w.battle
	var attack := BKAction.make(&"strike", "Strike", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 0)
	attack.accuracy = 1.0
	view.choose_action(attack)
	assert_eq(view.mode, BKBattleView.Mode.TARGET)
	var card := view.get_card(battle.enemies[0])
	assert_true(card.is_targetable())
	assert_false(view.get_card(battle.party[0]).is_targetable(), "heroes are not valid targets")
	view.go_back()
	assert_eq(view.mode, BKBattleView.Mode.COMMAND)
	view.choose_action(attack)
	view._on_card_chosen(card)
	assert_true(battle.enemies[0].hp < 500, "the strike landed")
	await wait_frames(3)
	assert_true(view._log.text.contains("hits"), "the log tells what happened")


func test_enemy_turns_play_and_victory_screen_shows() -> void:
	var foe := fighter(&"foe", {&"max_hp": 1, &"speed": 60})
	foe.gold = 5
	var w := _view([fighter(&"hero", {&"speed": 10, &"max_hp": 500})], [foe])
	var battle: BKBattle = w.battle
	var view: BKBattleView = w.view
	await wait_frames(4)
	assert_eq(battle.current, battle.party[0], "the fast enemy already played its turn")
	assert_true(battle.party[0].hp < 500)
	var finished := []
	view.finished.connect(func(outcome: BKBattle.Outcome) -> void: finished.append(outcome))
	var strike := BKAction.make(&"strike", "Strike", BKAction.Kind.DAMAGE, BKAction.Target.ALL_ENEMIES, 0)
	strike.accuracy = 1.0
	view.choose_action(strike)
	await wait_frames(2)
	assert_eq(view.mode, BKBattleView.Mode.ENDED)
	assert_true(view._end_layer.visible)
	var close: Button = view._end_box.get_children().back()
	close.pressed.emit()
	assert_eq(finished, [BKBattle.Outcome.VICTORY])


func test_demo_runs_in_every_art_direction() -> void:
	var demo: Node = add_to_tree(load("res://demo/battle/battle_demo.tscn").instantiate())
	await wait_frames(3)
	demo.view.enemy_delay = 0.0
	for da in demo.available_directions():
		demo.apply_art_direction(da)
		await wait_frames(1)
		assert_eq(demo.view._cards.size(), 6, da)
	var battle: BKBattle = demo.battle
	assert_eq(battle.enemies.size(), 3)
	# Let the AI play both sides to the end of each fight.
	for index in demo.encounters.size():
		if not battle.is_over() and index > 0:
			continue
		if index > 0:
			demo.rest()
			demo.start_encounter(index)
		for i in 400:
			if battle.is_over():
				break
			battle.run_ai_turn()
		assert_true(battle.is_over(), "fight %d ended" % index)
	await wait_frames(2)
	assert_true(demo.bag.container.count(&"gold_coins") >= 50)
	assert_eq(demo.battle.level_curve.validate(), PackedStringArray())
	demo.set_timed_commands(true)
	assert_true(demo.view.timed_commands)
	demo.set_timed_commands(false)


func _sure_hit(element: StringName = &"", target := BKAction.Target.ONE_ENEMY) -> BKAction:
	var action := BKAction.make(&"strike", "Strike", BKAction.Kind.DAMAGE, target, 0)
	action.accuracy = 1.0
	action.can_crit = false
	action.element = element
	return action


func test_timed_attack_and_guard_in_the_view() -> void:
	var brute := fighter(&"brute", {&"max_hp": 500, &"speed": 20})
	brute.basic_attack = _sure_hit()
	var w := _view([fighter(&"hero", {&"speed": 50, &"max_hp": 500})], [brute])
	var view: BKBattleView = w.view
	var battle: BKBattle = w.battle
	view.timed_commands = true
	await wait_frames(2)
	var prompt := view.get_timing_prompt()
	view.choose_action(_sure_hit())
	view._on_card_chosen(view.get_card(battle.enemies[0]))
	assert_eq(view.mode, BKBattleView.Mode.TIMING, "the timing bar comes first")
	assert_true(prompt.visible and prompt.running)
	assert_eq(battle.enemies[0].hp, 500, "nothing happened yet")
	prompt.cursor = (prompt.zone_start + prompt.zone_end) / 2.0
	assert_true(prompt.press())
	assert_eq(battle.enemies[0].hp, 474, "20 damage +30 %")
	# Defend until the brute attacks: the guard bar shows, a miss takes the full damage.
	for i in 10:
		if battle.current == battle.enemies[0]:
			break
		view.choose_action(view.defend_action)
		await wait_frames(1)
	await wait_frames(2)
	assert_eq(view.mode, BKBattleView.Mode.TIMING, "an enemy attack on a hero: guard bar")
	var hp := battle.party[0].hp
	prompt.cursor = 0.05
	assert_false(prompt.press(), "too early")
	assert_true(battle.party[0].hp < hp, "the attack landed")
	var fresh := BKBattleView.new()
	assert_false(fresh.timed_commands, "off by default")
	fresh.free()


func test_weak_tags_shake_lunge_and_level_up_screen() -> void:
	var foe := fighter(&"golem", {&"max_hp": 1, &"speed": 1})
	foe.affinities = {&"ice": 2.0}
	foe.xp = 150
	var battle := make_battle([fighter(&"mage", {&"speed": 50})], [foe], 3, false)
	battle.level_curve = BKLevelCurve.make(100, 1.0, {&"max_hp": 10, &"attack": 2})
	var view := BKBattleView.new()
	view.enemy_delay = 0.0
	view.battle = battle
	view.size = Vector2(1000, 640)
	add_to_tree(view)
	battle.start([fighter(&"mage", {&"speed": 50})], [foe], 3)
	await wait_frames(2)
	view.choose_action(_sure_hit(&"ice"))
	var card := view.get_card(battle.enemies[0])
	card.button.focus_entered.emit()
	assert_true(view._hint.text.contains("20 damage") and view._hint.text.contains("?"), view._hint.text)
	battle.reveal_affinity(BKBattler.PARTY, battle.enemies[0], &"ice")
	card.button.focus_entered.emit()
	assert_true(view._hint.text.contains("40 damage") and view._hint.text.contains("Weak!"), view._hint.text)
	view._on_card_chosen(card)
	await wait_frames(2)
	var tags := view._floats.get_children().map(func(l: Label) -> String: return l.text)
	assert_true(tags.has("Weak!"), str(tags))
	assert_true(view.get_card(battle.party[0]).lunge_offset != Vector2.ZERO, "the mage dashes toward the golem")
	view.shake()
	assert_true(view._shake_left > 0.0)
	await get_tree().create_timer(0.4).timeout
	assert_eq(view._content.position, view._content_origin, "back in place after the shake")
	assert_eq(view.mode, BKBattleView.Mode.ENDED)
	var texts := view._end_box.get_children().filter(func(c: Node) -> bool: return c is Label).map(func(l: Label) -> String: return l.text)
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Mage reaches level 2!")), str(texts))
