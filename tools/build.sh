#!/usr/bin/env bash
# Exports double-clickable builds into build/. With no arguments it builds
# Windows only; name presets to build others, e.g. `tools/build.sh Windows macOS Linux`.
#   McbeatySlayer.exe        Windows, single file (game packed inside)
#   McbeatySlayer-Mac.zip    macOS app (universal, ad-hoc signed)
#   McbeatySlayer.x86_64     Linux, single file
# Needs Godot 4.3 on PATH (or GODOT=/path/to/godot) with the 4.3 export
# templates installed (Editor > Manage Export Templates).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build
"$GODOT" --headless --path . --import
presets=("$@")
[ ${#presets[@]} -eq 0 ] && presets=(Windows)
for preset in "${presets[@]}"; do
	out=$(sed -n "/^name=\"$preset\"/,/^export_path=/p" export_presets.cfg | sed -n 's/^export_path="\(.*\)"/\1/p')
	echo "== $preset -> $out"
	"$GODOT" --headless --path . --export-release "$preset" "$out"
done
ls -lh build
