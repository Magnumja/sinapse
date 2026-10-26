#!/bin/bash
# Compila o Sinapse.app (precisa do Xcode ou das Command Line Tools: xcode-select --install).
#
#   ./build.sh            → build/Sinapse.app (só a arquitetura deste Mac)
#   ./build.sh install    → compila, copia para /Applications e abre
#   ./build.sh release    → binário universal (Apple Silicon + Intel) e build/Sinapse.zip
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP=build/Sinapse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns Assets/MenuIcon.png Assets/MenuIcon@2x.png Assets/LogoMark.png "$APP/Contents/Resources/"

# O SDK do macOS 27 transformou @State em macro, cujo plugin só vem com o Xcode completo.
# Com só as Command Line Tools, compila contra o SDK 26.x se ele existir.
SDK_ARGS=()
OLD_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort | tail -1 || true)
if [ ! -d /Applications/Xcode.app ] && [ -n "$OLD_SDK" ]; then SDK_ARGS=(-sdk "$OLD_SDK"); fi

compile() { # $1 = arquitetura, $2 = saída
    swiftc -O -swift-version 5 -parse-as-library ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} \
        -target "$1-apple-macos13.0" \
        Sources/*.swift \
        -o "$2"
}

if [ "$MODE" = "release" ]; then
    compile arm64 build/Sinapse-arm64
    compile x86_64 build/Sinapse-x86_64
    lipo -create build/Sinapse-arm64 build/Sinapse-x86_64 -output "$APP/Contents/MacOS/Sinapse"
    rm build/Sinapse-arm64 build/Sinapse-x86_64
else
    compile "$(uname -m)" "$APP/Contents/MacOS/Sinapse"
fi

# Atributos estendidos (Finder, iCloud, quarentena) impedem a assinatura.
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Pronto: $(pwd)/$APP"

case "$MODE" in
    install)
        pkill -x Sinapse || true
        ditto "$APP" /Applications/Sinapse.app
        mdimport /Applications/Sinapse.app
        open /Applications/Sinapse.app
        echo "Instalado em /Applications/Sinapse.app"
        ;;
    release)
        (cd build && ditto -c -k --keepParent Sinapse.app Sinapse.zip)
        echo "Release: $(pwd)/build/Sinapse.zip"
        ;;
esac
