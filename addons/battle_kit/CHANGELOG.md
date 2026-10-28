# Changelog

## 1.1.0 (2026-10-28)

Elemental affinities: `BKAction.element`, `BKBattlerData.affinities` (multipliers: weak, resist, immune, absorb; constants `WEAK`, `RESIST`, `IMMUNE`, `ABSORB`), `BKBattler.get_affinity()` and `Affinity`, "absorb" events, `element` / `affinity` on damage events, "Weak!" / "Resist" / "Immune" / "Absorb" on screen and in the log. Each side learns affinities by hitting (`knows_affinity()`, `reveal_affinity()`); the AI prefers known weaknesses and avoids known immunities (`ai_affinity_focus`, `ai_knows_affinities`). `BKBattle.preview_damage()` (rolls nothing), shown in the target hint.

Levels: `BKLevelCurve` (formula or table, max level, stat growth), `BKBattle.level_curve` and `share_xp`, `BKBattlerData.level_curve` and `growth`, `BKBattler.level`, `xp`, `gain_xp()`, `get_xp_to_next()`, `to_data()` / `load_data()`; signal `level_up`; `rewards.level_ups` and `rewards.xp_each`; level-ups on the victory screen. Level gains stack with `bonuses` (equipment, Skill Tree Kit).

Timed hits (off by default): `perform(action, targets, timed)` and `run_ai_turn(timed)`, `timed_attack_bonus`, `timed_guard_reduction`; `BKBattleView.timed_commands` with the new `BKTimingPrompt` (keyboard, mouse, gamepad).

Livelier screen: attackers dash toward their target, critical hits shake the screen, damage numbers pop and bounce (`lunge_distance`, `shake_strength`, `bouncy_numbers`).

Demo: fire and ice (Frost Lance, absorbing golems, fire-immune wisps), hero levels from a curve, a "Timed hits" switch. 27 tests.

Compatibility: 1.0 code and resources work unchanged; without elements, curve or timed commands, battles play exactly as before (same seeds, same results). `BKBattleView.Mode` gains `TIMING` at the end.

## 1.0.1 (2026-10-27)

README: new "Turn order" section (how speed changes reach the timeline, how ties are broken).

## 1.0.0 (2026-10-26)

First release: speed-based turn order with a timeline, skills with MP, items from an Inventory Kit bag, buffs and debuffs (stacks, damage over time, stuns, immunities, cures), revive, defend and flee, enemy AI (heals allies, focuses the weakest, weighted choices), rewards paid into the bag with a "left behind" report, battler bonuses for equipment and skill trees, the BKBattleView battle screen (mouse, keyboard, gamepad), the "Haunted Armory" demo in 4 art styles, 18 tests.
