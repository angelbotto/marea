#!/bin/bash
# Empaqueta Marea como Marea.app (bundle de barra de menú, sin icono en Dock).
# Uso:
#   ./build-app.sh            -> compila release y arma ./Marea.app
#   ./build-app.sh --install  -> además lo copia a /Applications (necesario para "abrir al login")
set -euo pipefail
cd "$(dirname "$0")"

APP="Marea.app"
CONTENTS="$APP/Contents"

echo "▸ Compilando release..."
swift build -c release

echo "▸ Armando ${APP}..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/Marea" "$CONTENTS/MacOS/Marea"
cp "Info.plist" "$CONTENTS/Info.plist"

echo "▸ Firmando ad-hoc (necesario para login item)..."
codesign --force --sign - --identifier "is.botto.marea" "$APP" >/dev/null 2>&1 || \
  echo "  (aviso: no se pudo firmar; la app corre igual, pero el login item puede fallar)"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/$APP"
  echo "▸ Instalando en ${DEST}..."
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "✓ Instalada. Ábrela con:  open \"$DEST\""
else
  echo "✓ Listo: $(pwd)/$APP"
  echo "  Para arranque al login, instálala:  ./build-app.sh --install"
fi
