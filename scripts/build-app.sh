#!/bin/bash
# Compile Rempart, crée Rempart.app, signe localement et installe dans /Applications.
# Usage : scripts/build-app.sh [--no-install]
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Rempart.app"

echo "→ Compilation (release)…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Rempart"

echo "→ Création du bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rempart"
cp Resources/block.html "$APP/Contents/Resources/"
cp scripts/rempart-hosts-daemon.sh scripts/com.rempart.hosts.plist scripts/install-daemon.sh "$APP/Contents/Resources/"

echo "→ Icône…"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Rempart</string>
    <key>CFBundleDisplayName</key><string>Rempart</string>
    <key>CFBundleIdentifier</key><string>com.rempart.app</string>
    <key>CFBundleExecutable</key><string>Rempart</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Rempart lit et redirige les onglets de ton navigateur, et envoie / lit des messages pour les demandes de déblocage à tes proches.</string>
</dict>
</plist>
EOF

echo "→ Signature locale…"
# Une identité stable garde les autorisations macOS (Accès complet au disque, Automatisation)
# entre les recompilations. Sinon : signature ad hoc (les autorisations sont à refaire à chaque build).
SIGN_ID="Rempart Local Signing"
security find-identity -p codesigning | grep -q "$SIGN_ID" || SIGN_ID="-"
codesign --force --options runtime --entitlements scripts/Rempart.entitlements -s "$SIGN_ID" "$APP"

if [ "$1" != "--no-install" ]; then
  echo "→ Installation dans /Applications…"
  pkill -x Rempart 2>/dev/null || true
  rm -rf /Applications/Rempart.app
  cp -R "$APP" /Applications/Rempart.app
  echo "Installé : /Applications/Rempart.app"
fi
echo "Terminé."
