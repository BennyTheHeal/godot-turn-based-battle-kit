class_name BKBattlerCard
extends PanelContainer
## One fighter on the battle screen: portrait, name, HP (and MP for heroes) bars, status
## icons. It is also the button used to pick a target.

signal chosen(card: BKBattlerCard)

var battler: BKBattler
var database: IKItemDatabase
var skin: IKSkin
var button := Button.new()
var portrait := TextureRect.new()
var _name := Label.new()
var _hp := ProgressBar.new()
var _hp_text := Label.new()
var _mp := ProgressBar.new()
var _mp_text := Label.new()
var _statuses := HBoxContainer.new()
var _active := false
var _targetable := false
var _time := 0.0
var _portrait_size := 72.0
## Extra portrait offset, animated by [method lunge].
var lunge_offset := Vector2.ZERO
var _lunge_tween: Tween


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 3)
	add_child(column)
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.name = "PortraitHolder"
	column.add_child(holder)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(portrait)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.clip_text = true
	_name.add_theme_font_size_override(&"font_size", 14)
	_name.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(_name)
	for pair in [[_hp, _hp_text, Color(0.35, 0.85, 0.4)], [_mp, _mp_text, Color(0.35, 0.6, 1.0)]]:
		var bar: ProgressBar = pair[0]
		var text: Label = pair[1]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0, 0, 0, 0.55)
		back.set_corner_radius_all(4)
		var fill := StyleBoxFlat.new()
		fill.bg_color = pair[2]
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(&"background", back)
		bar.add_theme_stylebox_override(&"fill", fill)
		text.add_theme_font_size_override(&"font_size", 11)
		text.add_theme_color_override(&"font_outline_color", Color.BLACK)
		text.add_theme_constant_override(&"outline_size", 3)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.mouse_filter = MOUSE_FILTER_IGNORE
		bar.add_child(text)
		text.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		column.add_child(bar)
	_statuses.add_theme_constant_override(&"separation", 2)
	_statuses.custom_minimum_size = Vector2(0, 20)
	_statuses.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_statuses)
	button.flat = true
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(func() -> void: chosen.emit(self))
	add_child(button)


func setup(p_battler: BKBattler, p_database: IKItemDatabase, p_skin: IKSkin, portrait_size: float) -> void:
	battler = p_battler
	database = p_database
	skin = p_skin
	_portrait_size = portrait_size
	var holder: Control = portrait.get_parent()
	holder.custom_minimum_size = Vector2(portrait_size, portrait_size)
	portrait.size = Vector2(portrait_size, portrait_size)
	custom_minimum_size = Vector2(maxf(portrait_size + 50.0, 140.0), 0)
	_mp.visible = battler.side == BKBattler.PARTY and battler.get_max_mp() > 0
	button.focus_entered.connect(func() -> void: _restyle())
	button.focus_exited.connect(func() -> void: _restyle())
	refresh()


func refresh() -> void:
	if battler == null:
		return
	portrait.texture = battler.data.get_icon(database)
	_name.text = battler.get_title()
	_hp.max_value = battler.get_max_hp()
	_hp.value = battler.hp
	_hp_text.text = "%d / %d" % [battler.hp, battler.get_max_hp()]
	_mp.max_value = maxi(1, battler.get_max_mp())
	_mp.value = battler.mp
	_mp_text.text = "%d / %d MP" % [battler.mp, battler.get_max_mp()]
	for child in _statuses.get_children():
		_statuses.remove_child(child)
		child.queue_free()
	for entry in battler.statuses:
		var status: BKStatus = entry.status
		var icon := TextureRect.new()
		icon.texture = status.get_icon(database)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(18, 18)
		icon.self_modulate = status.color.lerp(Color.WHITE, 0.35)
		icon.tooltip_text = "%s (%d)%s" % [status.get_title(), entry.turns, " x%d" % entry.stacks if entry.stacks > 1 else ""]
		_statuses.add_child(icon)
		if icon.texture == null:
			var tag := Label.new()
			tag.text = status.get_title().left(3)
			tag.add_theme_font_size_override(&"font_size", 10)
			tag.add_theme_color_override(&"font_color", status.color)
			icon.add_child(tag)
	modulate = Color(1, 1, 1) if battler.is_alive() else Color(0.55, 0.55, 0.55, 0.6)
	_restyle()


func set_active(value: bool) -> void:
	_active = value
	_restyle()


func set_targetable(value: bool) -> void:
	_targetable = value
	button.focus_mode = FOCUS_ALL if value else FOCUS_NONE
	button.mouse_filter = MOUSE_FILTER_STOP if value else MOUSE_FILTER_IGNORE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND if value else CURSOR_ARROW
	_restyle()


func is_targetable() -> bool:
	return _targetable


## A short color flash on the portrait (hit, heal).
func flash(color: Color) -> void:
	portrait.modulate = color
	var tween := create_tween()
	tween.tween_property(portrait, "modulate", Color.WHITE, 0.35)


## A quick dash of the portrait toward [param direction] (normalized) and back: the
## attacker's swing. [param distance] in pixels.
func lunge(direction: Vector2, distance: float = 18.0, time: float = 0.28) -> void:
	if distance <= 0.0 or direction == Vector2.ZERO:
		return
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	lunge_offset = Vector2.ZERO
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(self, "lunge_offset", direction.normalized() * distance, time * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(self, "lunge_offset", Vector2.ZERO, time * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Center of the portrait, in global coordinates (without the lunge).
func get_center() -> Vector2:
	return portrait.get_global_rect().get_center() - lunge_offset


## Where floating numbers start, in global coordinates.
func get_float_origin() -> Vector2:
	return portrait.get_global_rect().get_center() - Vector2(0, _portrait_size * 0.3)


func _process(delta: float) -> void:
	if battler == null:
		return
	_time += delta
	# Monsters float gently; the fighter whose turn it is bobs a little more.
	var amplitude := 0.0
	if battler.is_alive():
		amplitude = 4.0 if battler.side == BKBattler.ENEMIES else 0.0
		if _active:
			amplitude += 3.0
	portrait.position = Vector2(0.0, sin(_time * 2.4 + battler.index) * amplitude) + lunge_offset


func _restyle() -> void:
	if skin == null:
		return
	var state := IKSlotView.State.NORMAL
	if _active:
		state = IKSlotView.State.MARKED
	if _targetable and button.has_focus():
		state = IKSlotView.State.FOCUS
	elif _targetable:
		state = IKSlotView.State.HOVER
	add_theme_stylebox_override(&"panel", skin.get_slot_style(state))
	for style in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
