#!/usr/bin/env python3
"""Generează data/world.json: graful lumii (toate statele membre ONU).

Granițele pe uscat vin din mledoze/countries (ODbL, https://github.com/mledoze/countries).
Ieșirile la mare, mările, porțile și numele în română sunt scrise de mână mai jos.

Utilizare:
    python3 tools/build_world.py path/la/countries.json
"""
import json
import sys
from collections import deque
from pathlib import Path

SOURCE_URL = "https://raw.githubusercontent.com/mledoze/countries/master/countries.json"

def in_scope(c):
    return c["unMember"]


# Continentele pentru modul „pe continente”. Americile sunt un singur continent,
# iar Oceania nu are mod separat (apare doar pe harta lumii).
CONTINENTS = {"Europe": "europe", "Africa": "africa", "Asia": "asia", "Americas": "americas", "Oceania": "oceania"}
PLAYABLE_CONTINENTS = ["europe", "africa", "asia", "americas"]
# Țări transcontinentale, jucabile pe ambele continente.
EXTRA_CONTINENTS = {"RUS": ["asia"], "TUR": ["europe"], "KAZ": ["europe"]}

NAMES_RO = {
    "AGO": "Angola", "ALB": "Albania", "AND": "Andorra", "ARE": "Emiratele Arabe Unite",
    "ARM": "Armenia", "AUT": "Austria", "AZE": "Azerbaidjan", "BDI": "Burundi",
    "BEL": "Belgia", "BEN": "Benin", "BFA": "Burkina Faso", "BGR": "Bulgaria",
    "BHR": "Bahrain", "BIH": "Bosnia și Herțegovina", "BLR": "Belarus", "BWA": "Botswana",
    "CAF": "Republica Centrafricană", "CHE": "Elveția", "CIV": "Coasta de Fildeș",
    "CMR": "Camerun", "COD": "Republica Democratică Congo", "COG": "Republica Congo",
    "COM": "Comore", "CPV": "Capul Verde", "CYP": "Cipru", "CZE": "Cehia",
    "DEU": "Germania", "DJI": "Djibouti", "DNK": "Danemarca", "DZA": "Algeria",
    "EGY": "Egipt", "ERI": "Eritreea", "ESP": "Spania", "EST": "Estonia",
    "ETH": "Etiopia", "FIN": "Finlanda", "FRA": "Franța", "GAB": "Gabon",
    "GBR": "Regatul Unit", "GEO": "Georgia", "GHA": "Ghana", "GIN": "Guineea",
    "GMB": "Gambia", "GNB": "Guineea-Bissau", "GNQ": "Guineea Ecuatorială", "GRC": "Grecia",
    "HRV": "Croația", "HUN": "Ungaria", "IRL": "Irlanda", "IRN": "Iran",
    "IRQ": "Irak", "ISL": "Islanda", "ISR": "Israel", "ITA": "Italia",
    "JOR": "Iordania", "KEN": "Kenya", "KWT": "Kuweit", "LBN": "Liban",
    "LBR": "Liberia", "LBY": "Libia", "LIE": "Liechtenstein", "LSO": "Lesotho",
    "LTU": "Lituania", "LUX": "Luxemburg", "LVA": "Letonia", "MAR": "Maroc",
    "MCO": "Monaco", "MDA": "Republica Moldova", "MDG": "Madagascar", "MKD": "Macedonia de Nord",
    "MLI": "Mali", "MLT": "Malta", "MNE": "Muntenegru", "MOZ": "Mozambic",
    "MRT": "Mauritania", "MUS": "Mauritius", "MWI": "Malawi", "NAM": "Namibia",
    "NER": "Niger", "NGA": "Nigeria", "NLD": "Țările de Jos", "NOR": "Norvegia",
    "OMN": "Oman", "POL": "Polonia", "PRT": "Portugalia", "QAT": "Qatar",
    "ROU": "România", "RUS": "Rusia", "RWA": "Rwanda", "SAU": "Arabia Saudită",
    "SDN": "Sudan", "SEN": "Senegal", "SLE": "Sierra Leone", "SMR": "San Marino",
    "SOM": "Somalia", "SRB": "Serbia", "SSD": "Sudanul de Sud", "STP": "São Tomé și Príncipe",
    "SVK": "Slovacia", "SVN": "Slovenia", "SWE": "Suedia", "SWZ": "Eswatini",
    "SYC": "Seychelles", "SYR": "Siria", "TCD": "Ciad", "TGO": "Togo",
    "TUN": "Tunisia", "TUR": "Turcia", "TZA": "Tanzania", "UGA": "Uganda",
    "UKR": "Ucraina", "VAT": "Vatican", "YEM": "Yemen", "ZAF": "Africa de Sud",
    "ZMB": "Zambia", "ZWE": "Zimbabwe",
    # Asia, Americi, Oceania
    "AFG": "Afganistan", "ARG": "Argentina", "ATG": "Antigua și Barbuda", "AUS": "Australia",
    "BGD": "Bangladesh", "BHS": "Bahamas", "BLZ": "Belize", "BOL": "Bolivia",
    "BRA": "Brazilia", "BRB": "Barbados", "BRN": "Brunei", "BTN": "Bhutan",
    "CAN": "Canada", "CHL": "Chile", "CHN": "China", "COL": "Columbia",
    "CRI": "Costa Rica", "CUB": "Cuba", "DMA": "Dominica", "DOM": "Republica Dominicană",
    "ECU": "Ecuador", "FJI": "Fiji", "FSM": "Micronezia", "GRD": "Grenada",
    "GTM": "Guatemala", "GUY": "Guyana", "HND": "Honduras", "HTI": "Haiti",
    "IDN": "Indonezia", "IND": "India", "JAM": "Jamaica", "JPN": "Japonia",
    "KAZ": "Kazahstan", "KGZ": "Kârgâzstan", "KHM": "Cambodgia", "KIR": "Kiribati",
    "KNA": "Saint Kitts și Nevis", "KOR": "Coreea de Sud", "LAO": "Laos", "LCA": "Saint Lucia",
    "LKA": "Sri Lanka", "MDV": "Maldive", "MEX": "Mexic", "MHL": "Insulele Marshall",
    "MMR": "Myanmar", "MNG": "Mongolia", "MYS": "Malaysia", "NIC": "Nicaragua",
    "NPL": "Nepal", "NRU": "Nauru", "NZL": "Noua Zeelandă", "PAK": "Pakistan",
    "PAN": "Panama", "PER": "Peru", "PHL": "Filipine", "PLW": "Palau",
    "PNG": "Papua Noua Guinee", "PRK": "Coreea de Nord", "PRY": "Paraguay", "SGP": "Singapore",
    "SLB": "Insulele Solomon", "SLV": "El Salvador", "SUR": "Surinam", "THA": "Thailanda",
    "TJK": "Tadjikistan", "TKM": "Turkmenistan", "TLS": "Timorul de Est", "TON": "Tonga",
    "TTO": "Trinidad și Tobago", "TUV": "Tuvalu", "URY": "Uruguay", "USA": "Statele Unite ale Americii",
    "UZB": "Uzbekistan", "VCT": "Saint Vincent și Grenadinele", "VEN": "Venezuela", "VNM": "Vietnam",
    "VUT": "Vanuatu", "WSM": "Samoa",
}

# Nume alternative acceptate la scriere (pe lângă numele RO și EN).
ALIASES = {
    "NLD": ["Olanda", "Holland"], "GBR": ["Marea Britanie", "Anglia", "UK"],
    "CZE": ["Republica Cehă", "Czech Republic"], "CIV": ["Côte d'Ivoire"],
    "COD": ["RD Congo", "Congo-Kinshasa"], "COG": ["Congo", "Congo-Brazzaville"],
    "MDA": ["Moldova"], "TUR": ["Turkey", "Türkiye"], "SWZ": ["Swaziland"],
    "MKD": ["Macedonia"], "ARE": ["Emirate", "UAE", "EAU"], "VAT": ["Sfântul Scaun"],
    "BIH": ["Bosnia"], "CAF": ["RCA"],
    "USA": ["SUA", "America", "Statele Unite"], "MMR": ["Birmania", "Burma"],
    "KGZ": ["Kirghizstan"], "TLS": ["East Timor", "Timor-Leste"], "PRK": ["Korea de Nord"],
    "KOR": ["Korea de Sud"], "FSM": ["Micronesia"],
}

# Mări și oceane (în prototip, mările mici intră în cele mari: Adriatica și Egeea
# fac parte din Marea Mediterană, Marea Arabiei din Oceanul Indian etc.).
WATERS = {
    "W_ATL": ("Oceanul Atlantic", "Atlantic Ocean", ["Atlantic"]),
    "W_IND": ("Oceanul Indian", "Indian Ocean", ["Indian"]),
    "W_ARC": ("Oceanul Arctic", "Arctic Ocean", ["Arctic"]),
    "W_MED": ("Marea Mediterană", "Mediterranean Sea", ["Mediterana"]),
    "W_BLK": ("Marea Neagră", "Black Sea", []),
    "W_RED": ("Marea Roșie", "Red Sea", []),
    "W_NRT": ("Marea Nordului", "North Sea", []),
    "W_BAL": ("Marea Baltică", "Baltic Sea", []),
    "W_CAS": ("Marea Caspică", "Caspian Sea", []),
    "W_GUL": ("Golful Persic", "Persian Gulf", ["Golful Arab"]),
    "W_PAC": ("Oceanul Pacific", "Pacific Ocean", ["Pacific"]),
    "W_CAR": ("Marea Caraibilor", "Caribbean Sea", ["Caraibe", "Marea Caraibelor"]),
    "W_MEX": ("Golful Mexic", "Gulf of Mexico", ["Golful Mexicului"]),
    "W_SCS": ("Marea Chinei de Sud", "South China Sea", []),
    "W_ECS": ("Marea Chinei de Est", "East China Sea", ["Marea Galbenă", "Yellow Sea"]),
    "W_JPN": ("Marea Japoniei", "Sea of Japan", ["Marea de Est", "East Sea"]),
}

# Porți: canale și strâmtori. Trebuie numite ca să treci între cele două ape.
GATES = {
    "G_BAB": ("Strâmtoarea Bab-el-Mandeb", "Bab-el-Mandeb Strait", ["Bab el Mandeb", "Bab-el-Mandeb"]),
    "G_SUE": ("Canalul Suez", "Suez Canal", ["Suez"]),
    "G_TUR": ("Strâmtorile Bosfor și Dardanele", "Bosporus and Dardanelles",
              ["Bosfor", "Bosforul", "Dardanele", "Bosporus", "Dardanelles", "Strâmtorile Turcești"]),
    "G_GIB": ("Strâmtoarea Gibraltar", "Strait of Gibraltar", ["Gibraltar"]),
    "G_HOR": ("Strâmtoarea Ormuz", "Strait of Hormuz", ["Ormuz", "Hormuz"]),
    "G_DAN": ("Strâmtorile Daneze", "Danish Straits",
              ["Skagerrak", "Kattegat", "Øresund", "Oresund", "Canalul Kiel", "Kiel"]),
    "G_VOL": ("Canalul Volga-Don", "Volga-Don Canal", ["Volga-Don", "Volga Don"]),
    "G_MAL": ("Strâmtoarea Malacca", "Strait of Malacca", ["Malacca"]),
    "G_TAI": ("Strâmtoarea Taiwan", "Taiwan Strait", ["Taiwan", "Formosa"]),
    "G_KOR": ("Strâmtoarea Coreei", "Korea Strait", ["Tsushima", "Strâmtoarea Tsushima"]),
    "G_BER": ("Strâmtoarea Bering", "Bering Strait", ["Bering"]),
    "G_DRK": ("Pasajul Drake", "Drake Passage",
              ["Drake", "Strâmtoarea Magellan", "Magellan", "Capul Horn", "Cape Horn"]),
    "G_PAN": ("Canalul Panama", "Panama Canal", ["Panama"]),
    "G_FLA": ("Strâmtoarea Florida", "Straits of Florida", ["Florida"]),
}

# Legături între ape: (apa1, apa2, poartă sau None).
WATER_LINKS = [
    ("W_IND", "W_RED", "G_BAB"),
    ("W_RED", "W_MED", "G_SUE"),
    ("W_MED", "W_BLK", "G_TUR"),
    ("W_MED", "W_ATL", "G_GIB"),
    ("W_IND", "W_GUL", "G_HOR"),
    ("W_NRT", "W_BAL", "G_DAN"),
    ("W_BLK", "W_CAS", "G_VOL"),
    ("W_ATL", "W_NRT", None),
    ("W_ATL", "W_IND", None),
    ("W_ATL", "W_ARC", None),
    ("W_IND", "W_SCS", "G_MAL"),
    ("W_SCS", "W_ECS", "G_TAI"),
    ("W_ECS", "W_JPN", "G_KOR"),
    ("W_PAC", "W_ARC", "G_BER"),
    ("W_PAC", "W_ATL", "G_DRK"),
    ("W_CAR", "W_PAC", "G_PAN"),
    ("W_MEX", "W_ATL", "G_FLA"),
    ("W_SCS", "W_PAC", None),
    ("W_ECS", "W_PAC", None),
    ("W_JPN", "W_PAC", None),
    ("W_PAC", "W_IND", None),
    ("W_CAR", "W_ATL", None),
    ("W_MEX", "W_CAR", None),
]

# Ieșirile la mare ale fiecărei țări.
COASTS = {
    # Europa
    "ALB": ["W_MED"], "BEL": ["W_NRT"], "BIH": ["W_MED"], "BGR": ["W_BLK"],
    "HRV": ["W_MED"], "CYP": ["W_MED"], "DNK": ["W_NRT", "W_BAL"], "EST": ["W_BAL"],
    "FIN": ["W_BAL"], "FRA": ["W_ATL", "W_MED", "W_NRT"], "DEU": ["W_NRT", "W_BAL"],
    "GRC": ["W_MED"], "ISL": ["W_ATL", "W_ARC"], "IRL": ["W_ATL"], "ITA": ["W_MED"],
    "LVA": ["W_BAL"], "LTU": ["W_BAL"], "MLT": ["W_MED"], "MCO": ["W_MED"],
    "MNE": ["W_MED"], "NLD": ["W_NRT"], "NOR": ["W_NRT", "W_ATL", "W_ARC"],
    "POL": ["W_BAL"], "PRT": ["W_ATL"], "ROU": ["W_BLK"],
    "RUS": ["W_BAL", "W_BLK", "W_ARC", "W_CAS", "W_PAC", "W_JPN"], "SVN": ["W_MED"],
    "ESP": ["W_ATL", "W_MED"], "SWE": ["W_BAL", "W_NRT"], "UKR": ["W_BLK"],
    "GBR": ["W_ATL", "W_NRT"],
    # Africa
    "DZA": ["W_MED"], "AGO": ["W_ATL"], "BEN": ["W_ATL"], "CPV": ["W_ATL"],
    "CMR": ["W_ATL"], "COM": ["W_IND"], "COG": ["W_ATL"], "COD": ["W_ATL"],
    "CIV": ["W_ATL"], "DJI": ["W_IND", "W_RED"], "EGY": ["W_MED", "W_RED"],
    "GNQ": ["W_ATL"], "ERI": ["W_RED"], "GAB": ["W_ATL"], "GMB": ["W_ATL"],
    "GHA": ["W_ATL"], "GIN": ["W_ATL"], "GNB": ["W_ATL"], "KEN": ["W_IND"],
    "LBR": ["W_ATL"], "LBY": ["W_MED"], "MDG": ["W_IND"], "MRT": ["W_ATL"],
    "MUS": ["W_IND"], "MAR": ["W_ATL", "W_MED"], "MOZ": ["W_IND"], "NAM": ["W_ATL"],
    "NGA": ["W_ATL"], "STP": ["W_ATL"], "SEN": ["W_ATL"], "SYC": ["W_IND"],
    "SLE": ["W_ATL"], "SOM": ["W_IND"], "ZAF": ["W_ATL", "W_IND"], "SDN": ["W_RED"],
    "TZA": ["W_IND"], "TGO": ["W_ATL"], "TUN": ["W_MED"],
    # Asia de Vest și Iran
    "AZE": ["W_CAS"], "BHR": ["W_GUL"], "GEO": ["W_BLK"], "IRQ": ["W_GUL"],
    "ISR": ["W_MED", "W_RED"], "JOR": ["W_RED"], "KWT": ["W_GUL"], "LBN": ["W_MED"],
    "OMN": ["W_IND", "W_GUL"], "QAT": ["W_GUL"], "SAU": ["W_RED", "W_GUL"],
    "SYR": ["W_MED"], "TUR": ["W_MED", "W_BLK"], "ARE": ["W_GUL", "W_IND"],
    "YEM": ["W_RED", "W_IND"], "IRN": ["W_GUL", "W_IND", "W_CAS"],
    # Restul Asiei
    "BGD": ["W_IND"], "BRN": ["W_SCS"], "CHN": ["W_ECS", "W_SCS"], "IDN": ["W_IND", "W_PAC", "W_SCS"],
    "IND": ["W_IND"], "JPN": ["W_PAC", "W_JPN", "W_ECS"], "KAZ": ["W_CAS"], "TKM": ["W_CAS"],
    "KHM": ["W_SCS"], "KOR": ["W_JPN", "W_ECS"], "LKA": ["W_IND"], "MDV": ["W_IND"],
    "MMR": ["W_IND"], "MYS": ["W_IND", "W_SCS"], "PAK": ["W_IND"], "PHL": ["W_PAC", "W_SCS"],
    "PRK": ["W_JPN", "W_ECS"], "SGP": ["W_SCS"], "THA": ["W_IND", "W_SCS"], "TLS": ["W_IND", "W_PAC"],
    "VNM": ["W_SCS"],
    # Americi
    "ARG": ["W_ATL"], "ATG": ["W_CAR"], "BHS": ["W_ATL"], "BLZ": ["W_CAR"], "BRA": ["W_ATL"],
    "BRB": ["W_ATL"], "CAN": ["W_ATL", "W_PAC", "W_ARC"], "CHL": ["W_PAC"], "COL": ["W_CAR", "W_PAC"],
    "CRI": ["W_CAR", "W_PAC"], "CUB": ["W_CAR", "W_MEX", "W_ATL"], "DMA": ["W_CAR"],
    "DOM": ["W_CAR", "W_ATL"], "ECU": ["W_PAC"], "GRD": ["W_CAR"], "GTM": ["W_CAR", "W_PAC"],
    "GUY": ["W_ATL"], "HND": ["W_CAR", "W_PAC"], "HTI": ["W_CAR", "W_ATL"], "JAM": ["W_CAR"],
    "KNA": ["W_CAR"], "LCA": ["W_CAR"], "MEX": ["W_MEX", "W_CAR", "W_PAC"], "NIC": ["W_CAR", "W_PAC"],
    "PAN": ["W_CAR", "W_PAC"], "PER": ["W_PAC"], "SLV": ["W_PAC"], "SUR": ["W_ATL"],
    "TTO": ["W_CAR", "W_ATL"], "URY": ["W_ATL"], "USA": ["W_ATL", "W_PAC", "W_MEX", "W_ARC"],
    "VCT": ["W_CAR"], "VEN": ["W_CAR", "W_ATL"],
    # Oceania
    "AUS": ["W_IND", "W_PAC"], "FJI": ["W_PAC"], "FSM": ["W_PAC"], "KIR": ["W_PAC"],
    "MHL": ["W_PAC"], "NRU": ["W_PAC"], "NZL": ["W_PAC"], "PLW": ["W_PAC"], "PNG": ["W_PAC"],
    "SLB": ["W_PAC"], "TON": ["W_PAC"], "TUV": ["W_PAC"], "VUT": ["W_PAC"], "WSM": ["W_PAC"],
}

# Granițe greșite în sursă, ignorate (Sri Lanka e o insulă).
NOT_BORDERS = {("IND", "LKA")}

# Marea Caspică e tehnic un lac, deci sursa le consideră fără ieșire la mare.
CASPIAN_ONLY = {"AZE", "KAZ", "TKM"}


def build(countries):
    sel = {c["cca3"]: c for c in countries if in_scope(c)}
    errors = []

    nodes = []
    for code in sorted(sel):
        c = sel[code]
        if code not in NAMES_RO:
            errors.append(f"lipsește numele RO pentru {code}")
        nodes.append({
            "id": code,
            "type": "country",
            "name_ro": NAMES_RO.get(code, c["name"]["common"]),
            "name_en": c["name"]["common"],
            "aliases": ALIASES.get(code, []),
            "continents": [CONTINENTS[c["region"]]] + EXTRA_CONTINENTS.get(code, []),
            "capital": (c.get("capital") or [""])[0],
            "flag": c.get("flag", ""),
        })
    for wid, (ro, en, aliases) in WATERS.items():
        nodes.append({"id": wid, "type": "water", "name_ro": ro, "name_en": en, "aliases": aliases})

    edges = set()
    for code, c in sel.items():
        for other in c["borders"]:
            if other in sel and (min(code, other), max(code, other)) not in NOT_BORDERS:
                if code not in sel[other]["borders"]:
                    errors.append(f"graniță asimetrică {code}-{other}")
                edges.add((min(code, other), max(code, other), None))

    for code, waters in COASTS.items():
        if code not in sel:
            errors.append(f"COASTS conține {code}, care nu e în regiune")
            continue
        for w in waters:
            if w not in WATERS:
                errors.append(f"apă necunoscută {w} la {code}")
            edges.add((code, w, None))

    for code, c in sel.items():
        coastal = code in COASTS
        should = not c["landlocked"] or code in CASPIAN_ONLY
        if coastal != should:
            errors.append(f"{code}: ieșire la mare = {coastal}, sursa spune {should}")

    for a, b, gate in WATER_LINKS:
        if gate is not None and gate not in GATES:
            errors.append(f"poartă necunoscută {gate}")
        edges.add((min(a, b), max(a, b), gate))

    gates = [{"id": g, "name_ro": ro, "name_en": en, "aliases": al} for g, (ro, en, al) in GATES.items()]
    edge_list = [{"a": a, "b": b, **({"gate": g} if g else {})} for a, b, g in sorted(edges, key=lambda e: (e[0], e[1]))]

    # Totul trebuie să fie accesibil din România.
    adj = {n["id"]: set() for n in nodes}
    for e in edge_list:
        adj[e["a"]].add(e["b"])
        adj[e["b"]].add(e["a"])
    seen, queue = {"ROU"}, deque(["ROU"])
    while queue:
        for nxt in adj[queue.popleft()]:
            if nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)
    unreachable = sorted(set(adj) - seen)
    if unreachable:
        errors.append(f"locuri inaccesibile: {unreachable}")

    # Pe fiecare continent, toate țările lui trebuie să fie accesibile doar prin
    # țări de pe acel continent și prin ape.
    for cont in PLAYABLE_CONTINENTS:
        allowed = {n["id"] for n in nodes if n["type"] == "water" or cont in n.get("continents", [])}
        countries = sorted(i for i in allowed if not i.startswith("W_"))
        seen, queue = {countries[0]}, deque([countries[0]])
        while queue:
            for nxt in adj[queue.popleft()]:
                if nxt in allowed and nxt not in seen:
                    seen.add(nxt)
                    queue.append(nxt)
        missing = sorted(set(countries) - seen)
        if missing:
            errors.append(f"pe continentul {cont} sunt inaccesibile: {missing}")

    return {
        "version": 1,
        "region": "lume",
        "continents": PLAYABLE_CONTINENTS,
        "source": {"borders": SOURCE_URL, "license": "ODbL 1.0 (mledoze/countries)"},
        "nodes": nodes,
        "gates": gates,
        "edges": edge_list,
    }, errors


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    countries = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    world, errors = build(countries)
    if errors:
        sys.exit("Erori:\n  " + "\n  ".join(errors))
    out = Path(__file__).resolve().parent.parent / "data" / "world.json"
    out.write_text(json.dumps(world, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{out}: {len(world['nodes'])} locuri, {len(world['edges'])} legături, {len(world['gates'])} porți")


if __name__ == "__main__":
    main()
