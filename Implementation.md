# FlatlandU implementation notes

How FlatlandU is put together, what is shared between platforms and what is not, what has been ported from
FlatlandView, the development flags, and how to build it. For what the app does, see [README.md](README.md).

## 1. Structure of the project

FlatlandU is one Godot 4.7 project. Almost everything is GDScript that runs unchanged on macOS, Windows, iOS and
Android. The platform-specific parts are small: some phone-only Godot code, and two native plug-ins that draw the
iOS and Android dialogs and button bar.

```
FlatlandU/
├── project.godot, export_presets.cfg      project settings; the four export presets
├── scenes/main.tscn                       the one scene (runs scripts/main.gd)
├── scripts/
│   ├── main.gd                            main window: views, toolbar, status bar, dialogs
│   ├── core/                              settings, solar math, geography, data services
│   ├── views/                             3D globe / cube, flat maps, sky, satellites
│   └── ui/                                Godot dialogs and widgets
├── shaders/                               day/night, earth, stars, sky, cube
├── data/                                  cities, heritage sites, POIs, stars, map catalog, build info (JSON)
├── Assets/ Maps/ ExternalData/            icons, fonts, sounds, textures; maps; source data (not exported)
├── addons/
│   ├── build_number/                      editor plug-in: bumps the build number on export
│   └── FlatlandNativeUI/                  the native-UI plug-ins as Godot sees them (see section 3)
├── native/
│   ├── FlatlandNativeUI/                  Swift package (SwiftUI): iOS and macOS
│   └── FlatlandNativeUIAndroid/           Gradle project (Kotlin, Jetpack Compose): Android
├── android/                               Godot's Android Gradle template (generated, git-ignored)
└── tools/                                 scripts that produced data and assets from the Swift project
```

### 1.1 Shared by every platform

| Part | What it does |
|---|---|
| `scripts/core/settings.gd` (autoload `Settings`) | Every setting, its default, change notification, persistence (`user://settings.cfg`). |
| `scripts/core/solar.gd`, `geo.gd` | Sun position, equation of time, day/night geometry, geography helpers. |
| `scripts/views/solar_lunar_marker.gd` | The glossy yellow ball under the sun and bright blue ball under the moon (the sub-solar and sub-lunar points), as in the other Flatlands. Drawn on the globe, the cubic Earth (on the cube's surface), both 3D flat maps and the 2D flat view. Settings `show_sun_point` and `show_moon_point`. |
| `scripts/core/video_recorder.gd`, `scripts/core/quicktime_writer.gd` | The Record button in the button bar records the window to a QuickTime movie (.mov, Motion-JPEG, about 30 frames a second, scaled to at most 1920 on the long edge, no sound). Frames are written to the file as they are taken; the index is added when recording stops. The first press asks where to save (on a phone it goes straight to Movies); the second stops. Dev flag `--record=<file>` records 4 seconds. |
| `scripts/views/globe_view.gd` (camera modes), `scripts/main.gd` (context menu) | Right click (long press on a phone or tablet) in a 3D view opens a menu: Show Earth from Moon / from Sun (the camera sits there and follows the moon, facing the Earth), View Moon from Earth (stands still and points at the moon, moving round the Earth first if it is hidden behind it), Camera Flight (a slow wandering flight round the Earth that keeps clear of the Earth, poles, satellites and quake markers; ends on a double click), Reset View, and What's Here?. Not saved. Moving the camera or resetting the view returns to orbiting the Earth. Dev flag `--vantage=moon|sun|lookmoon|flight`. |
| `scripts/core/lunar.gd` | Moon position (right ascension, declination, distance, sub-lunar point) from the Astronomical Almanac's low-precision series. The 3D view draws the Moon at its true size and distance (texture in `Assets/Moon/`); the flat maps do not show it. Setting `show_moon`. |
| `scripts/core/city_db.gd`, `map_catalog.gd` | Cities, heritage sites, POIs; the catalog of maps and their textures. |
| `scripts/core/quake_service.gd` | USGS earthquake feed (HTTP, once a minute by default). |
| `scripts/core/satellite_service.gd` | Satellite elements (CelesTrak) and orbit propagation. |
| `scripts/core/build_info.gd` | Build number and timestamp (reads `data/build_info.json`). |
| `scripts/views/*` | `globe_view.gd` (globe and cube), `flat_view.gd` / `flat_stage.gd` (polar and rectangular maps), `intro_text.gd` (welcome text), `satellite_model.gd`, `shapes.gd`. |
| `shaders/*` | Day/night blending, earth, stars, sky, cube. |
| `scripts/ui/*_dialog.gd`, `status_bar.gd`, `time_label.gd`, `setting_controls.gd` | The Godot version of every dialog and widget. |
| `data/`, `Assets/` | All data and artwork. Only two maps are built in (`Assets/BuiltIn`); the rest live in `Maps/` and are loaded at runtime if present. |

The Godot dialogs are the only dialogs on macOS and Windows, and they are also the fallback on a phone whose build
has no native plug-in.

### 1.2 Phones only (iOS and Android), still Godot code

Selected with `OS.has_feature("mobile")`, or the `--phone` flag on a desktop (see section 5).

| Part | What it does |
|---|---|
| `scripts/core/layout.gd` | `Layout.is_phone()`, UI scale, safe-area insets (camera cut-out, home indicator). |
| `scripts/ui/phone_theme.gd` | Scaled-up theme: bigger text, controls, check boxes, arrows, rounded buttons. |
| `scripts/ui/phone_sheet.gd` | Full-screen sheet that slides up from the toolbar; footer buttons (Close at the lower right). |
| `scripts/main.gd` (phone branches) | Toolbar at the bottom, wrapped into rows, views shifted up; two-line status bar. |
| `scripts/core/power_manager.gd` (autoload `PowerManager`) | Frame-rate cap, pausing drawing under a sheet, Low Power Mode, keep-screen-on. Runs everywhere, but only has an effect on phones, apart from the frame-rate choice. |

### 1.3 Platform-specific native code

| Platform | Code | Technology |
|---|---|---|
| iOS, macOS | `native/FlatlandNativeUI/` | Swift 6 toolchain (Swift 5 mode), SwiftUI, [SwiftGodot](https://github.com/migueldeicaza/SwiftGodot) GDExtension. Dialogs are sheets (iOS: `UIHostingController` page sheet; macOS: a window, used only for development). The button bar is a view along the bottom edge of Godot's view (iOS) or a window (macOS, development only). |
| Android | `native/FlatlandNativeUIAndroid/` | Kotlin, Jetpack Compose (Material 3), a Godot Android plug-in (AAR). Dialogs are full-screen overlays that slide up; the button bar is an overlay at the bottom. |
| Windows | none | The Godot dialogs. |
| macOS (the app itself) | `native/FlatlandNativeUI/` | The same SwiftUI screens as iOS, in their own windows; the button bar is a SwiftUI view along the bottom of the Godot window, in as many rows as its width needs. |

`scripts/core/native_ui.gd` (class `NativeUI`) is the single place where Godot code talks to either plug-in; nothing
else in the project knows which platform's native code is in use.

## 2. How a native screen is drawn

Each dialog that has a native version provides two methods:

```
native_screen() -> Dictionary   {"screen": {title, pages: [{title, items: [...]}]}, "values": {key: value}}
native_event(kind, key, value)  kind "value" (a control was edited), "action" (a button or row was tapped),
                                "closed" (the screen went away)
```

`main.gd`'s `_popup()` calls `NativeUI.present(dialog)` first and falls back to the Godot dialog if that returns
false. Godot sends the plug-in JSON; the plug-in draws it and reports edits and taps back through signals.

```
GDScript (NativeUI)                 native plug-in (Swift or Kotlin)
show_screen(schema, values)  ─────▶  draws the screen
update_screen / update_value ─────▶  new content, navigation stays where it is
close_screen                 ─────▶  dismisses it
value_changed(key, json)     ◀─────  the user edited a control
action_triggered(id)         ◀─────  the user tapped a button or row
sheet_closed()               ◀─────  the screen went away
show_toolbar / update_toolbar / hide_toolbar ──▶  the button bar
toolbar_tapped(id), toolbar_height_changed(pixels) ◀──  taps; room Godot must leave at the bottom
power_state()                ─────▶  "normal", "low_power", "thermal" or "critical"
```

- **One description for both platforms.** Item kinds: section, toggle, choice, number, color, text, action, info,
  paragraph, row. `Schema.swift` and `Schema.kt` read the same JSON.
- **Preferences are not described twice.** `setting_controls.gd` records what each Godot control is while
  `prefs_dialog.gd` builds the Godot dialog, and `NativeUI` sends that record. The two versions cannot drift apart.
- **Native dialogs with Godot counterparts:** Preferences (with the Power page), About, Live Data, Today's Times,
  Earthquakes, Satellites, My Locations, Earthquake Regions, Debugger.
- **Names.** Swift `@Callable` methods keep camelCase in GDScript (`showScreen`); `@Signal` names become
  snake_case. `NativeUI._call()` accepts either. On Android the plug-in is the engine singleton `FlatlandNativeUI`
  (`Engine.get_singleton`); on iOS and macOS it is a class (`ClassDB.instantiate`). `NativeUI.available()` is false
  where the native code is missing, so desktop builds are unaffected.
- **Frame rate under a sheet.** While a native sheet covers a phone's screen, `PowerManager.set_covered(true)`
  turns Godot's drawing off (`RenderingServer.render_loop_enabled`); scripts and timers keep running.

## 3. Power management

`PowerManager` (autoload) keeps FlatlandU from using more battery than it needs:

- **Frame rate** (setting `frame_rate`): Auto, 30, 60 or 120. Auto on a phone is 60 fps while touching the screen
  and for 2.5 seconds after, then 30 fps. On a desktop Auto is not limited.
- **Draw on demand** (setting `draw_on_demand`, default on, phones only): two seconds after the last touch the cap
  drops to 5 fps (`STILL_FPS`), or 15 fps (`LIVE_FPS`) while something animates by itself (radiating quake rings,
  satellites, attract mode; the "Arrow and Ring" quake indicator and "None" do not count). Touch restores the chosen rate immediately. `flat_view.gd` also skips its per-frame
  `queue_redraw()` while covered; before, it redrew the whole 2D map every frame even under a sheet.
- **Low Power Mode / heat** (setting `follow_low_power`): the native plug-in reports the device state
  (iOS `ProcessInfo`, Android `PowerManager`); Low Power Mode or a hot device limits to 30 fps, a critical one to 20.
- **Covered or in the background:** drawing stops (see above).
- **Graphics quality** (setting `graphics_quality`: Auto, High, Medium, Low): `PowerManager.register_viewport()` sets
  each 3D view's anti-aliasing and `scaling_3d_scale` (High 4x MSAA at full resolution; Medium 2x at 80%; Low none at
  65% with 3D shadows off). Auto is Medium on a phone and High elsewhere. The two 3D views (globe, flat stage) skip
  their per-frame script work while `PowerManager.drawing()` is false.
- **Keep screen on** (setting `keep_screen_on`, default off): whether the phone may auto-lock. The project setting
  `display/window/energy_saving/keep_screen_on` is also off.

Measure with a Release build (the debugger adds load): Xcode's Energy gauge on iOS, Android Studio's Energy Profiler.

## 4. What is ported from FlatlandView

- **Views**: 3D globe (sun fixed, Earth turned by UTC, sun + cyan moon light, striped poles with gold balls,
  grid/tropics/polar circles/meridians, hour labels as extruded text, city markers/names, USGS earthquakes as
  arrows or spheres, heritage sites, POIs, optional star sky), flat north-centered and south-centered polar maps
  with the original pre-rendered night masks, and the rectangular map with the shifted night mask.
- **Hour labels**: none / solar / relative to noon / relative to home location / wall clock.
- **Data**: 410 cities + extras, 1121 UNESCO sites, POIs (exported from `MappableS.db` to `data/*.json`),
  live USGS feed once a minute with new-quake status messages and sounds.
- **UI**: icon toolbar with a "More" button (original icons on Windows and the Godot fallback; SF Symbols
  on iOS and macOS and Material icons on Android), time label (UTC/local), status bar, Preferences (General, Map
  picker with previews, Cities, Grid, Earthquakes, Colors and Fonts, Home, Power), Today's Times, Earthquake list,
  Live Data Status, About (spinning globe), debug info grid, snapshot (file dialog), "what's here" popup
  (right-click / double-click).
- **Assets**: 68 map definitions (`data/maps.json`, 182 map images), 1,098 night masks, button/sun/texture icons and sounds.

### Added in the second pass
Cubic world, extruded 3D city/location labels, per-map 2D light multiplier, 2D marker shadows, My Locations editor,
Earthquake Regions editor (filters the quake display), color and font preferences, a Debugger window (clock
control with time travel and speed, sun data, performance), a live NASA MODIS satellite map (downloaded from NASA
GIBS, cached daily, converted to the polar layouts), and an embedded "Simple" map set so the app always has maps.
Day/night in the flat views is now computed by a shader (same geometry as the pre-rendered masks).

### Added since
- **Sky**: a real star field (the 2000 brightest HYG v41 stars by RA/Dec, coloured by B-V, with hover tooltips on
  macOS and hidden when obscured) and a sun sphere in the sky. Data: `data/bright_stars.json`, built by
  `tools/extract_bright_stars.py`. HYG is CC BY-SA 4.0; the license text is in the About dialog.
- **Welcome text**: orbiting 3D title text with shadows; a Welcome toolbar button shows or hides it.
- **Satellites**: 22 tracked satellites (ISS, Tiangong, Hubble, NOAA, GOES, Webb, Roman, Himawari, MTG, MetOp-SG, ...)
  from CelesTrak elements (two-body plus J2; L2 and geostationary handled specially), drawn as pill-and-panel models
  with altitude labels on the globe and on the flat maps. Choose them in Preferences > Map > Satellites.
- **Flat maps in 3D**: the polar and rectangular maps are textures on a plane you can rotate and zoom, with a sun
  floating above, shadows cast away from the sun, extruded hour labels, 3D city and earthquake shapes, and
  satellites at one height over the map.
- **Cubic world**: faces follow the globe's longitudes and are shaded by the sun (`shaders/cube.gdshader`).
- **Preferences**: Show stars, Show FPS, 3D shadows, Show satellites, city and quake shapes, Power.
- **Maps**: Simple and Simple Political Map 1 are embedded in `Assets/BuiltIn`; the larger sets in `Maps/` are git-ignored.
- **Phones**: iOS and Android get a scaled-up UI, safe-area insets, portrait and landscape, a two-line status bar,
  full-screen sheets and a bottom button bar. The launch screen is a black field with the sun (`Assets/Splash.png`,
  drawn by `tools/render_splash.gd`). The app icon is `Assets/AppIcon.png`.
- **Native UI**: SwiftUI (iOS) and Jetpack Compose (Android) versions of every dialog, plus the bottom
  button bar (sections 1.3 and 2).
- **Power**: frame-rate control, pausing under sheets, Low Power Mode, keep-screen-on (section 3).
- **Build number**: starts at 100 and goes up at each export (`addons/build_number`); the build number and time are
  in About and in the Welcome text.
- **Fonts**: Noto Sans is bundled as the fallback font (`Assets/Fonts`, SIL Open Font License, shown in About).
  Hour labels, the welcome text and quake magnitudes use a heavy face (Arial Black, else Noto Black). The license
  text file is a plain `.txt`, so every export preset has `Assets/Fonts/*.txt` in its include filter; without it
  the Licenses view is empty in exported builds.

### Deliberately not ported
SQLite settings store (Godot's config file and JSON are used), macOS widgets, the SceneKit stencil/layer pipeline.

## 5. Development flags

Pass these after `--`, for example `Godot --path . -- --view=Cubic --open=about`.

- Content: `--view=`, `--map=`, `--hours=`, `--time=<unix>`, `--cam=yaw,pitch,dist`,
  `--set=key=value` (a setting for this run only, never saved).
- Dialogs and pictures: `--open=prefs|map|about|times|quakes|live|satellites|debug|locations|regions|toolbar|click`,
  `--shot=<png>`, `--resize=WxH`.
- Phone layout in a normal window: `--phone`, `--ui-scale=N`, `--safe=top,bottom,left,right`.
- Native UI on the Mac is always used. `--native-snap=<png>` saves a picture of the native screen and quits (the bar is
  part of the Godot window: use the system screenshot).
  `--fake-quakes` shows six made-up earthquakes (magnitude 3 to 8.5) and stops the real fetch, for checking indicators offline.

## 6. Building

### 6.1 What you need

- Godot 4.7.2 with its export templates (the Android template zip is also used to install the Gradle template).
- Xcode 27 for macOS and iOS. `xcode-select` points at the command-line tools here, so use
  `export DEVELOPER_DIR="/Applications/Xcode-27.2.app/Contents/Developer"`. If SwiftPM cannot clone packages, a broken
  `/usr/local/bin/git` is first on the path: `export PATH="/usr/bin:$PATH"`.
- JDK 17 and the Android SDK (platform 35 and 36, build tools) for Android. In Godot's editor settings, set the
  Android SDK and Java SDK paths and the debug keystore.
- Network access the first time: SwiftPM fetches SwiftGodot, swift-syntax and swift-argument-parser; Gradle fetches
  Gradle 8.11.1, the Android and Kotlin plug-ins and Jetpack Compose.

### 6.2 Run from the editor or the command line

```bash
Godot --path .                 # open the project in the editor (or add --editor)
Godot --path . -- --view=Cubic # run it, with development flags
Godot --headless --import      # refresh the class and import cache after adding scripts
```

### 6.3 The build number

`addons/build_number` raises the number in `data/build_info.json` (it starts at 100) and writes the build time at
each export. The editor plug-in must be enabled in Project Settings > Plugins (it is). Commit `build_info.json`
if you want the number to carry across machines.

### 6.4 macOS and Windows

Export from Godot with the "macOS" or "Windows Desktop" preset (Project > Export, or
`Godot --headless --path . --export-release macOS`). The presets write to `~/Desktop/FlatlandU.dmg` and
`~/Desktop/FlatlandU.exe`. The macOS build needs the Swift library (`libFlatlandNativeUI.dylib`, see 6.5) for its
button bar and dialogs; Windows needs nothing.

### 6.5 The Swift plug-in (iOS and macOS)

```bash
export PATH="/usr/bin:$PATH"
export DEVELOPER_DIR="/Applications/Xcode-27.2.app/Contents/Developer"
cd native/FlatlandNativeUI

# macOS (the Mac app's button bar and dialogs):
swift build -c release
D=../../addons/FlatlandNativeUI/bin/libFlatlandNativeUI.dylib
rm -f $D && cp .build/release/libFlatlandNativeUI.dylib $D && codesign --force -s - $D

# iOS (device and Simulator) as one xcframework. The two skip flags are needed because xcodebuild asks
# permission to run SwiftGodot's code generator and macros.
for dest in "generic/platform=iOS" "generic/platform=iOS Simulator"; do
  xcodebuild -scheme FlatlandNativeUI -configuration Release -destination "$dest" \
             -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation build
done
rm -rf ../../addons/FlatlandNativeUI/bin/FlatlandNativeUI.xcframework
xcodebuild -create-xcframework \
  -framework build/Build/Products/Release-iphoneos/PackageFrameworks/FlatlandNativeUI.framework \
  -framework build/Build/Products/Release-iphonesimulator/PackageFrameworks/FlatlandNativeUI.framework \
  -output ../../addons/FlatlandNativeUI/bin/FlatlandNativeUI.xcframework
```

Notes:
- Replace a dylib with `rm` then `cp` then `codesign --force -s -`; overwriting it in place or leaving it unsigned
  makes macOS kill Godot (exit 137).
- `native/.gdignore` keeps Godot from importing the build folders inside `native/`.
- `addons/FlatlandNativeUI/FlatlandNativeUI.gdextension` (from `FlatlandNativeUI.gdextension.template`) names the
  entry symbol `flatland_native_ui_entry` and the macOS library and iOS xcframework.
- SwiftGodot is pinned to a revision in `Package.swift`.

### 6.6 iOS app

1. Run the Swift step above, then export from Godot with the "iOS" preset (writes an Xcode project; the export path
   is `~/Desktop/FlatlandUExports/iOS/`).
2. Nothing to add by hand: Godot's export already links and embeds `FlatlandNativeUI.xcframework` (it appears under
   the target's *General > Frameworks, Libraries, and Embedded Content* as **Embed & Sign**, from
   `FlatlandU/dylibs/addons/FlatlandNativeUI/bin/`). It copies whatever xcframework is in
   `addons/FlatlandNativeUI/bin/` at export time, so rebuild the Swift plug-in (step 1) *before* exporting. Just
   check that **Signing & Capabilities** has your team selected.
3. Build for a real iPhone. The Simulator is not usable yet: Godot's `libgodot` has only an Intel (x86_64)
   Simulator slice, which fails with `Undefined symbol: _main` on an Apple Silicon Mac.
4. Check performance with a Release build, not Debug: choose **Product > Scheme > Edit Scheme…**, select *Run*, set
   *Build Configuration* to **Release**, and run on the iPhone. Then, to see the battery cost, start a run from
   **Product > Profile** and choose the Energy template, or watch the Energy gauge in Xcode's Debug navigator.
   Run it with the debugger detached for the truest numbers (*Debug > Detach*, or start the app from the iPhone's
   home screen).

### 6.7 The Android plug-in and app

```bash
cd native/FlatlandNativeUIAndroid
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :plugin:assembleRelease
cp plugin/build/outputs/aar/plugin-release.aar ../../addons/FlatlandNativeUI/bin/android/FlatlandNativeUI.aar
./gradlew :sample:installDebug     # optional: a small app that shows the native screens without Godot
```

- `libs/godot-classes.jar` is the classes of Godot's `godot-lib` from the 4.7.2 export template; it is only used to compile.
- The editor plug-in `addons/FlatlandNativeUI/export_plugin.gd` adds the AAR and its Jetpack Compose dependencies to
  Android exports. It is enabled in `project.godot`. Keep its dependency versions in step with
  `plugin/build.gradle.kts`.
- The Android preset needs **Use Gradle Build** on, and the build template installed in `android/build`
  (Project > Install Android Build Template, or unzip `android_source.zip` from the export templates there and write
  `android/.build_version`). `android/build/` is generated and over 100 MB, so it is git-ignored; install it again
  on a new clone.
- Export with the "Android" preset (`~/Desktop/FlatlandU.apk`) or
  `Godot --headless --path . --export-debug Android out.apk`. The preset excludes the iOS/macOS extension files so
  Android does not log a missing-library error.
- The Android emulator's software graphics cannot run Godot's Vulkan renderer here, so test the whole app on a phone;
  the `sample` app runs fine on the emulator.

### 6.8 Export filters

Every preset includes `Assets/Fonts/*.txt` (the font license) and the Android preset excludes
`addons/FlatlandNativeUI/*.gdextension` and `addons/FlatlandNativeUI/bin/*`. If you edit presets in the editor while
the file is also edited on disk, the editor's copy can overwrite the file: check these lines after saving.

### 6.9 Git

Git-ignored: `.godot/`, `*.import`, `ExternalData/`, `Maps/`, `FlatlandU Icons/`, the Swift and Gradle build
folders under `native/`, `android/build/`. Do not commit files over 100 MB (GitHub refuses the push).

## Code comments

Every function, class, variable and constant carries a comment that says what it is for and what it does, with its parameters and return value and references to related code. Keep them in step with the code: change the comment in the same edit as the code.

- **GDScript:** `##` doc comments above the declaration, using `[param name]`, `[method name]`, `[member name]`, `[constant NAME]` and `[signal name]`, with a `Returns:` line. Settings keys in `DEFAULTS` have a trailing `#` note each.
- **Shaders (`shaders/*.gdshader`):** `//` comments above each uniform, varying and function.
- **Swift (`native/FlatlandNativeUI`):** `///` documentation comments (`- Parameter x:` and `- Returns:`).
- **Kotlin (`native/FlatlandNativeUIAndroid`):** KDoc `/** */` with `@param`, `@property` and `@return`.
- **Python tools (`tools/*.py`):** docstrings, with `#` notes on module-level variables.

