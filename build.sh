#!/bin/bash
# 用 swiftc 构建 MuscleOS.app（仅需 Command Line Tools，不需要完整 Xcode）
# 默认构建通用版（Apple 芯片 + Intel）；只要本机架构：./build.sh --native
set -euo pipefail
cd "$(dirname "$0")"
OUT="build/MuscleOS.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build/obj
# 仅装 Command Line Tools 时，最新 SDK(27) 缺少 SwiftUI 宏插件(@State 等无法编译)，改用 26.x SDK
SDKARG=()
for v in MacOSX26.sdk MacOSX26.5.sdk; do
  if [ ! -d /Applications/Xcode.app ] && [ -d "/Library/Developer/CommandLineTools/SDKs/$v" ]; then
    SDKARG=(-sdk "/Library/Developer/CommandLineTools/SDKs/$v"); break
  fi
done
ARCHS=(arm64 x86_64)
[ "${1:-}" = "--native" ] && ARCHS=("$(uname -m)")
BINS=()
for a in "${ARCHS[@]}"; do
  swiftc -O -parse-as-library ${SDKARG[@]+"${SDKARG[@]}"} -target "$a-apple-macos14.0" \
    Sources/*.swift -o "build/obj/MuscleOS-$a"
  BINS+=("build/obj/MuscleOS-$a")
done
lipo -create "${BINS[@]}" -output "$OUT/Contents/MacOS/MuscleOS"
cp Info.plist "$OUT/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$OUT/Contents/Resources/"
codesign --force --sign - "$OUT"
echo "已构建：$(pwd)/$OUT（$(lipo -archs "$OUT/Contents/MacOS/MuscleOS")）"
