extends RefCounted
## Base class for Turn-Based Battle Kit tests: assertions and shared fixtures.

var _failures := PackedStringArray()
var _nodes: Array[Node] = []


func get_failures() -> PackedStringArray:
	return _failures


func get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Adds [param node] to the scene root; it is freed after the test.
func add_to_tree(node: Node) -> Node:
	get_tree().root.add_child(node)
	_nodes.append(node)
	return node


func wait_frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame


## Called by the runner after each test.
func cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	await get_tree().process_frame


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%sexpected <%s> but got <%s>" % [message + ": " if message else "", expected, actual])


func assert_ok(result: IKResult, message: String = "") -> void:
	if result == null or not result.ok:
		fail("%sexpected OK, got %s" % [message + ": " if message else "", result])


func assert_code(result: IKResult, code: IKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", IKResult.Code.keys()[code], result])


## Disconnects every signal of [param objects]. Call at the end of tests whose
## lambdas capture the emitter, otherwise the reference cycle leaks.
func disconnect_all(objects: Array) -> void:
	for object: Object in objects:
		for info in object.get_signal_list():
			for connection in object.get_signal_connection_list(info.name):
				object.disconnect(info.name, connection.callable)




# --- Fixtures ----------------------------------------------------------------

func assert_battle(result: BKResult, code: BKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", BKResult.Code.keys()[code], result])


## A fighter with no randomness in its stats: no crits, no evasion.
func fighter(id: StringName, stats: Dictionary = {}) -> BKBattlerData:
	var all := {&"max_hp": 100, &"max_mp": 20, &"attack": 20, &"defense": 0, &"magic": 10, &"resistance": 0, &"speed": 10}
	all.merge(stats, true)
	return BKBattlerData.make(id, String(id).capitalize(), all)


func make_db() -> IKItemDatabase:
	var db := IKItemDatabase.new()
	for id: StringName in [&"gold_coins", &"health_potion", &"bone"]:
		var item := IKItemDefinition.new()
		item.id = id
		item.max_stack = 99
		db.add_item(item)
	return db


## A battle with no damage variance, accuracy rolls that always hit, and a 4-slot bag.
func make_battle(party: Array, enemies: Array, seed_value: int = 1, start := true) -> BKBattle:
	var battle := BKBattle.new()
	battle.variance = 0.0
	battle.bag = IKContainer.new(&"bag", 4, make_db())
	add_to_tree(battle)
	if start:
		battle.start(party, enemies, seed_value)
	return battle


func one(battler: BKBattler) -> Array[BKBattler]:
	var list: Array[BKBattler] = [battler]
	return list
