#!/usr/bin/env python3
"""Adună steagurile (SVG, din lipis/flag-icons v7.2.3, licență MIT) în data/flags.json.

Utilizare:
    python3 tools/build_flags.py <director cu fișierele 4x3/<cod>.svg>
Steagurile se descarcă de la
    https://raw.githubusercontent.com/lipis/flag-icons/v7.2.3/flags/4x3/<cod>.svg
unde <cod> e codul ISO din două litere al țării (câmpul cca2 din world.json).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


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
            flags[node["id"]] = svg.read_text(encoding="utf-8")
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
