# Weather Circles for iOS

A SwiftUI iOS app that plots the current conditions at your location as a
UK Met Office–style **weather station circle** — cloud cover in oktas, a
wind barb in knots, the present-weather glyph, and the temperature — plus a
lock-screen widget of the same circle.

The renderer is a line-for-line port of
[`weather_circle.py`](reference/weather_circle.py) from
[yeled/weather-circles](https://github.com/yeled/weather-circles) (the TRMNL
plugin) into a SwiftUI `Canvas`. Same 260×260 coordinate space, same
constants, same Open-Meteo query.

## Style provenance

Everything visual comes from the original renderer, unchanged:

| Rule | Value (SVG user units) |
| --- | --- |
| Canvas / circle | 260×260 box, R = 64, stroke 7 |
| Oktas fill | `round(cloud% / 12.5)`; wedges from 12 o'clock: 2→90°, 4→180°, 6→270°, 7→315°, 8→full; 1/3 add a vertical line, 5 a horizontal; WMO 48 → X |
| Wind barb | knots (`wind_speed_unit=kn`), shaft 50 beyond the rim in the wind-*from* direction; half barb = 5 kt (13 long), full = 10 kt (24), pennant = 50 kt; calm < 1 kt → extra ring at R+8 |
| Halo | barb gets a background-colour casing so it survives a solid 8-okta disc |
| Present weather | drizzle comma, rain dot, heavy-rain dot triangle, snow star, sleet dot+star, shower triangle, thunder bolt, mist/fog lines — at (CX−R−26, CY), size 28, nudged vertically when a westerly barb shares that side |
| Tints | the `PRECIP_TINT` palette (rain `#2563eb`, thunder `#ca8a04`, …); `mono` draws them in ink for e-ink-ish surfaces (the lock screen) |
| Ink | `#1a1a2e` on light, `#eef2f8` on dark (the repo's suggested `--ink` for dark backgrounds) |
| Temperature | bold 26pt at top-right of the circle (`CX+R/2, CY−R−6`) in repo mode; the full station model moves it to the Met Office upper-left slot |

## The full station model (app only)

`StationPlot(fullStationModel: true)` adds the rest of the Met Office
surface-plot slots around the same circle — the widgets keep the plain
TRMNL circle, since accessory sizes can't carry the annotations:

| Slot | Position | Content | Source |
| --- | --- | --- | --- |
| TT | upper-left | air temperature | `temperature_2m` |
| TdTd | lower-left | dew point | `dew_point_2m` |
| PPP | upper-right | MSLP, coded tenths (1021.7 → `217`) | `pressure_msl` |
| a + pp | right | 3-h change in tenths (`+18`) + WMO barograph-trace glyph (rising, falling, rise-then-fall, …) | hourly `pressure_msl` with `past_hours=6` |
| W₁ | lower-right, small | most significant past-6-h weather glyph (TRMNL severity ranking) | past hourly `weather_code` |
| VV | left, above ww | visibility (shown in km — a small liberty vs the coded synoptic figure) | `visibility` |
| ww | left (as before) | present weather, now **phase-corrected by ECMWF's native `precipitation_type`** when precip is falling: ptype knows freezing rain / wet snow / mixed phases the derived WMO code misses; the code keeps character (drizzle, shower, thunder) | `weather_code` + `precipitation_type` |

Cloud *genus* (the C_L/C_M/C_H cumulus/stratus/cirrus glyphs) is the one
classic slot that can't be done honestly — NWP output has layer amounts,
not genus. Everything comes from one `best_match` call; the a+pp pair gets
the mirrored version of the ww collision nudge for easterly barbs.

## High/low (and the observation question)

Station circles are observational — the circle only ever encodes *now*.
Today's high/low from Open-Meteo's `daily` block is carried **around** the
circle, not in it: a marginal text annotation in the app and the rectangular
widget, the way synoptic charts annotate values beside the station plot.
(For what it's worth, the TRMNL plugin already plots *forecast slots* as
circles, so the purity line was crossed there first — a future idea here is
that same row of small hourly circles under the big one.)

## Project layout

```
WeatherCircles/         app target (UI, CoreLocation provider)
  StationGuide          the tap-to-explain copy, examples and views
Shared/                 compiled into both targets:
  StationObservation    model + oktas/WMO-code derivations
  StationPlot           the Canvas renderer (the port) + slot hit-testing
  StationSlot           the tappable pieces of the plot
  OpenMeteoClient       same query as the script + daily high/low
  WeatherStore          App Group cache shared with the widget
WeatherCirclesWidget/   widget extension: lock-screen circular /
                        rectangular / inline + home-screen small
Config/                 Info.plist + entitlements for both targets
reference/              the original weather_circle.py, for provenance
```

## Setup

1. Open `WeatherCircles.xcodeproj` (Xcode 16+). Note: if `xcodebuild` says
   it needs Xcode, this machine's `xcode-select` points at the Command Line
   Tools — either `sudo xcode-select -s /Applications/Xcode.app` or prefix
   commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
2. Set your **team** on both targets (Signing & Capabilities).
3. The App Group `group.com.evilforbeginners.weathercircles` is declared in
   both `Config/*.entitlements` and `WeatherStore.appGroupID` — register it
   for your team (Xcode offers to), or change it in those three places.
4. Run on your phone, grant location, then add the widget: lock screen →
   customise → **Weather Circle** (circular or rectangular), or the small
   home-screen widget.

CLI build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project WeatherCircles.xcodeproj -scheme WeatherCircles \
  -destination 'generic/platform=iOS Simulator' build
```

## How the widget stays current

The timeline provider asks for its own location fix (`NSWidgetWantsLocation`
— works once the app has While-Using permission), falling back to the app's
last cached coordinate, then London (the script's default). It fetches
Open-Meteo directly, caches through the App Group so app and widget share
the freshest observation, and asks WidgetKit to refresh every ~30 minutes
(the system decides the actual budget). Opening the app also reloads the
widget after each fetch.

## Roadmap

- A TRMNL-style row of small forecast-slot circles (the repo's rolling
  2-hour windows) under the big observation circle.
- Widget configuration (AppIntents) for a pinned location instead of
  follow-me, and an `&models=ecmwf_ifs025` toggle for ECMWF purists.
- The true coded VV figure (WMO 4377) instead of km, for maximum chart
  authenticity.
- An app icon — the circle itself, presumably at 3 oktas with a stiff
  south-westerly.

Weather data by [Open-Meteo](https://open-meteo.com) (CC-BY 4.0), no API key
required.

## Updating the README screenshot

`docs/screenshot.png` on `main` should always show the current app. After
any visual change:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project WeatherCircles.xcodeproj -scheme WeatherCircles \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot <udid>
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/WeatherCircles-*/Build/Products/Debug-iphonesimulator/WeatherCircles.app
xcrun simctl location booted set 51.5074,-0.1278
xcrun simctl launch booted com.evilforbeginners.WeatherCircles
sleep 8 && xcrun simctl io booted screenshot docs/screenshot.png
```

## Low-cloud genus (C_L) via METAR

No forecast API carries cloud genus — models output layer amounts, not
morphology. The only machine-reported genus is the CB / TCU suffix on
METAR cloud groups, so `MetarClient` asks aviationweather.gov for every
report in a ±1° box, takes the **nearest fresh (≤ 2 h) report that
actually describes the sky**, and parses `rawOb` itself (the API's
decoded `clouds` array silently drops the suffixes). Rules:

- Layer-attached only (`FEW026CB`); remarks like `CB DSNT W` never count.
- If the nearest station reports no CB/TCU, the glyph stays off — that
  *is* the observation; we don't scan outward for a more dramatic answer.
- CB outranks TCU. Drawn as the WMO C_L 9 (anvil) / C_L 2 (tall dome)
  glyphs below the circle; the caption notes the source station
  ("CB at KBCT").
- C_M/C_H remain empty forever — nothing observes them for us, and the
  circle doesn't fake things.

The widget skips the METAR leg (`includeCloudGenus: false`): it never
draws the full model, so timeline refreshes shouldn't spend the request.

## 0.3: cities, forecast row, icon

- **City picker** (tap the place name): Open-Meteo's geocoding API — same
  provider, no key. The selection and the last 8 choices persist in the
  App Group (`CityStore`), so the widget follows a pinned city too;
  "Current Location" returns to follow-me.
- **Forecast row**: the TRMNL plugin's rolling slots — eight 2-hour
  windows from the current hour, each drawn as a mini station circle.
  Every window shows its most significant hour (precip severity, else
  cloudiest — the plugin's rule, so a shower between slots still shows
  up). Hours are in the *location's* timezone: pin Tokyo and the row
  reads Tokyo's clock.
- **App icon**: generated by `scripts/make_icon.swift` (CoreGraphics,
  same 260-space geometry) — 3 oktas with a 35 kn south-westerly. Rerun
  the script and copy the PNG into the AppIcon set to regenerate.

## Pushing to TestFlight

Needs an Apple ID signed into Xcode (Settings → Accounts); signing and
upload are both cloud-managed from there. Icon must have no alpha
channel; `ITSAppUsesNonExemptEncryption=NO` is declared so builds don't
wait on a compliance answer.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project WeatherCircles.xcodeproj -scheme WeatherCircles \
  -destination 'generic/platform=iOS' -configuration Release \
  archive -archivePath /tmp/WeatherCircles.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath /tmp/WeatherCircles.xcarchive \
  -exportOptionsPlist scripts/exportOptions.plist \
  -exportPath /tmp/wc-testflight -allowProvisioningUpdates
```

`manageAppVersionAndBuildNumber` in the export options lets App Store
Connect bump the build number on repeat uploads of the same version.

## 0.4: the 7-day page

Swipe up from the main plot for the seven-day outlook (titled with the
location); swipe down to come back. Pull-to-refresh keeps the classic
downward drag on the main page — the "Updated…" caption is also
tappable to force a fetch, and the app refreshes on foreground and on
any location/city change. (The first cut paged in the other direction;
Charlie's thumbs overruled it.)

One circle per day, aggregated honestly rather than averaged:

- **ww glyph** — the day's *most severe* weather code (Open-Meteo's
  daily semantics; the same instinct as the TRMNL slot rule).
- **Okta fill** — *mean* cloud cover. An okta is an areal average by
  nature, so the mean is the one place averaging is true to the form.
- **Barb** — the day's *max* wind at the *dominant* direction. A mean
  barb would lie about gusty days.
- **Margins** — H/L and the precipitation sum, RRR-style.

Never a flat average of everything: that washes a
morning-fog-then-thunderstorm day into meaningless drizzle.

## 1.0: the plot explains itself

The station model is only readable if you already know it, so every piece
of it is now tappable. Tap the barb and you get the wind page; tap the
circle and you get oktas; tap `147` and you get the coded-pressure rule.
Each page carries four things: what the slot is, **what it says on your
circle right now**, drawn examples, and the key.

- `StationSlot` (Shared) is the slot identity — the renderer hit-tests
  it, so the geometry can't drift from what's drawn.
- `StationPlot.slotRegions` derives a box per slot from the same anchors
  `drawStationModelAnnotations` uses (including the barb-collision nudges,
  which are now shared computed properties rather than inline maths).
  Overlapping boxes resolve smallest-first, with the circle last so a barb
  rooted on the rim wins over the disc behind it.
- `StationPlot(onSelectSlot:)` opts a plot into the tap gesture and
  `highlightedSlot` outlines the tapped box in ink (no accent colour —
  nothing else in the app is coloured). The widgets and the forecast rows
  pass neither, so they stay inert.
- `StationPlot.Parts` masks the canvas down to one element, which is how
  the guide's illustrations show a bare barb or a lone dew point. The
  example observations set *only* the field being explained, so the
  annotation slots that aren't the point stay empty rather than drawing
  noise.
- `StationGuide.swift` (app only) holds the copy, the examples, and the
  views: `StationSlotDetail` for one slot, `StationGuideView` for the
  list. The list is the way in for slots today's weather doesn't draw
  (no CB, nothing falling) and the VoiceOver route, since a Canvas can't
  be aimed at — the tap overlay is `accessibilityHidden`.

Entry points: tap any part of the plot, or "What am I looking at?" in the
footer. A one-line "tap any part of the circle" nudge sits under the plot
until the guide is opened once (`guideHintSeen`).

## 1.1: corner labels dodge the barb; W₁ reads real METAR, not a model guess

Two bugs, both from the same root cause — the annotation slots assumed a
barb that only ever grew out of the circle's rim, when it actually always
draws full-length regardless of speed:

- **TT/TdTd/PPP/W₁ overlapping the barb.** ww/pp/genus already dodge a
  barb sharing their side by swapping to the opposite vertical half, but
  the four corner slots (fixed NW/SW/NE/SE) had no such nudge, so a wind
  from roughly that same diagonal drew the number right through the
  shaft. `StationPlot.clearBarb(_:)` sidesteps a corner anchor
  perpendicular to the shaft, just far enough to clear it, whenever the
  wind direction lines up with that corner — `temperatureAnchor`,
  `dewPointAnchor`, `pressureAnchor` and `pastWeatherAnchor` route both
  the drawing code and `slotRegions`' tap boxes through it, so the two
  can't drift apart.
- **W₁ (past weather) was reading a model guess, not an observation.**
  `pastSignificantWeatherCode` came from Open-Meteo's hourly `weather_code`
  over `past_hours` — the forecast model's own diagnostic, not a real
  report. Checked against a real storm (multiple METAR stations 50–120 km
  out reporting `TSRA`/`CB` over several hours): the model's hourly trace
  showed *zero* precipitation for the same window at the same
  coordinates. A longer lookback wouldn't have helped — the model simply
  never resolved the convection, the same reason C_L already uses METAR
  instead of a forecast field. `MetarClient.findings` now derives W₁ from
  the nearest currently-reporting station's actual present-weather groups
  (`TS`, `RA`, `SHRA`, `GR`, `FG`, …) over its `hours=6` history — real
  ground truth first, the model's guess only where no station is close
  enough to have one (`StationObservation.pastWeather`). One fetch now
  serves both genus and past weather, so this didn't cost a second
  request; `WeatherService.fetch`'s flag is renamed
  `includeStationObservations` to say so.
