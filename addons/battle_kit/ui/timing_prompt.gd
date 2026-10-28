class_name BKTimingPrompt
extends PanelContainer
## A timed command: a cursor crosses a bar, press [member action] (Enter / Space / gamepad A
## by default, or click) while it is in the bright zone. [signal finished] tells whether the
## press landed; no press before the end counts as a miss. Used by [BKBattleView] when
## [member BKBattleView.timed_commands] is on, for attacks and for guarding.

signal finished(success: bool)

## Seconds the cursor takes to cross the bar.
@export_range(0.2, 5.0, 0.05) var duration: float = 1.1
## The zone to hit, as parts of the bar (0 = left, 1 = right).
@export_range(0.0, 1.0, 0.01) var zone_start: float = 0.62
@export_range(0.0, 1.0, 0.01) var zone_end: float = 0.84
## Input action that presses. ui_accept covers Enter, Space and the gamepad's A button.
@export var action: StringName = &"ui_accept"
@export var bar_color := Color(0, 0, 0, 0.55)
@export var zone_color := Color(1.0, 0.82, 0.35, 0.9)
@export var cursor_color := Color(1, 1, 1)

## Cursor position, 0 to 1.
var cursor: float = 0.0
var running := false
var _label := Label.new()
var _bar := Control.new()
var _result := Label.new()


func _init() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
	column.add_child(_label)
	_bar.custom_minimum_size = Vector2(260, 22)
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	column.add_child(_bar)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result)


## Shows the prompt with [param text] ("Attack! Press at the right moment") and starts the cursor.
func start(text: String) -> void:
	_label.text = text
	_result.text = ""
	cursor = 0.0
	running = true
	visible = true
	_bar.queue_redraw()


## Presses now. Returns true when the cursor was in the zone.
func press() -> bool:
	if not running:
		return false
	var success := cursor >= zone_start and cursor <= zone_end
	_finish(success)
	return success


## Stops without a result signal (the battle ended, the screen closes).
func cancel() -> void:
	running = false
	visible = false


func _process(delta: float) -> void:
	if not running:
		return
	cursor += delta / maxf(0.05, duration)
	_bar.queue_redraw()
	if cursor >= 1.0:
		cursor = 1.0
		_finish(false)


func _input(event: InputEvent) -> void:
	if not running or not is_visible_in_tree():
		return
	var pressed := false
	if InputMap.has_action(action) and event.is_action_pressed(action, false):
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed:
		get_viewport().set_input_as_handled()  # the focused button must not also react
		press()


func _finish(success: bool) -> void:
	running = false
	_result.text = BKText.t("Great timing!") if success else BKText.t("Too bad...")
	_result.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.6) if success else Color(1.0, 0.6, 0.5))
	_bar.queue_redraw()
	finished.emit(success)
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void:
		if not running:
			visible = false)


func _draw_bar() -> void:
	var area := _bar.size
	_bar.draw_rect(Rect2(Vector2.ZERO, area), bar_color)
	_bar.draw_rect(Rect2(Vector2(area.x * zone_start, 0), Vector2(area.x * (zone_end - zone_start), area.y)), zone_color)
	var x := area.x * clampf(cursor, 0.0, 1.0)
	_bar.draw_rect(Rect2(Vector2(x - 2.0, -3.0), Vector2(4.0, area.y + 6.0)), cursor_color)
