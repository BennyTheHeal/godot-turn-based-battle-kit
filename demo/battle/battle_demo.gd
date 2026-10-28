extends IKInventoryUI
## Turn-Based Battle Kit demo: "The Haunted Armory". A knight, a ranger and a mage fight
## cursed objects in three encounters (the last one is a boss you cannot flee). Skills
## with MP, potions from the bag, poison, burn, stun and buffs, fire and ice against
## weaknesses and resistances (the AI learns them too), rewards paid into the bag, hero
## levels from a BKLevelCurve, optional timed hits, and the four art styles.

const ART := "res://addons/inventory_kit/art/"
const DIRECTIONS := {"painted": "Hand-painted", "realistic": "Realistic", "cartoon": "Cartoon", "flat": "Flat"}
const SITE := "https://banc-essai.site-testeurs.workers.dev/?src=battle-demo"
const XP_PER_LEVEL := 100
const FIRE := &"fire"
const ICE := &"ice"

var bag: IKInventory
var battle: BKBattle
var view: BKBattleView
var heroes: Array[BKBattler] = []
var encounters: Array[Dictionary] = []
var statuses: Dictionary = {}
var art_direction := ""
var _picker: OptionButton
var _party_label: RichTextLabel
var _status: Label
var _fight_buttons: Array[Button] = []
var _rest: Button


static func available_directions() -> Array[String]:
	var result: Array[String] = []
	for da in DIRECTIONS:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			result.append(da)
	return result


# --- Content -------------------------------------------------------------------

static func make_statuses() -> Dictionary:
	var poison := BKStatus.make(&"poison", "Poison", 4, true, &"herb")
	poison.damage_per_turn = 5
	poison.max_stacks = 3
	poison.color = Color(0.55, 0.95, 0.35)
	var burn := BKStatus.make(&"burn", "Burn", 3, true, &"coal")
	burn.damage_percent_per_turn = 0.06
	burn.color = Color(1.0, 0.55, 0.25)
	var bleed := BKStatus.make(&"bleed", "Bleed", 3, true, &"rawhide")
	bleed.damage_per_turn = 4
	bleed.max_stacks = 3
	var stun := BKStatus.make(&"stun", "Stun", 1, true, &"stone")
	stun.skips_turn = true
	stun.color = Color(1.0, 0.9, 0.4)
	var rust := BKStatus.make(&"rust", "Rust", 3, true, &"iron_nugget")
	rust.stat_percent = {&"defense": -0.3}
	var weaken := BKStatus.make(&"weaken", "Weaken", 3, true, &"bone")
	weaken.stat_percent = {&"attack": -0.25, &"magic": -0.25}
	var guard := BKStatus.make(&"guard", "Guard", 3, false, &"shield")
	guard.stat_percent = {&"defense": 0.6, &"resistance": 0.3}
	var haste := BKStatus.make(&"haste", "Haste", 3, false, &"feather")
	haste.stat_percent = {&"speed": 0.4}
	var valor := BKStatus.make(&"valor", "Valor", 3, false, &"ring")
	valor.stat_percent = {&"attack": 0.25}
	var regen := BKStatus.make(&"regen", "Regen", 3, false, &"apple")
	regen.damage_percent_per_turn = -0.08
	return {"poison": poison, "burn": burn, "bleed": bleed, "stun": stun, "rust": rust, "weaken": weaken,
		"guard": guard, "haste": haste, "valor": valor, "regen": regen}


static func _act(id: StringName, title: String, description: String, kind: BKAction.Kind, target: BKAction.Target,
		power: float, mp_cost: int, icon_item: StringName, with_statuses: Array = [], chance: float = 1.0) -> BKAction:
	var action := BKAction.make(id, title, kind, target, power, mp_cost, icon_item)
	action.description = description
	for status: BKStatus in with_statuses:
		action.statuses.append(status)
	action.status_chance = chance
	return action


static func make_heroes(s: Dictionary) -> Array[BKBattlerData]:
	var knight := BKBattlerData.make(&"knight", "Knight", {&"max_hp": 120, &"max_mp": 20, &"attack": 16, &"defense": 14,
		&"magic": 4, &"resistance": 6, &"speed": 9, &"crit_chance": 0.05, &"evasion": 0.03}, &"sword")
	knight.affinities = {ICE: BKBattlerData.RESIST}
	var bash := _act(&"shield_bash", "Shield Bash", "Hits one enemy, 35% chance to stun it.", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 6, 4, &"shield", [s.stun], 0.35)
	knight.actions.append(bash)
	knight.actions.append(_act(&"guard_up", "Guard Up", "+60% defense for 3 turns.", BKAction.Kind.SUPPORT, BKAction.Target.SELF, 0, 3, &"iron_helmet", [s.guard]))
	knight.actions.append(_act(&"rally", "Rally", "Every ally gets +25% attack for 3 turns.", BKAction.Kind.SUPPORT, BKAction.Target.ALL_ALLIES, 0, 8, &"gold_helmet", [s.valor]))
	var ranger := BKBattlerData.make(&"ranger", "Ranger", {&"max_hp": 85, &"max_mp": 30, &"attack": 14, &"defense": 8,
		&"magic": 6, &"resistance": 8, &"speed": 14, &"crit_chance": 0.15, &"evasion": 0.1}, &"bow")
	ranger.affinities = {FIRE: 1.5}
	ranger.actions.append(_act(&"poison_arrow", "Poison Arrow", "Hits one enemy and poisons it (stacks 3 times).", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 4, 4, &"arrows", [s.poison]))
	var twin := _act(&"twin_shot", "Twin Shot", "Two quick arrows at one enemy.", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 1, 5, &"spear")
	twin.hits = 2
	ranger.actions.append(twin)
	ranger.actions.append(_act(&"volley", "Volley", "Hits every enemy.", BKAction.Kind.DAMAGE, BKAction.Target.ALL_ENEMIES, 2, 7, &"pine_planks"))
	ranger.actions.append(_act(&"haste", "Haste", "+40% speed for one ally: more turns.", BKAction.Kind.SUPPORT, BKAction.Target.ONE_ALLY, 0, 5, &"stamina_potion", [s.haste]))
	var mage := BKBattlerData.make(&"mage", "Mage", {&"max_hp": 70, &"max_mp": 50, &"attack": 6, &"defense": 5,
		&"magic": 18, &"resistance": 14, &"speed": 11, &"crit_chance": 0.05, &"evasion": 0.05}, &"staff")
	mage.affinities = {FIRE: BKBattlerData.RESIST}
	var fireball := _act(&"fireball", "Fireball", "Fire damage to one enemy, 50% chance to burn.", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 12, 5, &"ruby", [s.burn], 0.5)
	fireball.scaling = BKAction.Scaling.MAGIC
	fireball.element = FIRE
	mage.actions.append(fireball)
	var frost := _act(&"frost_lance", "Frost Lance", "Ice damage to one enemy. Golems and the Dragon Helm hate it.", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 10, 5, &"sapphire")
	frost.scaling = BKAction.Scaling.MAGIC
	frost.element = ICE
	mage.actions.append(frost)
	var wave := _act(&"flame_wave", "Flame Wave", "Fire damage to every enemy, 25% chance to burn.", BKAction.Kind.DAMAGE, BKAction.Target.ALL_ENEMIES, 6, 10, &"topaz", [s.burn], 0.25)
	wave.scaling = BKAction.Scaling.MAGIC
	wave.element = FIRE
	mage.actions.append(wave)
	mage.actions.append(_act(&"mend", "Mend", "Heals one ally and gives Regen.", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 20, 4, &"emerald", [s.regen]))
	mage.actions.append(_act(&"raise", "Raise", "Brings a fallen ally back with half their HP.", BKAction.Kind.REVIVE, BKAction.Target.ONE_FALLEN_ALLY, 50, 12, &"amulet"))
	return [knight, ranger, mage]


static func make_item_actions(s: Dictionary) -> Array[BKAction]:
	var potion := BKAction.make_item(&"health_potion", "Health Potion", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 45)
	potion.description = "Restores 45 HP."
	var ether := BKAction.make_item(&"mana_potion", "Mana Potion", BKAction.Kind.RESTORE_MP, BKAction.Target.ONE_ALLY, 20)
	ether.description = "Restores 20 MP."
	var antidote := BKAction.make_item(&"antidote", "Antidote", BKAction.Kind.SUPPORT, BKAction.Target.ONE_ALLY)
	antidote.description = "Cures poison, burn and bleeding."
	antidote.cures.assign([&"poison", &"burn", &"bleed"])
	var tonic := BKAction.make_item(&"stamina_potion", "Stamina Potion", BKAction.Kind.SUPPORT, BKAction.Target.ONE_ALLY)
	tonic.description = "Haste for 3 turns."
	tonic.statuses.append(s.haste)
	var feast := BKAction.make_item(&"roast_meat", "Roast Meat", BKAction.Kind.HEAL, BKAction.Target.ALL_ALLIES, 25)
	feast.description = "Shared with the party: 25 HP each."
	return [potion, ether, antidote, tonic, feast]


static func _enemy(id: StringName, title: String, stats: Dictionary, icon_item: StringName, p_xp: int, p_gold: int) -> BKBattlerData:
	var data := BKBattlerData.make(id, title, stats, icon_item)
	data.xp = p_xp
	data.gold = p_gold
	return data


static func make_encounters(s: Dictionary) -> Array[Dictionary]:
	var armor := _enemy(&"haunted_armor", "Haunted Armor", {&"max_hp": 70, &"attack": 14, &"defense": 16, &"resistance": 4, &"speed": 7}, &"iron_chest", 20, 15)
	armor.actions.append(_act(&"rusty_grip", "Rusty Grip", "", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 2, 0, &"iron_gloves", [s.rust], 0.6))
	armor.immunities.assign([&"poison", &"bleed"])
	armor.affinities = {FIRE: BKBattlerData.WEAK}
	armor.drops.assign([BKDrop.make(&"iron_ingot", 0.5, 1, 2), BKDrop.make(&"health_potion", 0.25)])
	var blade := _enemy(&"restless_blade", "Restless Blade", {&"max_hp": 40, &"attack": 15, &"defense": 6, &"speed": 15, &"crit_chance": 0.2, &"evasion": 0.15}, &"dagger", 12, 8)
	blade.actions.append(_act(&"bleeding_cut", "Bleeding Cut", "", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 2, 0, &"dagger", [s.bleed], 0.5))
	blade.immunities.assign([&"poison", &"bleed"])
	blade.affinities = {ICE: BKBattlerData.WEAK}
	blade.drops.assign([BKDrop.make(&"iron_nugget", 0.6, 1, 3), BKDrop.make(&"steel_ingot", 0.1)])
	var golem := _enemy(&"ember_golem", "Ember Golem", {&"max_hp": 110, &"attack": 18, &"defense": 12, &"resistance": 8, &"speed": 6}, &"obsidian", 35, 25)
	var punch := _act(&"ember_punch", "Ember Punch", "", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 5, 0, &"coal", [s.burn], 0.5)
	punch.element = FIRE
	golem.actions.append(punch)
	golem.affinities = {FIRE: BKBattlerData.ABSORB, ICE: BKBattlerData.WEAK}
	var roar := _act(&"molten_roar", "Molten Roar", "", BKAction.Kind.SUPPORT, BKAction.Target.ALL_ENEMIES, 0, 0, &"obsidian", [s.weaken])
	roar.accuracy = 0.8
	roar.ai_weight = 0.5
	golem.actions.append(roar)
	golem.immunities.assign([&"burn", &"poison", &"bleed"])
	golem.drops.assign([BKDrop.make(&"coal", 1.0, 2, 4), BKDrop.make(&"obsidian", 0.3)])
	var ore := _enemy(&"living_ore", "Living Ore", {&"max_hp": 45, &"attack": 11, &"defense": 18, &"resistance": 6, &"speed": 8}, &"iron_ore", 10, 6)
	ore.actions.append(_act(&"rock_throw", "Rock Throw", "", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 3, 0, &"stone"))
	ore.actions.append(_act(&"harden", "Harden", "", BKAction.Kind.SUPPORT, BKAction.Target.SELF, 0, 0, &"iron_ore", [s.guard]))
	ore.immunities.assign([&"poison", &"bleed"])
	ore.affinities = {FIRE: BKBattlerData.RESIST}
	ore.drops.assign([BKDrop.make(&"iron_ore", 0.8, 1, 2), BKDrop.make(&"gold_nugget", 0.15)])
	var wisp := _enemy(&"wisp", "Wisp", {&"max_hp": 35, &"max_mp": 40, &"attack": 4, &"magic": 12, &"resistance": 12, &"speed": 13, &"evasion": 0.2}, &"magic_essence", 14, 10)
	var spark := _act(&"spark", "Spark", "", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 6, 0, &"magic_essence")
	spark.scaling = BKAction.Scaling.MAGIC
	wisp.basic_attack = spark
	wisp.affinities = {ICE: BKBattlerData.WEAK, FIRE: BKBattlerData.IMMUNE}
	wisp.actions.append(_act(&"wisp_mend", "Mend", "", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 18, 6, &"emerald"))
	wisp.drops.assign([BKDrop.make(&"magic_essence", 0.7), BKDrop.make(&"mana_potion", 0.2)])
	var helm := _enemy(&"dragon_helm", "The Dragon Helm", {&"max_hp": 260, &"max_mp": 99, &"attack": 20, &"defense": 16, &"magic": 16,
		&"resistance": 14, &"speed": 10, &"crit_chance": 0.1}, &"dragon_helmet", 120, 80)
	var breath := _act(&"dragon_breath", "Dragon Breath", "", BKAction.Kind.DAMAGE, BKAction.Target.ALL_ENEMIES, 8, 10, &"ruby", [s.burn], 0.4)
	breath.scaling = BKAction.Scaling.MAGIC
	breath.element = FIRE
	breath.ai_weight = 1.2
	helm.actions.append(breath)
	helm.actions.append(_act(&"horn_crush", "Horn Crush", "", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 10, 0, &"dragon_helmet", [s.stun], 0.3))
	var war_cry := _act(&"war_cry", "War Cry", "", BKAction.Kind.SUPPORT, BKAction.Target.SELF, 0, 0, &"dragon_chest", [s.valor])
	war_cry.ai_weight = 0.4
	helm.actions.append(war_cry)
	helm.immunities.assign([&"stun", &"poison", &"bleed"])
	helm.affinities = {FIRE: BKBattlerData.RESIST, ICE: 1.5}
	helm.drops.assign([BKDrop.make(&"dragon_helmet", 0.35), BKDrop.make(&"ruby", 1.0, 1, 2), BKDrop.make(&"health_potion", 1.0, 2, 2)])
	return [
		{"title": "Rusty Patrol", "enemies": [armor, blade, blade], "flee": true},
		{"title": "Ember Forge", "enemies": [ore, golem, ore], "flee": true},
		{"title": "The Dragon Helm (boss)", "enemies": [wisp, helm, wisp], "flee": false},
	]


# --- Demo --------------------------------------------------------------------

func _ready() -> void:
	var directions := available_directions()
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [directions[0], directions[0]])
	bag = IKInventory.new()
	bag.name = "Bag"
	bag.container_id = &"bag"
	bag.size = 10
	bag.database = database
	bag.initial_items.assign({&"health_potion": 4, &"mana_potion": 2, &"antidote": 2, &"stamina_potion": 1, &"roast_meat": 1, &"gold_coins": 50})
	add_child(bag)
	statuses = make_statuses()
	for data in make_heroes(statuses):
		heroes.append(BKBattler.from_data(data))
	encounters = make_encounters(statuses)
	battle = BKBattle.new()
	battle.name = "Battle"
	battle.item_actions = make_item_actions(statuses)
	# Each surviving hero gets the XP of a victory: +10 max HP, +2 attack, +2 magic, +1 defense
	# per level. Equipment or a Skill Tree Kit would go in hero.bonuses, on top of this.
	battle.level_curve = BKLevelCurve.make(XP_PER_LEVEL, 1.0, {&"max_hp": 10, &"attack": 2, &"magic": 2, &"defense": 1})
	for hero in heroes:
		hero.curve = battle.level_curve  # so the party panel can show the XP to the next level
	add_child(battle)
	_build_layout(directions)
	super._ready()
	battle.bag = bag.container
	view.battle = battle
	view.finished.connect(_on_finished)
	battle.battle_ended.connect(_on_battle_ended)
	battle.level_up.connect(func(hero: BKBattler, _from: int, to: int, _gains: Dictionary) -> void:
		_set_status("Level up! %s reaches level %d." % [hero.get_title(), to]))
	view.refused.connect(func(_r: BKResult, text: String) -> void: _set_status(text, true))
	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))
	apply_art_direction(directions[0])
	_refresh_party()
	start_encounter(0)


func apply_art_direction(da: String) -> void:
	art_direction = da
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [da, da])
	bag.container.database = database
	cursor.container.database = database
	theme = load(ART + "%s/%s_theme.tres" % [da, da])
	skin = load(ART + "%s/%s_skin.tres" % [da, da])
	view.database = database
	view.skin = skin
	var index := available_directions().find(da)
	if _picker != null and index >= 0 and _picker.selected != index:
		_picker.select(index)


func start_encounter(index: int) -> void:
	var encounter: Dictionary = encounters[index]
	battle.can_flee = encounter.flee
	for hero in heroes:
		if not hero.is_alive():
			hero.hp = 1
	battle.start(heroes, encounter.enemies)
	_set_status("%s: %s" % [encounter.title, "fight!" if encounter.flee else "no escape from this one."])
	_set_fights_enabled(false)


func rest() -> void:
	for hero in heroes:
		hero.restore()
	_refresh_party()
	_set_status("The party rests at the camp: HP and MP restored.")


func _on_battle_ended(_outcome: BKBattle.Outcome, _rewards: Dictionary) -> void:
	_refresh_party()


## Timed hits: press at the right moment to hit harder, or to guard against an enemy.
func set_timed_commands(enabled: bool) -> void:
	view.timed_commands = enabled
	_set_status("Timed hits on: press Enter, Space or A when the cursor is in the bright zone." if enabled else "Timed hits off.")


func _on_finished(outcome: BKBattle.Outcome) -> void:
	_set_fights_enabled(true)
	if outcome == BKBattle.Outcome.DEFEAT:
		rest()
		_set_status("Defeated... The party wakes up at the camp. Try another fight or use more potions.", true)
	elif outcome == BKBattle.Outcome.VICTORY:
		_set_status("Victory! Pick the next fight, or rest first.")
	else:
		_set_status("You got away. Pick a fight.")


func _refresh_party() -> void:
	if _party_label == null:
		return
	var lines := PackedStringArray()
	for hero in heroes:
		lines.append("[b]%s[/b] level %d  [color=#aab1bf]%d XP to the next[/color]" % [hero.get_title(), hero.level, hero.get_xp_to_next()])
	lines.append("[color=#aab1bf]Fire and ice: find the weaknesses. Choose a fight:[/color]")
	_party_label.text = "\n".join(lines)


func _set_fights_enabled(enabled: bool) -> void:
	for button in _fight_buttons:
		button.disabled = not enabled
	if _rest != null:
		_rest.disabled = not enabled


func _build_layout(directions: Array[String]) -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	column.add_child(header)
	var title := Label.new()
	title.text = "Turn-Based Battle Kit — The Haunted Armory"
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)
	_picker = OptionButton.new()
	for da in directions:
		_picker.add_item(DIRECTIONS[da])
	_picker.item_selected.connect(func(index: int) -> void: apply_art_direction(directions[index]))
	_picker.focus_mode = FOCUS_NONE
	header.add_child(_picker)
	var timed := CheckButton.new()
	timed.text = "Timed hits"
	timed.tooltip_text = "Press at the right moment: more damage when you attack, less when you guard."
	timed.focus_mode = FOCUS_NONE
	timed.toggled.connect(set_timed_commands)
	header.add_child(timed)
	var site := LinkButton.new()
	site.text = "More kits & our games »"
	site.uri = SITE
	site.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(site)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	_party_label = RichTextLabel.new()
	_party_label.bbcode_enabled = true
	_party_label.fit_content = true
	_party_label.scroll_active = false
	_party_label.custom_minimum_size = Vector2(260, 0)
	left.add_child(_party_label)
	for i in encounters.size():
		var button := Button.new()
		button.text = encounters[i].title
		button.focus_mode = FOCUS_NONE
		button.pressed.connect(start_encounter.bind(i))
		left.add_child(button)
		_fight_buttons.append(button)
	_rest = Button.new()
	_rest.text = "Rest (full HP and MP)"
	_rest.focus_mode = FOCUS_NONE
	_rest.pressed.connect(rest)
	left.add_child(_rest)
	var bag_frame := PanelContainer.new()
	left.add_child(bag_frame)
	var bag_box := VBoxContainer.new()
	bag_frame.add_child(bag_box)
	var bag_label := Label.new()
	bag_label.text = "Bag (potions for battle, rewards land here)"
	bag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bag_label.custom_minimum_size = Vector2(260, 0)
	bag_box.add_child(bag_label)
	var bag_view := IKContainerView.new()
	bag_view.name = "BagView"
	bag_view.columns = 5
	bag_view.inventory = bag
	bag_box.add_child(bag_view)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(260, 0)
	left.add_child(_status)

	view = BKBattleView.new()
	view.name = "BattleView"
	view.size_flags_horizontal = SIZE_EXPAND_FILL
	view.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(view)


func _set_status(text: String, warning: bool = false) -> void:
	if _status == null:
		return
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
