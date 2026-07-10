#!/usr/bin/env node --experimental-websocket
/**
 * Extract top articles from Yandex Dzen (dzen.ru) via Chrome DevTools Protocol.
 *
 * PREREQUISITES:
 *   Chrome launched with: --remote-debugging-port=9222 [--user-data-dir=/tmp/chrome-cdp-profile]
 *   Dzen open in a tab:     https://dzen.ru/articles?clid=1400
 *
 * USAGE:
 *   node --experimental-websocket extract-dzen-cdp.js
 *
 * OUTPUT: JSON — {count, articles: [{title, url, channel, views, views_raw, time, text_preview}]}
 */

const http = require("http");

function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve(JSON.parse(data)));
    }).on("error", reject);
  });
}

const EXTRACT_JS = `
(function() {
    var cards = document.querySelectorAll('[class*="card-article"]');
    var articles = [];
    var seen = new Set();

    cards.forEach(function(card) {
        var titleLink = card.querySelector('a[class*="titleLink"]');
        if (!titleLink) return;
        var href = titleLink.href.split('?')[0];
        if (seen.has(href)) return;
        seen.add(href);

        var title = titleLink.getAttribute('title') || titleLink.textContent.trim();
        var text = card.textContent.trim().replace(/\\\\s+/g, ' ');

        articles.push({
            title: title.substring(0, 250),
            url: href,
            channel: '',
            views_raw: '',
            time: '',
            text_preview: text.substring(0, 500)
        });
    });

    return JSON.stringify({count: articles.length, articles: articles});
})()`;

async function main() {
  const tabs = await getJson("http://127.0.0.1:9222/json");
  let wsUrl = null;
  for (const t of tabs) {
    if (t.url && t.url.includes("dzen.ru")) {
      wsUrl = t.webSocketDebuggerUrl;
      break;
    }
  }
  if (!wsUrl) {
    console.error("Dzen tab not found. Open https://dzen.ru/articles?clid=1400 in Chrome first.");
    process.exit(1);
  }

  const ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    ws.send(JSON.stringify({
      id: 1,
      method: "Runtime.evaluate",
      params: { expression: EXTRACT_JS, returnByValue: true },
    }));
  };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id === 1 && msg.result) {
      const raw = JSON.parse(msg.result.result.value);
      // Parse channels & views from text_preview
      raw.articles.forEach((a) => {
        const t = a.text_preview;
        // Channel is text before the view count
        const chMatch = t.match(/^(.+?)(\d[\d\s,]*)\s*(тыс|млн|читал|K|M)/);
        if (chMatch) a.channel = chMatch[1].trim();
        // Views
        const vMatch = t.match(/([\d\s,]+)\s*(тыс|млн)?\s*читал/);
        if (vMatch) a.views_raw = vMatch[0];
        // Time
        const tiMatch = t.match(/(\d+\s*(?:минут|час|день|дней|недел[ьи]|месяц)[а-яё]*\s*(?:назад)?)/i);
        if (tiMatch) a.time = tiMatch[1];
        // Clean up
        delete a.text_preview;
      });

      console.log(JSON.stringify(raw, null, 2));
      ws.close();
      process.exit(0);
    }
  };

  ws.onerror = (e) => { console.error("WebSocket error"); process.exit(1); };
  setTimeout(() => { console.error("Timeout"); process.exit(1); }, 15000);
}

main();
