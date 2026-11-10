# FlatlandU
November 2026\
Stuart Rankin

A Godot 4.7 port of **FlatlandView** (Stuart Rankin's macOS/SceneKit "Flatland" – day and night on the Earth,
in 3D and flat polar/equirectangular projections). All UI (menus, toolbar, dialogs, status bar) is built from
Godot Control nodes.

Open the folder in Godot 4.7 (or run `Godot --path .`).

## What is ported
- **Views**: 3D globe (sun fixed, Earth turned by UTC, sun + cyan moon light, striped poles with gold balls,
  grid/tropics/polar circles/meridians, hour labels as extruded text, city markers/names, USGS earthquakes as
  arrows or spheres, heritage sites, POIs, optional star sky), flat north-centered and south-centered polar maps
  with the original pre-rendered night masks, and the rectangular map with the shifted night mask.
- **Hour labels**: none / solar / relative to noon / relative to home location / wall clock.
- **Data**: 410 cities + extras, 1121 UNESCO sites, POIs (exported from `MappableS.db` to `data/*.json`),
  live USGS feed once a minute with new-quake status messages and sounds.
- **UI**: menu bar, icon toolbar (original icons), time label (UTC/local), status bar, Preferences (General, Map
  picker with previews, Cities, Grid, Earthquakes, Home), Today's Times, Earthquake list, Live Data Status, About
  (spinning globe), debug info grid, snapshot (file dialog), "what's here" popup (right-click / double-click).
- **Assets**: 68 map definitions (`data/maps.json`, 182 map images), 1,098 night masks, button/sun/texture icons and sounds.

## Added in the second pass
Cubic world, extruded 3D city/location labels, per-map 2D light multiplier, 2D marker shadows, My Locations editor,
Earthquake Regions editor (filters the quake display), color and font preferences, a Debugger window (clock
control with time travel and speed, sun data, performance), a live NASA MODIS satellite map (downloaded from NASA
GIBS, cached daily, converted to the polar layouts), and an embedded "Simple" map set so the app always has maps.
Day/night in the flat views is now computed by a shader (same geometry as the pre-rendered masks).

## Deliberately not ported
SQLite settings store (Godot's config file and JSON are used), macOS widgets, the SceneKit stencil/layer pipeline.

## Layout
- `scripts/core` settings, solar math, geography, map catalog, city DB, USGS service (autoloads and helpers)
- `scripts/views` globe and flat views; `scripts/ui` dialogs and widgets; `scripts/main.gd` main window
- `Assets/BuiltIn` holds the embedded Simple map; `Maps/` holds the other maps, loaded at runtime if present
  (`.gdignore` keeps them out of the importer and the export). `NightMasks/` is no longer used. `tools/` has the scripts that regenerated data and assets from the Swift project.

Development flags (after `--`): `--view=`, `--map=`, `--hours=`, `--time=<unix>`, `--cam=yaw,pitch,dist`,
`--open=prefs|map|about|times|quakes|live|click`, `--shot=<png>`.
