#!/usr/bin/env python3
"""Create individual article .md notes from Dzen/Raw/{date}.json"""
import json, os, re, sys

TODAY = sys.argv[1] if len(sys.argv) > 1 else None
if not TODAY:
    print("Usage: create-article-notes.py YYYY-MM-DD")
    sys.exit(1)

VAULT = os.path.expanduser("~/Marketing")
ART_DIR = f"{VAULT}/Dzen/Articles/{TODAY}"
os.makedirs(ART_DIR, exist_ok=True)

with open(f"{VAULT}/Dzen/Raw/{TODAY}.json") as f:
    data = json.load(f)

articles = data["articles"]

def parse_views(v):
    if not v: return 0
    v = re.sub(r'читал[аи]?', '', v)
    v = v.replace(" ", "").replace(" ", "").replace(" ", "")
    if "млн" in v:
        return float(v.replace("млн", "").replace(",", ".")) * 1_000_000
    if "тыс" in v:
        return float(v.replace("тыс", "").replace(",", ".")) * 1_000
    try:
        return float(v)
    except:
        return 0

articles.sort(key=lambda a: parse_views(a.get("views_raw", "0")), reverse=True)

for i, a in enumerate(articles):
    num = f"{i+1:02d}"
    safe_title = a["title"][:90].replace("/", "-").replace(":", " -").replace("?", "").replace('"', "'").replace("«", "").replace("»", "").strip()
    filename = f"{num} - {safe_title}.md"

    content = f"""---
date: {TODAY}
source_url: {a['url']}
views: {parse_views(a.get('views_raw','')):,.0f}
views_raw: {a.get('views_raw', '')}
channel: {a.get('channel', '')}
time: {a.get('time', '')}
topics: []
hooks: []
---

# {a['title']}

**Канал:** {a.get('channel', '?')}
**Просмотров:** {a.get('views_raw', '?')}
**Опубликовано:** {a.get('time', '?')}

🔗 [Читать на Дзене]({a['url']})

---
*Собрано автоматически. См. [[Dzen/Daily/{TODAY}|дайджест за {TODAY}]].*
"""
    with open(f"{ART_DIR}/{filename}", "w") as f:
        f.write(content)

print(f"✓ {len(articles)} article notes created in {ART_DIR}")
