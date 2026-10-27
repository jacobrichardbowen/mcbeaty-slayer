#!/usr/bin/env bash
# Exports double-clickable builds into build/, named with the version in
# project.godot (config/version). With no arguments it builds Windows only;
# name presets to build others, e.g. `tools/build.sh Windows macOS Linux`.
#   TowerOfPower_v005.exe        Windows, single file (game packed inside)
#   TowerOfPower_v005-Mac.zip    macOS app (universal, ad-hoc signed)
#   TowerOfPower_v005.x86_64     Linux, single file
# Needs Godot 4.3 on PATH (or GODOT=/path/to/godot) with the 4.3 export
# templates installed (Editor > Manage Export Templates).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build
"$GODOT" --headless --path . --import
version=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
presets=("$@")
[ ${#presets[@]} -eq 0 ] && presets=(Windows)
for preset in "${presets[@]}"; do
	out=$(sed -n "/^name=\"$preset\"/,/^export_path=/p" export_presets.cfg | sed -n 's/^export_path="\(.*\)"/\1/p')
	out=${out/TowerOfPower/TowerOfPower_v$version}
	echo "== $preset -> $out"
	"$GODOT" --headless --path . --export-release "$preset" "$out"
done
ls -lh build
