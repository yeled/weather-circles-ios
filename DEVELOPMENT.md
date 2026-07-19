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
Shared/                 compiled into both targets:
  StationObservation    model + oktas/WMO-code derivations
  StationPlot           the Canvas renderer (the port)
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
