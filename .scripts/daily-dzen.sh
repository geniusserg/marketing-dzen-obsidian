#!/bin/zsh -l
# Daily Dzen pipeline — runs at 20:00 via LaunchAgent
# Requires: Chrome + CDP (port 9222), Obsidian running, claude CLI
set -euo pipefail

VAULT="$HOME/Marketing"
TODAY=$(date +%Y-%m-%d)
LOG="/tmp/dzen-daily-${TODAY}.log"
exec 2>&1 | tee "$LOG"

echo "=== DZEN DAILY ${TODAY} ==="
echo "Start: $(date)"

# ── Stage 1: Launch Chrome with CDP (or reuse existing) ────
echo "→ Stage 1: Chrome CDP"
CDP_ALIVE=""
/usr/bin/curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1 && CDP_ALIVE=1 || true

if [ -z "$CDP_ALIVE" ]; then
  echo "  CDP not running, launching Chrome..."
  "$VAULT/.scripts/launch-dzen-cdp.sh" >> "$LOG" 2>&1
  # Wait for CDP port to open (up to 20s)
  for i in {1..20}; do
    /usr/bin/curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1 && break
    sleep 1 2>/dev/null || true
  done
  # Extra wait for Dzen page to render
  sleep 8 2>/dev/null || true
else
  echo "  CDP already alive, reusing"
  # Refresh Dzen page to get fresh articles
  "$VAULT/.scripts/reload-dzen-cdp.sh" 2>/dev/null || true
  sleep 5 2>/dev/null || true
fi

# ── Stage 2: Extract articles (with retry) ─────────────────
echo "→ Stage 2: Extracting articles via CDP"
cd "$VAULT"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

ARTICLES=0
for attempt in 1 2; do
  node --experimental-websocket .scripts/extract-dzen-cdp.js > "Dzen/Raw/${TODAY}.json" 2>> "$LOG" || true
  ARTICLES=$(python3 -c "import json; print(len(json.load(open('Dzen/Raw/${TODAY}.json'))['articles']))" 2>/dev/null || echo 0)
  echo "  Attempt $attempt: $ARTICLES articles"
  if [ "$ARTICLES" -gt 0 ]; then break; fi
  # Retry: reload page, wait longer
  "$VAULT/.scripts/reload-dzen-cdp.sh" 2>/dev/null || true
  sleep 10 2>/dev/null || true
done

echo "  Raw JSON: $(wc -c < "Dzen/Raw/${TODAY}.json") bytes, $ARTICLES articles"

if [ "$ARTICLES" -eq 0 ]; then
  echo "❌ FAILED: 0 articles after 2 attempts. Aborting."
  /usr/bin/curl -s -H "Title: Dzen FAILED ${TODAY}" -H "Priority: high" \
    -d "❌ 0 статей после 2 попыток. Проверь Chrome CDP." \
    https://ntfy.sh/sergey-test-4729 >/dev/null
  exit 1
fi

# ── Stage 3: Create article notes ───────────────────────────
echo "→ Stage 3: Creating article notes"
python3 "$VAULT/.scripts/create-article-notes.py" "$TODAY" >> "$LOG" 2>&1
echo "  Notes created"

# ── Stage 4: 4 parallel Claude agents ──────────────────────
echo "→ Stage 4: Launching 4 parallel Claude agents"
# settings.json permissions allow Bash/Read/Write/Agent for this vault
# settings.json env provides ANTHROPIC_AUTH_TOKEN

RAWF="$VAULT/Dzen/Raw/${TODAY}.json"
API="http://127.0.0.1:27123"

# Agent 1: Researcher
claude -p --dangerously-skip-permissions "Ты — marketing-аналитик Яндекс.Дзена. Прочитай $RAWF (20 статей). Дай анализ: топ-5 по просмотрам, группы тем, 6 категорий заголовков с подсчётом, доминирующие каналы. Сохрани ВСЕ результаты через REST API:
- PUT $API/vault/Dzen/Patterns/Hook%20Patterns.md (Authorization: Bearer \$OBSIDIAN_REST_API_KEY, Content-Type: text/markdown). YAML frontmatter: date: ${TODAY}. Включи таблицу паттернов заголовков с примерами и средними просмотрами.
- PUT $API/vault/Dzen/Patterns/Topic%20Heatmap.md — тепловая карта тем: сколько статей, сумма просмотров, средний охват.
Используй /usr/bin/curl для всех запросов. Добавляй [[wikilinks]] на Dzen/Daily/${TODAY}." \
  >> "$LOG" 2>&1 &

# Agent 2: Brainstormer
claude -p --dangerously-skip-permissions "Ты — креативный редактор Яндекс.Дзена. Прочитай $RAWF. На основе реальных популярных статей придумай 5 новых статей на русском языке. Для каждой: заголовок, почему сработает (какой паттерн из топа), структура (крючок→тело→раскрытие), на какую статью из топа похожа. Сохрани через REST API:
- PUT $API/vault/Dzen/Ideas/${TODAY}.md (Authorization: Bearer \$OBSIDIAN_REST_API_KEY, Content-Type: text/markdown). YAML frontmatter: date: ${TODAY}. Добавь [[wikilinks]] на Dzen/Daily/${TODAY} и референсные статьи." \
  >> "$LOG" 2>&1 &

# Agent 3: Copywriter
claude -p --dangerously-skip-permissions "Ты — редактор заголовков Дзена. Прочитай $RAWF. Выбери 5 лучших статей. Для каждой придумай минимум 2 A/B варианта заголовка. Оцени каждый по шкалам: кликабельность (1-10), интрига (1-10), ясность (1-10). Дай рекомендации по усилению (глаголы, цифры, «на самом деле», контраст). Сохрани через REST API:
- PUT $API/vault/Dzen/Ideas/${TODAY}-validated.md (Authorization: Bearer \$OBSIDIAN_REST_API_KEY, Content-Type: text/markdown). YAML frontmatter: date: ${TODAY}. [[wikilinks]] на Dzen/Daily/${TODAY}." \
  >> "$LOG" 2>&1 &

# Agent 4: Project Manager
claude -p --dangerously-skip-permissions "Ты — project manager. Для сегодняшнего анализа Дзена (${TODAY}) заверши работу. Прочитай $RAWF и готовые заметки в Dzen/Articles/${TODAY}/. Сделай:
1. PUT $API/vault/Dzen/Daily/${TODAY}.md — сводный дайджест с таблицей топ-10. В таблице ОБЯЗАТЕЛЬНО 5 колонок: # | Заголовок | Канал | Просмотры | 🔗 Дзен (ссылка на dzen.ru) | 📝 Obsidian ([[wikilink]] на заметку). Добавь паттерны дня, идеи, гипотезы.
2. PUT $API/vault/Dzen/Index.md — обнови MOC: добавь сегодняшний дайджест, идеи, валидированные заголовки.
3. PUT $API/vault/Dzen/Playbook.md — обнови накопленную стратегию новыми паттернами (сравни с предыдущими днями если есть).
4. Отправь пуш: /usr/bin/curl -H 'Title: Dzen Daily ${TODAY} ✅' -H 'Priority: default' -d '📊 Топ Дзена за ${TODAY}. N статей, дайджест в Obsidian.' https://ntfy.sh/sergey-test-4729
Все PUT через REST API (Authorization: Bearer \$OBSIDIAN_REST_API_KEY, Content-Type: text/markdown). Везде YAML frontmatter с date: ${TODAY} и [[wikilinks]]." \
  >> "$LOG" 2>&1 &

# Wait for all 4 agents
wait
echo "→ All 4 agents finished: $(date)"
echo "=== PIPELINE COMPLETE ==="
