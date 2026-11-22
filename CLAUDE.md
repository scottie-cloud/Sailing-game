# Sailing Game

A Godot 4.3 trading game under sail on Port Phillip Bay. The owner is not a
programmer and plays it in a phone browser; write for them in plain language.

## Layout

- `data/` content as plain lists (ports, cargoes, charters, ships). New
  content goes here, not into code.
- `sim/` rules with no nodes or drawing. Every rule has tests.
- `game/` screens and views. `main.gd` holds state and flow; views read from
  it and change nothing.
- `tests/run_tests.gd` rule and data tests; `tests/smoke_test.gd` a headless
  play-through; `tests/screenshots.gd` pictures of each screen.

## Working rules

- Scripts refer to each other with `const X = preload(...)`, not `class_name`.
- A view or helper that needs the game takes an untyped `game` reference.
  Give values read from it an explicit type (`var x: float = game.x`), since
  `:=` cannot infer one.
- History matters to the owner: charter stories, cargoes and ports should be
  accurate for the place and period. Say so when something is a guess.
- The map is to scale: 400 px to the nautical mile, north up.
- Keep `README.md` in step, especially "Where to change things".

## Checking a change

There may be no Godot available locally. The Build workflow is the check:

1. Push to a branch and open a pull request.
2. The workflow runs the rule tests, the play-through and the browser export,
   and fails on any script error, including errors while drawing.
3. It pushes a screenshot of each screen to the `ci-screenshots` branch.
   Fetch that branch and look at the pictures before calling a visual change
   done. Add a shot to `tests/screenshots.gd` for any new screen.

Merging to `main` publishes the game to GitHub Pages.
