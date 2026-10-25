#!/bin/zsh
# アイコン（.icns）を作る
#   tools/make_icon.sh <出力.icns> <形> <色 #RRGGBB>
set -euo pipefail
cd "${0:A:h}/.."

OUT=${1:?出力先の .icns を指定してください}
STYLE=${2:-corner}
ACCENT=${3:-#4C5BD4}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift tools/make_icon.swift "$WORK/icon_1024.png" "$STYLE" "$ACCENT"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z $px $px "$WORK/icon_1024.png" --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) "$WORK/icon_1024.png" --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
mkdir -p "${OUT:h}"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "作成しました: $OUT"
