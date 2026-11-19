#!/bin/bash
# macOS 端:用 p12 + mobileprovision 重签已有 IPA
# ./resign_ipa.sh -i in.ipa -k cert.p12 -m profile.mobileprovision [-p p12pwd] [-o out.ipa]
set -euo pipefail
IPA=""; P12=""; PROFILE=""; OUT="out-signed.ipa"; PWD12="${P12_PASSWORD:-}"
while getopts ":i:k:m:p:o:" o; do
  case $o in
    i) IPA="$OPTARG";; k) P12="$OPTARG";; m) PROFILE="$OPTARG";; p) PWD12="$OPTARG";; o) OUT="$OPTARG";;
    *) echo "用法: $0 -i in.ipa -k cert.p12 -m profile.mobileprovision [-p pwd] [-o out.ipa]"; exit 1;;
  esac
done
[ -f "$IPA" ] && [ -f "$P12" ] && [ -f "$PROFILE" ] || { echo "参数缺失"; exit 1; }

TMP=$(mktemp -d)
unzip -q "$IPA" -d "$TMP"
APP=$(find "$TMP/Payload" -maxdepth 1 -name "*.app" | head -n 1)
[ -d "$APP" ] || { echo "IPA 里没有 Payload/*.app"; exit 1; }

KC=$(mktemp -d)/sign.keychain-db
security create-keychain -p tmp123 "$KC"
security unlock-keychain -p tmp123 "$KC"
security import "$P12" -k "$KC" -P "$PWD12" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k tmp123 "$KC" >/dev/null
IDENTITY=$(security find-identity -v -p codesigning "$KC" | grep -o '"[^"]*"' | head -n 1 | tr -d '"')

security cms -D -i "$PROFILE" > "$TMP/profile.plist"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$TMP/profile.plist")
OLD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
NEW=$(echo "$BUNDLE" | cut -d. -f2-)
echo "包名: $OLD -> $NEW"
plutil -replace CFBundleIdentifier -string "$NEW" "$APP/Info.plist"

/usr/libexec/PlistBuddy -c "Print :Entitlements" "$TMP/profile.plist" > "$TMP/ent.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

find "$APP" \( -name "*.appex" -o -name "*.framework" -o -name "*.dylib" \) | while read -r sub; do
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$sub" || true
done
/usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$TMP/ent.plist" --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

( cd "$TMP" && zip -qry "$OLDPWD/$OUT" Payload )
security delete-keychain "$KC" 2>/dev/null || true
rm -rf "$TMP"
ls -lh "$OUT"
