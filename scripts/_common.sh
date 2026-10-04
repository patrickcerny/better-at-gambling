# Shared helpers for scripts/*.sh. Source, don't execute.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
if [[ ! -x "$GODOT" ]]; then
	echo "Godot not found at $GODOT; run tools/setup_toolchain.sh (or set GODOT)" >&2
	exit 2
fi
# Lines in Godot output that mean a run must fail even if the exit code is 0.
ERROR_PATTERN='SCRIPT ERROR|^ERROR:|Parse Error|Failed to load script|Invalid call|\[ERROR\]'
