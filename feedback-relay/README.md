# Feedback → Telegram

The app never holds the bot token. It sends feedback to this Cloudflare
Worker, which keeps the token as a secret and forwards the message to your
Telegram chat.

```
Basis app ──POST JSON──▶ Cloudflare Worker (token is a secret) ──▶ Telegram
```

## 1. Make the bot (Telegram, 2 min)

1. In Telegram, message **@BotFather** → `/newbot` → name it (e.g. *Basis
   Feedback*). It replies with a **token**. Treat it like a password: do not
   paste it into chats, the app, or GitHub.
2. Open your new bot and press **Start**, then send it any message.
3. Get your chat id: open
   `https://api.telegram.org/bot<TOKEN>/getUpdates` in your own browser and
   find `"chat":{"id": 123456789`. That number is `TELEGRAM_CHAT_ID`.

## 2. Make the Worker (Cloudflare, 5 min, free)

1. <https://dash.cloudflare.com> → **Workers & Pages** → **Create** →
   **Create Worker** → name it `basis-feedback` → **Deploy**.
2. **Edit code** → replace everything with `worker.js` from this folder →
   **Deploy**.
3. **Settings → Variables and Secrets** → add:

   | Name | Type | Value |
   |---|---|---|
   | `TELEGRAM_TOKEN` | **Secret** | the BotFather token |
   | `TELEGRAM_CHAT_ID` | **Secret** | your chat id |
   | `ALLOWED_ORIGINS` | Text | `https://basis-calculators.onrender.com` |

4. Copy the Worker's address, e.g. `https://basis-feedback.<you>.workers.dev`.

## 3. Point the app at it (Render)

Render → basis-calculators → **Environment** → add
`FEEDBACK_URL` = the Worker address → **Save, rebuild and deploy**.

`build.sh` passes it into the build. It refuses any value containing
`api.telegram.org` or something shaped like a bot token, so the token cannot
be baked into the app by mistake.

## What it protects against

- **Token theft** — only the Worker knows it.
- **Other sites using your relay** — only `ALLOWED_ORIGINS` may post from a
  browser.
- **Spam** — 5 messages per visitor per 10 minutes, 2,000-character cap.
- **Formatting tricks** — sent as plain text, never parsed as Markdown/HTML.

Feedback is always saved on the device first, so if the Worker is down the
message waits and is retried rather than lost.
