#!/bin/bash
# Fail (exit 1) when a Godot log contains real script/load errors.
# Usage: tools/ci_check_log.sh <logfile>...      (or: ... | tools/ci_check_log.sh -)
# Env:   CI_LOG_ALLOW  extra ERE of benign lines to ignore (appended to the built-in allowlist)
#
# FAIL patterns (case-sensitive, after stripping ANSI colour codes):
#   SCRIPT ERROR            runtime GDScript errors (also covers "SCRIPT ERROR: Parse Error")
#   Parse Error             GDScript compile errors
#   Compile Error           same, other spelling
#   ERROR: Failed to load   scenes/resources/scripts that could not be loaded
#   Failed to instantiate   scenes that load but cannot be instantiated
#   ERROR: Cannot open resource / Cannot load  (missing resource)
#
# ALLOWLIST: lines that match a fail pattern but are known benign. Built from real
# local runs (a fresh --import and headless runs of every demo mode produce none of the
# fail patterns at all, so this list is deliberately short). It only covers the audio
# device fallback that Godot logs on machines without a sound card (CI runners, Xvfb):
#   - "ALSA lib ..." / "Unable to open ... audio" / "audio driver" fallbacks to Dummy
# Never add script errors here.
set -u
FAIL_RE='SCRIPT ERROR|Parse Error|Compile Error|ERROR: Failed to load|Failed to instantiate|ERROR: Cannot open resource|ERROR: Cannot load'
ALLOW_RE='ALSA lib|[Aa]udio driver|[Uu]nable to open audio|[Cc]annot open audio|PulseAudio|pulse(audio)? (server|context)'
[ -n "${CI_LOG_ALLOW:-}" ] && ALLOW_RE="$ALLOW_RE|$CI_LOG_ALLOW"

[ $# -ge 1 ] || { echo "usage: $0 <logfile>... | -" >&2; exit 2; }
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
for f in "$@"; do
  if [ "$f" = "-" ]; then cat; else
    [ -r "$f" ] || { echo "ci_check_log: cannot read $f" >&2; exit 2; }
    cat "$f"
  fi
done | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' >"$tmp"

hits="$(grep -nE "$FAIL_RE" "$tmp" | grep -vE "$ALLOW_RE" || true)"
if [ -n "$hits" ]; then
  echo "ci_check_log: FOUND ERRORS IN GODOT LOG" >&2
  printf '%s\n' "$hits" | sed 's/^/  /' >&2
  # show the two lines after each hit (GDScript errors put file:line there)
  grep -nE -A2 "$FAIL_RE" "$tmp" | grep -vE "$ALLOW_RE" | head -60 | sed 's/^/    | /' >&2
  exit 1
fi
echo "ci_check_log: OK ($(wc -l <"$tmp") log lines checked)"
