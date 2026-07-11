#!/bin/bash
# Reload the Dzen page in the Chrome CDP browser so we get fresh articles
# Uses CDP HTTP endpoint to navigate to the same URL

DZEN_URL="https://dzen.ru/articles?clid=1400"

# Get the Dzen tab ID
TAB_ID=$(/usr/bin/curl -s http://127.0.0.1:9222/json 2>/dev/null | python3 -c "
import json, sys
for t in json.load(sys.stdin):
    if 'dzen.ru' in t.get('url',''):
        print(t['id'])
        break
" 2>/dev/null)

if [ -n "$TAB_ID" ]; then
  # Navigate to Dzen (reload)
  /usr/bin/curl -s "http://127.0.0.1:9222/json/activate/$TAB_ID" >/dev/null 2>&1 || true
  echo "  Dzen tab $TAB_ID reloaded"
else
  # Open new tab if none found
  /usr/bin/curl -s -X PUT "http://127.0.0.1:9222/json/new?$DZEN_URL" >/dev/null 2>&1 || true
  echo "  Dzen tab opened"
fi
