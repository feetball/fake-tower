#!/bin/bash
# Export release builds and package them with a README.txt and HOW_TO_PLAY.md.
# Usage: game/tools/export_build.sh <windows|linux|all> [--zip] [--out DIR]
#   env GODOT  godot binary (default: godot on PATH, else /home/user/tools/godot/godot)
#   Needs the 4.5.1 export templates in ~/.local/share/godot/export_templates/4.5.1.stable/
#   (windows_release_x86_64.exe, linux_release.x86_64, version.txt) and the import cache.
# Result: DIR/fake-tower-windows/{FakeTower.exe,README.txt} and
#         DIR/fake-tower-linux/{FakeTower.x86_64,FakeTower.pck,README.txt}
#         (each folder also gets HOW_TO_PLAY.md, copied from game/HOW_TO_PLAY.md)
#         (+ DIR/fake-tower-<platform>.zip with --zip). Default DIR: <repo>/build/dist.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$HERE/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/user/tools/godot/godot)}"
OUT="$GAME/../build/dist"
ZIP=0
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --zip) ZIP=1 ;;
    --out) OUT="$2"; shift ;;
    windows | linux) TARGETS+=("$1") ;;
    all) TARGETS=(windows linux) ;;
    *) echo "usage: $0 <windows|linux|all> [--zip] [--out DIR]" >&2; exit 2 ;;
  esac
  shift
done
[ ${#TARGETS[@]} -gt 0 ] || { echo "usage: $0 <windows|linux|all> [--zip] [--out DIR]" >&2; exit 2; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

readme() { # platform
  local run
  if [ "$1" = windows ]; then run="Double-click FakeTower.exe."; else
    run="Keep FakeTower.x86_64 and FakeTower.pck in the same folder, then: chmod +x FakeTower.x86_64 && ./FakeTower.x86_64"; fi
  cat <<TXT
Fake Tower
==========
Two voices claim to be the tower. One is lying.
4 to 8 players: 2 controllers (one is an impostor) and 2 to 6 pilots.

Run
  $run
$([ "$1" = windows ] && printf '  Windows SmartScreen may warn about an unsigned app: "More info" > "Run anyway".\n')
Host a game (one player)
  1. Start the game, enter your name, choose "Host Game".
  2. Tell the others your IP address. Same LAN: your local IP (for example 192.168.1.20).
     Over the internet: your public IP, with UDP port 27270 forwarded to your PC.
  3. Allow the game through the firewall when asked (UDP port 27270).
  4. When everyone has joined (minimum 4 players), press Start in the lobby.

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

for plat in "${TARGETS[@]}"; do
  case "$plat" in
    windows) preset="Windows Desktop"; bin="FakeTower.exe"; extra=() ;;
    linux) preset="Linux"; bin="FakeTower.x86_64"; extra=("FakeTower.pck") ;;
  esac
  dir="$OUT/fake-tower-$plat"
  rm -rf "$dir" "$OUT/fake-tower-$plat.zip"
  mkdir -p "$dir"
  echo "== exporting $preset -> $dir/$bin"
  "$GODOT" --headless --path "$GAME" --export-release "$preset" "$dir/$bin" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$OUT/export-$plat.log"
  [ -f "$dir/$bin" ] || { echo "export failed: $dir/$bin missing" >&2; exit 1; }
  for f in "${extra[@]}"; do [ -f "$dir/$f" ] || { echo "export failed: $dir/$f missing" >&2; exit 1; }; done
  # Godot can exit 0 while logging an export error: fail on that too.
  if grep -qE 'ERROR:|SCRIPT ERROR' "$OUT/export-$plat.log"; then echo "export log contains errors" >&2; exit 1; fi
  [ "$plat" = linux ] && chmod +x "$dir/$bin"
  readme "$plat" >"$dir/README.txt"
  [ -f "$GAME/HOW_TO_PLAY.md" ] || { echo "missing $GAME/HOW_TO_PLAY.md" >&2; exit 1; }
  cp "$GAME/HOW_TO_PLAY.md" "$dir/HOW_TO_PLAY.md"
  if [ $ZIP -eq 1 ]; then (cd "$OUT" && zip -qr -9 "fake-tower-$plat.zip" "fake-tower-$plat"); fi
  echo "== $plat: $(du -sh "$dir" | cut -f1)$([ $ZIP -eq 1 ] && echo ", zip $(du -h "$OUT/fake-tower-$plat.zip" | cut -f1)")"
done
