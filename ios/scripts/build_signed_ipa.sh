#!/bin/bash
# 安心加速器 iOS 壳 —— 编译 + p12 重签 + 打包 IPA(在 macOS 上运行)
# 用法:
#   P12_PASSWORD=123456 ./build_signed_ipa.sh -k cert.p12 -m profile.mobileprovision [-o out.ipa] [-b com.xxx.yyy]
set -euo pipefail

P12=""
PROFILE=""
OUT="AntiAccel.ipa"
BUNDLE_ID=""
TEAM_ID=""

usage() {
  cat <<EOF
参数:
  -k  <p12>          证书文件(必需)
  -m  <mobileprov>   描述文件(必需)
  -o  <ipa>          输出文件名,默认 AntiAccel.ipa
  -b  <bundle id>    强制覆盖 Bundle ID(默认跟随描述文件,最稳)
  -t  <team id>      强制指定 Team ID(默认跟随描述文件)
环境变量:
  P12_PASSWORD       证书口令,缺省空
EOF
  exit 1
}

while getopts ":k:m:o:b:t:h" opt; do
  case $opt in
    k) P12="$OPTARG" ;;
    m) PROFILE="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    b) BUNDLE_ID="$OPTARG" ;;
    t) TEAM_ID="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$P12" ] && usage
[ -z "$PROFILE" ] && usage
[ -f "$P12" ] || { echo "找不到证书: $P12"; exit 1; }
[ -f "$PROFILE" ] || { echo "找不到描述文件: $PROFILE"; exit 1; }

P12_PASSWORD="${P12_PASSWORD:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
PROJECT="$ROOT/AntiAccel.xcodeproj"
SCHEME="AntiAccel"
ARCHIVE="$BUILD/AntiAccel.xcarchive"
KEYCHAIN="$BUILD/sign.keychain-db"
KEYCHAIN_PASS="ipa-build-$$"
WORK="$BUILD/payload"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$WORK/Payload"
xcodebuild -version

echo "== 1. 解析描述文件 =="
PROFILE_PLIST="$BUILD/profile.plist"
security cms -D -i "$PROFILE" > "$PROFILE_PLIST"

PROFILE_UUID=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$PROFILE_PLIST")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$PROFILE_PLIST")
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$PROFILE_PLIST")
PROFILE_TEAM=$(echo "$APP_ID" | cut -d. -f1)
PROFILE_BUNDLE=$(echo "$APP_ID" | cut -d. -f2-)
[ -n "$TEAM_ID" ] || TEAM_ID="$PROFILE_TEAM"
[ -n "$BUNDLE_ID" ] || BUNDLE_ID="$PROFILE_BUNDLE"

echo "   描述文件: $PROFILE_NAME"
echo "   UUID    : $PROFILE_UUID"
echo "   TeamID  : $TEAM_ID"
echo "   BundleID: $BUNDLE_ID"

/usr/libexec/PlistBuddy -c "Print :Entitlements" "$PROFILE_PLIST" > "$BUILD/entitlements.plist" 2>/dev/null || true
if [ ! -s "$BUILD/entitlements.plist" ]; then
  cat > "$BUILD/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>application-identifier</key><string>${TEAM_ID}.${BUNDLE_ID}</string>
  <key>com.apple.developer.team-identifier</key><string>${TEAM_ID}</string>
  <key>get-task-allow</key><false/>
</dict>
</plist>
PLIST
fi

echo "== 2. 导入证书到临时钥匙串 =="
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -A
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | grep -o '"[^"]*"' | head -n 1 | tr -d '"')
[ -z "$IDENTITY" ] && { echo "证书导入失败,检查 p12 与口令"; exit 1; }
echo "   签名身份: $IDENTITY"

echo "== 3. 编译(不签名) =="
xcodebuild \
  -project "$PROJECT" \
  -target "AntiAccel" \
  -configuration Release \
  -sdk iphoneos \
  -archivePath "$ARCHIVE" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  DEVELOPMENT_TEAM="" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  archive | tail -n 30

APP_SRC="$ARCHIVE/Products/Applications/AntiAccel.app"
[ -d "$APP_SRC" ] || { echo "编译产物缺失: $APP_SRC"; exit 1; }

echo "== 4. 组装 Payload =="
cp -R "$APP_SRC" "$WORK/Payload/AntiAccel.app"
APP="$WORK/Payload/AntiAccel.app"

plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Info.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

echo "== 5. 逐层重签 =="
find "$APP" -name "*.framework" -maxdepth 3 -type d 2>/dev/null | while read -r fw; do
  echo "   framework: $(basename "$fw")"
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$fw" || true
done
find "$APP" \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null | while read -r lib; do
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$lib" || true
done
/usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$BUILD/entitlements.plist" --timestamp=none "$APP"

echo "== 6. 校验 =="
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | head -n 12
plutil -lint "$APP/Info.plist"

echo "== 7. 打包 IPA =="
( cd "$WORK" && /usr/bin/zip -qry "$OLDPWD/$OUT" Payload )
ls -lh "$OUT"
unzip -l "$OUT" | head -n 15

security delete-keychain "$KEYCHAIN" 2>/dev/null || true

echo
echo "完成: $(pwd)/$OUT"
echo "安装: 数据线连机用 Xcode Devices / 爱思助手投放, 或用 OTA 清单页分发"
echo "首次启动若提示未受信任: 设置 -> 通用 -> VPN与设备管理 -> 信任 $TEAM_ID"
