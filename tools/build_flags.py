#!/usr/bin/env python3
"""Adună steagurile (SVG, din lipis/flag-icons v7.2.3, licență MIT) în data/flags.json.

Utilizare:
    python3 tools/build_flags.py <director cu fișierele 4x3/<cod>.svg>
Steagurile se descarcă de la
    https://raw.githubusercontent.com/lipis/flag-icons/v7.2.3/flags/4x3/<cod>.svg
unde <cod> e codul ISO din două litere al țării (câmpul cca2 din world.json).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Motorul SVG din Godot (ThorVG) nu desenează <marker>, iar steagul SUA își pune cele 50 de stele
# ca marker pe vârfurile unei linii. Le scriem ca forme obișnuite, în aceleași poziții.
US_STAR = [(14, 0), (23, 27), (0, 10), (28, 10), (5, 27)]  # vârfurile stelei din marker
US_ROWS = [11, 37, 63, 89, 115, 141, 166, 192, 218]


def fix_markers(svg):
    if "<marker" not in svg:
        return svg
    stars = []
    for row, y in enumerate(US_ROWS):
        xs = [16, 77, 138, 199, 260, 320] if row % 2 == 0 else [47, 108, 169, 229, 290]
        stars += ["M" + "L".join(f"{x + dx} {y + dy}" for dx, dy in US_STAR) + "z" for x in xs]
    svg = re.sub(r"\s*<marker.*?</marker>", "", svg, flags=re.S)
    svg = re.sub(r'<path fill="none" marker-mid="[^"]*" d="[^"]*"/>',
                 f'<path fill="#fff" d="{"".join(stars)}"/>', svg)
    if "marker" in svg.replace("marker:none", ""):
        sys.exit("Steag cu <marker> pe care nu-l știu transforma")
    return svg


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    world = json.loads((ROOT / "data" / "world.json").read_text(encoding="utf-8"))
    flags, missing = {}, []
    for node in world["nodes"]:
        if node["type"] != "country":
            continue
        svg = src / f"{node['cca2'].lower()}.svg"
        if svg.exists():
            flags[node["id"]] = fix_markers(svg.read_text(encoding="utf-8"))
        else:
            missing.append(node["id"])
    if missing:
        sys.exit(f"Lipsesc steagurile pentru: {missing}")
    out = ROOT / "data" / "flags.json"
    out.write_text(json.dumps({"source": "lipis/flag-icons v7.2.3 (MIT)", "flags": flags}, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    print(f"{out}: {len(flags)} steaguri")


if __name__ == "__main__":
    main()
