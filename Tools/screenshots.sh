#!/bin/bash
# Gera os prints do README em docs/screenshots (usa o modo --preview, que não bloqueia nada).
# Uso: ./build.sh && ./Tools/screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/screenshots
RAW=build/raw-screenshots
mkdir -p "$OUT" "$RAW"

SDK_ARGS=()
OLD_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort | tail -1 || true)
if [ ! -d /Applications/Xcode.app ] && [ -n "$OLD_SDK" ]; then SDK_ARGS=(-sdk "$OLD_SDK"); fi

for screen in menu sessao ajustes perfis historico pausa cancelar fim; do
    build/Sinapse.app/Contents/MacOS/Sinapse --preview "$screen" --snapshot "$(pwd)/$RAW/$screen.png" &
    pid=$!
    sleep 3
    kill "$pid" 2>/dev/null || true
    swift ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} Tools/frame_screenshot.swift "$RAW/$screen.png" "$OUT/$screen.png"
done
