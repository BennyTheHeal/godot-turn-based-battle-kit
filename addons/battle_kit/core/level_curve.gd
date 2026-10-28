@tool
class_name BKLevelCurve
extends Resource
## XP needed for each level and what a level gives. Set it on [member BKBattle.level_curve]
## (the whole party) or on one [member BKBattlerData.level_curve]: victories then level the
## heroes up ([signal BKBattle.level_up]). Level gains are added on top of the base stats and
## of [member BKBattler.bonuses], so equipment and Skill Tree Kit bonuses keep working.
## [codeblock]
## var curve := BKLevelCurve.new()
## curve.base_xp = 100               # level 2 at 100 XP
## curve.exponent = 1.5              # level 3 at 283, level 4 at 520...
## curve.stat_growth = {&"max_hp": 12, &"attack": 2, &"defense": 1}
## battle.level_curve = curve
## [/codeblock]

@export_range(2, 999) var max_level: int = 50
## Total XP to reach level 2.
@export_range(1, 1000000) var base_xp: int = 100
## Total XP to reach level L = base_xp × (L - 1)^exponent. 1 = the same XP every level.
@export_range(1.0, 3.0, 0.05) var exponent: float = 1.5
## Exact totals instead of the formula: entry 0 = total XP for level 2, entry 1 = level 3...
## Levels past the end of the table follow the formula.
@export var xp_table: PackedInt32Array = []
## Stat gains per level, {&"max_hp": 10, &"attack": 2}. A fighter's own
## [member BKBattlerData.growth] replaces it.
@export var stat_growth: Dictionary[StringName, float] = {}


static func make(p_base_xp: int, p_exponent: float, p_growth: Dictionary, p_max_level: int = 50) -> BKLevelCurve:
	var curve := BKLevelCurve.new()
	curve.base_xp = p_base_xp
	curve.exponent = p_exponent
	curve.stat_growth.assign(p_growth)
	curve.max_level = p_max_level
	return curve


## Total XP needed to reach [param level] (0 for level 1).
func xp_to_reach(level: int) -> int:
	if level <= 1:
		return 0
	var at := level - 2
	if at < xp_table.size():
		return xp_table[at]
	return roundi(base_xp * pow(level - 1, exponent))


## The level a fighter with [param xp] total XP has reached (1 to [member max_level]).
func level_for_xp(xp: int) -> int:
	var level := 1
	while level < max_level and xp >= xp_to_reach(level + 1):
		level += 1
	return level


## XP still needed from [param xp] to the level after [param level] (0 at the max level).
func xp_to_next(level: int, xp: int) -> int:
	if level >= max_level:
		return 0
	return maxi(0, xp_to_reach(level + 1) - xp)


## Problems a developer should fix: totals that go down, unknown stats.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for i in range(1, xp_table.size()):
		if xp_table[i] <= xp_table[i - 1]:
			problems.append("xp_table must grow: entry %d (%d) <= entry %d (%d)" % [i, xp_table[i], i - 1, xp_table[i - 1]])
	for stat in stat_growth:
		if not BKBattlerData.STATS.has(stat):
			problems.append("stat_growth: unknown stat %s" % stat)
	return problems
