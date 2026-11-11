# FlatlandU
November 2026\
Stuart Rankin

A Godot 4.7 port of **FlatlandView** (Stuart Rankin's macOS/SceneKit "Flatland" – day and night on the Earth,
in 3D and flat polar/equirectangular projections). All UI (toolbar, dialogs, status bar) is built from
Godot Control nodes.

## Methodology
I used Claude to create FlatandU based on FlatlandView (which was written by hand by me)

## Goal
My goal was to have an updated version of Flatland where I can add new features and not worry about deprecated APIs. I chose Godot after using it for BoardTestG. Godot has most of the features I want (lighting, shadows, good 3D model, and the like) and need for Flatland. A bonus was Godot cross-compiles on my Mac so I can build for macOS, iOS/iPadOS, Android, and Windows. Older versions of Flatland only supported Apple products.

### Extending Flatland
A feature I wanted to add to the original Flatland was the display of satellites. I never did this due to the press of other concerns. FlatlandU made it straightforward to add satellites to the app.

Other extensions I am considering are: grouping earthquakes to avoid visual clutter, better star background (perhaps with lines delimiting constellations), and maybe adding motion detections (see HUDViewWatch) to update the background realtime.

An earlier version of Flatland had the moon in the overall view as well. That is a good candidate to add back.

## Features

### 3D View
#### Sphere
The earth is shown as a globe with a built-in map wrapped on a sphere. Lighting simulates day and night, and the sphere rotates once a day relative to the light.
#### Cube
I created a cubic shape as well with the map of the Earth plotted on it. This is more whimsy than for any other reason.
### 2D View
For fun, I implemented two-dimensional worlds as well - one is a standard equirectangular map, and two are polar maps (one north-centered and the other is south-centered). All elements are plotted on these maps as well.
#### Maps
The local build has access to many maps but the ones exported to other platforms have only two maps built-in. (They can read maps on mass storage devices however.)
##### Map Formats
All maps used by FlatlandU must be supplied in three formats:
1. Equirectangular (used by the Sphere, Cube, and flat map shapes).
2. North-centered polar.
3. South-centered polar.
In general, the larger the map, the better the end-product looks. However, the larger the map, the larger the binary.
#### Cities
A set of cities is built-into FlatlandU. Cities are shown with various markers to provide context for earthquakes.
### Earthquakes
The feature that is used the most with FlatlandU is seeing new earthquakes. Earthquake data is retrieved from the USGS periodically and new earthquakes are plotted. Earthquakes remain on the map for a set amount of time.
### Stars
This is a new, not fully completed feature that shows the arrangement of the 1000 brightest stars as a background to the main view.
### Satellites
This is also a not yet completed feature that shows various satellites (mainly Earth-observation satellites or space stations or weather satellites). Satellites are show over the map being used and labeled.

## Godot Notes
### User Interface
The user interface from Godot is acceptable on macOS and Windows where there is a great deal of space for the small text chosen by Godot. On smaller devices, the user interface becomes untenable. This required specific instructions to Claude to update how Godot displays on smaller devices, adding more code paths.

Godot cannot make use of native controls to the extent to make it practical to use them. This is to be expected given the goals of Godot (games, not user interfaces for non-game utilities).

# Implementation

Open the folder in Godot 4.7 (or run `Godot --path .`).

## What is ported
- **Views**: 3D globe (sun fixed, Earth turned by UTC, sun + cyan moon light, striped poles with gold balls,
  grid/tropics/polar circles/meridians, hour labels as extruded text, city markers/names, USGS earthquakes as
  arrows or spheres, heritage sites, POIs, optional star sky), flat north-centered and south-centered polar maps
  with the original pre-rendered night masks, and the rectangular map with the shifted night mask.
- **Hour labels**: none / solar / relative to noon / relative to home location / wall clock.
- **Data**: 410 cities + extras, 1121 UNESCO sites, POIs (exported from `MappableS.db` to `data/*.json`),
  live USGS feed once a minute with new-quake status messages and sounds.
- **UI**: icon toolbar with a "More" button (original icons; same bar on macOS, Windows, iOS and Android), time label (UTC/local), status bar, Preferences (General, Map
  picker with previews, Cities, Grid, Earthquakes, Home), Today's Times, Earthquake list, Live Data Status, About
  (spinning globe), debug info grid, snapshot (file dialog), "what's here" popup (right-click / double-click).
- **Assets**: 68 map definitions (`data/maps.json`, 182 map images), 1,098 night masks, button/sun/texture icons and sounds.

## Added in the second pass
Cubic world, extruded 3D city/location labels, per-map 2D light multiplier, 2D marker shadows, My Locations editor,
Earthquake Regions editor (filters the quake display), color and font preferences, a Debugger window (clock
control with time travel and speed, sun data, performance), a live NASA MODIS satellite map (downloaded from NASA
GIBS, cached daily, converted to the polar layouts), and an embedded "Simple" map set so the app always has maps.
Day/night in the flat views is now computed by a shader (same geometry as the pre-rendered masks).

## Added since
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
- **Preferences**: Show stars, Show FPS, 3D shadows, Show satellites, city and quake shapes.
- **Maps**: Simple and Simple Political Map 1 are embedded in `Assets/BuiltIn`; the larger sets in `Maps/` are git-ignored.
- **Phones**: iOS and Android get a scaled-up UI, safe-area insets, portrait and landscape, and a two-line status bar.
  The launch screen is a black field with the sun (`Assets/Splash.png`, drawn by `tools/render_splash.gd`).
  The app icon is `Assets/AppIcon.png`.
- **Fonts**: Noto Sans is bundled as the fallback font (`Assets/Fonts`, SIL Open Font License, shown in About).
  Hour labels, the welcome text and quake magnitudes use a heavy face (Arial Black, else Noto Black).
- **Exports**: `export_presets.cfg` writes the iOS build to `~/Desktop/FlatlandUIExports/iOS/FlatlandU.ipa`.

## Deliberately not ported
SQLite settings store (Godot's config file and JSON are used), macOS widgets, the SceneKit stencil/layer pipeline.

## Layout
- `scripts/core` settings, solar math, geography, map catalog, city DB, USGS service (autoloads and helpers)
- `scripts/views` globe and flat views; `scripts/ui` dialogs and widgets; `scripts/main.gd` main window
- `Assets/BuiltIn` holds the embedded Simple map; `Maps/` holds the other maps, loaded at runtime if present
  (`.gdignore` keeps them out of the importer and the export). `NightMasks/` is no longer used. `tools/` has the scripts that regenerated data and assets from the Swift project.

Development flags (after `--`): `--view=`, `--map=`, `--hours=`, `--time=<unix>`, `--cam=yaw,pitch,dist`,
`--open=prefs|map|about|times|quakes|live|satellites|click`, `--shot=<png>`,
`--set=key=value` (a setting for this run only, never saved), `--resize=WxH`, and for checking the phone layout in a
normal window `--phone`, `--ui-scale=N` and `--safe=top,bottom,left,right`.
