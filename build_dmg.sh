#!/usr/bin/env zsh
# ============================================================================
# GTA 6 (PS5) Canlı Türkçe Altyazı — macOS (.app + .dmg) Paketleyici (M2 ARM64)
# Çıktılar:
#   dist/GTA6 Türkçe Altyazı.app
#   dist/GTA6-PS5-Altyazi-macOS-M2.dmg
# ============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

APP_NAME="SaltCeviri"
DMG_NAME="SaltCeviri-macOS-M2.dmg"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
DMG_STAGE="$BUILD_DIR/dmg_stage"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"

echo "============================================================"
echo " SaltÇeviri — macOS .app ve .dmg Üretici (M2 ARM64)"
echo "============================================================"

rm -rf "$BUILD_DIR" "$DIST_DIR"/*.app "$DIST_DIR"/*.dmg "$DMG_STAGE"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$DMG_STAGE"

# 1) macOS Uygulama İkonu (.icns) Oluştur (Apple Quartz / sips + iconutil)
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

python3 - "$ICONSET_DIR" <<'EOF'
import struct
import sys
import zlib
from pathlib import Path

iconset = Path(sys.argv[1])
base_png = iconset.parent / "base_icon.png"

# Saf Python (stdlib zlib/struct) ile Vice City / GTA 6 temalı 256x256 baz ikon oluştur
w, h = 256, 256
rows = []
for y in range(h):
    row = bytearray([0])  # PNG filter byte 0
    for x in range(w):
        # Çerçeve ve köşe kontrolü
        in_border = (16 <= x < w - 16 and 16 <= y < h - 16) and (
            x < 26 or x >= w - 26 or y < 26 or y >= h - 26
        )
        # Alt altyazı kutusu
        in_sub_box = 34 <= x < w - 34 and 172 <= y < 224
        # Altyazı metin şeritleri
        in_spk_line = 48 <= x < 102 and 184 <= y < 194
        in_tr_line1 = 110 <= x < w - 48 and 184 <= y < 194
        in_tr_line2 = 64 <= x < w - 64 and 202 <= y < 212
        # Üst "VI" harf blokları
        in_v_left = 66 <= x < 90 and 54 <= y < 146
        in_v_right = 104 <= x < 128 and 54 <= y < 146
        in_v_bottom = 80 <= x < 114 and 122 <= y < 152
        in_i_bar = 150 <= x < 178 and 54 <= y < 152

        if in_spk_line:
            r, g, b, a = (255, 107, 157, 255)  # Lucia Pembe
        elif in_tr_line1:
            r, g, b, a = (79, 195, 247, 255)   # Jason Turkuaz
        elif in_tr_line2:
            r, g, b, a = (255, 213, 79, 255)   # Altın Sarısı
        elif in_sub_box:
            r, g, b, a = (8, 10, 16, 245)      # Koyu Altyazı Kutusu
        elif in_v_left or in_v_right or in_v_bottom:
            r, g, b, a = (242, 56, 143, 255)   # VI Pembe
        elif in_i_bar:
            r, g, b, a = (79, 195, 247, 255)   # VI Turkuaz
        elif in_border:
            r, g, b, a = (242, 56, 143, 255)   # Neon Çerçeve
        else:
            # Koyu Vice City gradyan arka plan
            r = 16 + (y * 18 // h)
            g = 18 + (x * 12 // w)
            b = 34 + (y * 24 // h)
            a = 255
        row.extend((r, g, b, a))
    rows.append(bytes(row))

raw_data = b"".join(rows)

def make_chunk(chunk_type: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)

png_bytes = (
    b"\x89PNG\r\n\x1a\n"
    + make_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    + make_chunk(b"IDAT", zlib.compress(raw_data, 9))
    + make_chunk(b"IEND", b"")
)
base_png.write_bytes(png_bytes)
EOF

if [ -f "$BUILD_DIR/base_icon.png" ]; then
    for sz in 16 32 128 256 512; do
        sips -z $sz $sz "$BUILD_DIR/base_icon.png" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null 2>&1
        dbl=$((sz * 2))
        sips -z $dbl $dbl "$BUILD_DIR/base_icon.png" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns" || true
fi

# 2) macOS .app Paket Yapısını Oluştur ve Native Swift (ARM64) Binary Derle
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/app"

if [ -f "$BUILD_DIR/AppIcon.icns" ]; then
    cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "[Derleme] Native SwiftUI + M2 Apple Vision ikili dosyası (arm64) derleniyor..."
swiftc -O -parse-as-library \
    -module-cache-path /tmp/swift-module-cache \
    -target arm64-apple-macosx13.0 \
    "$PROJECT_DIR"/macos-swift/Sources/GTA6Altyazi/*.swift \
    -lsqlite3 \
    -framework AppKit -framework SwiftUI -framework Vision -framework CoreGraphics -framework Network \
    -o "$APP_BUNDLE/Contents/MacOS/GTA6AltyaziLauncher"

chmod +x "$APP_BUNDLE/Contents/MacOS/GTA6AltyaziLauncher"

# Dağıtım paketi için temiz yapılandırma ve sözlük dosyalarını .app/Contents/Resources/app içine kopyala
mkdir -p "$APP_BUNDLE/Contents/Resources/app/data"
cp "$PROJECT_DIR/data/glossary.json" "$APP_BUNDLE/Contents/Resources/app/data/glossary.json"
cp "$PROJECT_DIR/config.json" "$APP_BUNDLE/Contents/Resources/app/config.json"
cp "$PROJECT_DIR/.env.example" "$APP_BUNDLE/Contents/Resources/app/.env.example"
if [ -f "$PROJECT_DIR/NOTLAR.md" ]; then
    cp "$PROJECT_DIR/NOTLAR.md" "$APP_BUNDLE/Contents/Resources/app/NOTLAR.md"
fi

# Info.plist oluştur (Ekran Kaydı izni açıklaması ve Retina desteği dahil)
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SaltÇeviri</string>
    <key>CFBundleDisplayName</key>
    <string>SaltÇeviri</string>
    <key>CFBundleIdentifier</key>
    <string>com.saltceviri.app</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>GTA6AltyaziLauncher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SaltÇeviri'nin PS Remote Play veya seçilen ekran bölgesindeki İngilizce altyazıları okuyup Türkçeye çevirmesi için ekran kaydı izni gereklidir.</string>
</dict>
</plist>
EOF

# 2.5) macOS İmzalama (Ekran Kaydı izni kimliği sabit kalsın diye)
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - --identifier com.saltceviri.app "$APP_BUNDLE"

# 3) DMG Sahnesini Hazırla (.app + Applications Kısayolu + Kurulum Notları)
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
if [ -f "$PROJECT_DIR/NOTLAR.md" ]; then
    cp "$PROJECT_DIR/NOTLAR.md" "$DMG_STAGE/KURULUM_NOTLARI.md"
fi

if [ "$1" = "--stage-only" ]; then
    echo "[Bilgi] .app paketi ve DMG sahnesi hazırlandı: $APP_BUNDLE"
    exit 0
fi

echo "[Bilgi] .dmg kurulum imajı oluşturuluyor..."
hdiutil create \
    -volname "SaltCeviri macOS M2" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$DMG_NAME"

rm -rf "$BUILD_DIR"

echo "============================================================"
echo " TAMAMLANDI!"
echo " Uygulama Paketi : $APP_BUNDLE"
echo " DMG Kurulum Dosyası : $DIST_DIR/$DMG_NAME"
echo "============================================================"
