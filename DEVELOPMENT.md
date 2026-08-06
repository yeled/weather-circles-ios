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
| PPP | upper-right | MSLP, coded tenths (1021.7 → `217`) — or the figure in full, per the pressure setting | `pressure_msl` |
| a + pp | right | 3-h change in tenths (`+18`, or `+1.8` in full) + WMO barograph-trace glyph (rising, falling, rise-then-fall, …) | hourly `pressure_msl` with `past_hours=6` |
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
  CountryChartView      the area chart: country outline + city circles
  CountryAtlas          bundled coastlines and city lists (Atlas.json)
Shared/                 compiled into both targets:
  StationObservation    model + oktas/WMO-code derivations
  StationPlot           the Canvas renderer (the port) + slot hit-testing
  StationSlot           the tappable pieces of the plot
  OpenMeteoClient       same query as the script + daily high/low
  AreaObservationsClient  many coordinates, one call — the area chart
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
  pass neither, so they stay inert. The outline is clamped to the 260-unit
  box: the Canvas clips to its own bounds, and the slots that hug the rim
  (the barb, VV, a+pp) otherwise pushed their padded box past the edge and
  lost that side's border.
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

## Screenshots and uploads (fastlane)

fastlane is pinned in the `Gemfile`, so the Mac and the CI runner agree on
a version — run it through bundler:

```sh
bundle install                          # once, and after any Gemfile change
bundle exec fastlane screenshots        # capture the set on all three device classes
bundle exec fastlane upload_screenshots # push fastlane/screenshots to ASC
bundle exec fastlane beta               # archive + upload a TestFlight build
bundle exec fastlane prepare_release    # open the App Store version, What's New, attach the build
bundle exec fastlane submit_release     # send the prepared version to Apple's review queue
bundle exec fastlane review_status      # live / in review / processing
```

`fastlane/changelog.txt` is the single source for release notes: `beta`
sends it as TestFlight's "What to Test" and `prepare_release` writes the
same text as the App Store's "What's New". Two copies is how they end up
disagreeing. Bump `CURRENT_PROJECT_VERSION` before `beta` — ASC rejects a
build number it has already seen for that version string.

`prepare_release` stops one step short of submitting: it opens (or reuses)
the editable version, writes What's New, waits for ASC to finish
processing the build — an upload is accepted long before the build can be
*selected* — and attaches it.

Submitting stays a separate, deliberate step, and `submit_release` is it.
Starting a review is the one thing here you can't undo quietly, so the
lane checks every precondition before it creates anything: that ASC is
preparing the version you think it is, that a build is actually attached,
and that nothing is already with Apple. It reuses an open submission left
by a failed run rather than making a second one — ASC allows only one at
a time — and won't add the same version twice.

Bundler needs a modern Ruby; macOS's own is 2.6. Homebrew's (`brew install
ruby`, `/opt/homebrew/opt/ruby/bin` on `PATH`) is what this repo has been
run against — the CI runner uses 3.4.

Everything but `screenshots` needs an App Store Connect API key — see the
comment at the top of the Fastfile for the three environment variables.
The `.p8` lives outside the repo and downloads exactly once.

`screenshots` runs the `WeatherCirclesUITests` target, which drives the
real UI: it taps the centre of the plot for the explainer sheet and the
footer button for the guide, so **the app carries no screenshot-only
code**. Earlier rounds of screenshots had to add temporary launch-argument
hooks to `ContentView` to force a sheet open, because `simctl` can't tap.
Only deterministic targets are used — "tap the wind barb" would be a
lottery, since the barb points wherever the weather says, so the explainer
shot aims at the circle, which is on every plot.

Notes worth keeping:

- `snapshot` matches simulators **by name against ones that already
  exist** and errors rather than creating them, so the lane creates any
  that are missing first.
- `erase_simulator(true)` is deliberate: the one-time "tap any part of the
  circle" nudge retires itself once the guide is opened — and the test
  opens it — so without a wipe every run after the first would silently
  lose that line from the main screenshot.
- ASC rejects anything that isn't an exact pixel size for its slot, and it
  asks for the 6.5" set by name (1284 × 2778 — iPhone 14 Plus). The other
  two are 6.9" (1320 × 2868) and iPad 13" (2064 × 2752).

### CI

`.github/workflows/ci.yml` builds the app, widget and UI test target on
every push and PR, and captures the screenshot set on `main` (or on
demand), leaving it as a downloadable artifact. macOS runners are free
here because the repo is public.

Both workflows pin `macos-26` and select **Xcode 26.6** explicitly — the
same toolchain used locally, and the one whose SDK the project is built
against. The runner image carries the iPhone 17 and iPad Pro (M5)
simulators the Snapfile asks for; an older image wouldn't.

`.github/workflows/release.yml` is `workflow_dispatch` only — uploading to
App Store Connect shouldn't be something a push can trigger by accident.
It needs three repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_KEY_P8` (the .p8 file's *contents*, which the workflow writes to the
runner's disk and nowhere else).

One caveat on the `beta` lane in CI: it signs for distribution, which a
runner can't do with the automatic signing used locally — that leans on an
Apple ID signed into Xcode. Set up `match`, or import a distribution p12
and profile, before running it there. `screenshots` and `review_status`
need no signing and work on CI as-is.

## 1.1: the 7-day page reaches the top

A page used to be `containerRelativeFrame(.vertical)` — the *safe area's*
height — while the ScrollView it pages through is the height of the whole
window. On iPhone 14 Plus that's 845 against 926: a page could never fill
the screen, so at the bottom of the scroll the leftover 81pt had to show
something, and what sat above page 2 was the main page's own footer,
stranded in the status bar strip. (Nobody noticed on page 1: what's above
*it* is blank inset.)

Measured rather than guessed, via a throwaway UI test that read element
frames before and after a swipe: the scroll travelled exactly 845pt, one
page height, and page 2's top landed correctly at y=47 — the shortfall was
never in the snapping, it was the page being smaller than its viewport.

Pages are now the full window height and apply the safe-area insets
themselves, so paging lands on a page exactly. Two things that bit on the
way, both worth remembering:

- `.viewAligned` snapping doesn't help. No snapping behaviour can show a
  page that the content isn't long enough to scroll to.
- Once the `GeometryReader` is `.ignoresSafeArea()` — which it must be, to
  measure the whole window — its proxy reports `safeAreaInsets` as **zero**,
  which quietly put the header under the status bar. The insets come from
  the window instead.

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

## 1.1: the area chart

A third vertical page, below the 7-day one: the outline of the country
you're in, with a circle on each of its major cities. Swipe up twice.

- **Points, not a lattice.** The first version tiled a regular 5 × 5 grid
  of model points over a 200 km window of Apple's basemap. It worked, but
  a perfect grid reads as a model dump, and a desaturated basemap fights
  the app's one-ink look. Cities scattered over a bare coastline read as a
  weather chart.
- **The outline is bundled, not fetched.** `scripts/make_atlas.py` builds
  `WeatherCircles/Atlas.json` from Natural Earth (public domain): 1:50m
  coastlines quantised to hundredths of a degree (~1.1 km), plus the 25
  biggest places per country. About 1 MB, no boundary service to be down,
  and coarse on purpose — the chart wants a recognisable shape, not a
  survey. Re-run the script to refresh it.
- **One landmass, not one country.** `CountryAtlas.region` finds the ring
  you're standing in, then keeps only rings within 12 % of its size around
  it. Otherwise a chart of France is sized to hold Guyane, and a chart of
  Britain wastes a fifth of its height on Shetland. Coastal points often
  fall *outside* a 1:50m trace (Sydney does), so a miss falls back to the
  nearest coastline — biased towards the biggest ring nearby, or a harbour
  city ends up with a chart of its own harbour island.
- **Spacing is chosen in degrees, not points.** The fetch has to be
  settled before there's a layout to measure, so cities are picked biggest
  first, each at least 8.5 % of the chart's width from the last.
- **Then a coverage pass, because population hugs the coast.** Australia
  by population alone is nine seaside cities and a blank middle — the part
  of the country a chart most wants a reading from. A staggered lattice
  sweeps the land, and any cell more than a quarter of the chart from
  everything picked so far pulls in the biggest place near it, or plots
  the bare spot if the country has nothing listed there (Alaska,
  Greenland). For that to find anything, `make_atlas.py` keeps each
  country's 25 biggest places **plus** its 12 loneliest — scored on
  distance to the nearest bigger place, which is how Alice Springs
  (Australia's 46th largest) gets into a 30-name list at all.
- **One request.** `AreaObservationsClient` sends every coordinate in a
  single Open-Meteo call (comma-separated `latitude`/`longitude`), asking
  only for what the plain circle draws. No METAR leg: a dozen station
  lookups to decorate thumbnails would be rude and slow.
- **Names are laid out, not just offset.** They draw in a second pass over
  the circles (an 8-okta disc is a solid black wall to a caption under
  it), and each takes the first slot — under, over, beside, shouldered —
  that hits no circle and no name already placed, sliding back inside the
  chart rather than falling off the edge. Keeping the *circles* apart
  isn't enough on a crowded country: a name is three times wider, and
  Denmark printed "Roskilde" straight through "København". When nothing
  fits, the name drops and the temperature stands alone. Order is where
  you are, then cities by size, so the least important name is the one
  that ends up compact.

## 1.2: pressure in full, and a Settings sheet

The most-asked-for change: `216` is the real notation, and it is
unreadable unless you already know the rule. `PressureStyle` (Shared) is
the two ways the pressure slots can be written — `.coded`, the chart's
shorthand and still the default, and `.hectopascals`, the figure itself —
stored in the App Group beside the pinned city (`PressureStyleStore`) and
read by the views through `@AppStorage`.

Only the *writing* changes. The slots keep their positions, the coding
rule is still taught, and nothing else on the circle moves — this is not
a units conversion (a hectopascal and a millibar are the same size; the
data was always hPa).

- `StationObservation.pressureText(_:)` / `pressureChangeText(_:)` are the
  two slots under a given style; `pressureCodedPPP` / `pressureChangeCodedPP`
  stay as the coded forms, since the guide still quotes them.
- `StationPlot.pressureStyle` is an explicit property, not a global read,
  so previews and the guide's illustrations draw the style they're asked
  for. The widgets never draw the full model, so they take the default.
- **The plate is 260 units wide and the spelled-out figures are twice as
  many characters**, which is the whole of the layout work. PPP drops from
  26pt to 20 and `pressureAnchor` is now clamped by the label's width, so
  a NE-ish barb nudge (up to 40 units) can't push `1021.6` off the edge
  where the Canvas would clip it. pp drops from 18pt to 14: between the
  rim and the right edge there are 58 units for the figure, the trace
  glyph and the gap, and `+1.1` doesn't fit at 18. The tap boxes derive
  from the same width, so hit-testing follows the setting.
- The guide's pressure and tendency pages are style-aware — `summary`,
  `meaning`, `howToRead` and `reading(for:)` take the style, and the copy
  for both lives in one private `PressureStyle` extension in
  `StationGuide.swift`. Teaching the coding rule to someone whose circle
  isn't using it would be a lie, so each style's key ends by pointing at
  the other one.
- Entry points: a gear in the main page's footer (`SettingsView`), and a
  segmented picker on the pressure and tendency guide pages — which is the
  page you are on at the moment you decide the shorthand is unreadable.
  Settings rows draw the same observation each way rather than describing
  the difference in words.
