#!/bin/zsh
# アプリを .app にまとめる。
#   ./build.sh          build/<名前>.app を作る
#   ./build.sh install  ~/Applications に入れて起動する
# 名前と見た目は brand/public.env で決まる。local/brand.env があれば、そちらを使う（手元用）。
#   BRAND=public ./build.sh  手元用の設定があっても、公開版で作る
set -euo pipefail
cd "${0:A:h}"

BRAND_FILE=brand/public.env
[[ "${BRAND:-}" != "public" && -f local/brand.env ]] && BRAND_FILE=local/brand.env
ICON_FILE=""
ICON_STYLE=corner
source "$BRAND_FILE"
echo "見た目の設定: $BRAND_FILE（$DISPLAY_NAME）"

# ビルドの中間ファイルは Dropbox で同期しない
mkdir -p .build build
xattr -w com.dropbox.ignored 1 .build 2>/dev/null || true
xattr -w com.dropbox.ignored 1 build 2>/dev/null || true

swift build -c release

# アイコン：ICON_FILE があればそれを使い、なければ描く
if [[ -z "$ICON_FILE" ]]; then
  ICON_FILE="build/icons/$APP_NAME-$ICON_STYLE-${ACCENT#\#}.icns"
  [[ -f "$ICON_FILE" ]] || ./tools/make_icon.sh "$ICON_FILE" "$ICON_STYLE" "$ACCENT"
fi

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Kado "$APP/Contents/MacOS/$APP_NAME"
cp "$ICON_FILE" "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
plutil -replace CFBundleExecutable -string "$APP_NAME" "$PLIST"
plutil -replace CFBundleName -string "$APP_NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$PLIST"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleURLTypes.0.CFBundleURLName -string "$BUNDLE_ID" "$PLIST"
plutil -replace CFBundleURLTypes.0.CFBundleURLSchemes -json "[\"$URL_SCHEME\"]" "$PLIST"
plutil -replace BrandAccentColor -string "$ACCENT" "$PLIST"
plutil -replace BrandSymbol -string "$SYMBOL" "$PLIST"

codesign --force --sign - "$APP"
echo "作成しました: $APP"

if [[ "${1:-}" == "install" ]]; then
  DEST="$HOME/Applications/$APP_NAME.app"
  mkdir -p "$HOME/Applications"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # URL スキームがインストールした方に届くよう、build/ の方は登録を外す
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
  "$LSREGISTER" -f "$DEST" 2>/dev/null || true
  open "$DEST"
  echo "インストールして起動しました: $DEST"
fi
