#!/usr/bin/env bash
# Screenshots og.html into public/og.png with the system Chrome. No deps.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || CHROME="$(command -v google-chrome || command -v chromium || true)"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1200,630 \
  --virtual-time-budget=4000 --screenshot="$PWD/public/og.png" "file://$PWD/og.html" 2>/dev/null
command -v pngquant >/dev/null && pngquant --quality=55-75 --force --output public/og.png public/og.png || true
command -v oxipng >/dev/null && oxipng -o 4 --strip safe public/og.png || true
ls -la public/og.png
