# AGENTS.md

Guidelines for AI coding agents working on this repository.

## Project

Food-Sort is a Godot 4.x (developed/tested with 4.7.2, mobile renderer) portrait
fruit-sorting puzzle prototype: 9 plates, 3 fruit types, 3 slots per plate.
Sort 12 trios (4 per fruit type) to complete the level. Mouse and touch input
are unified via `pointing/emulate_touch_from_mouse`.

## Running the tests

The test suite is a hand-rolled headless scene (no GUT/gdUnit):

```sh
Godot --headless --path <project> res://tests/test.tscn
```

It quits with exit code 0 when all checks pass, 1 otherwise. On this machine
the binary is `/Users/lexinshengwen/Downloads/Godot.app/Contents/MacOS/Godot`.
The suite covers board rules, drop geometry, refills/cascades, rescue reveals,
two full-level solver runs, and save/load. The `ERROR: Parse JSON failed`
line in the output is expected: it comes from the intentional corrupt-save
negative test.

## Architecture (keep this separation)

- `scripts/board.gd` (`Board`) — pure rules only: contents, reserve batches,
  move validation, trio clearing, preview refills, rescue reveals, save/load.
  No scene-tree or input dependencies. Emits ordered event dictionaries
  (`EVENT_MOVED/CLEAR/REFILL/REVEAL`) with `contents`/`previews` snapshots.
- `scripts/level_data.gd` (`LevelData`) — the only file to edit when changing
  level layout. Must keep exactly 12 trios (12 of each fruit) or the solver
  tests and `is_valid_state` counts will fail.
- `scripts/fruit_data.gd` (`FruitData`) — fruit ID registry and placeholder
  colors. Rules only use the string IDs; visuals can be replaced later.
- `scripts/main.gd` — scene wiring, HUD, drag-and-drop input, event animation.
- `scripts/plate.gd` (`PlateView`) / `scripts/fruit_view.gd` (`FruitView`) —
  drawing and per-plate geometry (drop ellipses, slot positions).
- `tests/test_board.gd` — the whole automated suite plus its level solver.

## Conventions

- GDScript 4 syntax, tabs for indentation, `class_name` + a leading `##` doc
  comment block per class and per non-obvious function (match existing style).
- Fruits are string IDs; never hardcode colors outside `FruitData`.
- GDScript `Dictionary` iterates in insertion order: never rely on it for
  tie-breaking (this caused an infinite solver loop before; see
  `_most_common_type` in `tests/test_board.gd`).
- Preserve existing gameplay behavior; prefer minimal, targeted fixes.

## Repository notes

- The default branch with the game code is `main`; other branches
  (`Test`, `Project-Setup`, `TESTING`) exist for experiments.
- The save file lives at `user://food_sort_save.json`; tests delete it
  before and after running.
