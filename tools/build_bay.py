#!/usr/bin/env python3
"""Builds game/bay_data.gd: the coastline of Port Phillip Bay for the game.

    pip install shapely mapbox-earcut numpy
    python3 tools/build_bay.py tools/source/port_phillip_land.geojson game/bay_data.gd

Source: tools/source/port_phillip_land.geojson, the land around the bay cut
from GSHHG, the Global Self-consistent, Hierarchical, High-resolution
Geography database (Wessel and Smith), at full resolution. GSHHG is
distributed under the GNU Lesser General Public License.

Ports are not part of this: they are listed in data/ports.gd.

The coast is clipped to the bay and projected to game pixels (400 px = 1
nautical mile, north up). Rivers and creeks too narrow to sail are closed
off, lakes are filled in, corners are rounded a little, and the land is cut
into triangles for drawing. A coarse grid of land and water is written too,
so the game can answer most "is this land?" questions without looking at
the whole coastline.
"""
import json
import math
import sys

import mapbox_earcut
import numpy as np
from shapely.geometry import Polygon, box, shape
from shapely.ops import unary_union
from shapely.prepared import prep

WEST, SOUTH, EAST, NORTH = 144.30, -38.42, 145.20, -37.78
PX_PER_NM = 400.0
LON_SCALE = math.cos(math.radians((SOUTH + NORTH) / 2.0))
# Water narrower than twice this (px) is closed off: about 280 metres across.
CLOSE_GAPS = 30.0
# Water cut off from the sea and smaller than this (px squared) is a lake: filled in.
SMALLEST_SEA = 2.0e6
# Size (px) of the squares in the coarse land-or-water grid.
GRID_CELL = 100
# Islets smaller than this (px squared) are left off: about a hectare and a half.
SMALLEST_ISLAND = 700.0


def to_px(lon, lat):
    return ((lon - WEST) * LON_SCALE * 60.0 * PX_PER_NM, (NORTH - lat) * 60.0 * PX_PER_NM)


WIDTH, HEIGHT = to_px(EAST, SOUTH)


def on_edge(p):
    return min(abs(p[0]), abs(p[0] - WIDTH), abs(p[1]), abs(p[1] - HEIGHT)) < 0.5


def chaikin(ring):
    """Rounds corners, leaving points on the map edge where they are."""
    out = []
    count = len(ring)
    for i in range(count):
        a, b = ring[i], ring[(i + 1) % count]
        if on_edge(a):
            out.append(a)
        else:
            out.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
        if not on_edge(b):
            out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
    return out


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        return [geometry]
    return [g for g in getattr(geometry, "geoms", []) if g.geom_type == "Polygon"]


def main(source, target):
    world = box(0.0, 0.0, WIDTH, HEIGHT)
    lonlat_box = box(WEST, SOUTH, EAST, NORTH)
    source_land = shape(json.load(open(source))).intersection(lonlat_box)
    pieces = []
    for polygon in polygons(source_land):
        exterior = [to_px(lon, lat) for lon, lat in polygon.exterior.coords]
        holes = [[to_px(lon, lat) for lon, lat in hole.coords] for hole in polygon.interiors]
        pieces.append(Polygon(exterior, holes).buffer(0))
    land = unary_union(pieces).intersection(world)

    # Close off narrow creeks, then fill in whatever water that leaves stranded.
    land = land.buffer(CLOSE_GAPS).buffer(-CLOSE_GAPS).intersection(world)
    for water in polygons(world.difference(land)):
        if water.area < SMALLEST_SEA:
            land = land.union(water)
    land = land.buffer(0)

    rings = []
    triangles = []
    for polygon in polygons(land):
        if polygon.area < SMALLEST_ISLAND:
            continue
        ring = chaikin([(x, y) for x, y in polygon.exterior.coords[:-1]])
        smooth = Polygon(ring).buffer(0).intersection(world).simplify(5.0)
        for part in polygons(smooth):
            if part.area < SMALLEST_ISLAND:
                continue
            points = [(round(x), round(y)) for x, y in part.exterior.coords[:-1]]
            rings.append(points)
            vertices = np.array(points, dtype=np.float64)
            indices = mapbox_earcut.triangulate_float64(vertices, np.array([len(points)], dtype=np.uint32))
            for t in range(0, len(indices), 3):
                a, b, c = (points[i] for i in indices[t:t + 3])
                # Leave out slivers with no area: there is nothing to draw.
                if abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) >= 2:
                    triangles.extend((a, b, c))

    # A coarse grid over the chart so the game can tell at once whether a
    # point is plainly land (L), plainly water (W) or near the shore (M).
    final_land = prep(unary_union([Polygon(ring) for ring in rings]))
    grid_rows = []
    for j in range(math.ceil(HEIGHT / GRID_CELL)):
        row = ""
        for i in range(math.ceil(WIDTH / GRID_CELL)):
            cell = box(i * GRID_CELL, j * GRID_CELL, (i + 1) * GRID_CELL, (j + 1) * GRID_CELL)
            row += "L" if final_land.contains(cell) else ("M" if final_land.intersects(cell) else "W")
        grid_rows.append(row)

    def vectors(points):
        return ", ".join("Vector2(%d, %d)" % p for p in points)

    lines = [
        "extends RefCounted",
        "## Generated by tools/build_bay.py: do not edit by hand.",
        "## Port Phillip Bay coastline from GSHHG full resolution (Wessel and Smith, LGPL).",
        "",
        "const SIZE := Vector2(%d, %d)" % (round(WIDTH), round(HEIGHT)),
        "const WEST := %.4f" % WEST,
        "const NORTH := %.4f" % NORTH,
        "const PX_PER_DEGREE_LON := %.4f" % (LON_SCALE * 60.0 * PX_PER_NM),
        "const PX_PER_DEGREE_LAT := %.4f" % (60.0 * PX_PER_NM),
        "",
    ]
    lines += ["## Coastline outlines, one closed ring per piece of land.", "const LAND_RINGS := ["]
    for ring in rings:
        lines.append("\t[%s]," % vectors(ring))
    lines += ["]", "", "## The same land cut into triangles: three points each.", "const LAND_TRIANGLES := ["]
    for i in range(0, len(triangles), 30):
        lines.append("\t%s," % vectors(triangles[i:i + 30]))
    lines += ["]", "", "## One letter per %d px square, row by row from the north:" % GRID_CELL,
              "## L all land, W all water, M the shore runs through it.",
              "const LAND_GRID_CELL := %d" % GRID_CELL, "const LAND_GRID := ["]
    for row in grid_rows:
        lines.append('\t"%s",' % row)
    lines += ["]", ""]
    open(target, "w").write("\n".join(lines))
    print("size", round(WIDTH), round(HEIGHT), "rings", [len(r) for r in rings], "triangles", len(triangles) // 3)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
