#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gravity-native.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
swiftc -swift-version 5 -O "$ROOT/Sources/Shared/CommentCore.swift" "$ROOT/Sources/Shared/ChatLayout.swift" "$ROOT/Sources/Upload/ChatFrameProcessor.swift" "$ROOT/Tests/Native/main.swift" -o "$WORK/native"
"$WORK/native"
