// Gimme query-interpreter (Supabase Edge Function).
//
// POST /functions/v1/interpret  { "query": "zyns" }
//   → 200 { "searchText": "convenience store", "label": "convenience store" }
//
// Exists so the Anthropic API key never ships inside the iOS app (spec §4.1) —
// it lives in Supabase secrets. Supabase verifies the caller's JWT (the app
// sends the project's anon key) before this function runs (verify_jwt = true).
// The app treats any failure here as a soft miss and falls back to its
// on-device rule-based interpreter, so this function can be best-effort.

import Anthropic from "npm:@anthropic-ai/sdk@0.104.1";

interface Interpretation {
  searchText: string;
  label: string;
}

const MAX_QUERY_LENGTH = 100;
const CACHE_MAX_ENTRIES = 500;

const SYSTEM_PROMPT = `You convert "a thing someone wants right now" into the best Google Maps text
search for finding the nearest place that carries it.

Rules:
- If the input is a product, brand, or slang (e.g. "zyns", "advil", "cold brew"),
  return the type of place most likely to stock it ("convenience store",
  "pharmacy", "coffee shop").
- If the input already names a kind of place or food ("gas station", "tacos"),
  return it as-is or lightly cleaned up.
- searchText must work well as a Google Maps text query. Keep it short.
- label is the short human-readable version of searchText shown in the UI.
- Never refuse; for unintelligible input, echo it back as both fields.`;

const OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    searchText: {
      type: "string",
      description: "Google Maps text query for the place type, e.g. 'convenience store'",
    },
    label: {
      type: "string",
      description: "Short human-readable label shown in the app UI",
    },
  },
  required: ["searchText", "label"],
  additionalProperties: false,
} as const;

// Per-instance cache: the query space is tiny ("zyns", "gas", …) and hot.
const cache = new Map<string, Interpretation>();

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST only" }, 405);
  }

  let query: string;
  try {
    const body = (await request.json()) as { query?: unknown };
    query = typeof body.query === "string" ? body.query.trim().toLowerCase() : "";
  } catch {
    return jsonResponse({ error: "Body must be JSON with a 'query' string" }, 400);
  }
  if (!query || query.length > MAX_QUERY_LENGTH) {
    return jsonResponse({ error: "'query' must be 1-100 characters" }, 400);
  }

  const cached = cache.get(query);
  if (cached) {
    return jsonResponse(cached);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "ANTHROPIC_API_KEY not configured" }, 500);
  }

  try {
    const client = new Anthropic({ apiKey });
    // No `thinking` param: this is a one-hop normalization with a tight
    // latency budget (the app gives the proxy 1.5 s before falling back);
    // structured output guarantees a parseable reply.
    const message = await client.messages.create({
      model: "claude-opus-4-8",
      max_tokens: 256,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: query }],
      output_config: {
        format: { type: "json_schema", schema: OUTPUT_SCHEMA },
      },
    });

    const text = message.content.find((block) => block.type === "text")?.text;
    if (!text) {
      return jsonResponse({ error: "Empty model response" }, 502);
    }
    const parsed = JSON.parse(text) as Interpretation;
    if (!parsed.searchText?.trim()) {
      return jsonResponse({ error: "Model returned no searchText" }, 502);
    }

    const result: Interpretation = {
      searchText: parsed.searchText.trim(),
      label: (parsed.label ?? parsed.searchText).trim(),
    };

    if (cache.size >= CACHE_MAX_ENTRIES) {
      const oldest = cache.keys().next().value;
      if (oldest !== undefined) cache.delete(oldest);
    }
    cache.set(query, result);

    return jsonResponse(result);
  } catch (error) {
    console.error("interpret failed", error);
    return jsonResponse({ error: "Upstream failure" }, 502);
  }
});
