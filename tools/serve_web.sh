#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$project_dir/docs/index.html" ]]; then
	echo "No Web build found. Run tools/export_web.sh first." >&2
	exit 1
fi

echo "Serving Stick! at http://127.0.0.1:8000"
echo "Press Ctrl+C to stop."
python3 -m http.server 8000 --bind 127.0.0.1 --directory "$project_dir/docs"
