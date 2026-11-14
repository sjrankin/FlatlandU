# FlatlandNativeUI

Native (SwiftUI) screens for Flatland, loaded by Godot as a GDExtension written with
[SwiftGodot](https://github.com/migueldeicaza/SwiftGodot). Preferences, About, Live Data, Today's Times, Earthquakes, Satellites, My Locations, Earthquake Regions, the Debugger and the bottom button bar. The overall structure and the full build instructions are in [Implementation.md](../../Implementation.md); this file keeps the Swift-side details.

## How it fits together

```
GDScript (scripts/core/native_ui.gd)            Swift (this package)
─────────────────────────────────────────       ───────────────────────────────────────────
show_preferences()  ── JSON schema + values ──▶ FlatlandNativeUI.showPreferences → SwiftUI sheet
                                                (iOS: UIHostingController, macOS: NSWindow)
Settings.set_value ◀── value_changed(key,json)─ the user edits a control
Reset / open Satellites ◀ action_triggered(id)─ the user taps an action row
Settings.changed   ── updateValue(key,json) ──▶ the sheet shows changes made on the Godot side
```

* The settings are described once. `scripts/ui/setting_controls.gd` records what each Godot control is
  while `prefs_dialog.gd` builds the Godot dialog; `NativeUI` sends that record as JSON. Nothing is
  defined twice, so the Godot dialog (desktop, Android, and the iOS fallback) and the native one cannot
  drift apart.
* `NativeUI.wanted()` is true on iOS (or with `-- --native-ui` on macOS) when the extension is loaded.
  `main.gd` then shows the native screen; otherwise it shows the Godot dialog as before.

## Building

SwiftPM downloads SwiftGodot (pinned to a revision in `Package.swift`), swift-argument-parser and
swift-syntax, and runs SwiftGodot's code generator and macros while compiling. If `swift build` cannot clone,
put Apple's git first (`export PATH="/usr/bin:$PATH"`): a broken `/usr/local/bin/git` was the cause here.

```bash
export PATH="/usr/bin:$PATH"
export DEVELOPER_DIR="/Applications/Xcode 27.app/Contents/Developer"
cd native/FlatlandNativeUI

# macOS (to try it in the Godot desktop build):
swift build -c release
cp .build/release/libFlatlandNativeUI.dylib ../../addons/FlatlandNativeUI/bin/

# iOS (device + Simulator), as one xcframework. The two skip flags are needed because xcodebuild asks
# permission to run SwiftGodot's code-generator plug-in and macros.
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

`addons/FlatlandNativeUI/FlatlandNativeUI.gdextension` (copied from the `.template` here) points Godot at both.

After exporting for iOS, in Xcode add `FlatlandNativeUI.xcframework` to the target's *Link Binary With
Libraries* and *Embed Frameworks* (the SwiftGodot Apple template documents this Godot export gap).

## Trying it on the Mac

`godot --path . -- --native-ui --open=native` opens the native window; `-- --native-ui` alone makes the
Preferences button use it.

## Status

* macOS: built; loads in Godot 4.7.2; opens the native window; edits from Swift reach `Settings` with the
  right types (bool, int, colour string); closing reports back. (Checked with the `debugEdit` method, not by
  clicking.)
* iOS: device and Simulator frameworks build and the entry symbol is present. Not yet run on a device; the
  Xcode embedding step above has not been tried.
* `@Callable` methods keep their camelCase names in GDScript (`showPreferences`); `@Signal` names become
  snake_case (`value_changed`).
