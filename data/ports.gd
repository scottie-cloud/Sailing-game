extends RefCounted
## The ports. To add one, give it a name and its real longitude and latitude.
## The game puts it in the nearest water with room to dock, so a position on
## the shore is fine.
##   premium  optional: how much more trade with a hard-to-reach port pays
##            (1.4 = 40% more). Leave it out for an ordinary port.

const PORTS := {
	# Hobsons Bay, off Williamstown: where ships for Melbourne lay.
	"melbourne": {"name": "Melbourne", "lon": 144.907, "lat": -37.868},
	"geelong": {"name": "Geelong", "lon": 144.362, "lat": -38.143},
	"queenscliff": {"name": "Queenscliff", "lon": 144.666, "lat": -38.264},
	"mornington": {"name": "Mornington", "lon": 145.034, "lat": -38.214},
	# Outside the Heads on the ocean coast: reached only through the Rip.
	"barwon": {"name": "Barwon Heads", "lon": 144.497, "lat": -38.288, "premium": 1.4},
}
