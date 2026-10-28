class_name BKText
extends RefCounted
## Every text Turn-Based Battle Kit shows to players goes through here, so it can be
## translated or reworded with Godot's translation system (template:
## [code]addons/battle_kit/translations/battle_kit.csv[/code]).

static var result_texts := {
	BKResult.Code.INVALID_ARGUMENT: "That did not work.",
	BKResult.Code.BATTLE_OVER: "The battle is over.",
	BKResult.Code.NOT_YOUR_TURN: "It is not this fighter's turn.",
	BKResult.Code.NOT_ENOUGH_MP: "Not enough MP.",
	BKResult.Code.NO_ITEM: "None left in the bag.",
	BKResult.Code.INVALID_TARGET: "Choose another target.",
	BKResult.Code.CANNOT_FLEE: "There is no escape from this fight!",
}


static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


static func result_message(result: BKResult) -> String:
	if result == null or result.ok:
		return ""
	if result.inventory_result != null and not result.inventory_result.player_text.is_empty():
		return IKText.result_message(result.inventory_result)
	return t(result_texts.get(result.code, "That did not work."))


## One battle log line for [param event] (see [BKBattle] for event types). Empty for
## events that need no line.
static func describe(event: Dictionary) -> String:
	var target: BKBattler = event.get("target")
	var who := target.get_title() if target != null else ""
	var actor: BKBattler = event.get("actor")
	var by := actor.get_title() if actor != null else ""
	match String(event.type):
		"damage":
			var extra := t(" (critical!)") if event.get("critical", false) else ""
			extra += affinity_suffix(event.get("affinity", BKBattler.Affinity.NORMAL))
			if event.get("timed", false):
				extra += t(" (timed!)")
			return t("%s hits %s for %d%s.") % [by, who, event.amount, extra]
		"absorb":
			return t("%s absorbs the attack and recovers %d HP.") % [who, event.amount]
		"heal":
			return t("%s recovers %d HP.") % [who, event.amount]
		"mp":
			return t("%s recovers %d MP.") % [who, event.amount]
		"miss":
			return t("%s misses %s.") % [by, who]
		"status":
			return t("%s is affected by %s.") % [who, (event.status as BKStatus).get_title()]
		"immune":
			return t("%s is immune to %s.") % [who, (event.status as BKStatus).get_title()]
		"cured":
			return t("%s is no longer affected by %s.") % [who, (event.status as BKStatus).get_title()]
		"expired":
			return t("%s on %s wears off.") % [(event.status as BKStatus).get_title(), who]
		"tick":
			if event.amount >= 0:
				return t("%s takes %d damage from %s.") % [who, event.amount, (event.status as BKStatus).get_title()]
			return t("%s recovers %d HP from %s.") % [who, -event.amount, (event.status as BKStatus).get_title()]
		"stunned":
			return t("%s cannot move!") % who
		"defend":
			return t("%s defends.") % who
		"revived":
			return t("%s is back on their feet!") % who
		"defeated":
			return t("%s is defeated.") % who
		"fled":
			return t("You got away!")
		"flee_failed":
			return t("Could not escape!")
		"used":
			return t("%s uses %s.") % [by, (event.action as BKAction).get_title()]
	return ""


## The short tag shown on the battle screen: "Weak!", "Resist", "Immune", "Absorb" (empty
## for normal damage).
static func affinity_tag(affinity: BKBattler.Affinity) -> String:
	match affinity:
		BKBattler.Affinity.WEAK:
			return t("Weak!")
		BKBattler.Affinity.RESIST:
			return t("Resist")
		BKBattler.Affinity.IMMUNE:
			return t("Immune")
		BKBattler.Affinity.ABSORB:
			return t("Absorb")
	return ""


## What a log line adds after the damage: " (weak!)", " (resisted)", " (immune)".
static func affinity_suffix(affinity: BKBattler.Affinity) -> String:
	match affinity:
		BKBattler.Affinity.WEAK:
			return t(" (weak!)")
		BKBattler.Affinity.RESIST:
			return t(" (resisted)")
		BKBattler.Affinity.IMMUNE:
			return t(" (immune)")
	return ""


## "Knight reaches level 3! +12 Max Hp, +2 Attack".
static func level_up_line(info: Dictionary) -> String:
	var battler: BKBattler = info.get("battler")
	var line := t("%s reaches level %d!") % [battler.get_title() if battler != null else "", int(info.get("to", 1))]
	var parts := PackedStringArray()
	var gains: Dictionary = info.get("gains", {})
	for stat: StringName in gains:
		var amount: float = gains[stat]
		var shown := ("%+d" % roundi(amount)) if absf(amount) >= 1.0 or is_zero_approx(amount) else ("%+.0f%%" % (amount * 100.0))
		parts.append("%s %s" % [shown, t(String(stat).capitalize())])
	if not parts.is_empty():
		line += " " + ", ".join(parts)
	return line
