#!/bin/bash
# 为 32 位老 iPad（armv7，iOS 9.3+：iPad mini 1、iPad 4 等）手工编译 MusicPlayer.app。
# 新版 Xcode 的 SDK 没有 32 位库，所以这里只借用它的头文件，
# 链接时用自己生成的 .tbd 桩（只含 install-name），符号留给设备上的 dyld 解析。
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
TARGET=armv7-apple-ios9.3
OUT=build
APP=$OUT/MusicPlayer.app
rm -rf "$APP" "$OUT/stubs"
mkdir -p "$APP" "$OUT/stubs"

stub() { # 名称 install-name [导出符号]
  cat > "$OUT/stubs/$1.tbd" <<EOF
--- !tapi-tbd
tbd-version:     4
targets:         [ armv7-ios ]
install-name:    '$2'
exports:
  - targets:         [ armv7-ios ]
    symbols:         [ ${3:-} ]
...
EOF
}
stub libSystem /usr/lib/libSystem.B.dylib dyld_stub_binder
stub libobjc /usr/lib/libobjc.A.dylib
for fw in Foundation CoreFoundation UIKit CoreGraphics QuartzCore AVFoundation CoreMedia MediaPlayer; do
  stub $fw /System/Library/Frameworks/$fw.framework/$fw
done

for src in Main Sonos; do
  # -marm：全部按 ARM（非 Thumb）指令编译。新版 Xcode 的链接器不再给指向 Thumb 代码的指针
  # （入口点、方法实现、block 等）打 Thumb 标记，老系统会以 ARM 模式执行 Thumb 代码而崩溃。
  xcrun clang -target $TARGET -isysroot "$SDK" -fobjc-arc -Os -fno-autolink -marm \
    -Wall -Werror=unguarded-availability -Wno-deprecated-declarations \
    -c $src.m -o "$OUT/$src.o"
done

xcrun clang -target $TARGET -isysroot "$SDK" -nostdlib \
  -Wl,-undefined,dynamic_lookup -Wl,-dead_strip \
  "$OUT/Main.o" "$OUT/Sonos.o" "$OUT"/stubs/*.tbd -o "$APP/MusicPlayer"

cp Info.plist "$APP/Info.plist"
plutil -convert binary1 "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"
xcrun swift MakeIcon.swift "$APP"

file "$APP/MusicPlayer"
echo "built $APP"
