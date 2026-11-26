#!/bin/bash
# Export release builds and package them with a README.txt and HOW_TO_PLAY.md.
# Usage: game/tools/export_build.sh <target...> [--zip] [--out DIR]
#   targets: windows linux web macos android ios, or all (= windows linux, the CI release set)
#   env GODOT  godot binary (default: godot on PATH, else /home/user/tools/godot/godot)
#   Needs the import cache and the 4.5.1 export templates in
#   ~/.local/share/godot/export_templates/4.5.1.stable/ (from Godot_v4.5.1-stable_export_templates.tpz):
#     windows  windows_release_x86_64.exe        linux    linux_release.x86_64
#     web      web_nothreads_release.zip         macos    macos.zip
#     android  android_release.apk (android_debug.apk without a release keystore)
#     ios      ios.zip
#   Android also needs a JDK (JAVA_HOME or java on PATH), the Android SDK with build-tools
#   (ANDROID_HOME or ANDROID_SDK_ROOT; Godot reads it into its editor settings) and a keystore
#   from the environment, never from the repo:
#     GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD  -> signed release APK, or
#     GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD    -> debug-signed APK.
#   iOS writes an Xcode project only (build and sign it on a Mac); Godot refuses to write it
#   without an Apple team id, so set IOS_TEAM_ID (it is put into a temporary copy of the preset).
# Result: DIR/fake-tower-<target>/ with the build, README.txt and HOW_TO_PLAY.md:
#   windows  FakeTower.exe                 linux  FakeTower.x86_64 + FakeTower.pck
#   web      index.html + index.{js,wasm,pck,...} (serve the folder over HTTPS)
#   macos    Fake Tower.app (universal, ad-hoc signed)   android  FakeTower.apk
#   ios      FakeTower.xcodeproj + FakeTower/ (sources and the .pck)
#   (+ DIR/fake-tower-<target>.zip with --zip). Default DIR: <repo>/build/dist.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$HERE/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/user/tools/godot/godot)}"
TEMPLATES="${GODOT_TEMPLATES:-$HOME/.local/share/godot/export_templates/4.5.1.stable}"
OUT="$GAME/../build/dist"
ZIP=0
TARGETS=()
USAGE="usage: $0 <windows|linux|web|macos|android|ios|all>... [--zip] [--out DIR]"
while [ $# -gt 0 ]; do
  case "$1" in
    --zip) ZIP=1 ;;
    --out) OUT="$2"; shift ;;
    windows | linux | web | macos | android | ios) TARGETS+=("$1") ;;
    all) TARGETS+=(windows linux) ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
  shift
done
[ ${#TARGETS[@]} -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

die() { echo "export_build: $*" >&2; exit 1; }

need_template() { # file...
  for t in "$@"; do
    [ -f "$TEMPLATES/$t" ] || die "missing export template $TEMPLATES/$t (extract it from Godot_v4.5.1-stable_export_templates.tpz, see .github/actions/setup-godot)"
  done
}

readme() { # platform
  local run host="" extra=""
  case "$1" in
    windows) run="Double-click FakeTower.exe."
      extra='  Windows SmartScreen may warn about an unsigned app: "More info" > "Run anyway".' ;;
    linux) run="Keep FakeTower.x86_64 and FakeTower.pck in the same folder, then: chmod +x FakeTower.x86_64 && ./FakeTower.x86_64" ;;
    macos) run='Move "Fake Tower.app" to Applications and open it. It is not notarized: the first time,
  right-click it and choose Open (or run: xattr -dr com.apple.quarantine "/Applications/Fake Tower.app").
  Allow microphone access when asked (radio voice).' ;;
    web) run="Upload this folder to any static web host (GitHub Pages works: no special headers needed)
  and open index.html over HTTPS (browsers only allow the microphone on HTTPS or localhost).
  Locally: python3 -m http.server in this folder, then http://localhost:8000/ .
  Demo modes take the launch arguments from the URL: index.html?demo=pilot or ?demo=controller."
      host="  A browser cannot host: join a game hosted on a PC or a dedicated server." ;;
    android) run="Install FakeTower.apk (allow installs from this source), start it, allow the microphone." ;;
    ios) run="Open FakeTower.xcodeproj on a Mac with Xcode, pick your signing team, build and run on the device." ;;
  esac
  cat <<TXT
Fake Tower
==========
Two voices claim to be the tower. One is lying.
4 to 8 players: 2 controllers (one is an impostor) and 2 to 6 pilots.

Run
  $run
${extra:+$extra
}
Host a game (one player)
  1. Start the game, enter your name, choose "Host Game".
  2. Tell the others your IP address. Same LAN: your local IP (for example 192.168.1.20).
     Over the internet: your public IP, with UDP port 27270 forwarded to your PC.
  3. Allow the game through the firewall when asked (UDP port 27270).
  4. When everyone has joined (minimum 4 players), press Start in the lobby.
${host:+$host
}
Join a game
  Choose "Join Game", type the host's IP address (port 27270 is the default), press Join.

Practice alone
  Choose "Solo Practice" in the main menu.

Voice: hold Space to talk on the radio. Allow microphone access if asked.
Controls: see the in-game How to Play screen, or HOW_TO_PLAY.md in this folder
(the full player manual: pilot and controller guides, the ILS 27 approach, spotting the impostor).
Default network port: 27270 (UDP).
TXT
}

# Put the iOS team id into a temporary copy of export_presets.cfg (restored on exit).
PRESETS="$GAME/export_presets.cfg"
PRESETS_BACKUP=""
restore_presets() {
  if [ -n "$PRESETS_BACKUP" ] && [ -f "$PRESETS_BACKUP" ]; then mv -f "$PRESETS_BACKUP" "$PRESETS"; fi
}
trap restore_presets EXIT

prepare() { # target -> sets preset, bin, extra, mode
  mode=--export-release
  case "$1" in
    windows) preset="Windows Desktop"; bin="FakeTower.exe"; extra=(); need_template windows_release_x86_64.exe ;;
    linux) preset="Linux"; bin="FakeTower.x86_64"; extra=("FakeTower.pck"); need_template linux_release.x86_64 ;;
    web) preset="Web"; bin="index.html"; extra=("index.js" "index.wasm" "index.pck"); need_template web_nothreads_release.zip ;;
    macos) preset="macOS"; bin="FakeTower.zip"; extra=(); need_template macos.zip ;;
    android)
      preset="Android"; bin="FakeTower.apk"; extra=()
      local java="${JAVA_HOME:+$JAVA_HOME/bin/}java"
      command -v "$java" >/dev/null 2>&1 || die "android: no JDK (set JAVA_HOME or put java on PATH)"
      local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
      [ -n "$sdk" ] && [ -d "$sdk/build-tools" ] || die "android: no Android SDK with build-tools (set ANDROID_HOME or ANDROID_SDK_ROOT)"
      export ANDROID_HOME="$sdk"
      if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
        [ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] || die "android: GODOT_ANDROID_KEYSTORE_RELEASE_PATH does not exist"
        [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ] && [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ] \
          || die "android: set GODOT_ANDROID_KEYSTORE_RELEASE_USER and GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"
        need_template android_release.apk
      elif [ -n "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}" ]; then
        [ -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ] || die "android: GODOT_ANDROID_KEYSTORE_DEBUG_PATH does not exist"
        [ -n "${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-}" ] && [ -n "${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-}" ] \
          || die "android: set GODOT_ANDROID_KEYSTORE_DEBUG_USER and GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD"
        need_template android_debug.apk
        mode=--export-debug
        echo "== android: no release keystore in the environment, exporting a debug-signed APK"
      else
        die "android: no keystore; set GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD} (or the _DEBUG_ ones)"
      fi ;;
    ios)
      preset="iOS"; bin="FakeTower.ipa"; extra=("FakeTower.xcodeproj")
      need_template ios.zip
      [ -n "${IOS_TEAM_ID:-}" ] || die "ios: set IOS_TEAM_ID (Apple developer team id); Godot will not write the Xcode project without one"
      [[ "$IOS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "ios: IOS_TEAM_ID must be 10 upper-case letters/digits"
      PRESETS_BACKUP="$(mktemp "$GAME/.export_presets.XXXXXX")"
      cp "$PRESETS" "$PRESETS_BACKUP"
      sed -i "s/^application\/app_store_team_id=\"\"/application\/app_store_team_id=\"$IOS_TEAM_ID\"/" "$PRESETS" ;;
  esac
}

for plat in "${TARGETS[@]}"; do
  prepare "$plat"
  dir="$OUT/fake-tower-$plat"
  rm -rf "$dir" "$OUT/fake-tower-$plat.zip"
  mkdir -p "$dir"
  echo "== exporting $preset -> $dir/$bin"
  "$GODOT" --headless --path "$GAME" "$mode" "$preset" "$dir/$bin" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$OUT/export-$plat.log"
  restore_presets
  PRESETS_BACKUP=""
  # iOS with export_project_only writes the Xcode project next to the (absent) .ipa.
  if [ "$plat" != ios ]; then [ -f "$dir/$bin" ] || die "export failed: $dir/$bin missing"; fi
  for f in "${extra[@]}"; do [ -e "$dir/$f" ] || die "export failed: $dir/$f missing"; done
  # Godot can exit 0 while logging an export error: fail on that too.
  if grep -qE 'ERROR:|SCRIPT ERROR' "$OUT/export-$plat.log"; then die "export log contains errors"; fi
  case "$plat" in
    linux) chmod +x "$dir/$bin" ;;
    macos) # ship the .app itself (unzip keeps the permissions and the ad-hoc signature)
      (cd "$dir" && unzip -q "$bin" && rm -f "$bin")
      [ -d "$dir/Fake Tower.app/Contents/MacOS" ] || die "macos: no .app in the exported zip" ;;
  esac
  readme "$plat" >"$dir/README.txt"
  [ -f "$GAME/HOW_TO_PLAY.md" ] || die "missing $GAME/HOW_TO_PLAY.md"
  cp "$GAME/HOW_TO_PLAY.md" "$dir/HOW_TO_PLAY.md"
  if [ $ZIP -eq 1 ]; then (cd "$OUT" && zip -qry -9 "fake-tower-$plat.zip" "fake-tower-$plat"); fi
  echo "== $plat: $(du -sh "$dir" | cut -f1)$([ $ZIP -eq 1 ] && echo ", zip $(du -h "$OUT/fake-tower-$plat.zip" | cut -f1)")"
done
