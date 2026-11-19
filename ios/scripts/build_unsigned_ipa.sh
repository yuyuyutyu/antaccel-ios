#!/bin/bash
# 只出未签名 IPA(不依赖任何证书),给 Windows 端用 ESign/zsign/爱思助手 本地重签
set -euo pipefail

OUT="${1:-AntiAccel-unsigned.ipa}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build-unsigned"

rm -rf "$BUILD"
mkdir -p "$BUILD/Payload"

xcodebuild \
  -project "$ROOT/AntiAccel.xcodeproj" \
  -target AntiAccel \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$BUILD/dd" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  DEVELOPMENT_TEAM="" \
  build | tail -n 20

APP="$BUILD/dd/Build/Products/Release-iphoneos/AntiAccel.app"
[ -d "$APP" ] || { echo "编译产物缺失: $APP"; exit 1; }

cp -R "$APP" "$BUILD/Payload/AntiAccel.app"
rm -rf "$BUILD/Payload/AntiAccel.app/_CodeSignature"
( cd "$BUILD" && /usr/bin/zip -qry "$OLDPWD/$OUT" Payload )
ls -lh "$OUT"
unzip -l "$OUT" | head -n 12
