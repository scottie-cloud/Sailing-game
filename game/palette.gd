extends RefCounted
## Colours shared by the views.

const SEA := Color("1f6f9c")
## Solid colours, so overlapping strokes along the coast do not build up.
const SHALLOW_OUTER := Color("2a7fa6")
const SHALLOW_INNER := Color("3f97b3")
const LAND_FILL := Color("5d8a4a")
const LAND_EDGE := Color("e3d6a1")
## Waters not yet on the player's own chart.
const UNSURVEYED := Color("cdbb8f")
## Shoals: sand you can cross, sand you can cross only on the tide, and sand
## too shallow for the ship as she is now.
const SHOAL := Color("d9c98a")
const SHOAL_ON_TIDE := Color("f0a93a")
const SHOAL_TOO_SHALLOW := Color("e2553f")
## The next mark, the destination and the route.
const GOLD := Color("ffd24a")
## The course of the record passage.
const RECORD := Color("7fe7ff")
