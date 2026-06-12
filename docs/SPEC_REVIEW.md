# Gimme Spec Review

**Reviewed:** `docs/SPEC.md` v1.0 (draft)
**Outcome:** 14 findings — 4 blocking, 6 significant, 4 minor. All blocking and
significant findings resolved in spec v1.1; resolutions are cross-referenced as
R1–R10 in §12 of the spec. Two proposals were considered and **rejected** (see end).

---

## Blocking findings

### F1 — Client-side LLM call ships an extractable Anthropic key  → R1

The draft's "pre-processing (maybe an LLM call)" implied calling the LLM from the app.
Any API key embedded in an iOS binary is recoverable (strings dump / proxy
interception); an Anthropic key in the wild is an unbounded billing and abuse
liability. There is no client-side mitigation that actually works.

**Resolution:** LLM interpretation moved behind a small serverless function the
user controls (a Supabase Edge Function, `supabase/`), with platform JWT auth.
The app works fully
without it via the on-device rule-based interpreter — which also covers the latency
problem: an LLM round-trip (even fast) is a tax on a flow whose entire promise is
"arrow in under 10 seconds." The proxy gets a hard 1.5 s timeout with silent fallback.

Note the asymmetry with the Google key: Google *designs* for client-shipped keys
(bundle-ID + API restriction in Cloud Console), Anthropic does not. The spec now
states both policies explicitly (§4.1, §4.5).

### F2 — Compass arrow will visibly spin the wrong way at north  → R3

The draft said "arrow rotation = bearing − heading" and stopped. Animating that
naively in SwiftUI produces a 350° whirl every time the value crosses 0°/360° —
the single most common bug in compass apps, and it makes the core UI feel broken.

**Resolution:** Continuous unwrapped accumulator with `shortestSignedDelta`,
specified in §6.5 and required to be unit-tested across the boundary in both
directions and across multiple revolutions.

### F3 — True vs magnetic heading unaddressed  → R4

Bearings computed from coordinates are relative to **true** north;
`CLHeading.magneticHeading` is relative to **magnetic** north. Declination is ~13°E in
San Francisco — enough to point you down the wrong street. The draft didn't say which
heading the arrow uses.

**Resolution:** Prefer `trueHeading` (valid when ≥ 0; requires location updates
running, which we always do), fall back to `magneticHeading`, calibration hint when
accuracy > 25°. Specified in §6.6/§3.3.

### F4 — No story for heading-unavailable devices or the Simulator  → R5

`CLLocationManager.headingAvailable()` is false on the Simulator (and some hardware).
The draft's app would render a frozen or garbage arrow there — undemoable,
untestable, and a guaranteed dev-experience papercut.

**Resolution:** North-up fallback mode: arrow shows absolute bearing with a caption,
distance still live. §3.3.

---

## Significant findings

### F5 — Per-keystroke search is a billing and UX mistake  → R2

Text Search (New) bills per request, and partial queries ("zy", "zyn") produce junk
churn in the arrow. **Resolution:** explicit submit + chips (§3.5). Recents make
repeat queries one tap.

### F6 — "Nearest" goes stale as the user walks  → R7

Walk 600 m and the nearest gas station may now be a different one behind you; a static
target quietly breaks the product promise. **Resolution:** silent re-search after
250 m of travel from the search origin; replace the target only on success so a failed
refresh never kills a working arrow (§5.3).

### F7 — Arrival state will flap at the threshold  → R6

GPS noise of ±10–20 m around a hard 25 m cutoff toggles pointing↔arrived repeatedly.
**Resolution:** hysteresis — enter at < 25 m, exit only at > 40 m (§5.3).

### F8 — Reduced-accuracy ("Precise: Off") users get a confidently wrong arrow  → R8

With approximate location (~1–3 km), a bearing to a target 500 m away is noise
presented as fact. **Resolution:** detect `accuracyAuthorization == .reducedAccuracy`,
show "approximate" treatment + a hint to enable Precise Location, damp the arrow
(§7). Don't block the flow — coarse "it's that way, roughly" still has value at
multi-km distances.

### F9 — Places field selection / cost discipline unspecified  → R9

The New Places API bills by field-mask tier; an unconstrained mask silently lands in
the most expensive tier. **Resolution:** explicit minimal field mask (id, displayName,
formattedAddress, location, currentOpeningHours.openNow) written into the spec and
asserted in `GooglePlacesClient` tests (§4.3, §9).

### F10 — Inventory overpromise risk  → R10

"Points at the nearest place that has Zyns" is not something we can verify; users
standing in a store that doesn't stock the item is the failure mode. **Resolution:**
copy rules (§3.6): resolve to *categories*, show the transparent "Zyns → convenience
store" caption, never claim stock. Non-goal recorded in §1.3.

---

## Minor findings

### F11 — Empty Places response shape

Text Search returns `{}` (no `places` key) for zero results; a strict decoder throws
and surfaces a fake error. Now specified (§4.3) and unit-tested (decode `{}` → `[]`).

### F12 — xcconfig URL comment trap

`https://…` in an xcconfig is truncated at `//` (comment syntax). The example secrets
file documents the `https:/$()/` escape. (§4.5)

### F13 — Latest-wins search races

Rapid resubmission could let a slow earlier response overwrite a newer target.
Resolved via `Task` cancellation, latest-wins, and a unit test for it (§5.3, §9).

### F14 — Recents + privacy manifest

`UserDefaults` is on Apple's required-reason API list; using it without a
`PrivacyInfo.xcprivacy` declaration (CA92.1) is an App Store rejection vector.
Manifest contents specified in §8.

---

## Proposals considered and rejected

**Route distance (walking) instead of straight-line.** Honest appeal, but it costs a
second metered API (Routes) on every refresh, adds latency to the hot loop, and the
arrow — not the number — is the product. Rejected for v1; mitigated with the
"as the crow flies" footnote and the Open-in-Maps escape hatch. (§6.7)

**Google Places iOS SDK instead of REST.** The SDK adds tens of MB, its own key
plumbing, and an update treadmill — for one endpoint we can call with `URLSession` in
~80 lines and stub-test cleanly. Rejected; REST with a typed client. (§5.2)

---

## Residual risks (accepted, documented)

- Magnetic-only fallback can be ~10–15° off in the worst CONUS locations; calibration
  hint and true-heading preference bound the exposure.
- Category resolution for genuinely ambiguous items ("charger"?) depends on Places
  text relevance; the optional Claude interpreter exists precisely to raise this
  ceiling without an app update.
- Crow-flies vs route distance divergence near rivers/highways — §6.7.
