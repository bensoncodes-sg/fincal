// Basis feedback relay: a Cloudflare Worker.
//
// The app POSTs its feedback JSON here. This Worker holds the Telegram bot
// token as a SECRET and forwards a plain-text message to your chat. The token
// never reaches the app, so nobody reading the web app's code can use it.
//
// Settings > Variables and Secrets:
//   TELEGRAM_TOKEN    (Secret)  from @BotFather
//   TELEGRAM_CHAT_ID  (Secret)  your chat id
//   ALLOWED_ORIGINS   (Text)    e.g. https://basis-calculators.onrender.com
//
// It accepts only the shape the app sends, caps lengths, allows only your
// site's origin, and throttles each visitor, so the endpoint being public
// cannot turn your Telegram into a spam inbox.

const CATEGORIES = {
  wrongNumber: 'A number looks wrong',
  bug: 'Something is broken',
  suggestion: 'Suggestion',
  other: 'Something else',
};
const MAX_MESSAGE = 2000;
const WINDOW_MS = 10 * 60 * 1000; // 10 minutes
const MAX_PER_WINDOW = 5;
const recent = new Map(); // best effort, per Worker instance

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allowed = (env.ALLOWED_ORIGINS || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    const originOk = allowed.includes(origin);
    const cors = {
      'Access-Control-Allow-Origin': originOk ? origin : 'null',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Accept',
      'Access-Control-Max-Age': '86400',
      Vary: 'Origin',
    };
    const reply = (status, body) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { ...cors, 'Content-Type': 'application/json' },
      });

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: originOk ? 204 : 403, headers: cors });
    }
    if (request.method !== 'POST') return reply(405, { error: 'POST only' });
    // Browsers always send Origin on a cross-site POST. The Android app does
    // not, so a missing Origin is allowed; a wrong one is not.
    if (origin && !originOk) return reply(403, { error: 'origin not allowed' });
    if (!env.TELEGRAM_TOKEN || !env.TELEGRAM_CHAT_ID) {
      return reply(500, { error: 'relay not configured' });
    }

    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    const now = Date.now();
    const hits = (recent.get(ip) || []).filter((t) => now - t < WINDOW_MS);
    if (hits.length >= MAX_PER_WINDOW) return reply(429, { error: 'slow down' });
    hits.push(now);
    recent.set(ip, hits);

    let item;
    try {
      const raw = await request.text();
      if (raw.length > 8000) return reply(413, { error: 'too large' });
      item = JSON.parse(raw);
    } catch {
      return reply(400, { error: 'invalid JSON' });
    }

    const message = typeof item.message === 'string' ? item.message.trim() : '';
    if (!message) return reply(400, { error: 'empty message' });
    const category = CATEGORIES[item.category] || CATEGORIES.other;
    const rating =
      Number.isInteger(item.rating) && item.rating >= 1 && item.rating <= 5
        ? `${'\u2605'.repeat(item.rating)}${'\u2606'.repeat(5 - item.rating)}`
        : null;
    const short = (v, n) => (typeof v === 'string' ? v.slice(0, n) : '');

    const lines = [
      `\u{1F4CA} Basis feedback \u2014 ${category}`,
      rating ? `Rating: ${rating}` : null,
      item.calculatorId ? `Calculator: ${short(item.calculatorId, 60)}` : null,
      `Ruleset: ${short(item.rulesetVersion, 40)}`,
      `From: ${origin || 'Android app'}`,
      '',
      message.slice(0, MAX_MESSAGE),
    ].filter((l) => l !== null);

    // Plain text, no parse_mode: nothing a user types can be read as markup.
    const tg = await fetch(
      `https://api.telegram.org/bot${env.TELEGRAM_TOKEN}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: env.TELEGRAM_CHAT_ID,
          text: lines.join('\n'),
          disable_web_page_preview: true,
        }),
      },
    );
    if (!tg.ok) return reply(502, { error: 'telegram rejected the message' });
    return reply(200, { ok: true });
  },
};
