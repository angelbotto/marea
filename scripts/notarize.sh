#!/bin/bash
# Notariza Marea.app para poder compartirla fuera de este Mac (sin aviso de Gatekeeper).
#
# REQUISITOS (una sola vez, acción del usuario):
#   1. Certificado "Developer ID Application" en el llavero.
#      Xcode → Settings → Accounts → Manage Certificates → + → "Developer ID Application".
#   2. Credenciales de notarytool guardadas en el llavero con el perfil "marea":
#      xcrun notarytool store-credentials marea \
#        --apple-id "TU_APPLE_ID" --team-id 22R43BN2XG --password "APP_SPECIFIC_PASSWORD"
#      (la app-specific password se crea en https://account.apple.com → Sign-In and Security)
#
# Uso: ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Marea.app"
ZIP="Marea-notarize.zip"
PROFILE="marea"

echo "▸ Verificando requisitos..."
if ! security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
  echo "❌ Falta el certificado 'Developer ID Application' en el llavero."
  echo "   Créalo en Xcode → Settings → Accounts → Manage Certificates → + Developer ID Application."
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "❌ Falta el perfil de credenciales '$PROFILE'."
  echo "   Créalo con: xcrun notarytool store-credentials $PROFILE --apple-id <id> --team-id 22R43BN2XG --password <app-specific>"
  exit 1
fi

echo "▸ Compilando release firmado con Developer ID..."
DEVID=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -1 | awk '{print $2}')
xcodebuild -project Marea.xcodeproj -scheme Marea -configuration Release \
  -derivedDataPath .xcbuild \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" build

BUILT=".xcbuild/Build/Products/Release/$APP"
rm -rf "$APP"; cp -R "$BUILT" "$APP"

echo "▸ Empaquetando y enviando a notarizar (puede tardar unos minutos)..."
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ Grapando el ticket..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"
echo "✓ $APP notarizada y grapada. Ya se puede compartir por AirDrop/descarga sin bloqueo de Gatekeeper."
