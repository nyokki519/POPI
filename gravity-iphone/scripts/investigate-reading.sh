#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${GRAVITY_SWIFTC:-swiftc}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gravity-investigate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# This is an archival reproduction of v0.5 bugs, not the current regression suite.
BASE=b2d18fc78c6d7f17492c9c67609476be03b37359
for SOURCE in CommentCore ChatLayout; do
  git -C "$ROOT" show "$BASE:gravity-iphone/Sources/Shared/$SOURCE.swift" > "$WORK/$SOURCE.swift"
done
"$COMPILER" -module-cache-path "$WORK/cache" -swift-version 5 -O \
  "$WORK/CommentCore.swift" "$WORK/ChatLayout.swift" \
  "$ROOT/research/reading-v0.5/main.swift" -o "$WORK/probe"
"$WORK/probe"
