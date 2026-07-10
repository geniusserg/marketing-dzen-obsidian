#!/bin/bash
# Launch Chrome with CDP for Dzen extraction.
# The Chrome profile lives in /tmp/chrome-cdp-profile (isolated from main profile).
# You'll need to log into Dzen once in this profile.

PROFILE="/tmp/chrome-cdp-profile"
CDP_PORT=9222
DZEN_URL="https://dzen.ru/articles?clid=1400"

# Kill any existing Chrome
osascript -e 'tell application "Google Chrome" to quit' 2>/dev/null || true
pkill -9 -x "Google Chrome" 2>/dev/null || true
sleep 3

# Fresh profile if needed
[ -d "$PROFILE" ] || mkdir -p "$PROFILE"

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port="$CDP_PORT" \
  --user-data-dir="$PROFILE" \
  "$DZEN_URL" \
  > /tmp/chrome-cdp.log 2>&1 &

echo "Chrome launched (PID $!). CDP on port $CDP_PORT."
echo "Profile: $PROFILE (log into Dzen once, then run: node --experimental-websocket .scripts/extract-dzen-cdp.js)"
