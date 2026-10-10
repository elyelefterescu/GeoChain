# GeoChain

Joc de geografie pentru Android și Windows, făcut în [Godot 4](https://godotengine.org).
Primești o țară de pornire și o destinație și ajungi acolo din vecin în vecin, pe uscat sau pe apă.
Cu cât faci mai puține mutări, cu atât scorul e mai mare.

## Reguli (prototip)

- **O mutare**: țară → țară vecină, țară → mare/ocean la care are ieșire, mare → mare legată de ea.
- **Porți**: canalele și strâmtorile (Suez, Panama, Bosfor, Gibraltar…) trebuie numite ca să treci între două ape. Nu costă o mutare.
- **Normal**: cel mult 2 mutări pe apă la rând. Greșelile (loc care nu e legat, poartă greșită, prea multă apă) scad punctajul.
- **Sandbox**: fără limite, vezi vecinii ca butoane, poți da înapoi și poți vedea traseul minim.
- **Mări detaliate** (opțional): Adriatica, Ionică, Tireniană, Egee, Marmara, Azov, Golful Aden, Golful Oman, Canalul Mânecii și Golful Botnic devin locuri separate, cu porți noi (Otranto, Dardanele, Bosfor, Kerci, Pas-de-Calais). Pe harta simplă, numele lor duc la marea mare din care fac parte.
- **Limba**: română sau engleză (buton sus). Numele țărilor, mărilor și porților se pot scrie în oricare dintre limbi.
- **Harta**: toată lumea sau un singur continent (Europa, Africa, Asia, Americile unite). Oceania apare doar pe harta lumii.
- **Scor**: 3 stele dacă egalezi traseul minim, 2 stele cu cel mult 2 mutări în plus, altfel 1 stea. Puncte: 1000 − 100 × mutări în plus − 50 × greșeli.

## Globul

Globul 3D se rotește cu mouse-ul sau degetul și face zoom cu rotița sau cu două degete. O atingere pe o țară sau o mare înseamnă o mutare acolo.
Pe glob nu apar nume, doar la țările prin care ai trecut. Culori: albastru = unde ești, verde = unde ai fost,
mov = pornirea și destinația, portocaliu = greșeli, roșu = unde nu ai voie, galben = puncte obligatorii.

## Cum rulezi

1. Instalează [Godot 4.3](https://godotengine.org/download) (versiunea standard, nu .NET).
2. Deschide Godot, apasă **Import** și alege `project.godot` din acest folder.
3. Apasă **F5** ca să pornești jocul.

Ca să faci un .exe pentru Windows: în Godot, **Project → Export → Windows** (prima dată îți cere să descarci șabloanele de export).

Testele, din linia de comandă:

```
godot --headless --path . --script res://tests/run_tests.gd
```

## Structura

| Cale | Ce conține |
|---|---|
| `data/world.json` | Graful lumii: 194 de țări (193 membre ONU + Vatican), 16 mări și oceane (+10 detaliate), 19 porți |
| `tools/build_world.py` | Generează `world.json` și verifică datele (granițe simetrice, ieșiri la mare, conectivitate pe fiecare continent) |
| `scripts/world_graph.gd` | Graful, căutarea după nume și traseul minim (BFS cu regula apei) |
| `scripts/game_session.gd` | O partidă: mutări, greșeli, stele, puncte |
| `scripts/main.gd` | Ecranul prototipului (fără glob încă) |
| `scripts/i18n.gd` | Textele interfeței în română și engleză |
| `scripts/globe.gd`, `shaders/globe.gdshader` | Globul 3D: rotire, zoom, atingere, culori, granițe |
| `data/globe/` | Texturile globului (harta colorată și harta ascunsă de identificare), generate de `tools/build_globe.py` |
| `tests/run_tests.gd` | Testele |

## Date

Granițele pe uscat vin din [mledoze/countries](https://github.com/mledoze/countries), licență
[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Ieșirile la mare, mările, porțile și
numele în română sunt adăugate de mână în `tools/build_world.py`.

Pentru simplitate, mările mici fac parte din cele mari (Adriatica și Egeea sunt în Marea Mediterană,
Marea Arabiei în Oceanul Indian etc.). Sunt incluse statele membre ONU, plus Vaticanul (sursa îl marchează ca membru).

Contururile globului vin din [Natural Earth](https://www.naturalearthdata.com) (domeniu public), scara 1:50m.

Ca să regenerezi datele:

```
curl -sSLo countries.json https://raw.githubusercontent.com/mledoze/countries/master/countries.json
python3 tools/build_world.py countries.json
# globul (necesită numpy și pillow):
for f in ne_50m_admin_0_countries ne_50m_geography_marine_polys; do
  curl -sSLo $f.geojson https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/$f.geojson
done
python3 tools/build_globe.py .
```
