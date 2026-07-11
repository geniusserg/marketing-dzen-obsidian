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

# ── Stage 4: Claude with 4 agents ───────────────────────────
echo "→ Stage 4: Claude analysis (4 agents)"
# settings.json env provides ANTHROPIC_AUTH_TOKEN etc.

claude -p "$(cat <<PROMPT
Ты — marketing-аналитик. Только что спарсены топ-статьи сегодняшнего Яндекс.Дзена (${TODAY}). Они лежат в:
- Raw JSON: $VAULT/Dzen/Raw/${TODAY}.json
- Готовые заметки: $VAULT/Dzen/Articles/${TODAY}/
- Obsidian vault: $VAULT (REST API http://127.0.0.1:27123/vault/, ключ из env OBSIDIAN_REST_API_KEY)

Твоя задача — разбить работу на 4 агента (запускай их ПАРАЛЛЕЛЬНО через Agent tool):

🎯 **Agent 1 — Researcher (анализ паттернов)**
Прочитай Dzen/Raw/${TODAY}.json. Выдели:
- Топ-5 статей по просмотрам
- Общие темы и повторяющиеся форматы
- Паттерны заголовков (вопросы, цифры, провокация, контраст)
- Какие каналы доминируют
Сохрани выводы через REST API PUT в Dzen/Patterns/Hook Patterns.md и Dzen/Patterns/Topic Heatmap.md. YAML frontmatter: date: ${TODAY}.

🎯 **Agent 2 — Brainstormer (генерация идей)**
На основе паттернов от Researcher придумай 5 новых статей для Дзена — с заголовками, примерной структурой и почему это сработает. Сохрани через REST API в Dzen/Ideas/${TODAY}.md.

🎯 **Agent 3 — Copywriter (A/B заголовки)**
Возьми идеи от Brainstormer. Предложи минимум 2 A/B-варианта заголовка на каждую идею. Проверь на кликабельность. Сохрани через REST API в Dzen/Ideas/${TODAY}-validated.md.

🎯 **Agent 4 — Project Manager (дайджест + пуш)**
Собери всё вместе:
- Напиши Dzen/Daily/${TODAY}.md — сводный дайджест: таблица топ-10 (с колонками: 🔗 ссылка на Дзен, 📝 [[wikilink]] на заметку в Obsidian), ключевые выводы
- Обнови Dzen/Index.md — добавь ссылку на сегодняшний дайджест
- Отправь результат в ntfy.sh:
  curl -H "Title: Dzen Daily ${TODAY}" -H "Priority: default" -H "Click: http://127.0.0.1:27123/vault/Dzen/Daily/${TODAY}.md" \
    -d "Топ-5 Дзена за сегодня. Читай дайджест в Obsidian." https://ntfy.sh/sergey-test-4729

**Важно:** все файлы сохраняй через Obsidian REST API (PUT http://127.0.0.1:27123/vault/путь/к/файлу.md, Authorization: Bearer \$OBSIDIAN_REST_API_KEY). У каждой заметки YAML frontmatter с date: ${TODAY}. В дайджесте ОБЯЗАТЕЛЬНО делай таблицу с двумя ссылками: внешняя (🔗 на dzen.ru) и внутренняя (📝 [[wikilink]]).
PROMPT
)" >> "$LOG" 2>&1

echo "→ Done: $(date)"
echo "=== PIPELINE COMPLETE ==="
