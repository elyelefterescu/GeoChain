#!/usr/bin/env python3
"""Hărțile regiunilor pentru modul State/Județe: SUA (48 de state lipite), România (județele)
și Regatul Unit (Marea Britanie: comitatele Angliei, consiliile Scoției, zonele Țării Galilor).
Sursa: Natural Earth (domeniu public).

Pentru fiecare regiune <key> (usa, romania, uk):
  data/<key>.json              graful (ca world.json): nume RO/EN, capitale/reședințe, vecini pe uscat
  data/globe_<key>/ids.png     identificarea locurilor pe harta regiunii (R + 256 * G = index;
                               0 = în afara hărții, se vede globul lumii; B = 255 uscat în joc)
  data/globe_<key>/color.png   locurile gri deschis, lacurile albastre
  data/globe_<key>/index.json  lista locurilor, centrele lor și marginile regiunii (bounds)

Utilizare:
    python3 tools/build_regions.py <director> [key ...]
Fișiere necesare: ne_10m_admin_1_states_provinces_lakes.geojson și ne_50m_lakes.geojson.
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
# Cel puțin atâtea perechi de pixeli vecini ca două locuri să fie vecine (nu doar un colț, ca la Four Corners).
MIN_BORDER = 6

# ---------- SUA ----------
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
USA_ALIASES = {
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


def usa_unit(p):
    code = p["postal"]
    if p["adm0_a3"] != "USA":
        return None
    if code == "DC":
        code = "MD"  # Washington D.C. nu e stat; îl lăsăm în Maryland, ca să nu rămână o gaură
    if code not in STATES:
        return None  # Alaska, Hawaii
    ro, en, capital = STATES[code]
    return {"id": "US-" + code, "name_ro": ro, "name_en": en, "capital": capital,
            "aliases": USA_ALIASES.get(code, [])}


# ---------- România ----------
# nume Natural Earth: (nume RO, nume EN, reședința)
ROMANIA = {
    "Alba": ("Alba", "Alba", "Alba Iulia"), "Arad": ("Arad", "Arad", "Arad"),
    "Arges": ("Argeș", "Argeș", "Pitești"), "Bacau": ("Bacău", "Bacău", "Bacău"),
    "Bihor": ("Bihor", "Bihor", "Oradea"), "Bistrita-Nasaud": ("Bistrița-Năsăud", "Bistrița-Năsăud", "Bistrița"),
    "Botosani": ("Botoșani", "Botoșani", "Botoșani"), "Braila": ("Brăila", "Brăila", "Brăila"),
    "Brasov": ("Brașov", "Brașov", "Brașov"), "Bucharest": ("București", "Bucharest", "București"),
    "Buzau": ("Buzău", "Buzău", "Buzău"), "Calarasi": ("Călărași", "Călărași", "Călărași"),
    "Caras-Severin": ("Caraș-Severin", "Caraș-Severin", "Reșița"), "Cluj": ("Cluj", "Cluj", "Cluj-Napoca"),
    "Constanta": ("Constanța", "Constanța", "Constanța"), "Covasna": ("Covasna", "Covasna", "Sfântu Gheorghe"),
    "Dâmbovita": ("Dâmbovița", "Dâmbovița", "Târgoviște"), "Dolj": ("Dolj", "Dolj", "Craiova"),
    "Galati": ("Galați", "Galați", "Galați"), "Giurgiu": ("Giurgiu", "Giurgiu", "Giurgiu"),
    "Gorj": ("Gorj", "Gorj", "Târgu Jiu"), "Harghita": ("Harghita", "Harghita", "Miercurea Ciuc"),
    "Hunedoara": ("Hunedoara", "Hunedoara", "Deva"), "Ialomita": ("Ialomița", "Ialomița", "Slobozia"),
    "Iasi": ("Iași", "Iași", "Iași"), "Ilfov": ("Ilfov", "Ilfov", "Buftea"),
    "Maramures": ("Maramureș", "Maramureș", "Baia Mare"), "Mehedinti": ("Mehedinți", "Mehedinți", "Drobeta-Turnu Severin"),
    "Mures": ("Mureș", "Mureș", "Târgu Mureș"), "Neamt": ("Neamț", "Neamț", "Piatra Neamț"),
    "Olt": ("Olt", "Olt", "Slatina"), "Prahova": ("Prahova", "Prahova", "Ploiești"),
    "Salaj": ("Sălaj", "Sălaj", "Zalău"), "Satu Mare": ("Satu Mare", "Satu Mare", "Satu Mare"),
    "Sibiu": ("Sibiu", "Sibiu", "Sibiu"), "Suceava": ("Suceava", "Suceava", "Suceava"),
    "Teleorman": ("Teleorman", "Teleorman", "Alexandria"), "Timis": ("Timiș", "Timiș", "Timișoara"),
    "Tulcea": ("Tulcea", "Tulcea", "Tulcea"), "Vaslui": ("Vaslui", "Vaslui", "Vaslui"),
    "Vâlcea": ("Vâlcea", "Vâlcea", "Râmnicu Vâlcea"), "Vrancea": ("Vrancea", "Vrancea", "Focșani"),
}


def romania_unit(p):
    if p["adm0_a3"] != "ROU":
        return None
    ro, en, capital = ROMANIA[p["name"]]
    aliases = ["Bucuresti", "Municipiul București", "Bucharest"] if p["name"] == "Bucharest" else []
    return {"id": "RO-" + re.sub("[^A-Z]", "", p["iso_3166_2"].split("-")[1]), "name_ro": ro, "name_en": en,
            "capital": capital, "aliases": aliases + ([en] if en != ro else [])}


# ---------- Regatul Unit (doar Marea Britanie: Irlanda de Nord nu are graniță pe uscat cu ea) ----------
# Anglia: comitatele ceremoniale (unitățile Natural Earth se adună în ele). Scoția: consiliile.
# Țara Galilor: zonele principale. Fără insulele legate doar cu vaporul (Wight, Orkney, Shetland, Hebridele Exterioare).
UK_SKIP = {"GB-IOW", "GB-ELS", "GB-ORK", "GB-ZET"}
# Unde region_sub din Natural Earth nu e comitatul ceremonial.
UK_FIX = {
    "GB-BAS": "Somerset", "GB-NSM": "Somerset", "GB-SGC": "Gloucestershire", "GB-BST": "Bristol",
    "GB-ERY": "East Riding of Yorkshire", "GB-KHL": "East Riding of Yorkshire",
    "GB-NEL": "Lincolnshire", "GB-NLN": "Lincolnshire", "GB-WRL": "Merseyside", "GB-SHN": "Merseyside",
    "GB-MDB": "North Yorkshire", "GB-RCC": "North Yorkshire", "GB-LND": "Greater London",
    "GB-IOS": "Cornwall",
}
UK_RO = {"Greater London": "Londra Mare", "Kent": "Kent", "Cornwall": "Cornwall"}
UK_ALIASES = {"Greater London": ["Londra", "London"], "North Ayshire": ["North Ayrshire"],
              "Perthshire and Kinross": ["Perth and Kinross"], "Rhondda, Cynon, Taff": ["Rhondda Cynon Taf"]}
UK_NAMES = {"North Ayshire": "North Ayrshire", "Perthshire and Kinross": "Perth and Kinross",
            "Rhondda, Cynon, Taff": "Rhondda Cynon Taf"}
# Legături peste ape înguste, cu pod: Anglesey are poduri spre Gwynedd.
# Plus granițe reale foarte scurte, sub pragul de pixeli: Rutland–Cambridgeshire (Peterborough).
UK_BRIDGES = [("Anglesey", "Gwynedd"), ("Rutland", "Cambridgeshire")]


def uk_unit(p):
    if p["adm0_a3"] != "GBR" or p["geonunit"] == "Northern Ireland" or p["iso_3166_2"] in UK_SKIP:
        return None
    if p["geonunit"] == "England":
        name = UK_FIX.get(p["iso_3166_2"], p["region_sub"])
    else:
        name = p["name"]
    shown = UK_NAMES.get(name, name)
    slug = re.sub("[^A-Z]", "", shown.upper())[:10]
    return {"id": "UK-" + slug, "name_ro": UK_RO.get(shown, shown), "name_en": shown, "capital": "",
            "aliases": UK_ALIASES.get(name, []) + ([shown] if UK_RO.get(shown, shown) != shown else [])}


REGIONS = {
    "usa": {"unit": usa_unit, "bounds": (-127.0, 23.0, -65.0, 50.5), "size": (3072, 1344), "known": KNOWN},
    "romania": {"unit": romania_unit, "bounds": (19.8, 43.4, 30.2, 48.6), "size": (2048, 1408)},
    "uk": {"unit": uk_unit, "bounds": (-8.8, 49.6, 2.4, 59.4), "size": (1792, 2304), "bridges": UK_BRIDGES, "min_border": 2},
}


def polygons(geom):
    return [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]


def build(key, cfg, admin, lakes):
    lon0, lat0, lon1, lat1 = cfg["bounds"]
    W, H = cfg["size"]

    def to_px(ring):
        return [((lon - lon0) / (lon1 - lon0) * W, (lat1 - lat) / (lat1 - lat0) * H) for lon, lat in ring]

    def fill(draw, geom, value):
        for poly in polygons(geom):
            draw.polygon(to_px(poly[0]), fill=value)
            for hole in poly[1:]:
                draw.polygon(to_px(hole), fill=0)

    units = []
    for f in admin:
        u = cfg["unit"](f["properties"])
        if u:
            units.append((u, f))
    nodes = {}
    for u, f in units:
        nodes.setdefault(u["id"], u)
    ids = sorted(nodes, key=lambda i: nodes[i]["name_en"])
    index = {nid: i + 1 for i, nid in enumerate(ids)}
    water = len(ids) + 1  # lacurile

    layer = Image.new("I", (W, H), 0)
    draw = ImageDraw.Draw(layer)
    for f in lakes:
        fill(draw, f["geometry"], water)
    for u, f in units:
        fill(draw, f["geometry"], index[u["id"]])
    grid = np.array(layer, dtype=np.int32)

    # Vecinii: perechi de pixeli alăturați din locuri diferite.
    n = len(ids)
    pairs = {}
    for a, b in ((grid[:, :-1], grid[:, 1:]), (grid[:-1, :], grid[1:, :])):
        m = (a != b) & (a >= 1) & (a <= n) & (b >= 1) & (b <= n)
        for x, y in zip(a[m], b[m]):
            k = (min(x, y), max(x, y))
            pairs[k] = pairs.get(k, 0) + 1
    least = cfg.get("min_border", MIN_BORDER)
    edges = {tuple(sorted((ids[x - 1], ids[y - 1]))) for (x, y), c in pairs.items() if c >= least}
    weak = sorted((ids[x - 1], ids[y - 1], c) for (x, y), c in pairs.items() if c < least)
    by_name = {nodes[i]["name_en"]: i for i in ids}
    for a, b in cfg.get("bridges", []):
        edges.add(tuple(sorted((by_name[a], by_name[b]))))
    if "known" in cfg:
        known = {tuple(sorted(("US-" + line.split()[0], "US-" + b))) for line in cfg["known"].splitlines()
                 for b in line.split()[1:]}
        if edges != known:
            sys.exit(f"{key}: granițe diferite de cele cunoscute: lipsă {sorted(known - edges)}, în plus {sorted(edges - known)}")
    # Fiecare loc trebuie să poată fi atins de oriunde.
    adj = {i: set() for i in ids}
    for a, b in edges:
        adj[a].add(b)
        adj[b].add(a)
    seen, queue = {ids[0]}, [ids[0]]
    for x in queue:
        for y in adj[x] - seen:
            seen.add(y)
            queue.append(y)
    if len(seen) != n:
        sys.exit(f"{key}: locuri fără legătură: {sorted(set(ids) - seen)}")
    print(f"{key}: {n} locuri, {len(edges)} granițe; ignorate (doar un colț): {weak}")

    # Centrul (unde stă numele): pixelul locului cel mai apropiat de mijlocul lui.
    centers = {}
    ys, xs = np.nonzero((grid >= 1) & (grid <= n))
    vals = grid[ys, xs]
    for i, nid in enumerate(ids):
        sel = vals == i + 1
        px, py = xs[sel], ys[sel]
        cx, cy = px.mean(), py.mean()
        j = np.argmin((px - cx) ** 2 + (py - cy) ** 2)
        centers[nid] = [round(lat1 - (py[j] + 0.5) / H * (lat1 - lat0), 3),
                        round(lon0 + (px[j] + 0.5) / W * (lon1 - lon0), 3)]

    graph = {"version": 1, "region": key, "continents": [],
             "source": "Natural Earth (domeniu public): ne_10m_admin_1_states_provinces_lakes, ne_50m_lakes",
             "nodes": [{"id": i, "type": "country", "name_ro": nodes[i]["name_ro"], "name_en": nodes[i]["name_en"],
                        "aliases": nodes[i]["aliases"], "continents": [],
                        "capital": nodes[i]["capital"], "capital_ro": nodes[i]["capital"]} for i in ids],
             "gates": [], "edges": [{"a": a, "b": b} for a, b in sorted(edges)]}
    graph["edges_detailed"] = graph["edges"]
    (ROOT / "data" / f"{key}.json").write_text(json.dumps(graph, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    out = ROOT / "data" / f"globe_{key}"
    out.mkdir(parents=True, exist_ok=True)
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    rgb[..., 0] = grid & 255
    rgb[..., 1] = grid >> 8
    rgb[..., 2] = np.where((grid >= 1) & (grid <= n), 255, 0)
    Image.fromarray(rgb, "RGB").save(out / "ids.png", optimize=True)
    lut = np.zeros((water + 1, 3), dtype=np.uint8)
    lut[1:water] = (226, 226, 222)
    lut[water] = (22, 58, 110)
    Image.fromarray(lut[grid], "RGB").save(out / "color.png", optimize=True)
    (out / "index.json").write_text(json.dumps({
        "width": W, "height": H, "bounds": list(cfg["bounds"]), "ids": ids + [key.upper() + "_LAKES"],
        "centers": centers}, ensure_ascii=False) + "\n", encoding="utf-8")
    for imp in ("ids", "color"):
        (out / f"{imp}.png.import").write_text("[remap]\n\nimporter=\"keep\"\n", encoding="utf-8")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    admin = json.loads((src / "ne_10m_admin_1_states_provinces_lakes.geojson").read_text(encoding="utf-8"))["features"]
    lakes = json.loads((src / "ne_50m_lakes.geojson").read_text(encoding="utf-8"))["features"]
    for key in sys.argv[2:] or REGIONS:
        build(key, REGIONS[key], admin, lakes)


if __name__ == "__main__":
    main()
