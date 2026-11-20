# Shared helpers for scripts/*.sh. Source, don't execute.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
if [[ ! -x "$GODOT" ]]; then
	echo "Godot not found at $GODOT; run tools/setup_toolchain.sh (or set GODOT)" >&2
	exit 2
fi
# Lines in Godot output that mean a run must fail even if the exit code is 0.
ERROR_PATTERN='SCRIPT ERROR|^ERROR:|Parse Error|Failed to load script|Invalid call|\[ERROR\]'
# Godot's leak report when a headless run quits (objects GUT still holds at exit). It says nothing
# about a test, and it made every CI run red, so it doesn't count as an error.
EXIT_NOISE='^ERROR: [0-9]+ resources still in use at exit|^ERROR: Pages in use exist at exit in PagedAllocator|^ERROR: [0-9]+ RID allocations of type .* were leaked at exit'
# Prints the log's real error lines; succeeds when there is at least one.
real_errors() { # log
	grep -E "$ERROR_PATTERN" "$1" | grep -vE "$EXIT_NOISE" | grep -q . || return 1
	grep -E "$ERROR_PATTERN" -A2 "$1" | grep -vE "$EXIT_NOISE" | head -40
}
