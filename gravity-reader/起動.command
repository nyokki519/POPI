#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Macで起動してください。macOS 14以降に対応しています。"
    exit 69
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "初回のみ、AppleのCommand Line Toolsをインストールする必要があります。"
    echo "これから表示されるAppleの画面でインストールしてください。"
    echo "完了後、もう一度この起動.commandをダブルクリックしてください。"
    xcode-select --install || true
    read -r -p "Enterで閉じます。" _
    exit 0
fi
LOG="$HOME/Library/Logs/GravityCommentReader"
mkdir -p "$LOG"
echo "GRAVITY Comment Readerを準備しています。初回は少し時間がかかります。"
if APP="$(bash "$ROOT/scripts/build-mac.sh" 2> "$LOG/build.log")"; then
    open "$APP"
    echo "アプリを開きました。次回から同じ起動.commandを使えます。"
    echo "生成されたアプリ: $APP"
else
    echo "ビルドに失敗しました。下にエラーを表示します。"
    cat "$LOG/build.log"
    echo "ログ: $LOG/build.log"
    read -r -p "Enterで閉じます。" _
    exit 1
fi
