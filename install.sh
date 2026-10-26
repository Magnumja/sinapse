#!/bin/bash
# Instala (ou atualiza) o Sinapse a partir da última versão publicada no GitHub.
#   curl -fsSL https://raw.githubusercontent.com/Magnumja/sinapse/main/install.sh | bash
set -euo pipefail

REPO="Magnumja/sinapse"
URL="https://github.com/$REPO/releases/latest/download/Sinapse.zip"
DEST="/Applications/Sinapse.app"

if [ "$(uname)" != "Darwin" ]; then
    echo "O Sinapse só funciona no macOS." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Baixando o Sinapse…"
curl -fL --progress-bar "$URL" -o "$TMP/Sinapse.zip"
ditto -x -k "$TMP/Sinapse.zip" "$TMP"

echo "→ Instalando em /Applications…"
pkill -x Sinapse 2>/dev/null || true
rm -rf "/Applications/Sinapse.app"
ditto "$TMP/Sinapse.app" "$DEST"
# O app não é notarizado pela Apple: tira a marca de "baixado da internet" para o macOS abrir sem bloquear.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"
echo "✓ Pronto! Procure o ícone do cérebro na barra de menu (perto do relógio)."
