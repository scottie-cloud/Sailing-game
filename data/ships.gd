extends RefCounted
## Ships and upgrades.
##
## SHIPS, smallest first in SHIP_ORDER:
##   price         cost new (the old ship is traded in at half its price)
##   hold          cargo units before upgrades
##   hull_speed    top speed in knots before upgrades
##   turn          how readily she turns (1.0 = the cutter)
##   strain_limit  seconds she stands being overpowered before a sail splits
##   draught       how deep she sits with an empty hold, in metres
##   laden         how much deeper she sits with a full hold
##   size          how large she is drawn (1.0 = the cutter)
##   rig           her masts: "y" is the position along the deck (negative is
##                 forward), "boom" the length of the sail's foot, "jib" whether
##                 a headsail is set ahead of that mast
##
## UPGRADES, in the order of UPGRADE_ORDER:
##   cost  price of the first level; each further level costs 1.6 times more
##   max   the highest level
## What each upgrade does is worked out in sim/shipyard.gd.

const SHIPS := {
	"cutter": {"name": "Cutter", "draught": 1.4, "laden": 0.3, "price": 0, "hold": 10, "hull_speed": 7.0, "turn": 1.0, "strain_limit": 1200.0, "size": 1.0,
		"blurb": "One mast, quick to turn. A boat for learning the bay.",
		"rig": [{"y": -10.0, "boom": 40.0, "jib": true}]},
	"ketch": {"name": "Ketch", "draught": 2.2, "laden": 0.5, "price": 700, "hold": 28, "hull_speed": 8.0, "turn": 0.8, "strain_limit": 1500.0, "size": 1.25,
		"blurb": "Two masts and more than twice the hold. A working coaster.",
		"rig": [{"y": -14.0, "boom": 36.0, "jib": true}, {"y": 16.0, "boom": 22.0, "jib": false}]},
	"schooner": {"name": "Schooner", "draught": 3.0, "laden": 0.7, "price": 2200, "hold": 45, "hull_speed": 9.5, "turn": 0.65, "strain_limit": 1800.0, "size": 1.5,
		"blurb": "Fast and roomy, but slow in stays: plan her turns.",
		"rig": [{"y": -18.0, "boom": 28.0, "jib": true}, {"y": 6.0, "boom": 36.0, "jib": false}]},
}
const SHIP_ORDER: Array[String] = ["cutter", "ketch", "schooner"]

const UPGRADES := {
	"hold": {"name": "Bigger hold", "effect": "+5 cargo", "cost": 150, "max": 3},
	"sails": {"name": "Better sails", "effect": "+6% speed", "cost": 200, "max": 3},
	"keel": {"name": "Deeper keel", "effect": "25% less sideways slip", "cost": 180, "max": 2},
	"rigging": {"name": "Stronger rigging", "effect": "stands a blow 50% longer", "cost": 160, "max": 2},
}
const UPGRADE_ORDER: Array[String] = ["hold", "sails", "keel", "rigging"]
