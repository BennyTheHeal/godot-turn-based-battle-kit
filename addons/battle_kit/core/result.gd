class_name BKResult
extends RefCounted
## Outcome of a battle action: refused (see [member code]) or done, with the list of what
## happened in [member events] (damage, heals, misses, statuses, defeats...).

enum Code {
	OK,
	INVALID_ARGUMENT,
	## The battle is over (victory, defeat or escape).
	BATTLE_OVER,
	## The actor is not the battler whose turn it is.
	NOT_YOUR_TURN,
	NOT_ENOUGH_MP,
	## Item actions: the bag has none left (see [member inventory_result]).
	NO_ITEM,
	## Missing, dead (or alive, for revives) or wrong-side target.
	INVALID_TARGET,
	## This battle does not allow escaping.
	CANNOT_FLEE,
}

var code: Code = Code.OK
var message: String = ""
## What happened, in order. Each event is a Dictionary with at least "type" and "target"
## (a [BKBattler]); see [BKBattle] for the list of types and their fields.
var events: Array[Dictionary] = []
var inventory_result: IKResult

var ok: bool:
	get:
		return code == Code.OK


static func success(p_events: Array[Dictionary] = []) -> BKResult:
	var result := BKResult.new()
	result.events = p_events
	return result


static func failure(error_code: Code, error_message: String = "") -> BKResult:
	var result := BKResult.new()
	result.code = error_code
	result.message = error_message
	return result


func code_name() -> String:
	return Code.keys()[code]


## Events of one type ("damage", "heal", "miss", "status"...).
func events_of(type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event.type == type:
			found.append(event)
	return found


func _to_string() -> String:
	return "BKResult(OK, %d events)" % events.size() if ok else "BKResult(%s: %s)" % [code_name(), message]
