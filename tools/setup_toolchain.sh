#!/usr/bin/env bash
# Downloads and verifies the pinned toolchain: Godot (headless-capable Linux binary),
# matching export templates, and the GUT test add-on. Idempotent; safe to re-run.
# Usage: tools/setup_toolchain.sh [--no-templates]
set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_TAG="${GODOT_VERSION}-stable"
GODOT_ZIP="Godot_v${GODOT_TAG}_linux.x86_64.zip"
GODOT_ZIP_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
TEMPLATES_TPZ="Godot_v${GODOT_TAG}_export_templates.tpz"
TEMPLATES_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
GUT_TAG="v9.7.1"
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/tools"
CACHE="$TOOLS/.cache"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable"
WANT_TEMPLATES=1
[[ "${1:-}" == "--no-templates" ]] && WANT_TEMPLATES=0

mkdir -p "$CACHE" "$TOOLS/godot"

fetch_verified() { # url dest sha512
	local url="$1" dest="$2" sum="$3"
	if [[ -f "$dest" ]] && echo "$sum  $dest" | sha512sum -c --status; then
		return 0
	fi
	echo "[setup] downloading $(basename "$dest")"
	curl -fsSL --retry 4 --retry-delay 2 -o "$dest.part" "$url"
	mv "$dest.part" "$dest"
	echo "$sum  $dest" | sha512sum -c --status || { echo "[setup] checksum mismatch for $dest" >&2; rm -f "$dest"; exit 1; }
}

# 1. Godot editor/headless binary -> tools/godot/godot
if ! "$TOOLS/godot/godot" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}.stable"; then
	fetch_verified "$BASE_URL/$GODOT_ZIP" "$CACHE/$GODOT_ZIP" "$GODOT_ZIP_SHA512"
	unzip -oq "$CACHE/$GODOT_ZIP" -d "$CACHE"
	mv -f "$CACHE/Godot_v${GODOT_TAG}_linux.x86_64" "$TOOLS/godot/godot"
	chmod +x "$TOOLS/godot/godot"
fi
echo "[setup] godot $("$TOOLS/godot/godot" --headless --version)"

# 2. Export templates (large, ~1.3 GB download)
if [[ $WANT_TEMPLATES -eq 1 && ! -f "$TEMPLATE_DIR/linux_release.x86_64" ]]; then
	fetch_verified "$BASE_URL/$TEMPLATES_TPZ" "$CACHE/$TEMPLATES_TPZ" "$TEMPLATES_SHA512"
	rm -rf "$CACHE/tpz" && mkdir -p "$CACHE/tpz" "$TEMPLATE_DIR"
	unzip -oq "$CACHE/$TEMPLATES_TPZ" -d "$CACHE/tpz"
	cp -f "$CACHE/tpz/templates/"* "$TEMPLATE_DIR/"
	rm -rf "$CACHE/tpz" "$CACHE/$TEMPLATES_TPZ"
fi
[[ $WANT_TEMPLATES -eq 1 ]] && echo "[setup] export templates in $TEMPLATE_DIR"

# 3. GUT (vendored in addons/gut; only fetched if missing)
if [[ ! -f "$ROOT/addons/gut/plugin.cfg" ]]; then
	echo "[setup] fetching GUT $GUT_TAG"
	rm -rf "$CACHE/gut"
	git clone -q --depth 1 --branch "$GUT_TAG" https://github.com/bitwes/Gut.git "$CACHE/gut"
	mkdir -p "$ROOT/addons"
	cp -r "$CACHE/gut/addons/gut" "$ROOT/addons/gut"
fi
echo "[setup] GUT $(grep '^version' "$ROOT/addons/gut/plugin.cfg")"

# 4. First import so class_name caches exist
"$TOOLS/godot/godot" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
echo "[setup] done"
