# Gimme interpreter (Supabase Edge Function)

Optional backend that upgrades Gimme's query understanding with Claude
(`claude-opus-4-8`). The app works fully without it — its on-device rule-based
interpreter covers the common cases — but this function handles the long tail
("that pink drink from tiktok" → "smoothie shop") without app updates.

**Why a backend at all:** the Anthropic API key must never ship inside the iOS
binary. It lives here, as a Supabase secret. See `docs/SPEC.md` §4.1/§4.4.
This is the app's *only* backend component, and it's optional.

## API

```
POST https://<project-ref>.supabase.co/functions/v1/interpret
Authorization: Bearer <supabase anon key>
{ "query": "zyns" }
→ 200 { "searchText": "convenience store", "label": "convenience store" }
```

Auth: Supabase verifies the JWT before the function runs (`verify_jwt = true`
in `config.toml`). The app sends the project's **anon key**, which is designed
to be shipped in clients.

## Deploy

```sh
# one-time tooling
npm install -g supabase            # or: brew install supabase/tap/supabase

# from the repo root
supabase login
supabase link --project-ref <your-project-ref>
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy interpret
```

Then point the app at it in `Config/Secrets.xcconfig`:

```
GIMME_PROXY_URL = https:/$()/<your-project-ref>.supabase.co/functions/v1/interpret
GIMME_PROXY_AUTH_TOKEN = <anon key from Project Settings → API>
```

(The `$()` is the xcconfig escape for `//`, which otherwise starts a comment.)

## Smoke test

```sh
curl -s -X POST "https://<ref>.supabase.co/functions/v1/interpret" \
  -H "Authorization: Bearer <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "zyns"}'
```

## Notes

- The app enforces a 1.5 s timeout and silently falls back to rule-based
  interpretation on any failure — this function is allowed to be best-effort.
- Responses are cached in-memory per function instance (the query space is
  tiny and hot).
- CI typechecks the function with `deno check`.
