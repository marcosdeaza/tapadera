#!/bin/bash
# Compila Tapadera.app. Sin Xcode project: swiftc + bundle a mano.
#   ./build.sh [directorio-de-salida]     (por defecto: ./build)
set -euo pipefail

cd "$(dirname "$0")"
OUT="${1:-build}"
APP="$OUT/Tapadera.app"

echo "· compilando binario universal (arm64 + x86_64)"
mkdir -p "$OUT/obj"
for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "${arch}-apple-macos13.0" \
        -o "$OUT/obj/Tapadera-$arch" Sources/App.swift
done
lipo -create -output "$OUT/obj/Tapadera" \
    "$OUT/obj/Tapadera-arm64" "$OUT/obj/Tapadera-x86_64"

echo "· generando icono"
mkdir -p "$OUT/png" "$OUT/Tapadera.iconset"
swiftc -O -o "$OUT/obj/mkicon" ../tools/mkicon.swift
"$OUT/obj/mkicon" "$OUT/png"
cp "$OUT/png/icon_16.png"   "$OUT/Tapadera.iconset/icon_16x16.png"
cp "$OUT/png/icon_32.png"   "$OUT/Tapadera.iconset/icon_16x16@2x.png"
cp "$OUT/png/icon_32.png"   "$OUT/Tapadera.iconset/icon_32x32.png"
cp "$OUT/png/icon_64.png"   "$OUT/Tapadera.iconset/icon_32x32@2x.png"
cp "$OUT/png/icon_128.png"  "$OUT/Tapadera.iconset/icon_128x128.png"
cp "$OUT/png/icon_256.png"  "$OUT/Tapadera.iconset/icon_128x128@2x.png"
cp "$OUT/png/icon_256.png"  "$OUT/Tapadera.iconset/icon_256x256.png"
cp "$OUT/png/icon_512.png"  "$OUT/Tapadera.iconset/icon_256x256@2x.png"
cp "$OUT/png/icon_512.png"  "$OUT/Tapadera.iconset/icon_512x512.png"
cp "$OUT/png/icon_1024.png" "$OUT/Tapadera.iconset/icon_512x512@2x.png"
iconutil -c icns "$OUT/Tapadera.iconset" -o "$OUT/Tapadera.icns"

echo "· armando bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/obj/Tapadera" "$APP/Contents/MacOS/Tapadera"
cp "$OUT/Tapadera.icns" "$APP/Contents/Resources/Tapadera.icns"
cp Info.plist "$APP/Contents/Info.plist"

echo "· firmando (ad-hoc)"
codesign --force --deep -s - "$APP"

rm -rf "$OUT/obj" "$OUT/png" "$OUT/Tapadera.iconset"
echo "listo → $APP"
