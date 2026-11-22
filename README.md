# Sailing Game

A trading game for Android about making fast passages under sail. You start
with a small boat in a sheltered bay and learn to sail one step at a time.

Built with [Godot 4.3](https://godotengine.org/download).

## Stage 1 (what exists now)

- Port Phillip Bay, to scale, from a detailed real coastline, with place
  names and the bay's nineteenth-century lighthouses marked. Passing a light
  tells you what it is; at night the lights flash on the horizon. Five ports:
  Melbourne, Geelong, Queenscliff, Mornington and Barwon Heads. Mid-bay there is no land in
  sight, so you sail by the chart.
- Choose your destination in port. Cargo is worth more the further it goes.
- You steer, and the sails trim themselves. Switch to trimming by hand
  ("Trim: by hand", then Haul in / Ease out) and a well-set sail is faster
  than the automatic trim; a badly set one is slower.
- A red wedge shows the no-go zone: you cannot sail straight into the wind.
  When your destination is upwind you have to zig-zag (tack) towards it.
- Time runs up to 6x faster on open water and drops to normal when you steer,
  get stuck head to wind, or come near land or your destination.
- Each port sells one cargo that spoils (pays a premium for a fast passage,
  sells at a loss after a slow one) and one that keeps (small steady profit).
- A speed panel shows speed now, what the current heading is worth, the
  point of sail, progress towards the next mark, and a dial of how fast the
  boat goes in every direction.
- In port, **Plan route** opens a chart. Tap the water to add marks; each leg
  shows an estimated speed and time, and turns red if it points too close to
  the wind. Under sail the plan is drawn on the water and the game tracks
  whether you are ahead of or behind it.
- Sound: wind that rises with the breeze, water along the hull that grows
  with speed, a sail that shakes when it is not drawing, rain in a squall and
  a bell on arrival. A "Sound" button under sail switches it off.
- Shallow water: the sands inside the Heads, the Prince George Bank, the
  Swan Bay flats and the bar at Point Henry. Every ship has a draught, deeper
  when loaded, and the tide puts up to 0.9 m more water over a shoal. A ship
  too deep for the water runs aground. The cutter crosses the sands; the
  ketch needs the tide; the schooner keeps to the channels and can only
  reach Geelong on the tide with part of a cargo. The chart colours each
  shoal you have found for your ship as she is loaded.
- You chart the bay yourself. The chart starts blank except for the waters
  about Melbourne; whatever passes within three miles of the ship is surveyed
  for good. Shoals are unmarked until your lead finds them, and you can run
  aground on one you did not know of. You hear of new ports in the ports you
  reach, or find them by sighting them. Your own best passages, loaded with
  the chart's Record button, are your sailing directions.
- A Pause button under sail.
- A trim bar above the speed panel: a green band shows where the sail sets
  well and slides as the heading or wind changes; keep the white marker in it.
- The tide floods into the bay and ebbs out on a 12.4 hour cycle. It runs up
  to 3 knots in the Rip and gently elsewhere. The chart shows its state, and
  "Wait 1h" lets it turn before you leave.
- Squalls cross the bay with the wind. The chart shows their forecast tracks.
  Reef the sail before one hits: reefed she is slower in ordinary wind but
  safe in a blow; overpowered for too long, a sail splits and she is slow
  until repaired in port.
- Barwon Heads, on the ocean coast outside the Heads, can only be reached
  through the Rip and pays 40% more for cargo carried to or from it.
- The wind is different each day in port and shifts during a passage, so a
  plan made in port needs adjusting at sea.
- A ship's log records every passage with the course sailed. The course of
  the best passage on a route is drawn on the chart and can be loaded as the
  plan with one tap.
- The port shows what each cargo should fetch at your destination. Some ports
  want particular goods and pay more; landing a lot of one cargo gluts the
  market for a while.
- Charters: paid jobs drawn from the bay's trading history (the Geelong wool
  clip, tools for the Ballarat diggings, the Queenscliff couta boats' race to
  market, lime and timber for early Melbourne). Deliver enough of the cargo
  in the time allowed for a bonus.
- A shipyard: three ships (cutter, ketch, schooner) and four upgrades (hold,
  sails, keel, rigging). Each route records your best
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

## Where to change things

| To change | Edit |
| --- | --- |
| Ports (name, real position, premium) | `data/ports.gd` |
| Cargoes (price, where sold, where wanted) | `data/goods.gd` |
| Place names and lighthouses on the chart | `data/chart_features.gd` |
| Shoals: where they are and how deep | `data/shoals.gd` |
| How draught, depth and tide decide who floats | `sim/shoals.gd` |
| Which ports tell you of which others | `data/ports.gd` (`tells_of`) |
| How the player's own chart is kept | `sim/survey.gd` |
| Charters and their stories | `data/charters.gd` |
| Ships and upgrades | `data/ships.gd` |
| How prices, charters and upgrades work | `sim/trade.gd`, `sim/market.gd`, `sim/contracts.gd`, `sim/shipyard.gd` |
| How the boat sails | `sim/sailing_model.gd`, `sim/ship_state.gd` |
| Wind, squalls and tide | `sim/weather.gd`, `sim/tide.gd` |
| How fast time runs | `sim/time_compression.gd` |
| Where buttons and panels sit | `game/ui_builder.gd` |
| Colours | `game/palette.gd` |
| How loud each sound is, and when | `sim/sound_mix.gd` |
| The sounds themselves | `tools/make_sounds.py`, which writes `audio/` |
| The coastline | `tools/build_bay.py`, which writes `game/bay_data.gd` |

Each file in `data/` starts with a note on what its fields mean. After any
change, the tests check that the lists still hold together: every cargo is
sold at a real port, every charter names real ports and a cargo sold where
it starts, every port lands in water with room to dock.

## Layout

- `data/` the content: ports, cargoes, charters, ships. Plain lists.
- `sim/` the rules, with no visuals: sailing, weather, tides, prices,
  charters, the shipyard, route estimates, time compression.
- `game/` what is on screen:
  - `main.gd` the game's state and what happens in port and under sail
  - `sea_view.gd` the sailing view from above; `deck_view.gd` from the deck
  - `hud.gd` wind dial, minimap, trim bar and speed panel
  - `chart.gd`, `log_screen.gd`, `list_screen.gd` the full-screen pages
  - `ui_builder.gd` where every button and panel is laid out
  - `world.gd` the map; `save_game.gd` the save file
- `tests/` rule tests, a headless play-through, and a script that takes a
  screenshot of each screen.
- `tools/` the script that builds the map from coastline data.

## Map data

The coastline is cut from GSHHG, the Global Self-consistent, Hierarchical,
High-resolution Geography database (Wessel and Smith), at full resolution.
GSHHG is distributed under the GNU Lesser General Public License; the cut
used here is `tools/source/port_phillip_land.geojson`, and
`tools/build_bay.py` turns it into `game/bay_data.gd`. It shows Corio Bay,
Hobsons Bay, Swan Bay and Swan Island, the Mud Islands and the Rip at their
true size.

Place names and lighthouses are in `data/chart_features.gd`. Their positions
and dates were set down from general knowledge, not taken from a chart or a
source, and should be checked before being relied on. The same goes for
the shoals in `data/shoals.gd`: they put the sands and channels in roughly
the right places, with round-number depths, and are not a chart.

## Planned stages

1. Steering (done)
2. Manual sail trim (done)
3. Changing weather: wind shifts, squalls, reefing, tides (done)
4. Longer routes with a forecast to plan around
5. Bigger square-rigged ships

Numbers worth tuning once it has been played: par passage times and prices in
`sim/trade.gd`, compression speeds in `sim/time_compression.gd`, and the boat's
speed table in `sim/sailing_model.gd`.
