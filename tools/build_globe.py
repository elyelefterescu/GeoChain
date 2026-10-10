#!/usr/bin/env python3
"""Generează texturile globului din contururile Natural Earth (domeniu public).

Ieșiri în data/globe/:
  ids.png    hartă ascunsă de identificare: fiecare pixel spune ce loc e acolo
             (R + 256 * G = indexul locului, 0 = teritoriu neutru; B = 255 pe uscat)
  color.png  harta de bază, fără nume: țările gri deschis, teritoriile neutre gri mai închis,
             apa albastru închis (culorile rămân libere pentru traseu)
  index.json lista locurilor în ordinea indexurilor, cu centrul fiecăruia

Utilizare:
    python3 tools/build_globe.py <director cu fișierele .geojson Natural Earth>
Fișiere necesare (din github.com/nvkelso/natural-earth-vector/tree/master/geojson):
    ne_50m_admin_0_countries.geojson, ne_50m_geography_marine_polys.geojson
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

W, H = 4096, 2048
ROOT = Path(__file__).resolve().parent.parent

# Coduri Natural Earth care diferă de cele din world.json.
NE_CODES = {"SDS": "SSD"}

# Numele mărilor din Natural Earth -> apele noastre. None = se decide după poziție.
MARINE = {
    "W_MED": ["Mediterranean Sea", "Balearic Sea", "Golfe du Lion", "Strait of Gibraltar"],
    "W_ADR": ["Adriatic Sea"], "W_EGE": ["Aegean Sea"], "W_ION": ["Ionian Sea"], "W_TYR": ["Tyrrhenian Sea"],
    "W_BLK": ["Black Sea"], "W_RED": ["Red Sea"], "W_ADN": ["Gulf of Aden"], "W_GUL": ["Persian Gulf"],
    "W_OMG": ["Gulf of Oman"], "W_CAS": ["Caspian Sea"],
    "W_IND": ["INDIAN OCEAN", "Arabian Sea", "Bay of Bengal", "Laccadive Sea", "Andaman Sea", "Gulf of Mannar",
              "Gulf of Kutch", "Mozambique Channel", "Timor Sea", "Great Australian Bight", "Strait of Malacca"],
    "W_BAL": ["Baltic Sea", "Gulf of Finland"], "W_BOT": ["Gulf of Bothnia"], "W_NRT": ["North Sea"],
    "W_MAN": ["English Channel"],
    "W_ATL": ["North Atlantic Ocean", "South Atlantic Ocean", "Irish Sea", "Bristol Channel", "Bay of Biscay",
              "Sargasso Sea", "Gulf of Guinea", "Labrador Sea", "Gulf of Saint Lawrence", "Gulf of Maine",
              "Bay of Fundy", "Chesapeake Bay", "Río de la Plata", "Golfo San Jorge", "Amazon River", "Norwegian Sea",
              "Inner Seas"],  # Inner Seas = apele de pe coasta de vest a Scoției
    "W_CAR": ["Caribbean Sea", "Gulf of Honduras"],
    "W_MEX": ["Gulf of Mexico", "Bahía de Campeche", "Straits of Florida"],
    "W_PAC": ["North Pacific Ocean", "South Pacific Ocean", "Philippine Sea", "Coral Sea", "Tasman Sea",
              "Solomon Sea", "Bismarck Sea", "Gulf of Alaska", "Bering Sea", "Golfo de California",
              "Golfo de Panamá", "Bay of Plenty", "Celebes Sea", "Sulu Sea", "Molucca Sea", "Banda Sea",
              "Ceram Sea", "Arafura Sea", "Gulf of Carpentaria", "Great Barrier Reef", "Sea of Okhotsk",
              "Shelikhova Gulf", "Cook Inlet", "Bristol Bay", "Makassar Strait", "Java Sea", "Columbia River",
              "Luzon Strait", "Inner Sea"],  # Inner Sea = Marea Interioară Seto, Japonia
    "W_SCS": ["South China Sea", "Gulf of Thailand", "Gulf of Tonkin", "Strait of Singapore"],
    "W_ECS": ["East China Sea", "Yellow Sea", "Bo Hai", "Taiwan Strait", "Yangtze River"],
    "W_JPN": ["Sea of Japan", "Korea Strait"],
    "W_ARC": ["Arctic Ocean", "Barents Sea", "Kara Sea", "Laptev Sea", "Chukchi Sea", "Beaufort Sea", "White Sea",
              "Hudson Bay", "James Bay", "Hudson Strait", "Ungava Bay", "Amundsen Gulf", "Viscount Melville Sound",
              "The North Western Passages", "Melville Bay", "Greenland Sea", "Baffin Bay", "Davis Strait"],
}
# Mări mici care lipsesc din Natural Earth la scara 50m: dreptunghiuri (lat_min, lat_max, lon_min, lon_max)
# aplicate doar pe apa încă neatribuită sau atribuită mării din jur.
BOXES = {
    "W_MAR": (40.25, 41.15, 26.6, 29.95, ["W_BLK", "W_EGE"]),
    "W_AZO": (45.2, 47.35, 34.8, 39.4, ["W_BLK"]),
    # Kattegatul e inclus de Natural Earth în Atlantic; ține de Marea Nordului, ca Skagerrakul.
    "W_NRT": (55.9, 57.8, 10.3, 12.9, []),
    # Centura Mare și Centura Mică duc spre Baltica.
    "W_BAL": (54.8, 55.9, 9.6, 12.0, []),
    # Lacul Maracaibo se varsă în Marea Caraibilor, nu în Pacific.
    "W_CAR": (8.5, 11.8, -72.6, -70.4, []),
    # Golfurile adânci din vestul Golfului Hudson țin de Oceanul Arctic.
    "W_ARC": (63.0, 66.8, -97.0, -86.0, []),
}
# Centrele apelor (lat, lon), unde se rotește globul când ajungi acolo.
WATER_CENTERS = {
    "W_ATL": (15, -40), "W_IND": (-15, 75), "W_ARC": (80, 0), "W_PAC": (5, -160), "W_MED": (35, 18),
    "W_BLK": (43.3, 34.5), "W_RED": (20, 38.5), "W_NRT": (56, 3.5), "W_BAL": (57, 19.5), "W_CAS": (42, 50.5),
    "W_GUL": (27, 51.5), "W_CAR": (15, -75), "W_MEX": (25, -90), "W_SCS": (12, 114), "W_ECS": (30, 125),
    "W_JPN": (40, 135), "W_ADR": (43, 15.5), "W_ION": (38, 19), "W_TYR": (40, 12), "W_EGE": (39, 25),
    "W_MAR": (40.7, 28.2), "W_AZO": (46.2, 36.7), "W_ADN": (12.5, 48), "W_OMG": (24.5, 58.5),
    "W_MAN": (50.2, -2), "W_BOT": (63, 20.5),
}


# Cât de departe (în pixeli, ~0,09° fiecare) se întinde o mare numită peste apa nenumită de lângă ea.
NEAREST_SEA_PX = 60


def fallback_ocean(lat, lon):
    """Oceanul pentru apa pe care Natural Earth nu o numește (ex. Oceanul de Sud)."""
    ocean = np.full(lat.shape, "W_PAC", dtype=object)
    ocean[(lon >= -70) & (lon <= 20)] = "W_ATL"
    ocean[(lon > 20) & (lon <= 147)] = "W_IND"
    ocean[lat > 66] = "W_ARC"
    return ocean


def to_px(ring):
    return [((lon + 180) / 360 * W, (90 - lat) / 180 * H) for lon, lat in ring]


def polygons(geom):
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    if geom["type"] == "MultiPolygon":
        return geom["coordinates"]
    return []


def fill(draw, geom, value):
    for poly in polygons(geom):
        draw.polygon(to_px(poly[0]), fill=value)
        for hole in poly[1:]:
            draw.polygon(to_px(hole), fill=0)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    world = json.loads((ROOT / "data" / "world.json").read_text(encoding="utf-8"))
    node_ids = [n["id"] for n in world["nodes"]]
    countries = {n["id"] for n in world["nodes"] if n["type"] == "country"}
    index = {nid: i + 1 for i, nid in enumerate(node_ids)}
    errors = []

    # 1. Apele numite.
    sea_layer = Image.new("I", (W, H), 0)
    draw = ImageDraw.Draw(sea_layer)
    marine = json.loads((src / "ne_50m_geography_marine_polys.geojson").read_text(encoding="utf-8"))
    name_to_water = {name: wid for wid, names in MARINE.items() for name in names}
    for f in marine["features"]:
        wid = name_to_water.get(f["properties"].get("name"))
        if wid:
            fill(draw, f["geometry"], index[wid])
    ids = np.array(sea_layer, dtype=np.int32)

    lat = np.repeat((90 - (np.arange(H) + 0.5) * 180 / H)[:, None], W, axis=1)
    lon = np.repeat((-180 + (np.arange(W) + 0.5) * 360 / W)[None, :], H, axis=0)

    # 2. Uscatul (teritoriile care nu sunt în joc rămân neutre, index 0).
    land_layer = Image.new("I", (W, H), -1)
    draw = ImageDraw.Draw(land_layer)
    admin = json.loads((src / "ne_50m_admin_0_countries.geojson").read_text(encoding="utf-8"))
    label = {}
    for f in admin["features"]:
        p = f["properties"]
        code = next((c for c in (p["ISO_A3"], NE_CODES.get(p["ADM0_A3"]), p["ADM0_A3"]) if c in countries), None)
        fill(draw, f["geometry"], index[code] if code else 0)
        if code:
            label[code] = (p["LABEL_Y"], p["LABEL_X"])
    land = np.array(land_layer, dtype=np.int32)
    is_land = land >= 0

    # Golfurile și apele de lângă țărm pe care Natural Earth nu le acoperă iau marea
    # cea mai apropiată, întinzând apele numite pixel cu pixel doar peste apă.
    # Abia ce rămâne departe de orice mare numită (ex. Oceanul de Sud) primește oceanul după longitudine.
    for _ in range(NEAREST_SEA_PX):
        empty = (ids == 0) & ~is_land
        if not empty.any():
            break
        grown = ids.copy()
        for shifted in (np.roll(ids, 1, axis=1), np.roll(ids, -1, axis=1),
                        np.vstack([ids[:1], ids[:-1]]), np.vstack([ids[1:], ids[-1:]])):
            take = empty & (grown == 0) & (shifted != 0)
            grown[take] = shifted[take]
        ids = grown
    # Bălțile închise între țărmuri (nelegate prin apă de o mare numită) iau marea cea mai apropiată,
    # de data asta și peste uscat. Oceanul de Sud (sub 45° S) rămâne pe longitudine.
    pockets = (ids == 0) & ~is_land & (lat > -45)
    spread = ids.copy()
    while pockets.any() and (spread[pockets] == 0).any():
        before = spread
        for shifted in (np.roll(before, 1, axis=1), np.roll(before, -1, axis=1),
                        np.vstack([before[:1], before[:-1]]), np.vstack([before[1:], before[-1:]])):
            take = (spread == 0) & (shifted != 0)
            spread = np.where(take, shifted, spread)
    ids[pockets] = spread[pockets]
    empty = ids == 0
    fb = fallback_ocean(lat[empty], lon[empty])
    ids[empty] = np.vectorize(index.get)(fb)
    for wid, (la0, la1, lo0, lo1, around) in BOXES.items():
        box = (lat >= la0) & (lat <= la1) & (lon >= lo0) & (lon <= lo1)
        replace = np.isin(ids, [index[a] for a in around] + [index["W_ATL"], index["W_IND"], index["W_PAC"]])
        ids[box & replace] = index[wid]

    ids[is_land] = land[is_land]

    # Țările foarte mici (Vatican, Monaco, insule) primesc un punct, ca să poată fi atinse.
    counts = np.bincount(ids.ravel(), minlength=len(node_ids) + 1)
    for code in countries:
        if code not in label:
            errors.append(f"{code} lipsește din Natural Earth")
            continue
        if counts[index[code]] < 12:
            la, lo = label[code]
            x, y = int((lo + 180) / 360 * W), int((90 - la) / 180 * H)
            yy, xx = np.ogrid[:H, :W]
            ids[((yy - y) ** 2 + (xx - x) ** 2 <= 4)] = index[code]
    counts = np.bincount(ids.ravel(), minlength=len(node_ids) + 1)
    for nid in node_ids:
        if counts[index[nid]] == 0:
            errors.append(f"{nid} nu apare pe glob")
    if errors:
        sys.exit("Erori:\n  " + "\n  ".join(errors))

    out = ROOT / "data" / "globe"
    out.mkdir(parents=True, exist_ok=True)
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    rgb[..., 0] = ids & 255
    rgb[..., 1] = ids >> 8
    rgb[..., 2] = np.where(np.isin(ids, [0] + [index[c] for c in countries]), 255, 0)
    Image.fromarray(rgb, "RGB").save(out / "ids.png", optimize=True)

    # 3. Harta de bază (fără nume). Țările sunt toate gri deschis, ca să nu se confunde
    # cu culorile traseului; granițele le desenează globul.
    lut = np.zeros((len(node_ids) + 1, 3), dtype=np.uint8)
    lut[0] = (165, 165, 165)  # teritoriu neutru
    for nid in node_ids:
        lut[index[nid]] = (226, 226, 222) if nid in countries else (22, 58, 110)
    color = lut[ids]
    # apa mai închisă spre poli, ca să se vadă relieful globului
    water = ~np.isin(ids, [0] + [index[c] for c in countries])
    shade = (0.85 + 0.15 * np.cos(np.radians(lat)))[..., None]
    color = np.where(water[..., None], (color * shade).astype(np.uint8), color)
    Image.fromarray(color, "RGB").save(out / "color.png", optimize=True)

    centers = {nid: label.get(nid) or WATER_CENTERS[nid] for nid in node_ids}
    (out / "index.json").write_text(json.dumps({
        "width": W, "height": H,
        "ids": node_ids,
        "centers": {nid: [round(c[0], 3), round(c[1], 3)] for nid, c in centers.items()},
    }, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{out}: {len(node_ids)} locuri pe glob")


if __name__ == "__main__":
    main()
