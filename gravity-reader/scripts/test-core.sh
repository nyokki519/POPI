#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${GRAVITY_SWIFTC:-swiftc}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gravity-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
"$COMPILER" -module-cache-path "$WORK/cache" -swift-version 5 "$ROOT/Sources/CommentCore.swift" "$ROOT/Tests/main.swift" -o "$WORK/tests"
"$WORK/tests"
"$COMPILER" -module-cache-path "$WORK/cache" -swift-version 5 "$ROOT/Sources/CommentCore.swift" "$ROOT/Tests/Replay/main.swift" -o "$WORK/replay"
"$WORK/replay"
