#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"

if [[ -z "$godot_bin" ]]; then
	if command -v godot >/dev/null 2>&1; then
		godot_bin="$(command -v godot)"
	elif command -v godot4 >/dev/null 2>&1; then
		godot_bin="$(command -v godot4)"
	elif [[ -x /home/wayne/Godot_v4.6.3-stable_linux.x86_64 ]]; then
		godot_bin=/home/wayne/Godot_v4.6.3-stable_linux.x86_64
	else
		echo "Godot was not found. Set GODOT_BIN to the Godot executable." >&2
		exit 1
	fi
fi

mkdir -p "$project_dir/build/web"
"$godot_bin" --headless --path "$project_dir" --export-release Web "$project_dir/build/web/index.html"

echo "Web build created at: $project_dir/build/web/index.html"
