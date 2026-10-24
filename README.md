# Save the Thief

2.5D physics puzzle for Android, made with **Godot 4.7.2** (GDScript, Jolt physics).
Tap groups of coloured blocks so rocks, a boulder or lava drain into the pit instead of
crushing the thief, then open the exit.

## Project layout

| Folder | Contents |
|---|---|
| `scenes/` | `Game.tscn` (the game builds its level in code) |
| `scripts/` | gameplay: blocks, hazards, planks, cloth, thief, UI, synthesised audio |
| `autoload/` | singletons: `GameState`, `AudioManager`, `AdsManager`, `Materials`, `Haptics` |
| `levels/` | `level_01.json` ... `level_15.json` |
| `assets/` | textures (`assets/textures/<name>.png` is used automatically), audio overrides, models |
| `docs/` | production roadmap |

## What is NOT in this repository (download / create it on each machine)

| Item | Why it's left out | How to get it |
|---|---|---|
| Godot editor binary | 170 MB, different per OS | https://godotengine.org/download/archive/4.7.2-stable/ |
| Export templates | large, per machine | Godot editor: *Editor > Manage Export Templates*, or the `.tpz` from the same page |
| `.godot/` | cache, rebuilt on first open | opens/imports automatically |
| `export/` (APK/AAB) | build output | re-export (see below) |
| Original texture packs (`.zip`) | large source files | keep them outside the repo; only the optimised copies in `assets/textures/` are used |
| Keystores and passwords | secrets | stored in `.godot/export_credentials.cfg` (never committed) |

## Run on a desktop

1. Install Godot 4.7.2 and open `project.godot` (first open imports assets).
2. Press **F5**. Debug keys: **R** restart, **N**/**P** next/previous level.

## Build the Android APK on a Linux VPS (headless)

```bash
# 1. Get the code
git clone https://github.com/<you>/<repo>.git save-the-thief && cd save-the-thief

# 2. Godot 4.7.2 (Linux) + export templates
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
wget https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip Godot_v4.7.2-stable_linux.x86_64.zip
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable
unzip -j Godot_v4.7.2-stable_export_templates.tpz -d ~/.local/share/godot/export_templates/4.7.2.stable
GODOT=./Godot_v4.7.2-stable_linux.x86_64

# 3. Java 17 + Android SDK command-line tools (for apksigner), e.g. on Ubuntu:
sudo apt install -y openjdk-17-jdk-headless unzip
#    then install the Android command-line tools and run:
#    sdkmanager "platform-tools" "build-tools;35.0.0" "platforms;android-35"

# 4. A signing key (debug key for testing; use a real upload key for Play Store)
keytool -genkeypair -v -keystore ~/debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"

# 5. Tell Godot where the SDK, Java and key are (first run creates editor settings)
$GODOT --headless --path . --import
#    edit ~/.config/godot/editor_settings-4.7.tres:
#      export/android/android_sdk_path = "/path/to/android-sdk"
#      export/android/java_sdk_path    = "/usr/lib/jvm/java-17-openjdk-amd64"
#    and create .godot/export_credentials.cfg:
#      [preset.0]
#      [preset.0.options]
#      keystore/release="/home/<user>/debug.keystore"
#      keystore/release_user="androiddebugkey"
#      keystore/release_password="android"

# 6. Export
mkdir -p export && $GODOT --headless --path . --export-release "Android" export/SaveTheThief.apk
```

## Assets you can drop in

Put PNGs in `assets/textures/` with these names and they are used automatically:
`wood_wall.png`, `wood_wall_dark.png`, `wood_plank.png`, `stone.png`, `lava.png`, `fabric.png`,
`block_red.png`, `block_blue.png`, `block_yellow.png`, `block_green.png`, `ui_button.png`, `ui_panel.png`.
The drain pit uses the PBR set in `assets/textures/pit/`.
A rigged thief model goes in `assets/models/thief.glb` (animations: idle, scared, run, fall, cheer).
Sounds are synthesised in code; a file in `assets/audio/` with the same name replaces one (see `AudioManager.gd`).

## License note

Godot Engine is MIT-licensed; its license text must be shown in the app's credits.
