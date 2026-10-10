# GeoChain

Joc de geografie pentru Android și Windows, făcut în [Godot 4](https://godotengine.org).
Primești o țară de pornire și o destinație și ajungi acolo din vecin în vecin, pe uscat sau pe apă.
Cu cât faci mai puține mutări, cu atât scorul e mai mare.

## Reguli (prototip)

- **O mutare**: țară → țară vecină, țară → mare/ocean la care are ieșire, mare → mare legată de ea.
- **Porți**: canalele și strâmtorile (Suez, Panama, Bosfor, Gibraltar…) trebuie numite ca să treci între două ape. Nu costă o mutare.
- **Normal**: cel mult 2 mutări pe apă la rând. Greșelile (loc care nu e legat, poartă greșită, prea multă apă) scad punctajul.
- **Strâmtori între țări** (Normal și Sandbox): unele țări fără graniță pe uscat sunt legate de o strâmtoare (Bering între SUA și Rusia, Pas-de-Calais între Marea Britanie și Franța, Bab el-Mandeb, Ormuz, Torres…). Treci direct dintr-o țară în cealaltă dacă numești strâmtoarea. Lista e în `data/straits.json`.
- **Sandbox**: îți creezi singur jocul: alegi țara de pornire, destinația, până la 6 țări interzise și până la 4 obligatorii (le vizitezi în orice ordine). Fără limite, vezi vecinii ca butoane, poți da înapoi și poți vedea traseul minim.
- **Bac**: doar pe uscat; între unele țări (`data/ferries.json`) treci cu bacul, dacă răspunzi corect la 2 din 3 întrebări de geografie cu variante. Dacă nu reușești, mai încerci. Întrebările nu se repetă până nu se termină, iar la repetare variantele se amestecă.
- **Mări detaliate** (opțional): Adriatica, Ionică, Tireniană, Egee, Marmara, Azov, Golful Aden, Golful Oman, Canalul Mânecii și Golful Botnic devin locuri separate, cu porți noi (Otranto, Dardanele, Bosfor, Kerci, Pas-de-Calais). Pe harta simplă, numele lor duc la marea mare din care fac parte.
- **Limba**: română sau engleză (buton sus). Numele țărilor, mărilor și porților se pot scrie în oricare dintre limbi.
- **Harta**: toată lumea sau un singur continent (Europa, Africa, Asia, Americile unite). Oceania apare doar pe harta lumii.
- **Scor**: 3 stele dacă egalezi traseul minim, 2 stele cu cel mult 2 mutări în plus, altfel 1 stea. Puncte: 1000 − 100 × mutări în plus − 50 × greșeli.

## Reguli de dificultate

Butonul **Reguli** deschide lista regulilor; fiecare se pornește sau se oprește separat, iar **Ușor**, **Mediu** și **Greu**
sunt scurtături care bifează mai multe deodată. Regulile se aplică în modul Normal și se țin minte între jocuri.

| Regulă | Ce face |
|---|---|
| Lungimea traseului | Scurt (3–4 mutări), mediu (5–7), lung (8+) sau oricare |
| Mutări pe apă la rând | Cel mult 2, cel mult 1, doar pe uscat sau oricâte |
| Destinație ghicitoare | Destinația apare ca steag sau ca nume de capitală, nu ca nume de țară. Cu „Steag”, fiecare mutare se alege din 6 variante: cea mai bună, cea de pe drumul cel mai scurt doar pe uscat, una utilă, un vecin care nu ajută și țări de pe același continent care nu sunt vecine (mările apar cu numele). Când mutarea bună e pe apă, 2 variante sunt ape, una corectă; altfel toate sunt steaguri |
| 3 vieți | La a treia greșeală ai pierdut |
| Țară interzisă | O țară de pe traseul cel mai scurt devine interzisă (roșu pe glob): de preferat una fără de care drumul e cu 1–3 mutări mai lung; pe trasee lungi, unde mereu există un ocol la fel de scurt, prima țară de pe traseu |
| Punct obligatoriu | Trebuie să treci printr-o țară anume (galben pe glob) |
| Mări detaliate | Mările mici devin locuri separate, cu porți noi |
| Porți cu variante | Alegi canalul sau strâmtoarea dintre 3 variante, în loc să scrii (pornită implicit; Greu o oprește) |
| Fără sugestii | Nu mai apar sugestii când scrii |
| Ceață | Granițele apar doar la locurile prin care ai trecut |
| Cronometru | 30 de secunde pe mutare; dacă expiră, e o greșeală |
| Mod capitale | Scrii capitala țării în care mergi (București în loc de România) |
| Bonus „par” | +300 dacă egalezi traseul minim, −150 pe fiecare mutare în plus |

## Globul

Globul 3D se rotește cu mouse-ul sau degetul și face zoom cu rotița sau cu două degete. Globul doar ajută: un clic pe el nu face o mutare. Muți scriind numele locului (sau capitala, în modul capitale) ori alegând steagul, în varianta cu steaguri.
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
| `scripts/globe.gd`, `shaders/globe.gdshader` | Globul 3D: rotire, zoom, culori, granițe |
| `data/globe/` | Texturile globului (harta colorată și harta ascunsă de identificare), generate de `tools/build_globe.py` |
| `scripts/rules.gd`, `scripts/challenge.gd` | Regulile de dificultate și alegerea la întâmplare a partidei |
| `data/flags.json` | Steagurile (SVG), generate de `tools/build_flags.py` |
| `tests/run_tests.gd` | Testele |

## Date

Granițele pe uscat vin din [mledoze/countries](https://github.com/mledoze/countries), licență
[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Ieșirile la mare, mările, porțile și
numele în română sunt adăugate de mână în `tools/build_world.py`.

Pentru simplitate, mările mici fac parte din cele mari (Adriatica și Egeea sunt în Marea Mediterană,
Marea Arabiei în Oceanul Indian etc.). Sunt incluse statele membre ONU, plus Vaticanul (sursa îl marchează ca membru).

Fontul este [Nunito](https://github.com/googlefonts/nunito), licență SIL Open Font License (`fonts/OFL.txt`).

Steagurile vin din [lipis/flag-icons](https://github.com/lipis/flag-icons) v7.2.3, licență MIT.

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
