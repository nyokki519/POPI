#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "このアプリのビルドにはMacが必要です。Linuxではコメント処理のテストのみ実行できます。" >&2
    exit 69
fi
VERSION="$(sw_vers -productVersion)"
if (( ${VERSION%%.*} < 14 )); then
    echo "macOS 14以降が必要です。現在: $VERSION" >&2
    exit 69
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Apple Command Line Toolsが必要です。起動.commandから初回セットアップを実行してください。" >&2
    exit 69
fi
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${SDK_VERSION%%.*} < 14 )); then
    echo "macOS 14以降のSDKが必要です。Apple Command Line ToolsまたはXcodeを更新してください。現在のSDK: $SDK_VERSION" >&2
    exit 69
fi
BUILD="${GRAVITY_BUILD_DIR:-$HOME/Library/Application Support/GravityCommentReader/build}"
APP="$BUILD/GRAVITY Comment Reader.app"
mkdir -p "$BUILD"
# Include toolchain and launcher inputs in the cache identity.
HASH="$({ shasum -a 256 "$ROOT"/Sources/*.swift "$ROOT/scripts/build-mac.sh"; xcrun swiftc --version; printf "%s\n" "$SDK_VERSION"; } | shasum -a 256 | awk '{print $1}')"
if [[ -x "$APP/Contents/MacOS/GravityCommentReader" && -f "$BUILD/source.sha256" && "$(cat "$BUILD/source.sha256")" == "$HASH" ]]; then
    printf '%s\n' "$APP"
    exit 0
fi
# Build into a staging directory so a failed compile preserves the previous app.
STAGE="$(mktemp -d "$BUILD/staging.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
CANDIDATE="$STAGE/GRAVITY Comment Reader.app"
mkdir -p "$CANDIDATE/Contents/MacOS" "$CANDIDATE/Contents/Resources"
ARCH="$(uname -m)"
# Run core and native OCR checks automatically on the first build / source change.
xcrun swiftc -swift-version 5 -module-cache-path "$BUILD/module-cache" \
    "$ROOT/Sources/CommentCore.swift" "$ROOT/Tests/main.swift" -o "$STAGE/core-checks"
"$STAGE/core-checks" >&2
xcrun swiftc -swift-version 5 -target "$ARCH-apple-macos14.0" -module-cache-path "$BUILD/module-cache" \
    "$ROOT/Sources/CommentCore.swift" "$ROOT/Sources/CaptureOCR.swift" "$ROOT/Sources/SpeechOutput.swift" "$ROOT/Tests/MacChecks.swift" \
    -framework AppKit -framework ScreenCaptureKit -framework Vision -framework AVFoundation -framework CoreAudio -framework AudioToolbox -framework CoreVideo \
    -o "$STAGE/mac-checks"
"$STAGE/mac-checks" >&2
xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos14.0" \
    -module-cache-path "$BUILD/module-cache" \
    "$ROOT/Sources/CommentCore.swift" "$ROOT/Sources/CaptureOCR.swift" "$ROOT/Sources/SpeechOutput.swift" "$ROOT/Sources/App.swift" \
    -framework AppKit -framework ScreenCaptureKit -framework Vision -framework AVFoundation -framework CoreAudio -framework AudioToolbox -framework CoreVideo \
    -o "$CANDIDATE/Contents/MacOS/GravityCommentReader"
cat > "$CANDIDATE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GravityCommentReader</string>
<key>CFBundleIdentifier</key><string>org.popi.gravitycommentreader</string>
<key>CFBundleName</key><string>GRAVITY Comment Reader</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>選択したGRAVITYコメント欄を読み取り、Macで読み上げるために使用します。</string>
</dict></plist>
PLIST
plutil -lint "$CANDIDATE/Contents/Info.plist" >&2
codesign --force --sign - --identifier org.popi.gravitycommentreader "$CANDIDATE" >&2
codesign --verify --strict "$CANDIDATE" >&2
# Replace only the app produced by this builder, after successful validation.
if [[ -d "$APP" ]]; then rm -rf "$APP"; fi
mv "$CANDIDATE" "$APP"
printf '%s\n' "$HASH" > "$BUILD/source.sha256"
printf '%s\n' "$APP"
