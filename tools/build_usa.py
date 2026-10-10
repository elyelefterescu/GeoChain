#!/usr/bin/env python3
"""Harta SUA: cele 48 de state lipite (fără Alaska și Hawaii), din Natural Earth (domeniu public).

Ieșiri:
  data/usa.json              graful statelor (ca world.json): nume RO/EN, capitale, vecini pe uscat
  data/globe_usa/ids.png     identificarea statelor pe o hartă doar a regiunii SUA (R + 256 * G = index;
                             0 = în afara hărții, se vede globul lumii; B = 255 uscat al unui stat)
  data/globe_usa/color.png   statele gri deschis, lacurile albastre
  data/globe_usa/index.json  lista statelor, centrele lor și marginile regiunii (bounds)

Utilizare:
    python3 tools/build_usa.py <director>
Fișiere necesare: usa_states_10m.geojson (statele SUA din ne_10m_admin_1_states_provinces_lakes)
și ne_50m_lakes.geojson.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
# lon_min, lat_min, lon_max, lat_max
BOUNDS = (-127.0, 23.0, -65.0, 50.5)
W, H = 3072, 1344
# Cel puțin atâtea perechi de pixeli vecini ca două state să fie vecine (nu doar un colț, ca la Four Corners).
MIN_BORDER = 6

# postal: (nume RO, nume EN, capitală)
STATES = {
    "AL": ("Alabama", "Alabama", "Montgomery"), "AZ": ("Arizona", "Arizona", "Phoenix"),
    "AR": ("Arkansas", "Arkansas", "Little Rock"), "CA": ("California", "California", "Sacramento"),
    "CO": ("Colorado", "Colorado", "Denver"), "CT": ("Connecticut", "Connecticut", "Hartford"),
    "DE": ("Delaware", "Delaware", "Dover"), "FL": ("Florida", "Florida", "Tallahassee"),
    "GA": ("Georgia", "Georgia", "Atlanta"), "ID": ("Idaho", "Idaho", "Boise"),
    "IL": ("Illinois", "Illinois", "Springfield"), "IN": ("Indiana", "Indiana", "Indianapolis"),
    "IA": ("Iowa", "Iowa", "Des Moines"), "KS": ("Kansas", "Kansas", "Topeka"),
    "KY": ("Kentucky", "Kentucky", "Frankfort"), "LA": ("Louisiana", "Louisiana", "Baton Rouge"),
    "ME": ("Maine", "Maine", "Augusta"), "MD": ("Maryland", "Maryland", "Annapolis"),
    "MA": ("Massachusetts", "Massachusetts", "Boston"), "MI": ("Michigan", "Michigan", "Lansing"),
    "MN": ("Minnesota", "Minnesota", "Saint Paul"), "MS": ("Mississippi", "Mississippi", "Jackson"),
    "MO": ("Missouri", "Missouri", "Jefferson City"), "MT": ("Montana", "Montana", "Helena"),
    "NE": ("Nebraska", "Nebraska", "Lincoln"), "NV": ("Nevada", "Nevada", "Carson City"),
    "NH": ("New Hampshire", "New Hampshire", "Concord"), "NJ": ("New Jersey", "New Jersey", "Trenton"),
    "NM": ("New Mexico", "New Mexico", "Santa Fe"), "NY": ("New York", "New York", "Albany"),
    "NC": ("Carolina de Nord", "North Carolina", "Raleigh"), "ND": ("Dakota de Nord", "North Dakota", "Bismarck"),
    "OH": ("Ohio", "Ohio", "Columbus"), "OK": ("Oklahoma", "Oklahoma", "Oklahoma City"),
    "OR": ("Oregon", "Oregon", "Salem"), "PA": ("Pennsylvania", "Pennsylvania", "Harrisburg"),
    "RI": ("Rhode Island", "Rhode Island", "Providence"), "SC": ("Carolina de Sud", "South Carolina", "Columbia"),
    "SD": ("Dakota de Sud", "South Dakota", "Pierre"), "TN": ("Tennessee", "Tennessee", "Nashville"),
    "TX": ("Texas", "Texas", "Austin"), "UT": ("Utah", "Utah", "Salt Lake City"),
    "VT": ("Vermont", "Vermont", "Montpelier"), "VA": ("Virginia", "Virginia", "Richmond"),
    "WA": ("Washington", "Washington", "Olympia"), "WV": ("Virginia de Vest", "West Virginia", "Charleston"),
    "WI": ("Wisconsin", "Wisconsin", "Madison"), "WY": ("Wyoming", "Wyoming", "Cheyenne"),
}
ALIASES = {
    "NC": ["Carolina de Nord", "North Carolina", "Carolina Nord"], "SC": ["Carolina de Sud", "Carolina Sud"],
    "ND": ["Dakota Nord"], "SD": ["Dakota Sud"], "WV": ["Virginia Vest"],
    "NM": ["Noul Mexic"], "NY": ["Statul New York"], "NJ": ["Noul Jersey"], "PA": ["Pensilvania"],
    "LA": ["Luisiana"], "MA": ["Massachussetts"], "CA": ["Californa"],
}
# Granițele pe uscat cunoscute (pentru verificare): 105 perechi. Fără colțuri (Four Corners)
# și fără granițe doar pe apă (Michigan–Minnesota, New York–Rhode Island).
KNOWN = """AL FL GA MS TN
AZ CA NV UT NM
AR LA MS MO OK TN TX
CA NV OR
CO KS NE NM OK UT WY
CT MA NY RI
DE MD NJ PA
GA FL NC SC TN
ID MT NV OR UT WA WY
IL IN IA KY MO WI
IN KY MI OH
IA MN MO NE SD WI
KS MO NE OK
KY MO OH TN VA WV
LA MS TX
ME NH
MD PA VA WV
MA NH NY RI VT
MI OH WI
MN ND SD WI
MS TN
MO NE OK TN
MT ND SD WY
NE SD WY
NV OR UT
NH VT
NJ NY PA
NM OK TX
NY PA VT
NC SC TN VA
ND SD
OH PA WV
OK TX
OR WA
PA WV
SD WY
TN VA
UT WY
VA WV"""


def to_px(ring):
    lon0, lat0, lon1, lat1 = BOUNDS
    return [((lon - lon0) / (lon1 - lon0) * W, (lat1 - lat) / (lat1 - lat0) * H) for lon, lat in ring]


def polygons(geom):
    return [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]


def fill(draw, geom, value):
    for poly in polygons(geom):
        draw.polygon(to_px(poly[0]), fill=value)
        for hole in poly[1:]:
            draw.polygon(to_px(hole), fill=0)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    codes = sorted(STATES, key=lambda c: STATES[c][1])
    ids = ["US-" + c for c in codes]
    index = {c: i + 1 for i, c in enumerate(codes)}
    water = len(codes) + 1  # lacurile (Marile Lacuri și altele)

    layer = Image.new("I", (W, H), 0)
    draw = ImageDraw.Draw(layer)
    lon0, lat0, lon1, lat1 = BOUNDS
    for f in json.loads((src / "ne_50m_lakes.geojson").read_text(encoding="utf-8"))["features"]:
        fill(draw, f["geometry"], water)
    states = json.loads((src / "usa_states_10m.geojson").read_text(encoding="utf-8"))["features"]
    centers = {}
    for f in states:
        p = f["properties"]
        code = p["postal"]
        if code == "DC":
            code = "MD"  # Washington D.C. nu e stat; îl lăsăm în Maryland, ca să nu rămână o gaură
        if code not in index:
            continue  # Alaska, Hawaii
        fill(draw, f["geometry"], index[code])
        if p["postal"] != "DC":
            centers["US-" + code] = [round(p["latitude"], 3), round(p["longitude"], 3)]
    grid = np.array(layer, dtype=np.int32)

    # Vecinii: perechi de pixeli alăturați din state diferite.
    pairs = {}
    for a, b in ((grid[:, :-1], grid[:, 1:]), (grid[:-1, :], grid[1:, :])):
        m = (a != b) & (a >= 1) & (a <= len(codes)) & (b >= 1) & (b <= len(codes))
        for x, y in zip(a[m], b[m]):
            key = (min(x, y), max(x, y))
            pairs[key] = pairs.get(key, 0) + 1
    edges = sorted(tuple(sorted((codes[x - 1], codes[y - 1]))) for (x, y), n in pairs.items() if n >= MIN_BORDER)
    weak = sorted((codes[x - 1], codes[y - 1], n) for (x, y), n in pairs.items() if n < MIN_BORDER)
    print(f"{len(edges)} granițe; ignorate (doar un colț): {weak}")
    known = {tuple(sorted((line.split()[0], b))) for line in KNOWN.splitlines() for b in line.split()[1:]}
    if set(edges) != known:
        sys.exit(f"Granițe diferite de cele cunoscute: lipsă {sorted(known - set(edges))}, în plus {sorted(set(edges) - known)}")

    nodes = []
    for c in codes:
        ro, en, capital = STATES[c]
        nodes.append({"id": "US-" + c, "type": "country", "name_ro": ro, "name_en": en,
                      "aliases": ALIASES.get(c, []), "continents": [], "postal": c,
                      "capital": capital, "capital_ro": capital})
    graph = {"version": 1, "region": "usa", "continents": [],
             "source": "Natural Earth (domeniu public): ne_10m_admin_1_states_provinces_lakes, ne_50m_lakes",
             "nodes": nodes, "gates": [],
             "edges": [{"a": "US-" + a, "b": "US-" + b} for a, b in edges]}
    graph["edges_detailed"] = graph["edges"]
    (ROOT / "data" / "usa.json").write_text(json.dumps(graph, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    out = ROOT / "data" / "globe_usa"
    out.mkdir(parents=True, exist_ok=True)
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    rgb[..., 0] = grid & 255
    rgb[..., 1] = grid >> 8
    rgb[..., 2] = np.where((grid >= 1) & (grid <= len(codes)), 255, 0)
    Image.fromarray(rgb, "RGB").save(out / "ids.png", optimize=True)
    lut = np.zeros((water + 1, 3), dtype=np.uint8)
    lut[1:water] = (226, 226, 222)
    lut[water] = (22, 58, 110)
    Image.fromarray(lut[grid], "RGB").save(out / "color.png", optimize=True)
    (out / "index.json").write_text(json.dumps({
        "width": W, "height": H, "bounds": list(BOUNDS), "ids": ids + ["US_LAKES"], "centers": centers,
    }, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{out}: {len(ids)} state")


if __name__ == "__main__":
    main()
