#!/usr/bin/env bash
# Face GeoChain.aab pentru Google Play din APK-ul semnat exportat cu presetul „Android”.
# Exportul Gradle al Godot are nevoie de Maven Central, care nu e accesibil în mediul de build,
# așa că transformăm APK-ul în bundle cu aapt2 și bundletool, apoi îl semnăm cu aceeași cheie.
# Rulează: tools/android/build_aab.sh <GeoChain.apk> <GeoChain.aab> <keystore>
# Variabile: ANDROID_SDK (implicit /opt/android-sdk), BUNDLETOOL (bundletool-all.jar),
# GODOT_TEMPLATES (folderul șabloanelor Godot), KEY_PASS (implicit geochain2026).
set -euo pipefail
APK=$(realpath "$1"); OUT=$(realpath -m "$2"); KS=$(realpath "$3")
SDK=${ANDROID_SDK:-/opt/android-sdk}
BT=$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)
BUNDLETOOL=${BUNDLETOOL:-/opt/tools/bundletool.jar}
TEMPLATES=${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates/4.7.2.stable}
PASS=${KEY_PASS:-geochain2026}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp "$APK" "$W/in.apk"
# Exportul Godot scoate themed_icon.xml, dar tabela de resurse încă îl cere; aapt2 convert nu acceptă asta.
mkdir -p "$W/t/res/mipmap-anydpi-v26"
unzip -q -p "$TEMPLATES/android_release.apk" res/mipmap-anydpi-v26/themed_icon.xml > "$W/t/res/mipmap-anydpi-v26/themed_icon.xml"
(cd "$W/t" && zip -q ../in.apk res/mipmap-anydpi-v26/themed_icon.xml)
"$BT/aapt2" convert --output-format proto -o "$W/proto.apk" "$W/in.apk"
mkdir -p "$W/x" "$W/base/manifest" "$W/base/dex" "$W/base/root"
(cd "$W/x" && unzip -q ../proto.apk && rm -rf META-INF)
mv "$W/x/AndroidManifest.xml" "$W/base/manifest/"
mv "$W/x/resources.pb" "$W/base/"
mv "$W/x"/classes*.dex "$W/base/dex/"
mv "$W/x/res" "$W/x/assets" "$W/x/lib" "$W/base/"
(cd "$W/x" && cp -r . ../base/root/)
(cd "$W/base" && zip -qr -D ../base.zip .)
cat > "$W/config.json" <<'JSON'
{"optimizations":{"uncompressNativeLibraries":{"enabled":true,"alignment":"PAGE_ALIGNMENT_16K"},
 "splitsConfig":{"splitDimension":[{"value":"ABI"},{"value":"SCREEN_DENSITY"},{"value":"LANGUAGE","negate":true}]}}}
JSON
rm -f "$OUT"
java -jar "$BUNDLETOOL" build-bundle --modules="$W/base.zip" --output="$OUT" --config="$W/config.json"
jarsigner -keystore "$KS" -storepass "$PASS" -sigalg SHA256withRSA -digestalg SHA-256 "$OUT" geochain
java -jar "$BUNDLETOOL" validate --bundle="$OUT" >/dev/null
echo "Gata: $OUT"
