# Gimme — Product & Engineering Spec

**Version:** 1.1 (post-review — see `docs/SPEC_REVIEW.md` for the review findings folded into this revision)
**Status:** Approved for build
**Platform:** iOS 17.0+, iPhone
**Author:** Claude (for Alec)

---

## 1. Overview

**Gimme** answers one question: *"Where's the nearest ___, and which way do I walk?"*

You type the thing you want — "Zyns", "gas", "ice cream", anything — and Gimme shows a
compass arrow pointing at the nearest place that has it, plus the distance. As you move
and rotate, the arrow and distance update live. Edit the query and it recalculates.

No map, no list of 20 results, no reviews. A query box and an arrow. Dead simple.

### 1.1 Problem

Maps apps are overkill for "I just need the closest X." They demand multiple taps,
show ads and sponsored pins, and make you interpret a top-down map while walking.
A compass is the lowest-friction possible answer to "which way?"

### 1.2 Goals

- **G1:** From app open to pointing arrow in under 10 seconds for a common query.
- **G2:** Handle colloquial / product-level queries ("Zyns", "advil", "cold brew"),
  not just business categories.
- **G3:** Live, smooth direction + distance updates while walking.
- **G4:** Production quality: graceful permission/network/no-result handling,
  accessibility, no secrets in the binary repo, tests, CI.

### 1.3 Non-goals (v1)

- Turn-by-turn navigation or route distance (we show straight-line distance; see §6.7).
- Android, iPad, watchOS, widgets.
- Accounts, favorites sync, social anything.
- In-store inventory verification ("do they actually stock Zyns?") — we resolve the
  *category of place most likely to carry the item*, not stock levels. Copy must not
  overpromise (see §5.6).
- Background location / notifications.

### 1.4 Naming

App name: **Gimme**. Bundle ID: `ai.florafauna.gimme`. Repo: `gimme-compass`.

---

## 2. User stories

| # | Story | Acceptance |
|---|-------|-----------|
| U1 | As a user, I type "zyns" and get an arrow + distance to the nearest place likely to sell them. | Arrow within 2s of search completion (p50, good network); points at a convenience store / smoke shop. |
| U2 | As a user, I walk and the arrow/distance update continuously. | Heading updates ≥ 5 Hz feel; distance updates on each location fix; no arrow "spin glitch" crossing north. |
| U3 | As a user, I edit my query and the target recalculates. | New search runs on submit; previous target replaced; recents updated. |
| U4 | As a user, I tap a suggestion chip (Zyns, Gas, Ice cream, Coffee, ATM…) to skip typing. | One tap → search. |
| U5 | As a user near the destination, I'm told I've arrived. | Within 25 m → "You're basically there" state with place name/address. |
| U6 | As a user, I can jump to Apple Maps for the final approach. | "Open in Maps" opens the place pin. |
| U7 | As a user who denied location, I get a clear path to fix it. | Explainer + deep link to Settings. |
| U8 | As a VoiceOver user, I can find out which way to go. | Arrow has a spoken relative direction ("ahead", "to your right", …) and distance. |

---

## 3. UX spec

### 3.1 Screen inventory

One screen (`RootView`) with mutually exclusive content states, plus the system
location-permission dialog. No navigation stack in v1.

```
┌──────────────────────────────┐
│  [  I want… Zyns        ⌕ ]  │  ← query bar (TextField, submit on return)
│  (Zyns)(Gas)(Ice cream)(…)   │  ← suggestion + recents chips
│                              │
│             ▲                │
│            ╱ ╲               │  ← the arrow (rotates with device heading)
│           ╱   ╲              │
│          ╱_____╲             │
│                              │
│         0.4 mi NE            │  ← distance + cardinal direction
│      7-Eleven                │  ← resolved place name
│   1601 Divisadero St         │  ← address (secondary)
│      Open now                │  ← open/closed if known
│                              │
│     [ Open in Maps ]         │
└──────────────────────────────┘
```

### 3.2 Content states

| State | Trigger | UI |
|-------|---------|----|
| **Setup required** | Google Places API key missing from build config | Instructions to add `Secrets.xcconfig` (dev-facing; never ships if release checklist followed) |
| **Permission needed** | Location not determined | Friendly explainer + "Allow location" button → system prompt |
| **Permission denied** | Denied/restricted | Explainer + "Open Settings" deep link |
| **Locating** | Have permission, no fix yet | Spinner + "Finding you…" |
| **Idle** | Located, no query yet | Big prompt: "What do you want?" + chips |
| **Searching** | Query submitted | Arrow area shows progress; query bar disabled-ish |
| **Pointing** | Target resolved | Arrow + distance + place card (the main state) |
| **Arrived** | Distance < 25 m | Checkmark, "You're basically there", place card, Maps button |
| **No results** | Search returned empty | "Couldn't find that nearby" + suggestions to rephrase |
| **Error** | Network/API failure | Human-readable message + Retry |

State transitions are owned by a single `CompassViewModel.Phase` enum — no scattered
booleans.

### 3.3 The arrow

- Arrow rotation = `bearing(user → target) − deviceHeading`, animated.
- Crossing 0°/360° must take the **shortest angular path** (continuous unwrapped angle,
  see §6.5) — a naive `rotationEffect(bearing - heading)` spins 350° the wrong way.
- Uses **true heading** when available, falling back to magnetic heading (see §6.6).
- **Heading-unavailable fallback** (no magnetometer / Simulator): arrow is drawn
  north-up at the absolute bearing, with a caption "N-up — compass unavailable" so the
  app remains usable and demoable in the Simulator.
- Calibration hint: if heading accuracy is worse than 25°, show "Wave your phone in a
  figure-8 to calibrate."

### 3.4 Distance display

- Locale-aware (`Locale.measurementSystem`):
  - Imperial: `< 0.18 mi` → feet (rounded to 10), else miles (1 decimal).
  - Metric: `< 1 km` → meters (rounded to 10), else km (1 decimal).
- Cardinal direction of the bearing appended ("0.4 mi NE").
- Straight-line ("as the crow flies"). A one-time footnote in the place card clarifies
  this ("distance is as the crow flies").

### 3.5 Query input

- Search runs on **explicit submit** (return key or chip tap), not per keystroke —
  cheaper (Places billing), calmer UX, and matches "I know what I want" intent.
- Chips: 5 fixed suggestions (`Zyns`, `Gas`, `Ice cream`, `Coffee`, `ATM`) followed by
  up to 8 recents (deduped, case-insensitive, persisted in `UserDefaults`).
- Re-search triggers:
  1. New query submitted.
  2. User has moved > 250 m from the location where the current search ran (the
     "nearest X" may have changed). Silent refresh; only swap targets if the new
     nearest differs.
  3. Manual: pull on the arrow area exposes a refresh (v1: small refresh button in the
     place card).

### 3.6 Copy guidelines

- Never claim inventory ("sells Zyns") — say "nearest convenience store" via the
  resolved-category label, e.g. chip query "Zyns" shows *"Zyns → convenience store"*
  as a subtle caption so the resolution is transparent.
- Errors are human: "Can't reach the internet" not "URLError -1009".

### 3.7 Accessibility

- All states VoiceOver-labeled. Pointing state exposes a combined element:
  *"7-Eleven, 0.4 miles, to your right"* — relative direction quantized to 8 sectors
  (ahead / ahead-right / right / behind-right / behind / …), recomputed as you turn.
- Dynamic Type supported throughout (no fixed font sizes; arrow scales with layout).
- Color is never the only signal (open/closed uses text, not just green/red).

---

## 4. System architecture

```
┌─────────────────────────────── iOS app (SwiftUI, MVVM) ───────────────────────────────┐
│                                                                                       │
│  RootView ── CompassView / QueryBar / state views                                     │
│      │                                                                                │
│  CompassViewModel (@MainActor, @Observable)  ←— single source of truth (Phase enum)   │
│      │            │                  │                                                │
│  LocationService  QueryInterpreting  PlaceSearching                                   │
│  (CoreLocation:   (protocol)         (protocol)                                       │
│   fixes+heading)      │                  │                                            │
│                   RuleBasedInterpreter   GooglePlacesClient ───────► Google Places    │
│                   ClaudeProxyInterpreter ──► Gimme proxy (optional)  API (New)        │
│                   (falls back to rules)        │                     searchText       │
└────────────────────────────────────────────────┼──────────────────────────────────────┘
                                                 ▼
                                   Cloudflare Worker (server/)
                                   @anthropic-ai/sdk → claude-opus-4-8
                                   (Anthropic key lives ONLY here)
```

### 4.1 Why this shape

- **Protocols for every effectful dependency** (`LocationProviding`, `PlaceSearching`,
  `QueryInterpreting`) → the view model is fully unit-testable with mocks; no network
  or CoreLocation in tests.
- **LLM is optional and server-side.** Shipping an Anthropic API key inside an iOS
  binary is not acceptable (extractable in minutes). The app calls a tiny proxy we
  control; if the proxy URL isn't configured or the call fails/times out (1.5 s), the
  on-device rule-based interpreter answers. The app is fully functional with zero
  backend.
- **Google Places key ships in the client by design** — that is Google's sanctioned
  model for iOS: the key must be **restricted to the `ai.florafauna.gimme` bundle ID
  and to the Places API** in Google Cloud Console (release checklist item, §10).

### 4.2 Query interpretation pipeline

```
raw text ──► normalize (trim, lowercase, collapse whitespace)
        ──► [ClaudeProxyInterpreter if proxy configured]──► {searchText, label}
        │        └─ timeout 1.5 s / any error ─┐
        └──► RuleBasedInterpreter ◄────────────┘
                 │
                 ├─ known product/slang → category ("zyns" → "convenience store")
                 └─ unknown → pass through verbatim (Places text search is already
                    good at natural language)
```

Rule table (v1, extensible): zyn/zyns/nicotine pouches → convenience store;
vape/juul → vape shop; gas/fuel/petrol → gas station; ice cream → ice cream shop;
coffee/cold brew/latte → coffee shop; atm/cash → atm; beer/liquor/wine → liquor store;
advil/tylenol/ibuprofen/band aids → pharmacy; groceries → grocery store;
weed → cannabis dispensary; cigarettes/smokes → convenience store.

Both interpreters return `InterpretedQuery { searchText, displayLabel }` so the UI can
show the transparent "Zyns → convenience store" caption.

### 4.3 Places search

**Endpoint:** `POST https://places.googleapis.com/v1/places:searchText`
(Places API *New*; Text Search accepts arbitrary natural-language queries — the right
fit; Nearby Search (New) only takes fixed type enums.)

Request:

```json
{
  "textQuery": "convenience store",
  "pageSize": 8,
  "rankPreference": "DISTANCE",
  "locationBias": {
    "circle": { "center": { "latitude": 37.77, "longitude": -122.43 }, "radius": 50000 }
  }
}
```

Headers: `X-Goog-Api-Key`, and a **minimal field mask** (billing is per-field-tier):
`X-Goog-FieldMask: places.id,places.displayName,places.formattedAddress,places.location,places.currentOpeningHours.openNow`

- `rankPreference: DISTANCE` + max bias radius (50 km) → "nearest" semantics that still
  work in rural areas.
- We request 8 results but **target = first result**; the rest are kept in memory so a
  future "next nearest" gesture is cheap (not in v1 UI).
- Empty result set arrives as `{}` (no `places` key) — must decode as empty, not error.

### 4.4 Claude proxy (server/, optional deploy)

Cloudflare Worker, TypeScript, official `@anthropic-ai/sdk`.

- `POST /interpret` `{ "query": "zyns" }` → `{ "searchText": "convenience store", "label": "convenience store" }`
- Model: `claude-opus-4-8`, `max_tokens: 256`, **structured output**
  (`output_config.format` JSON schema) so the response is guaranteed parseable.
  No `thinking` param (omitted = off on Opus 4.8): this is a one-hop normalization
  where p95 latency budget is ~1.2 s; reasoning depth buys nothing here.
- In-isolate LRU cache (query → result) since the query space is tiny and hot.
- Optional shared-secret header (`X-Gimme-Auth`) checked against a Worker secret so the
  endpoint isn't an open Anthropic relay.
- The Worker is **not required** for the app to function (rule-based fallback).

### 4.5 Configuration & secrets

| Secret | Where it lives | How it gets there |
|--------|----------------|-------------------|
| Google Places API key | `Config/Secrets.xcconfig` (gitignored) → Info.plist at build time | Developer creates from `Config/Secrets.example.xcconfig` |
| Proxy URL + auth token (optional) | same | same |
| Anthropic API key | Cloudflare Worker secret (`wrangler secret put`) | never in the repo or app |

`Secrets.xcconfig` is optionally `#include?`d so a fresh clone **builds without it**;
the app then shows the Setup-required state. Note: xcconfig treats `//` as a comment,
so URLs are written with the `https:/$()/` escape (documented in the example file).

---

## 5. Detailed component spec

### 5.1 `LocationService` (`LocationProviding`)

- Wraps one `CLLocationManager`; `@Observable`, delegate-based (heading has no
  async/await API).
- Exposes: `authorizationStatus`, `location: CLLocation?`, `headingDegrees: Double?`
  (true heading preferred — see §6.6), `headingAccuracy: Double?`,
  `isHeadingAvailable` (`CLLocationManager.headingAvailable()`).
- Config: `desiredAccuracy = kCLLocationAccuracyBest`, `distanceFilter = 5` m,
  `headingFilter = 2°`, `activityType = .otherNavigation`.
- Starts/stops with scene phase (no background usage → no battery drain complaints,
  no background-location App Review questions).
- Permission: `requestWhenInUseAuthorization()` only. Never request Always.

### 5.2 `GooglePlacesClient` (`PlaceSearching`)

- `func searchNearest(matching:near:) async throws -> [Place]`
- Pure `URLSession` (injectable for tests via `URLProtocol` stub). No Google SDK
  dependency — keeps the binary small and the surface auditable.
- Maps HTTP/transport failures to `GimmeError` cases: `.offline`, `.apiKeyInvalid`
  (400/403), `.rateLimited` (429), `.searchFailed` (other).
- 10 s request timeout.

### 5.3 `CompassViewModel` (`@MainActor @Observable`)

State:

```swift
enum Phase { case setupRequired, needsPermission, permissionDenied,
             locating, idle, searching, pointing, arrived, noResults, error(GimmeError) }
var phase: Phase
var query: String                  // bound to TextField
var target: Place?
var resolvedLabel: String?         // "convenience store" caption
var distanceMeters: Double?
var arrowRotation: Double          // continuous, unwrapped (see §6.5)
var bearingDegrees: Double?        // absolute, for cardinal + N-up fallback
```

Behavior:

- `submit()` — interpret → search → set target / noResults / error. Cancels any
  in-flight search (latest-wins via `Task` cancellation).
- Recomputes `distance`, `bearing`, `arrowRotation` whenever location/heading change
  (observation-driven).
- Arrival when `distance < 25` m; un-arrives (back to pointing) if user walks away
  > 40 m (hysteresis so the state doesn't flap at the threshold).
- Movement re-search: if `location.distance(from: searchOrigin) > 250` m, silently
  re-run the current query; replace target only on success (never degrade a working
  arrow because a refresh failed).
- Persists submitted queries to `RecentQueriesStore`.

### 5.4 `RuleBasedInterpreter` / `ClaudeProxyInterpreter`

As §4.2. Both are `Sendable` value types. The proxy interpreter takes the URL, optional
auth token, and a `URLSession`; enforces its own 1.5 s timeout so a slow proxy can
never make the app feel broken; **any** failure silently falls back (the user should
not know or care whether an LLM was involved).

### 5.5 `RecentQueriesStore`

`UserDefaults`-backed, max 8, newest-first, case-insensitive dedupe. (Declared in the
privacy manifest under the User Defaults required-reason API, CA92.1.)

### 5.6 `Place` model

```swift
struct Place: Equatable, Identifiable {
  let id: String            // Google place id
  let name: String
  let coordinate: CLLocationCoordinate2D
  let address: String?
  let isOpenNow: Bool?      // tri-state; nil = unknown → show nothing
}
```

### 5.7 Open in Maps

`MKMapItem` with the place coordinate + name, `openInMaps()` — no URL-scheme string
building.

---

## 6. Algorithms & domain math (`GeoMath`)

### 6.1 Initial great-circle bearing

```
θ = atan2( sin Δλ · cos φ₂ , cos φ₁ · sin φ₂ − sin φ₁ · cos φ₂ · cos Δλ )
```

normalized to [0, 360). Standard forward-azimuth formula; exact for our purpose.

### 6.2 Distance

Haversine (pure function, unit-tested) — matches `CLLocation.distance(from:)` within
noise at city scales; pure function keeps tests dependency-free.

### 6.3 Cardinal direction

Bearing quantized to 16-wind (N, NNE, NE, …) for display; 8 sectors for the VoiceOver
relative direction.

### 6.4 Relative direction (accessibility)

`relative = normalize(bearing − heading)` → sectors: ahead (±22.5°), ahead-right,
right, behind-right, behind, behind-left, left, ahead-left.

### 6.5 Angle continuity (the spin bug)

SwiftUI animates `rotationEffect` along the numeric path. Going from 350° to 10° must
animate +20°, not −340°. We keep a **continuous accumulator**:

```
unwrap(target, previous) = previous + shortestSignedDelta(previous mod 360, target)
```

`shortestSignedDelta` ∈ (−180, 180]. Unit-tested across the wrap boundary in both
directions and over multiple revolutions.

### 6.6 True vs magnetic heading

Bearing math produces **true** bearings. `CLHeading.trueHeading` requires location
services running (declination needs a location) — we always run both, so prefer
`trueHeading` when `>= 0` (CoreLocation signals invalid as negative), else fall back to
`magneticHeading` (error ≤ ~15° worst case in CONUS; acceptable fallback, and the
calibration hint covers gross magnetometer error).

### 6.7 Straight-line distance honesty

Crow-flies distance can undershoot walking distance significantly (rivers, highways).
v1 accepts this consciously: the arrow is the product; the distance is a hint. The
place card carries the "as the crow flies" footnote, and "Open in Maps" exists for the
cases where geometry betrays you. Route distance would add a second paid API call per
update — explicitly deferred.

---

## 7. Error handling & edge cases

| Case | Behavior |
|------|----------|
| No network | `.error(.offline)` with Retry; existing target (if any) is kept and arrow keeps working — direction needs no network |
| API key invalid / quota | `.error(.apiKeyInvalid / .rateLimited)`; dev-readable detail logged via `os.Logger`, never in UI |
| Empty results | `.noResults` with rephrase suggestions |
| Location precise-off (reduced accuracy) | Works (Places bias radius is 50 km) but show hint "Turn on Precise Location for a better arrow"; bearing to a target 800 m away is meaningless under ~1–3 km accuracy, so Pointing UI shows distance card with "approximate" badge and damps the arrow |
| Heading unavailable (Simulator, rare hardware) | N-up fallback (§3.3) |
| Magnetic interference | Calibration hint at accuracy > 25° |
| Stale fix (> 30 s old) on foreground | Treat as locating until a fresh fix arrives |
| App backgrounded | Stop location + heading; restart on foreground |
| In-flight search superseded | `Task` cancellation; latest query wins |
| Same place re-selected on refresh | No UI churn (Equatable check) |
| Query is empty/whitespace | Submit is a no-op |
| Airplane-mode mid-walk | Arrow keeps pointing (pure math); distance keeps updating from GPS (GPS works offline); only *new* searches fail |

---

## 8. Privacy, security, compliance

- **Location**: when-in-use only, never stored off-device, sent only to Google Places
  as a search bias (covered in privacy nutrition label: Precise Location, App
  Functionality, Not Linked, No Tracking).
- **Queries**: sent to Google Places; sent to the Claude proxy only if configured.
  Recents stored locally only.
- **PrivacyInfo.xcprivacy** ships in the bundle: NSPrivacyTracking = false; collected
  data = precise location (app functionality, not linked); required-reason API:
  UserDefaults (CA92.1).
- **Keys**: Google key bundle-ID-restricted (checklist); Anthropic key server-side
  only; `Secrets.xcconfig` gitignored with a committed `.example`.
- **ATS**: default (all endpoints HTTPS).
- `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only).

---

## 9. Testing strategy

| Layer | How | What |
|-------|-----|------|
| `GeoMath` | XCTest, pure | bearing on meridian/equator/known city pairs, haversine vs known distances, signed-delta + unwrap across wrap boundary, cardinal/relative quantization edges |
| `RuleBasedInterpreter` | XCTest, pure | slang table, case/whitespace, pass-through, empty |
| `DistanceFormatter` | XCTest, injected measurement system | ft/mi and m/km thresholds, rounding |
| `GooglePlacesClient` | XCTest + `URLProtocol` stub | request shape (URL, headers incl. field mask, JSON body), fixture decode, empty `{}` decode, 403→`.apiKeyInvalid`, network error→`.offline` |
| `CompassViewModel` | XCTest + mocks, `@MainActor` | submit→pointing, empty→noResults, error→error, latest-wins cancellation, arrival hysteresis, movement re-search threshold, recents recording |
| Manual device pass | checklist in README | calibration, true-heading sanity vs Maps, walk test, permission flows |

No UI snapshot tests in v1 (cost/benefit; the view layer is deliberately thin).

CI (GitHub Actions, macOS runner): build + run unit tests on iPhone simulator on every
push/PR. Server: `tsc --noEmit` typecheck.

---

## 10. Release checklist (v1)

1. Google Cloud: Places API (New) enabled; key restricted to iOS bundle
   `ai.florafauna.gimme` **and** API-restricted to Places API (New).
2. `Secrets.xcconfig` present locally / in CI signing lane; never committed.
3. (Optional) Worker deployed; `ANTHROPIC_API_KEY` + `GIMME_AUTH_TOKEN` set via
   `wrangler secret put`; proxy URL added to Secrets.
4. App icon assets added (placeholder catalog ships in repo).
5. Privacy nutrition labels in App Store Connect match §8.
6. Manual device pass (§9) on a physical iPhone.
7. Verify Setup-required state never reachable in Release (key present).

---

## 11. Milestones

| M | Scope |
|---|-------|
| M1 | Project scaffolding, models, GeoMath + tests |
| M2 | LocationService, PlacesClient + tests |
| M3 | ViewModel + tests, full state machine |
| M4 | Views (all states), accessibility, polish |
| M5 | Proxy worker, README, CI, release checklist |

All milestones ship in this build.

---

## 12. Resolved questions (from review)

See `docs/SPEC_REVIEW.md`. Summary of the load-bearing resolutions:

- **R1** LLM call moved server-side behind an optional proxy; on-device rules are the
  default path. (Was: "maybe an llm call" client-side.)
- **R2** Search on explicit submit, not per-keystroke (billing + UX).
- **R3** Angle unwrapping specified and unit-tested (the classic compass-app bug).
- **R4** True-heading-with-magnetic-fallback policy specified.
- **R5** Heading-unavailable (Simulator) N-up fallback added — also makes the app
  demoable without hardware.
- **R6** Arrival hysteresis (25 m in / 40 m out) so the state doesn't flap.
- **R7** Movement-based re-search keeps "nearest" honest on long walks; never degrades
  a working target on refresh failure.
- **R8** Reduced-accuracy mode handled explicitly instead of pretending the arrow is
  precise.
- **R9** Field mask minimized for Places billing; `pageSize` 8 with first-result
  targeting.
- **R10** Inventory honesty: resolve to place *categories*, transparent caption, no
  "sells X" copy.
