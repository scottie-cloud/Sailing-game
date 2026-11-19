# Sailing Game

A trading game for Android about making fast passages under sail. You start
with a small boat in a sheltered bay and learn to sail one step at a time.

Built with [Godot 4.3](https://godotengine.org/download).

## Stage 1 (what exists now)

- One bay, two ports (Port Haven and Eastpoint), one small boat, steady wind.
- You only steer; the sails trim themselves.
- A red wedge shows the no-go zone: you cannot sail straight into the wind.
  Port Haven to Eastpoint is upwind, so you have to zig-zag (tack). The trip
  back is a fast downwind run.
- Time runs up to 6x faster on open water and drops to normal when you steer,
  get stuck head to wind, or come near land or your destination.
- Each port sells one cargo that spoils (pays a premium for a fast passage,
  sells at a loss after a slow one) and one that keeps (small steady profit).
- Profits buy a bigger hold and better sails. Each route records your best
  passage time.

## Playing on a phone

Every change merged to `main` is published as a browser version at
https://scottie-cloud.github.io/Sailing-game/ (turn the phone sideways).
This needs GitHub Pages switched on once: repository Settings, Pages,
Source: GitHub Actions.

## Running it on a computer

1. Install Godot 4.3 or later (standard version, not .NET).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (or the play button).

Steer with the on-screen `<` `>` buttons, or the arrow keys / A and D.

For an installable Android app, follow Godot's
[Android export guide](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_for_android.html).

## Tests

The sailing, trading and time rules are plain scripts in `sim/` with tests:

```bash
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/smoke_test.gd
```

## Layout

- `sim/` game rules with no visuals: sailing maths, ship motion, trade,
  time compression, and the list of learning stages.
- `game/` the map and the playable scene (drawn in code).
- `tests/` headless tests.

## Planned stages

1. Steering (this prototype)
2. Manual sail trim: faster than the automatic trim if you get it right
3. Changing weather: wind shifts, gusts, reefing
4. Longer routes with a forecast to plan around
5. Bigger square-rigged ships

Numbers worth tuning once it has been played: par passage times and prices in
`sim/trade.gd`, compression speeds in `sim/time_compression.gd`, and the boat's
speed table in `sim/sailing_model.gd`.
