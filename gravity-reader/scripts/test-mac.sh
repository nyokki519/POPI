#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == "Darwin" ]] || { echo "Mac専用検査です。" >&2; exit 69; }
bash "$ROOT/scripts/test-core.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gravity-mac-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$WORK/cache" \
 "$ROOT/Sources/CommentCore.swift" "$ROOT/Sources/CaptureOCR.swift" "$ROOT/Sources/SpeechOutput.swift" "$ROOT/Tests/MacChecks.swift" \
 -framework AppKit -framework ScreenCaptureKit -framework Vision -framework AVFoundation -framework CoreAudio -framework AudioToolbox -framework CoreVideo -o "$WORK/mac-checks"
"$WORK/mac-checks"
bash "$ROOT/scripts/build-mac.sh"
