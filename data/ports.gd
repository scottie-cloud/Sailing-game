extends RefCounted
## The ports. To add one, give it a name and its real longitude and latitude.
## The game puts it in the nearest water with room to dock, so a position on
## the shore is fine.
##   premium  optional: how much more trade with a hard-to-reach port pays
##            (1.4 = 40% more). Leave it out for an ordinary port.

const PORTS := {
	"melbourne": {"name": "Melbourne", "lon": 144.91, "lat": -37.88},
	"geelong": {"name": "Geelong", "lon": 144.39, "lat": -38.13},
	"queenscliff": {"name": "Queenscliff", "lon": 144.68, "lat": -38.25},
	"mornington": {"name": "Mornington", "lon": 145.02, "lat": -38.21},
	# Outside the Heads on the ocean coast: reached only through the Rip.
	"barwon": {"name": "Barwon Heads", "lon": 144.49, "lat": -38.30, "premium": 1.4},
}
