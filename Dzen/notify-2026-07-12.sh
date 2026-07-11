#!/bin/bash
# Dzen Daily 2026-07-12 — push notification
/usr/bin/curl -H "Title: Dzen Daily 2026-07-12 ✅" \
  -H "Priority: default" \
  -H "Click: http://127.0.0.1:27123/vault/Dzen/Daily/2026-07-12.md" \
  -d "Анализ завершён. Топ: история+СССР+авто. 20 статей, гипотезы и A/B заголовки в Obsidian." \
  https://ntfy.sh/sergey-test-4729
