class_name BKBattleView
extends PanelContainer
## A ready-to-use battle screen for a [BKBattle]: turn order, enemy and party cards, a
## battle log, floating numbers, the command menu (Attack, Skills, Items, Defend, Flee),
## target picking and the victory screen with the rewards. Mouse, keyboard and gamepad:
## arrows / d-pad move, Enter / A confirms, Escape / B goes back. Enemy turns play by
## themselves after [member enemy_delay]. Styled by an Inventory Kit [IKSkin] and your Theme.
## Attackers dash toward their target, critical hits shake the screen, numbers pop, and
## elemental hits say "Weak!" or "Resist". Optional timed commands ([member timed_commands]):
## press at the right moment to hit harder or to guard.

## The player closed the end screen.
signal finished(outcome: BKBattle.Outcome)
signal refused(result: BKResult, text: String)

enum Mode { IDLE, COMMAND, LIST, TARGET, ENDED, TIMING }

@export var battle: BKBattle:
	set(value):
		_disconnect_battle()
		battle = value
		_connect_battle()
@export var skin: IKSkin:
	set(value):
		skin = value
		if is_inside_tree():
			_rebuild_cards()
## Item icons for battlers, actions and statuses. Empty = the bag's database.
@export var database: IKItemDatabase
## Seconds before an enemy acts, so the player can follow. 0 = at once (next frame).
@export_range(0.0, 3.0, 0.05) var enemy_delay := 0.8
## Log lines kept on screen.
@export_range(1, 30) var log_lines := 9
## Portrait sizes in pixels: bigger for a full-screen battle.
@export var enemy_portrait := 80.0
@export var party_portrait := 52.0
## While picking a target, the hint shows the expected damage (and the affinity, once known).
@export var show_damage_preview := true
@export_group("Timed commands")
## Off by default. On: a hero's attack shows a timing bar (press at the right moment for
## [member BKBattle.timed_attack_bonus] more damage) and an enemy attack on a hero shows a
## guard bar ([member BKBattle.timed_guard_reduction] less damage). Enter / Space / gamepad A, or click.
@export var timed_commands := false
## Seconds the timing cursor takes to cross the bar.
@export_range(0.2, 5.0, 0.05) var timing_duration := 1.1
@export_group("Feel")
## Pixels an attacker dashes toward its target. 0 = no dash.
@export_range(0.0, 80.0, 1.0) var lunge_distance := 18.0
## Screen shake on critical hits, in pixels. 0 = no shake.
@export_range(0.0, 30.0, 0.5) var shake_strength := 6.0
## Damage numbers pop and bounce. Off = numbers that only rise and fade.
@export var bouncy_numbers := true

var mode: Mode = Mode.IDLE
var defend_action := BKAction.make(&"defend", "Defend", BKAction.Kind.DEFEND, BKAction.Target.SELF)
var flee_action := BKAction.make(&"flee", "Flee", BKAction.Kind.FLEE, BKAction.Target.SELF)
var _cards: Dictionary = {}  # BKBattler -> BKBattlerCard
var _timeline := HBoxContainer.new()
var _enemy_row := HBoxContainer.new()
var _party_row := HBoxContainer.new()
var _log := RichTextLabel.new()
var _commands := VBoxContainer.new()
var _command_panel := PanelContainer.new()
var _command_title := Label.new()
var _hint := Label.new()
var _floats := Control.new()
var _end_layer := CenterContainer.new()
var _end_box := VBoxContainer.new()
var _lines: PackedStringArray = []
var _pending: BKAction
var _list_kind := ""
var _turn_serial := 0
var _fallback_skin: IKSkin
var _timing := BKTimingPrompt.new()
var _timing_callback: Callable
var _content: Control
var _content_origin := Vector2.ZERO
var _shake_left := 0.0
var _shake_total := 0.25
var _shake_power := 0.0


func _init() -> void:
	_build()


func _ready() -> void:
	if battle != null and not battle.get_all().is_empty():
		_rebuild_cards()
		if battle.current != null:
			_on_turn_started(battle.current)


func get_card(battler: BKBattler) -> BKBattlerCard:
	return _cards.get(battler)


## The timing bar of [member timed_commands].
func get_timing_prompt() -> BKTimingPrompt:
	return _timing


## Shakes the battle screen (critical hits do it for you).
func shake(strength: float = -1.0, time: float = 0.25) -> void:
	var power := shake_strength if strength < 0.0 else strength
	if power <= 0.0 or _content == null:
		return
	if _shake_left <= 0.0:
		_content_origin = _content.position
	_shake_left = time
	_shake_total = time
	_shake_power = power


func _process(delta: float) -> void:
	if _shake_left <= 0.0 or _content == null:
		return
	_shake_left -= delta
	if _shake_left <= 0.0:
		_content.position = _content_origin
		return
	var fade := _shake_left / _shake_total
	_content.position = _content_origin + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_power * fade


## Starts picking targets for [param action] (or performs it at once if it needs none).
func choose_action(action: BKAction) -> void:
	if battle == null or battle.current == null:
		return
	var check := battle.can_perform(action, [])
	if not check.ok and check.code != BKResult.Code.INVALID_TARGET:
		_refuse(check)
		return
	if not action.targets_one():
		_perform(action, [])
		return
	_pending = action
	mode = Mode.TARGET
	var valid := battle.get_valid_targets(battle.current, action)
	for battler: BKBattler in _cards:
		_cards[battler].set_targetable(valid.has(battler))
	_hint.text = BKText.t("Choose a target for %s (Escape to go back).") % action.get_title()
	_hint.visible = true
	_show_list([])
	if not valid.is_empty():
		var first: BKBattlerCard = _cards[valid[0]]
		_focus_later(first.button)


## Leaves target picking or a sub-list, back to the main commands.
func go_back() -> void:
	if mode == Mode.TARGET or mode == Mode.LIST:
		_clear_targets()
		_show_commands()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel") and (mode == Mode.TARGET or mode == Mode.LIST):
		go_back()
		get_viewport().set_input_as_handled()


# --- Battle signals ----------------------------------------------------------

func _connect_battle() -> void:
	if battle == null:
		return
	battle.battle_started.connect(_on_battle_started)
	battle.turn_started.connect(_on_turn_started)
	battle.turn_events.connect(_on_turn_events)
	battle.action_resolved.connect(_on_action_resolved)
	battle.battle_ended.connect(_on_battle_ended)


func _disconnect_battle() -> void:
	if battle == null:
		return
	for pair in [[battle.battle_started, _on_battle_started], [battle.turn_started, _on_turn_started],
			[battle.turn_events, _on_turn_events], [battle.action_resolved, _on_action_resolved],
			[battle.battle_ended, _on_battle_ended]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _on_battle_started() -> void:
	for child in _floats.get_children():
		child.queue_free()
	_lines.clear()
	_log.text = ""
	_end_layer.visible = false
	_timing.cancel()
	mode = Mode.IDLE
	_rebuild_cards()


func _on_turn_started(actor: BKBattler) -> void:
	_turn_serial += 1
	_refresh_all()
	for battler: BKBattler in _cards:
		_cards[battler].set_active(battler == actor)
	if actor.side == BKBattler.PARTY:
		_show_commands()
	else:
		mode = Mode.IDLE
		_command_panel.visible = false
		_hint.text = BKText.t("%s is acting...") % actor.get_title()
		_hint.visible = true
		var serial := _turn_serial
		if enemy_delay <= 0.0 or not is_inside_tree():
			_run_enemy.call_deferred(serial)
		else:
			get_tree().create_timer(enemy_delay).timeout.connect(_run_enemy.bind(serial))


func _on_turn_events(_actor: BKBattler, events: Array[Dictionary]) -> void:
	_show_events(events)


func _on_action_resolved(actor: BKBattler, action: BKAction, events: Array[Dictionary]) -> void:
	if action != null and action.kind == BKAction.Kind.DAMAGE:
		for event in events:
			if event.type in ["damage", "miss", "absorb"] and event.get("target") != actor:
				_lunge(actor, event.target)
				break
	_show_events(events)


func _on_battle_ended(outcome: BKBattle.Outcome, rewards: Dictionary) -> void:
	mode = Mode.ENDED
	_timing.cancel()
	_command_panel.visible = false
	_hint.visible = false
	_refresh_all()
	for battler: BKBattler in _cards:
		_cards[battler].set_active(false)
		_cards[battler].set_targetable(false)
	for child in _end_box.get_children():
		_end_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.add_theme_font_size_override(&"font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match outcome:
		BKBattle.Outcome.VICTORY:
			title.text = BKText.t("Victory!")
			title.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
		BKBattle.Outcome.DEFEAT:
			title.text = BKText.t("Defeat...")
			title.add_theme_color_override(&"font_color", Color(1.0, 0.45, 0.4))
		_:
			title.text = BKText.t("You got away!")
	_end_box.add_child(title)
	if outcome == BKBattle.Outcome.VICTORY:
		var xp := Label.new()
		xp.text = BKText.t("+%d XP") % int(rewards.get("xp", 0))
		xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_end_box.add_child(xp)
		for info: Dictionary in rewards.get("level_ups", []):
			var up := Label.new()
			up.text = BKText.level_up_line(info)
			up.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
			up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			up.custom_minimum_size = Vector2(340, 0)
			_end_box.add_child(up)
		_end_box.add_child(_reward_grid(rewards.get("items", {})))
		var left: Dictionary = rewards.get("left_behind", {})
		if not left.is_empty():
			var full := Label.new()
			full.text = BKText.t("Your bag is full, left behind:")
			full.add_theme_color_override(&"font_color", Color(1.0, 0.6, 0.5))
			full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_end_box.add_child(full)
			_end_box.add_child(_reward_grid(left))
	var close := Button.new()
	close.text = BKText.t("Continue")
	close.pressed.connect(func() -> void:
		_end_layer.visible = false
		finished.emit(outcome))
	_end_box.add_child(close)
	_end_layer.visible = true
	_focus_later.call_deferred(close)


# --- Commands ----------------------------------------------------------------

func _show_commands() -> void:
	mode = Mode.COMMAND
	_pending = null
	_hint.visible = false
	var actor := battle.current
	if actor == null:
		return
	_command_title.text = BKText.t("%s's turn") % actor.get_title()
	var entries: Array = [
		[BKText.t("Attack"), func() -> void: choose_action(actor.get_attack()), true, ""],
		[BKText.t("Skills"), func() -> void: _open_list("skills"), not actor.data.actions.is_empty(), ""],
		[BKText.t("Items"), func() -> void: _open_list("items"), not battle.get_item_actions().is_empty(), ""],
		[BKText.t("Defend"), func() -> void: choose_action(defend_action), true, BKText.t("Halves the damage taken until your next turn.")],
	]
	if battle.can_flee:
		entries.append([BKText.t("Flee"), func() -> void: choose_action(flee_action), true, ""])
	_fill(entries)


func _open_list(kind: String) -> void:
	mode = Mode.LIST
	_list_kind = kind
	var actor := battle.current
	var actions: Array[BKAction] = actor.data.actions if kind == "skills" else battle.get_item_actions()
	var entries: Array = []
	for action in actions:
		var label := action.get_title()
		if action.mp_cost > 0:
			label += "   %d MP" % action.mp_cost
		if action.is_item():
			label += "   x%d" % battle.bag.count(action.item_id)
		var picked := action
		entries.append([label, func() -> void: choose_action(picked), actor.can_pay(action), action.description, action.get_icon(_database())])
	entries.append([BKText.t("Back"), go_back, true, ""])
	_show_list(entries)


func _fill(entries: Array) -> void:
	_command_panel.visible = true
	_show_list(entries)


func _show_list(entries: Array) -> void:
	for child in _commands.get_children():
		if child != _command_title:
			_commands.remove_child(child)
			child.queue_free()
	if entries.is_empty():
		return
	var first: Button = null
	for entry: Array in entries:
		var button := Button.new()
		button.text = entry[0]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not entry[2]
		button.tooltip_text = BKText.t(entry[3]) if not String(entry[3]).is_empty() else ""
		if entry.size() > 4 and entry[4] != null:
			button.icon = entry[4]
			button.expand_icon = true
			button.add_theme_constant_override(&"icon_max_width", 24)
		button.pressed.connect(entry[1])
		_commands.add_child(button)
		if first == null and not button.disabled:
			first = button
	if first != null:
		_focus_later.call_deferred(first)


func _perform(action: BKAction, targets: Array[BKBattler]) -> void:
	_clear_targets()
	var actor := battle.current
	if timed_commands and action.kind == BKAction.Kind.DAMAGE and actor != null and actor.side == BKBattler.PARTY:
		var check := battle.can_perform(action, targets)
		if not check.ok:
			_refuse(check)
			_show_commands()
			return
		_command_panel.visible = false
		var serial := _turn_serial
		_start_timing(BKText.t("Attack! Press at the right moment."), func(success: bool) -> void:
			if serial == _turn_serial:
				_do_perform(action, targets, success))
		return
	_do_perform(action, targets, false)


func _do_perform(action: BKAction, targets: Array[BKBattler], timed: bool) -> void:
	var result := battle.perform(action, targets, timed)
	if not result.ok:
		_refuse(result)
		_show_commands()


func _start_timing(text: String, callback: Callable) -> void:
	mode = Mode.TIMING
	_hint.visible = false
	_timing_callback = callback
	_timing.duration = timing_duration
	_timing.start(text)


func _on_timing_finished(success: bool) -> void:
	var callback := _timing_callback
	_timing_callback = Callable()
	if callback.is_valid():
		callback.call(success)


func _on_card_chosen(card: BKBattlerCard) -> void:
	if mode != Mode.TARGET or _pending == null or not card.is_targetable():
		return
	var targets: Array[BKBattler] = [card.battler]
	_perform(_pending, targets)


func _run_enemy(serial: int) -> void:
	if serial != _turn_serial or battle == null or battle.is_over():
		return
	if battle.current == null or battle.current.side != BKBattler.ENEMIES:
		return
	if not timed_commands:
		battle.run_ai_turn()
		return
	# Same choice as run_ai_turn(), but the player may guard before it lands.
	var choice := battle.choose_ai_action(battle.current)
	var action: BKAction = choice.action
	var targets: Array[BKBattler] = []
	targets.assign(choice.targets)
	var hits_heroes := action.kind == BKAction.Kind.DAMAGE and (action.target == BKAction.Target.ALL_ENEMIES or targets.any(func(b: BKBattler) -> bool: return b.side == BKBattler.PARTY))
	if not hits_heroes:
		battle.perform(action, targets)
		return
	_start_timing(BKText.t("%s attacks! Press at the right moment to guard.") % battle.current.get_title(), func(success: bool) -> void:
		if serial == _turn_serial and not battle.is_over():
			battle.perform(action, targets, success))


func _refuse(result: BKResult) -> void:
	var text := BKText.result_message(result)
	_add_line("[color=#ff9a8a]%s[/color]" % text)
	refused.emit(result, text)


func _clear_targets() -> void:
	_pending = null
	_hint.visible = false
	for battler: BKBattler in _cards:
		_cards[battler].set_targetable(false)


# --- Display -----------------------------------------------------------------

func _show_events(events: Array[Dictionary]) -> void:
	for event in events:
		var line := BKText.describe(event)
		if not line.is_empty():
			_add_line(line)
		var target: BKBattler = event.get("target")
		var card := get_card(target) if target != null else null
		if card == null:
			continue
		match String(event.type):
			"damage", "tick":
				var amount: int = event.amount
				var critical: bool = event.get("critical", false)
				if amount >= 0:
					_float(card, ("%d!" if critical else "%d") % amount, Color(1.0, 0.85, 0.35) if critical else Color(1, 1, 1), critical)
					if amount > 0:
						card.flash(Color(1.0, 0.35, 0.3))
					if critical:
						shake()
				else:
					_float(card, "+%d" % -amount, Color(0.5, 1.0, 0.55))
				var tag := BKText.affinity_tag(event.get("affinity", BKBattler.Affinity.NORMAL))
				if not tag.is_empty():
					_float(card, tag, _affinity_color(event.affinity))
				if event.get("timed", false):
					_float(card, BKText.t("Timed!"), Color(0.6, 0.9, 1.0))
			"absorb":
				_float(card, "+%d" % int(event.amount), Color(0.5, 1.0, 0.55))
				_float(card, BKText.affinity_tag(BKBattler.Affinity.ABSORB), _affinity_color(BKBattler.Affinity.ABSORB))
				card.flash(Color(0.6, 1.0, 0.6))
			"heal", "revived":
				_float(card, "+%d" % int(event.amount), Color(0.5, 1.0, 0.55))
				card.flash(Color(0.6, 1.0, 0.6))
			"mp":
				_float(card, "+%d MP" % int(event.amount), Color(0.55, 0.75, 1.0))
			"miss":
				_float(card, BKText.t("Miss"), Color(0.8, 0.8, 0.8))
			"status":
				var status: BKStatus = event.status
				_float(card, status.get_title(), status.color)
			"immune":
				_float(card, BKText.t("Immune"), Color(0.8, 0.8, 0.8))
	_refresh_all()


func _float(card: BKBattlerCard, text: String, color: Color, big: bool = false) -> void:
	# Next frame: cards made this frame (start of a battle) are not laid out yet.
	_spawn_float.call_deferred(card, text, color, big)


func _affinity_color(affinity: BKBattler.Affinity) -> Color:
	match affinity:
		BKBattler.Affinity.WEAK:
			return Color(1.0, 0.6, 0.2)
		BKBattler.Affinity.RESIST:
			return Color(0.65, 0.75, 0.95)
		BKBattler.Affinity.ABSORB:
			return Color(0.5, 1.0, 0.7)
	return Color(0.8, 0.8, 0.8)


func _lunge(actor: BKBattler, target: BKBattler) -> void:
	var from := get_card(actor)
	var to := get_card(target)
	if from == null or to == null or lunge_distance <= 0.0 or not from.is_inside_tree():
		return
	var direction := to.get_center() - from.get_center()
	if direction.length() < 1.0:
		direction = Vector2.UP if actor.side == BKBattler.PARTY else Vector2.DOWN
	from.lunge(direction.normalized(), lunge_distance)


func _spawn_float(card: BKBattlerCard, text: String, color: Color, big: bool = false) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 28 if big else 22)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	_floats.add_child(label)
	# Several numbers on the same card at once stack up instead of overlapping.
	var stacked := 0
	for other in _floats.get_children():
		if other != label and other.get_meta(&"card", null) == card:
			stacked += 1
	label.set_meta(&"card", card)
	label.position = card.get_float_origin() - _floats.global_position - Vector2(label.get_minimum_size().x / 2.0, 22.0 * stacked)
	var tween := label.create_tween()
	if bouncy_numbers:
		# Pops out big, jumps up, falls back with a bounce, then fades.
		label.pivot_offset = label.get_minimum_size() / 2.0
		label.scale = Vector2.ONE * (1.9 if big else 1.5)
		var top := label.position.y - (40.0 if big else 32.0)
		tween.tween_property(label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(label, "position:y", top, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(label, "position:y", top + 14.0, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.15)
	else:
		tween.tween_property(label, "position:y", label.position.y - 46.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tween.tween_callback(label.queue_free)


func _add_line(line: String) -> void:
	_lines.append(line)
	while _lines.size() > log_lines:
		_lines.remove_at(0)
	_log.text = "\n".join(_lines)


func _rebuild_cards() -> void:
	for row in [_enemy_row, _party_row]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	_cards.clear()
	if battle == null:
		return
	for battler in battle.enemies:
		_add_card(battler, _enemy_row, enemy_portrait)
	for battler in battle.party:
		_add_card(battler, _party_row, party_portrait)
	_refresh_all()


func _add_card(battler: BKBattler, row: HBoxContainer, portrait_size: float) -> void:
	var card := BKBattlerCard.new()
	card.setup(battler, _database(), _skin(), portrait_size)
	card.chosen.connect(_on_card_chosen)
	card.button.focus_entered.connect(_preview.bind(card))
	card.button.mouse_entered.connect(_preview.bind(card))
	row.add_child(card)
	_cards[battler] = card


func _refresh_all() -> void:
	for battler: BKBattler in _cards:
		_cards[battler].refresh()
	_refresh_timeline()


func _refresh_timeline() -> void:
	for child in _timeline.get_children():
		_timeline.remove_child(child)
		child.queue_free()
	if battle == null or battle.is_over():
		return
	var first := true
	for battler in battle.get_turn_order(8):
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override(&"panel", _skin().get_slot_style(IKSlotView.State.MARKED if first else IKSlotView.State.NORMAL))
		frame.tooltip_text = battler.get_title()
		var icon := TextureRect.new()
		icon.texture = battler.data.get_icon(_database())
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var side := 40.0 if first else 30.0
		icon.custom_minimum_size = Vector2(side, side)
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		frame.add_child(icon)
		var band := ColorRect.new()
		band.color = Color(0.4, 0.7, 1.0) if battler.side == BKBattler.PARTY else Color(1.0, 0.4, 0.35)
		band.custom_minimum_size = Vector2(0, 3)
		band.mouse_filter = MOUSE_FILTER_IGNORE
		var column := VBoxContainer.new()
		column.add_theme_constant_override(&"separation", 2)
		column.alignment = BoxContainer.ALIGNMENT_END
		column.add_child(frame)
		column.add_child(band)
		_timeline.add_child(column)
		first = false


## Hint while picking: "Choose a target... · 12-15 damage · Weak!" (or "?" until the
## affinity is known).
func _preview(card: BKBattlerCard) -> void:
	if mode != Mode.TARGET or _pending == null or battle == null or battle.current == null or not card.is_targetable():
		return
	var text := BKText.t("Choose a target for %s (Escape to go back).") % _pending.get_title()
	if show_damage_preview and _pending.kind == BKAction.Kind.DAMAGE:
		var guess := battle.preview_damage(battle.current, _pending, card.battler)
		var parts := PackedStringArray([text])
		if guess.max < 0:
			parts.append(BKText.t("heals it"))
		elif guess.min == guess.max:
			parts.append(BKText.t("%d damage") % guess.max)
		else:
			parts.append(BKText.t("%d-%d damage") % [guess.min, guess.max])
		if not guess.known:
			parts.append("?")
		else:
			var tag := BKText.affinity_tag(guess.affinity)
			if not tag.is_empty():
				parts.append(tag)
		text = "  ·  ".join(parts)
	_hint.text = text


func _reward_grid(items: Dictionary) -> Control:
	var grid := HFlowContainer.new()
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.custom_minimum_size = Vector2(320, 0)
	for item_id: StringName in items:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override(&"panel", _skin().get_slot_style(IKSlotView.State.NORMAL))
		var definition := _database().get_item(item_id) if _database() != null else null
		frame.tooltip_text = definition.display_name if definition != null else String(item_id)
		var icon := TextureRect.new()
		icon.texture = definition.icon if definition != null else null
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = _skin().slot_size - Vector2.ONE * _skin().icon_margin * 2.0
		frame.add_child(icon)
		var amount := Label.new()
		amount.text = str(items[item_id])
		_skin().apply_amount_label(amount)
		amount.size_flags_horizontal = SIZE_SHRINK_END
		amount.size_flags_vertical = SIZE_SHRINK_END
		frame.add_child(amount)
		grid.add_child(frame)
	return grid


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_content = margin
	var split := HBoxContainer.new()
	split.add_theme_constant_override(&"separation", 12)
	margin.add_child(split)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(column)
	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override(&"separation", 8)
	column.add_child(order_row)
	var order_label := Label.new()
	order_label.text = BKText.t("Turn order")
	order_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	order_row.add_child(order_label)
	_timeline.add_theme_constant_override(&"separation", 4)
	_timeline.alignment = BoxContainer.ALIGNMENT_BEGIN
	order_row.add_child(_timeline)
	_enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_enemy_row.add_theme_constant_override(&"separation", 14)
	_enemy_row.size_flags_vertical = SIZE_EXPAND | SIZE_SHRINK_CENTER
	column.add_child(_enemy_row)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
	_hint.visible = false
	column.add_child(_hint)
	_timing.size_flags_horizontal = SIZE_SHRINK_CENTER
	_timing.finished.connect(_on_timing_finished)
	column.add_child(_timing)
	_party_row.add_theme_constant_override(&"separation", 10)
	_party_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_party_row)
	# Commands: a full-height column on the right, so long skill lists always fit.
	var side_column := VBoxContainer.new()
	side_column.add_theme_constant_override(&"separation", 10)
	side_column.custom_minimum_size = Vector2(240, 0)
	split.add_child(side_column)
	side_column.add_child(_command_panel)
	var log_panel := PanelContainer.new()
	log_panel.size_flags_vertical = SIZE_EXPAND_FILL
	side_column.add_child(log_panel)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override(&"normal_font_size", 13)
	log_panel.add_child(_log)
	_commands.add_theme_constant_override(&"separation", 4)
	_command_panel.add_child(_commands)
	_command_title.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
	_commands.add_child(_command_title)
	_command_panel.visible = false
	_floats.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_floats)
	_end_layer.mouse_filter = MOUSE_FILTER_STOP
	_end_layer.visible = false
	add_child(_end_layer)
	var end_panel := PanelContainer.new()
	end_panel.custom_minimum_size = Vector2(380, 0)
	_end_layer.add_child(end_panel)
	var end_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		end_margin.add_theme_constant_override("margin_" + side, 18)
	end_panel.add_child(end_margin)
	_end_box.add_theme_constant_override(&"separation", 10)
	end_margin.add_child(_end_box)


## Focus moves only if the control is still on screen (menus are rebuilt quickly).
func _focus_later(control: Control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()


func _database() -> IKItemDatabase:
	if database != null:
		return database
	return battle.bag.database if battle != null and battle.bag != null else null


func _skin() -> IKSkin:
	if skin != null:
		return skin
	if _fallback_skin == null:
		_fallback_skin = IKSkin.create_default()
	return _fallback_skin
