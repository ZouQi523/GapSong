#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/GapSong.app"
BIN="$APP/Contents/MacOS/GapSong"

rm -rf "$APP"
rm -f build/GapSong.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.modulecache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos15.0" \
    -o "$BIN" \
    Sources/GapSong/*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework Translation \
    -framework NaturalLanguage \
    -framework CryptoKit

cp Resources/Info.plist "$APP/Contents/Info.plist"

# 从审核通过的原图生成 macOS 所需的各档图标，保留原图不变。
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Icons/gapsong-icon-v1.png \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Resources/Icons/gapsong-icon-v1.png \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# GPL 分发：二进制包内附一份许可证
if [ -f LICENSE ]; then cp LICENSE "$APP/Contents/Resources/LICENSE"; fi
# 同步目录可能自动附加 FinderInfo；在本机临时目录完成资源签名。
SIGNING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gapsong-sign.XXXXXX")
SIGNED_APP="$SIGNING_DIR/GapSong.app"
ditto --norsrc "$APP" "$SIGNED_APP"
xattr -cr "$SIGNED_APP"
codesign --force --sign - "$SIGNED_APP"
codesign --verify --strict "$SIGNED_APP"
ditto --norsrc "$SIGNED_APP" "$APP"
# 同步目录可能给 bundle 重新加上 FinderInfo：清一次；若同步服务又加回来，
# 只影响本地这个副本，分发包 build/GapSong.zip 已在临时目录验证过签名。
xattr -cr "$APP"
if ! codesign --verify --strict "$APP" 2>/dev/null; then
    echo "⚠️ build/GapSong.app 被同步服务附加了扩展属性；build/GapSong.zip 不受影响"
fi
# ZIP 保留已验证的签名，并隔离同步服务随后添加的扩展属性。
ditto -c -k --norsrc --noextattr --keepParent "$SIGNED_APP" build/GapSong.zip

echo "✅ built: $APP"

# ./build.sh --install：顺带覆盖安装到 /Applications，方便从启动台/聚焦搜索打开
if [ "${1:-}" = "--install" ]; then
    rm -rf /Applications/GapSong.app
    ditto --norsrc "$SIGNED_APP" /Applications/GapSong.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/GapSong.app 2>/dev/null || true
    echo "✅ installed: /Applications/GapSong.app"
fi
