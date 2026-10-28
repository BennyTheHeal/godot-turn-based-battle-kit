# Turn-Based Battle Kit for Godot 4

Turn-based RPG battles, ready to play: a **speed-based turn order** (fast fighters act more often, shown on a timeline), **skills that cost MP**, **items from your bag** (potions, antidotes), **buffs and debuffs** (poison, burn, stun, guard, haste... stacking, ticking, wearing off), **elemental weaknesses and resistances**, an **enemy AI** that heals its allies, focuses the weak and remembers what hurts you, **levels** with an XP curve, optional **timed hits**, **rewards** (XP, gold, drops) paid into your inventory, and a **finished, lively battle screen** that works with the mouse, the keyboard and a gamepad.

**Pay what you want, from $0.** Code under MIT. Made by Benny, entirely with AI tools. Official page, downloads and playable web demo: https://banc-essai.site-testeurs.workers.dev/battle-kit/
More kits, and our game prototypes waiting for testers: https://banc-essai.site-testeurs.workers.dev/

- **Fighters as resources** (`BKBattlerData`): stats (`max_hp`, `max_mp`, `attack`, `defense`, `magic`, `resistance`, `speed`, `crit_chance`, `evasion`), actions, immunities, XP, gold and drops.
- **Actions** (`BKAction`): damage (physical or magic, several hits), heals, MP restore, support, revive, defend, flee; one target, all enemies, all allies, self or a fallen ally; MP cost, accuracy, crits, statuses with a chance, cures, and a delay that makes heavy moves slower.
- **Statuses** (`BKStatus`): stat changes in percent or flat, damage or healing per turn (flat or % of max HP), skipped turns, stacks, durations, debuff or buff.
- **Elements** (1.1): `action.element = &"fire"`, and per fighter `affinities = {&"fire": 2.0, &"ice": 0.5, &"earth": 0.0, &"water": -1.0}`: weak, resist, immune, absorb (any multiplier works). The screen says "Weak!" / "Resist" / "Immune" / "Absorb", the log too. Each side learns an affinity by hitting it; the AI then prefers the weaknesses it knows and avoids immunities (`ai_affinity_focus`, or `ai_knows_affinities` for a boss that knows everything). `preview_damage()` gives the expected damage without rolling anything, and the target hint shows it ("12-15 damage · Weak!", "?" until known).
- **Levels** (1.1): `BKLevelCurve` (XP formula or exact table, max level, stat growth per level; `BKBattlerData.growth` per fighter). Victories level the surviving heroes up (`share_xp` to split), signal `level_up`, HP and MP rise with the max, and the victory screen lists who reached which level. Level gains stack with `battler.bonuses`, so equipment and Skill Tree Kit bonuses keep working. `battler.to_data()` saves HP, MP, level and XP.
- **Timed hits** (1.1, off by default): `view.timed_commands = true` shows a timing bar on each attack (press at the right moment: +30 % damage) and on each enemy attack against a hero (press to guard: -40 %). Enter, Space, gamepad A or a click. Without the view: `perform(action, targets, true)`.
- **Rules that hold**: refusals instead of errors (`NOT_ENOUGH_MP`, `NO_ITEM`, `INVALID_TARGET`, `CANNOT_FLEE`...), items taken from the bag only when the action happens, rewards added to the bag with everything that did not fit reported in `left_behind` (never lost silently). Same seed, same battle.
- **Plugs into your game**: `battler.bonuses` takes flat bonuses from equipment, set bonuses or our Skill Tree Kit's `skills.get_bonuses()`. Heroes keep their HP and MP from fight to fight.
- **BKBattleView**: turn order, enemy and party cards (HP, MP, status icons with turns left), command menu (Attack, Skills, Items, Defend, Flee), target picking with a damage preview, battle log, victory screen with the rewards and level-ups. It feels alive without new art: attackers dash toward their target (`lunge_distance`), critical hits shake the screen (`shake_strength`), damage numbers pop and bounce (`bouncy_numbers`). Icons from the 120 Inventory Kit items in 4 art styles, or your own textures.
- Translatable texts, 27 automated tests, pure GDScript. Everything new in 1.1 is opt-in: a 1.0 project plays exactly the same.

## Install

1. Copy `addons/inventory_kit/` and `addons/battle_kit/` into your project's `addons/` folder (skip Inventory Kit if you already have it).
2. Open `demo/battle/battle_demo.tscn`: "The Haunted Armory", three heroes against cursed objects, three fights and a boss.

## Five-minute setup

```gdscript
var knight := BKBattlerData.make(&"knight", "Knight", {&"max_hp": 120, &"attack": 16, &"defense": 14, &"speed": 9}, &"sword")
var fireball := BKAction.make(&"fireball", "Fireball", BKAction.Kind.DAMAGE, BKAction.Target.ONE_ENEMY, 12, 5, &"ruby")
fireball.scaling = BKAction.Scaling.MAGIC
mage.actions.append(fireball)

var battle := BKBattle.new()
battle.bag = bag.container                    # potions come from here, rewards go here
battle.item_actions = [BKAction.make_item(&"health_potion", "Potion", BKAction.Kind.HEAL, BKAction.Target.ONE_ALLY, 45)]
add_child(battle)

var view := BKBattleView.new()                # the whole battle screen
view.battle = battle
view.skin = preload("res://addons/inventory_kit/art/painted/painted_skin.tres")
view.theme = preload("res://addons/inventory_kit/art/painted/painted_theme.tres")
view.finished.connect(func(outcome): print(outcome))
add_child(view)

battle.start([knight_battler, mage_battler], [wolf_data, wolf_data])
```

Elements, levels and timed hits:

```gdscript
fireball.element = &"fire"
golem_data.affinities = {&"fire": BKBattlerData.ABSORB, &"ice": BKBattlerData.WEAK}

battle.level_curve = BKLevelCurve.make(100, 1.5, {&"max_hp": 12, &"attack": 2, &"magic": 2})
battle.level_up.connect(func(hero, from, to, gains): print(hero.get_title(), " reaches level ", to))

view.timed_commands = true                    # off by default
```

Skill Tree Kit: keep `hero.bonuses = skills.get_bonuses()` (levels add on top), and turn its abilities into battle skills: `skills.ability_unlocked.connect(func(ability, _skill): hero.data.actions.append(my_actions[ability]))`.

Without the view, drive it yourself: on `turn_started(actor)`, heroes call `battle.perform(action, [target])`, enemies call `battle.run_ai_turn()`. Every result lists what happened in `result.events` ("damage", "heal", "miss", "status", "defeated"...).

## Classes

| Class | Role |
|---|---|
| `BKBattlerData`, `BKAction`, `BKStatus`, `BKDrop` | Fighters (with `affinities`, `growth`, `level_curve`), actions (with `element`), statuses and drops as resources |
| `BKLevelCurve` | XP per level (formula or table), max level, stat growth |
| `BKBattler` | A fighter during battle: HP, MP, statuses, level and XP, `get_stat()` with bonuses and levels, `get_affinity()`, `gain_xp()`, `restore()`, `to_data()` |
| `BKBattle` | Turn order, `perform()` (optionally timed), `run_ai_turn()`, `choose_ai_action()`, `preview_damage()`, `knows_affinity()` / `reveal_affinity()`, rewards and XP; signals `turn_started`, `action_resolved`, `level_up`, `battle_ended`... |
| `BKResult`, `BKText` | Outcome codes and events ("damage" with `element`, `affinity`, `timed`; "absorb"), player texts and log lines |
| `BKBattleView`, `BKBattlerCard`, `BKTimingPrompt` | The battle screen, the cards, the timing bar |

## Turn order

Each fighter books its next turn `100 / speed` time units after its last one; the first turns start slightly staggered (×0.9 to 1.0, from the seed). `get_turn_order(8)` rebuilds the timeline from current stats every time the screen refreshes, so a haste or slow shows at once for later turns, but a turn already booked does not move: the new speed counts from the following turn. Statuses that will wear off are not predicted. Ties are not random: heroes act before enemies, then fighters go in slot order.

## Running the tests

```bash
godot --headless --path <project> --import
godot --headless --path <project> -s res://tests/battle_kit/run_tests.gd
```

## Licenses

- Source code: MIT (`LICENSE.txt`).
- The item art in `addons/inventory_kit/art/` is covered by Inventory Kit's `LICENSE_ART.txt`: free to use in your games, please do not re-upload it; link to the official page instead.
- Found a bug or want a feature? Tell us: https://banc-essai.site-testeurs.workers.dev/
