#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${GRAVITY_SWIFTC:-swiftc}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gravity-investigate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
"$COMPILER" -module-cache-path "$WORK/cache" -swift-version 5 -O \
  "$ROOT/Sources/Shared/CommentCore.swift" "$ROOT/Sources/Shared/ChatLayout.swift" \
  "$ROOT/research/reading-v0.5/main.swift" -o "$WORK/probe"
"$WORK/probe"
