extends RefCounted
## Shallow water. Each shoal is an outline of real longitudes and latitudes
## and a depth at low water in metres; the tide adds up to 0.9 m on top.
## A ship that draws more than the water over a shoal runs aground on it.
##
## The outlines and depths are set down from general knowledge of the bay,
## not from a chart: they put the sands and channels in roughly the right
## places and no more. Between the West Sand and the Middle Ground runs the
## Symonds Channel; south of both, along the Sorrento shore, the South
## Channel; west of the West Sand, under the Bellarine shore, the West Channel.

const SHOALS := [
	{"name": "West Sand", "depth": 2.0,
		"note": "Part of the Great Sands inside the Heads. The Mud Islands stand on it.",
		"outline": [[144.745, -38.200], [144.800, -38.205], [144.815, -38.275], [144.770, -38.295], [144.740, -38.270]]},
	{"name": "Middle Ground", "depth": 2.0,
		"note": "The eastern half of the Great Sands, with the South Channel along its southern edge.",
		"outline": [[144.830, -38.235], [144.905, -38.255], [144.915, -38.300], [144.850, -38.305], [144.825, -38.280]]},
	{"name": "Prince George Bank", "depth": 2.5,
		"note": "A bank off Indented Head, on the way between Geelong and the Heads.",
		"outline": [[144.730, -38.105], [144.775, -38.100], [144.785, -38.135], [144.745, -38.145]]},
	{"name": "Swan Bay flats", "depth": 1.0,
		"note": "Swan Bay is all shallows: water for a dinghy, and that only on the tide.",
		"outline": [[144.615, -38.195], [144.690, -38.185], [144.700, -38.232], [144.672, -38.257], [144.625, -38.255]]},
	{"name": "Point Henry bar", "depth": 2.8,
		"note": "The bar across the way in to Geelong. Until a channel was cut through it, large ships lightened their cargo here or waited for the tide.",
		"outline": [[144.425, -38.150], [144.447, -38.150], [144.457, -38.060], [144.435, -38.060]]},
]
