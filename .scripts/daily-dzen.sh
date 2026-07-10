#!/bin/zsh -l
# Daily Dzen pipeline — runs at 20:00 via LaunchAgent
# Requires: Chrome + CDP (port 9222), Obsidian running, claude CLI, gh CLI
set -euo pipefail

VAULT="$HOME/Marketing"
TODAY=$(date +%Y-%m-%d)
LOG="/tmp/dzen-daily-${TODAY}.log"
exec 2>&1 | tee -a "$LOG"

echo "=== DZEN DAILY ${TODAY} ==="
echo "Start: $(date)"

# ── Stage 1: Launch Chrome with CDP ──────────────────────
echo "→ Stage 1: Launching Chrome CDP"
"$VAULT/.scripts/launch-dzen-cdp.sh" >> "$LOG" 2>&1
# Wait for browser + page load
for i in {1..15}; do
  /usr/bin/curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1 && break
  true  # minimal wait
done

# ── Stage 2: Extract articles ────────────────────────────
echo "→ Stage 2: Extracting articles via CDP"
cd "$VAULT"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

node --experimental-websocket .scripts/extract-dzen-cdp.js > "Dzen/Raw/${TODAY}.json" 2>> "$LOG"
echo "  Raw JSON saved ($(wc -c < "Dzen/Raw/${TODAY}.json") bytes, $(python3 -c "import json; print(len(json.load(open('Dzen/Raw/${TODAY}.json'))['articles']), 'articles')"))"

# ── Stage 3: Claude with 4 agents ────────────────────────
echo "→ Stage 3: Claude analysis (4 agents)"
# settings.json env provides ANTHROPIC_AUTH_TOKEN etc.

claude -p "$(cat <<PROMPT
Ты — marketing-аналитик. Только что спарсены топ-статьи сегодняшнего Яндекс.Дзена. Они лежат в:
- Raw JSON: $VAULT/Dzen/Raw/${TODAY}.json
- Obsidian vault: $VAULT (доступен по REST API http://127.0.0.1:27123/vault/, ключ из env OBSIDIAN_REST_API_KEY)

Твоя задача — разбить работу на 4 агента (запускай их параллельно через Agent tool):

🎯 **Agent 1 — Researcher (анализ паттернов)**
Прочитай Dzen/Raw/${TODAY}.json. Выдели:
- Топ-5 статей по просмотрам
- Общие темы и повторяющиеся форматы
- Паттерны заголовков (вопросы, цифры, провокация, контраст)
- Какие каналы доминируют
Сохрани выводы в Dzen/Patterns/Hook Patterns.md и Dzen/Patterns/Topic Heatmap.md (через REST API PUT). Используй YAML frontmatter с date: ${TODAY}.

🎯 **Agent 2 — Brainstormer (генерация идей)**
На основе паттернов от Researcher придумай 5 новых статей для Дзена — с заголовками, примерной структурой и почему это сработает. Сохрани в Dzen/Ideas/${TODAY}.md.

🎯 **Agent 3 — Copywriter (валидация + улучшение)**
Возьми идеи от Brainstormer. Проверь заголовки на кликабельность (цифры, вопросы, интрига). Предложи улучшения. Добавь A/B-варианты заголовков (минимум 2 варианта на каждую идею). Сохрани в Dzen/Ideas/${TODAY}-validated.md.

🎯 **Agent 4 — Project Manager (дайджест + пуш)**
Собери всё вместе:
- Напиши Dzen/Daily/${TODAY}.md — сводный дайджест с таблицей топ-5, ключевыми выводами и ссылками [[wikilinks]] на все материалы дня
- Обнови Dzen/Index.md — добавь ссылку на сегодняшний дайджест
- Обнови Dzen/Playbook.md — добавь новые паттерны если они появились
- Отправь результат в ntfy.sh: curl -H "Title: Dzen Daily ${TODAY}" -H "Priority: default" -d "Топ-5 Дзена за сегодня обработан. Читай: http://127.0.0.1:27123/vault/Dzen/Daily/${TODAY}.md" https://ntfy.sh/sergey-test-4729

**Важно:** все файлы сохраняй через Obsidian REST API (PUT http://127.0.0.1:27123/vault/путь/к/файлу.md, заголовок Authorization: Bearer \$OBSIDIAN_REST_API_KEY). У каждой заметки должен быть YAML frontmatter с date: ${TODAY}.
PROMPT
)" >> "$LOG" 2>&1

echo "→ Done: $(date)"
echo "=== PIPELINE COMPLETE ==="
