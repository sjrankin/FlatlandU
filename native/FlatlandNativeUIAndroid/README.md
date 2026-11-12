# FlatlandNativeUI for Android

The Android counterpart of `../FlatlandNativeUI` (Swift): Flatland's dialogs and button bar drawn with Jetpack
Compose (Material 3) instead of Godot controls. Godot describes each screen as JSON; this plugin draws it and
reports edits and taps back through signals. The calls and signals are the same as on iOS (see
`FlatlandNativeUIPlugin.kt`), and `scripts/core/native_ui.gd` (class `NativeUI`) is the only Godot code that talks to it.

## Pieces
- `plugin/` : the Godot Android plugin (an AAR). `Schema.kt` reads the JSON, `ScreenViews.kt`, `ItemViews.kt` and
  `Controls.kt` draw it, `Toolbar.kt` is the button bar, `Presenter.kt` puts them over Godot's view.
- `sample/` : a small app that shows one of every kind of item without Godot (`./gradlew :sample:installDebug`).
- `../../addons/FlatlandNativeUI/export_plugin.gd` : editor plugin that adds the AAR and its Compose dependencies
  to Android exports. It is enabled in `project.godot`.

## Build the plugin
```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :plugin:assembleRelease
cp plugin/build/outputs/aar/plugin-release.aar ../../addons/FlatlandNativeUI/bin/android/FlatlandNativeUI.aar
```
`libs/godot-classes.jar` is the classes of Godot's `godot-lib` (from the 4.7.2 export template); it is only used to compile.

## Export
The Android preset needs **Use Gradle Build** on, and the build template installed (`android/build`, from
Project > Install Android Build Template). Both are done in this project. Then export as usual.
Dependency versions in `plugin/build.gradle.kts` and `export_plugin.gd` must match.
