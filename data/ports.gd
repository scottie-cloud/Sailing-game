extends RefCounted
## The ports. To add one, give it a name and its real longitude and latitude.
## The game puts it in the nearest water with room to dock, so a position on
## the shore is fine.
##   premium   optional: how much more trade with a hard-to-reach port pays
##             (1.4 = 40% more). Leave it out for an ordinary port.
##   tells_of  the ports you hear of when you call here. The game starts at
##             Melbourne, so every port must be reachable by word of mouth
##             from there.
##   word      how people in other ports describe where it lies

const PORTS := {
	# Hobsons Bay, off Williamstown: where ships for Melbourne lay.
	"melbourne": {"name": "Melbourne", "lon": 144.907, "lat": -37.868, "tells_of": ["mornington", "geelong"],
		"word": "the anchorage in Hobsons Bay, at the head of Port Phillip"},
	"geelong": {"name": "Geelong", "lon": 144.362, "lat": -38.143, "tells_of": ["queenscliff"],
		"word": "west along the northern shore, at the head of Corio Bay"},
	"queenscliff": {"name": "Queenscliff", "lon": 144.666, "lat": -38.264, "tells_of": ["barwon", "geelong", "mornington"],
		"word": "at the Heads, on the western side, just inside the Rip"},
	"mornington": {"name": "Mornington", "lon": 145.034, "lat": -38.214, "tells_of": ["queenscliff"],
		"word": "across the bay to the south-east, under Mount Martha"},
	# Outside the Heads on the ocean coast: reached only through the Rip.
	"barwon": {"name": "Barwon Heads", "lon": 144.497, "lat": -38.288, "premium": 1.4, "tells_of": ["queenscliff"],
		"word": "outside the Heads, a few miles west along the ocean coast"},
}
