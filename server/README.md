# Gimme interpreter proxy

Optional Cloudflare Worker that upgrades Gimme's query understanding with
Claude (`claude-opus-4-8`). The app works fully without it — its on-device
rule-based interpreter covers the common cases — but the proxy handles the
long tail ("that pink drink from tiktok" → "smoothie shop") without app updates.

**Why a proxy at all:** the Anthropic API key must never ship inside the iOS
binary. It lives here, as a Worker secret. See `docs/SPEC.md` §4.1/§4.4.

## API

```
POST /interpret
{ "query": "zyns" }
→ 200 { "searchText": "convenience store", "label": "convenience store" }
```

Auth (optional): if the `GIMME_AUTH_TOKEN` secret is set, requests must carry
the same value in an `X-Gimme-Auth` header.

## Deploy

```sh
cd server
npm install
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put GIMME_AUTH_TOKEN   # optional but recommended
npm run deploy
```

Then point the app at it in `Config/Secrets.xcconfig`:

```
GIMME_PROXY_URL = https:/$()/gimme-interpreter-proxy.<your-subdomain>.workers.dev/interpret
GIMME_PROXY_AUTH_TOKEN = <same token>
```

(The `$()` is the xcconfig escape for `//`, which otherwise starts a comment.)

## Notes

- The app enforces a 1.5 s timeout and silently falls back to rule-based
  interpretation on any failure — this worker is allowed to be best-effort.
- Responses are cached per isolate (the query space is tiny and hot).
