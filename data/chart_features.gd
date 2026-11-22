extends RefCounted
## Names and lights marked on the chart. Positions are real longitudes and
## latitudes, set down from general knowledge of the bay and good to a mile
## or so: check them against a proper chart before relying on them.
##
## PLACES
##   kind  "water" for bays and channels, "land" for points, hills and districts
##   rank  1 is shown on the planning chart and the sea; 2 only on the sea,
##         once the ship is near
##
## LIGHTS
##   year  when a light was first shown there
##   note  a line of history, shown beside the light

const PLACES := [
	{"name": "Port Phillip", "lon": 144.87, "lat": -38.08, "kind": "water", "rank": 1},
	{"name": "Corio Bay", "lon": 144.42, "lat": -38.115, "kind": "water", "rank": 1},
	{"name": "Hobsons Bay", "lon": 144.935, "lat": -37.885, "kind": "water", "rank": 1},
	{"name": "Swan Bay", "lon": 144.655, "lat": -38.228, "kind": "water", "rank": 2},
	{"name": "The Rip", "lon": 144.632, "lat": -38.302, "kind": "water", "rank": 1},
	{"name": "Bass Strait", "lon": 144.50, "lat": -38.37, "kind": "water", "rank": 1},
	{"name": "Capel Sound", "lon": 144.87, "lat": -38.335, "kind": "water", "rank": 2},
	{"name": "Bellarine Peninsula", "lon": 144.56, "lat": -38.19, "kind": "land", "rank": 1},
	{"name": "Mornington Peninsula", "lon": 145.03, "lat": -38.33, "kind": "land", "rank": 1},
	{"name": "Point Lonsdale", "lon": 144.60, "lat": -38.275, "kind": "land", "rank": 2},
	{"name": "Point Nepean", "lon": 144.68, "lat": -38.318, "kind": "land", "rank": 2},
	{"name": "Swan Island", "lon": 144.69, "lat": -38.245, "kind": "land", "rank": 2},
	{"name": "Mud Islands", "lon": 144.765, "lat": -38.262, "kind": "land", "rank": 2},
	{"name": "Indented Head", "lon": 144.70, "lat": -38.14, "kind": "land", "rank": 2},
	{"name": "Portarlington", "lon": 144.65, "lat": -38.125, "kind": "land", "rank": 2},
	{"name": "Point Henry", "lon": 144.43, "lat": -38.14, "kind": "land", "rank": 2},
	{"name": "Point Wilson", "lon": 144.50, "lat": -38.075, "kind": "land", "rank": 2},
	{"name": "Point Cook", "lon": 144.79, "lat": -37.925, "kind": "land", "rank": 2},
	{"name": "Point Gellibrand", "lon": 144.895, "lat": -37.862, "kind": "land", "rank": 2},
	{"name": "St Kilda", "lon": 144.99, "lat": -37.865, "kind": "land", "rank": 2},
	{"name": "Frankston", "lon": 145.14, "lat": -38.145, "kind": "land", "rank": 2},
	{"name": "Mount Martha", "lon": 145.03, "lat": -38.275, "kind": "land", "rank": 2},
	{"name": "Arthurs Seat", "lon": 144.95, "lat": -38.36, "kind": "land", "rank": 2},
	{"name": "Sorrento", "lon": 144.74, "lat": -38.35, "kind": "land", "rank": 2},
]

const LIGHTS := [
	{"name": "Point Lonsdale", "lon": 144.6153, "lat": -38.2917, "year": 1863,
		"note": "Marks the western head of the Rip."},
	{"name": "Queenscliff High Light", "lon": 144.6615, "lat": -38.2716, "year": 1862,
		"note": "The black lighthouse on Shortland Bluff. In line with the Low Light it leads ships through the Rip."},
	{"name": "Queenscliff Low Light", "lon": 144.6630, "lat": -38.2745, "year": 1862,
		"note": "The white lighthouse below the bluff."},
	{"name": "Gellibrand Point", "lon": 144.9073, "lat": -37.8690, "year": 1849,
		"note": "The bluestone tower at Williamstown, later the time-ball tower by which ships set their chronometers."},
	{"name": "South Channel Pile Light", "lon": 144.855, "lat": -38.318, "year": 1874,
		"note": "A light on piles in the water, marking the channel through the sands."},
	{"name": "West Channel Pile Light", "lon": 144.757, "lat": -38.19, "year": 1881,
		"note": "Marks the shorter channel for small craft bound to Geelong and Melbourne."},
	{"name": "Eastern Light", "lon": 144.928, "lat": -38.353, "year": 1883,
		"note": "The tall iron light at the foot of Arthurs Seat, a guide through the South Channel."},
]
