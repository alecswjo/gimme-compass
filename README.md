# Gimme

You want a thing — **Zyns, gas, ice cream, anything**. Gimme points an arrow at
the nearest place that has it and tells you how far. That's the whole app.

```
   [ I want… Zyns  ⌕ ]
   (Zyns)(Gas)(Ice cream)(Coffee)(ATM)

           ▲
          ╱ ╲          ← rotates live with your compass heading
         ╱___╲

        0.4 mi NE
        7-Eleven
   1601 Divisadero St
        Open now

     [ Open in Maps ]
```

- **Docs:** [`docs/SPEC.md`](docs/SPEC.md) (product + engineering spec) ·
  [`docs/SPEC_REVIEW.md`](docs/SPEC_REVIEW.md) (the adversarial review behind it)
- **Platform:** iOS 17+, iPhone, SwiftUI, Xcode 16+
- **Search:** Google Places API (New) Text Search, ranked by distance
- **Query smarts:** on-device rules ("zyns" → convenience store) + optional
  Claude-powered interpreter on Supabase ([`supabase/`](supabase/README.md))

## Quick start

1. **Get a Google Places key.** In Google Cloud Console: enable **Places API
   (New)**, create an API key, and restrict it — *Application restriction:* iOS
   apps, bundle ID `ai.florafauna.gimme`; *API restriction:* Places API (New).
2. **Configure secrets:**

   ```sh
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   # edit Config/Secrets.xcconfig and set GOOGLE_PLACES_API_KEY
   ```

   `Secrets.xcconfig` is gitignored. The project builds without it, but the app
   shows a setup screen instead of searching.
3. **Open `Gimme.xcodeproj`** in Xcode 16+, set your signing team on the Gimme
   target, and run on a device. (The Simulator works too — it has no
   magnetometer, so the arrow falls back to north-up mode by design.)

### Optional: Claude-powered query understanding

The on-device interpreter covers the common cases. To handle the long tail
("hangover cure", "that pink drink"), deploy the Supabase Edge Function in
[`supabase/`](supabase/README.md) and add its URL + your project's anon key to
`Secrets.xcconfig`. The Anthropic API key lives only in Supabase secrets —
never in the app. If the function is slow (>1.5 s) or down, the app silently
falls back to the on-device rules. This is the app's only backend component,
and it's optional.

## How it works

```
query ─► interpreter (rules, or Claude proxy w/ fallback) ─► Places Text Search
                                                              (rank by DISTANCE)
GPS fix ──┐                                                        │
          ├─► bearing(user → place) − device heading ─► arrow      ▼
heading ──┘     (unwrapped angle, no 360° spin)         nearest place
                haversine distance ─► "0.4 mi NE"
```

Key behaviors (see the spec for the full list):

- **True heading** preferred, magnetic fallback; calibration hint when the
  compass is noisy; north-up fallback when there's no magnetometer.
- **Re-search after 250 m of travel** — "nearest" stays honest as you walk; a
  failed refresh never kills a working arrow.
- **Arrival at <25 m** with hysteresis (exit at >40 m) so it doesn't flap.
- **Reduced-accuracy mode** (Precise Location off) shows an "approximate"
  treatment instead of pretending.
- Straight-line distance, labeled as such; "Open in Maps" for the final approach.

## Project layout

```
Gimme/                  app target (synchronized folder — files added on disk appear in Xcode)
  App/                  entry point + build-config plumbing
  Models/               Place, GimmeError
  Services/             LocationService, GooglePlacesClient, interpreters, recents
  ViewModels/           CompassViewModel — the entire state machine
  Views/                RootView + state views, compass, query bar
  Utilities/            GeoMath (bearing/haversine/unwrap), DistanceFormatter
  Resources/            assets, PrivacyInfo.xcprivacy
GimmeTests/             unit tests (pure logic, stubbed network, mocked location)
Config/                 Info.plist, xcconfigs (secrets pattern)
supabase/               optional Claude interpreter (Supabase Edge Function)
docs/                   SPEC.md, SPEC_REVIEW.md
```

## Testing

```sh
xcodebuild -project Gimme.xcodeproj -scheme Gimme \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Covered: bearing/distance math (including the angle-unwrap spin bug), distance
formatting thresholds, query rule mapping, Places request shape + response
decoding + error mapping (via `URLProtocol` stub), and the view-model state
machine (latest-wins cancellation, arrival hysteresis, movement re-search,
permission flows) — all with no network or CoreLocation dependency.

CI runs the iOS tests and typechecks the Edge Function on every PR
(`.github/workflows/ci.yml`).

### Manual device pass (before shipping)

- [ ] Compass sanity: arrow direction agrees with Apple Maps' compass
- [ ] Walk test: distance counts down, arrow tracks while turning
- [ ] Calibration hint appears near magnetic interference (figure-8 clears it)
- [ ] Permission flows: allow / deny / Settings round-trip / Precise off
- [ ] Airplane mode: existing arrow keeps working; new search shows offline error
- [ ] Arrival state at the door; un-arrives walking away

## Release checklist

See `docs/SPEC.md` §10 — key restriction, privacy labels, real app icon, and
the manual device pass above.
