#!/usr/bin/env python3
"""Builds WeatherCircles/Atlas.json — the country outlines and major-city
lists the area chart draws.

Source is Natural Earth (public domain): 1:50m admin-0 countries for the
coastlines, 1:10m populated places for the cities. Both are downloaded on
demand and cached in /tmp. Run it again to refresh:

    python3 scripts/make_atlas.py

The output is deliberately coarse — the chart wants a recognisable outline,
not a survey. Coordinates are stored as integer hundredths of a degree
(~1.1 km), which both shrinks the file and speeds up decoding; rings that
round away to nothing are dropped, as are specks well under a pixel at any
size we draw. Countries with far-flung territories (France, Norway, the
US) keep all their rings: the app picks the landmass you're actually
standing on at draw time, so the chart doesn't zoom out to fit Guyane.
"""

import json
import math
import os
import urllib.request

BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
COUNTRIES = "ne_50m_admin_0_countries.geojson"
PLACES = "ne_10m_populated_places_simple.geojson"

CITIES_PER_COUNTRY = 25
REMOTE_PER_COUNTRY = 12
# A ring is kept if it's a decent fraction of the country's biggest ring,
# OR big enough to stand on its own — Hawaii is a rounding error next to
# the American mainland, but it's the only land its own chart would have.
MIN_RING_FRACTION = 0.004
MIN_RING_DEGREES = 0.25          # bounding box side, roughly 25 km
OUT = os.path.join(os.path.dirname(__file__), "..", "WeatherCircles", "Atlas.json")


def load(name):
    cached = os.path.join("/tmp", name)
    if not os.path.exists(cached):
        print(f"downloading {name}…")
        urllib.request.urlretrieve(BASE + name, cached)
    with open(cached) as handle:
        return json.load(handle)


def ring_area(points):
    """Shoelace area in square degrees — only ever compared with itself."""
    total = 0.0
    for i in range(len(points)):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % len(points)]
        total += x1 * y2 - x2 * y1
    return abs(total) / 2


def quantise(points):
    """Hundredths of a degree, with runs of identical points collapsed."""
    out = []
    for x, y in points:
        pair = (round(x * 100), round(y * 100))
        if not out or out[-1] != pair:
            out.append(pair)
    if len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def iso_of(properties):
    for key in ("ISO_A2_EH", "ISO_A2", "WB_A2", "ADM0_A3"):
        code = properties.get(key)
        if code and code not in ("-99", "-", ""):
            return code
    return None


def build_countries():
    countries = {}
    for feature in load(COUNTRIES)["features"]:
        properties = feature["properties"]
        code = iso_of(properties)
        if not code:
            continue
        geometry = feature["geometry"]
        polygons = (geometry["coordinates"] if geometry["type"] == "MultiPolygon"
                    else [geometry["coordinates"]])
        rings = [polygon[0] for polygon in polygons]        # outer rings only
        if not rings:
            continue
        biggest = max(ring_area(ring) for ring in rings)
        kept = []
        for ring in rings:
            xs = [point[0] for point in ring]
            ys = [point[1] for point in ring]
            standalone = max(max(xs) - min(xs), max(ys) - min(ys)) >= MIN_RING_DEGREES
            if not standalone and biggest > 0 and ring_area(ring) < biggest * MIN_RING_FRACTION:
                continue
            points = quantise(ring)
            if len(points) >= 4:
                kept.append([value for pair in points for value in pair])
        if not kept:
            continue
        # Codes collide: Natural Earth files Australia's Ashmore and Cartier
        # Islands under AU as well, and a handful of other dependencies do
        # the same to their sovereign. Biggest landmass wins the code, which
        # is the one a chart of "the country I'm in" wants.
        entry = {
            "name": properties.get("NAME_EN") or properties.get("NAME") or code,
            "rings": kept,
            "_area": sum(ring_area(ring) for ring in rings),
        }
        if code not in countries or countries[code]["_area"] < entry["_area"]:
            countries[code] = entry
    for entry in countries.values():
        del entry["_area"]
    return countries


def build_cities():
    cities = {}
    for feature in load(PLACES)["features"]:
        properties = feature["properties"]
        code = properties.get("iso_a2")
        if not code or code in ("-99", "-", ""):
            continue
        population = properties.get("pop_max") or properties.get("pop_min") or 0
        cities.setdefault(code, []).append({
            "n": properties.get("name") or properties.get("nameascii") or "?",
            "y": round(float(properties["latitude"]), 3),
            "x": round(float(properties["longitude"]), 3),
            "p": int(population),
            "c": 1 if properties.get("adm0cap") else 0,
        })
    for code, places in cities.items():
        cities[code] = biggest_and_remotest(places)
    return cities


def biggest_and_remotest(places):
    """The country's biggest places, plus its loneliest ones.

    Population alone gives Australia nine coastal cities and nothing in
    the middle, which is exactly where a weather chart wants a reading —
    Alice Springs is only the 46th largest place in the country. So each
    place is also scored on how far it is from the nearest *bigger* place,
    and the most isolated few are kept whatever their size. Cheap, and it
    picks out the outback, the Sahara and the Amazon on its own.
    """
    ranked = sorted(places, key=lambda place: -place["p"])
    keep = {id(place): place for place in ranked[:CITIES_PER_COUNTRY]}
    for index, place in enumerate(ranked):
        bigger = ranked[:index]
        if not bigger:
            place["_lonely"] = 999.0
            continue
        shrink = max(0.15, math.cos(math.radians(place["y"])))
        place["_lonely"] = min(
            math.hypot((place["x"] - other["x"]) * shrink, place["y"] - other["y"])
            for other in bigger)
    for place in sorted(ranked, key=lambda place: -place["_lonely"])[:REMOTE_PER_COUNTRY]:
        keep[id(place)] = place
    out = sorted(keep.values(), key=lambda place: -place["p"])
    for place in out:
        place.pop("_lonely", None)
    return out


def main():
    atlas = {"countries": build_countries(), "cities": build_cities()}
    path = os.path.normpath(OUT)
    with open(path, "w") as handle:
        json.dump(atlas, handle, separators=(",", ":"))
    size = os.path.getsize(path)
    points = sum(len(ring) // 2 for country in atlas["countries"].values()
                 for ring in country["rings"])
    print(f"{path}: {size / 1024:.0f} KB, {len(atlas['countries'])} countries, "
          f"{points} outline points, "
          f"{sum(len(v) for v in atlas['cities'].values())} cities")


if __name__ == "__main__":
    main()
