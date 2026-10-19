#!/usr/bin/env bash
# Signs the exported macOS app and packs the release zip, plus a .dmg when a third path is given. Run
# by .github/workflows/release.yml; works locally too.
# Usage: tools/macos/package.sh <Godot export .zip> <output .zip> [<output .dmg>]
#
# The .dmg is an ISO 9660 image with Rock Ridge and Apple extensions written by genisoimage (the
# same recipe Bitcoin Core shipped its Mac builds with for years): macOS mounts it like any disk
# image, keeps the executable bits, and the signed .app inside is what Gatekeeper checks, so the
# image itself needs no signature.
#
# Godot's own rcodesign mode refuses apps with GDExtension libraries (GodotSteam), so the "macOS"
# preset only ad-hoc signs (built-in signer) and this script re-signs the whole .app with rcodesign
# (apple-codesign; binary from $RCODESIGN, default `rcodesign` on PATH):
# - All six secrets in the environment -> Developer ID signature with hardened runtime, secure
#   timestamp and tools/macos/entitlements.plist on the main executable, then notarization with the
#   App Store Connect API key and stapling of the ticket:
#     MACOS_CERT_P12       base64 of the "Developer ID Application" certificate + key (.p12)
#     MACOS_CERT_PASSWORD  password of that .p12
#     APPLE_API_KEY_P8     contents of AuthKey_<id>.p8 (or base64 of the file)
#     APPLE_API_KEY_ID     the key's ID; APPLE_API_ISSUER_ID: the issuer UUID
#     APPLE_TEAM_ID        team ID, checked against the certificate
# - Otherwise -> ad-hoc signature with the same entitlements (Apple Silicon runs no unsigned code;
#   Gatekeeper still asks the player to allow the app once).
# Writes signed=true|false to $GITHUB_OUTPUT when set. Secret material goes to a private temp dir
# that is deleted on exit, and nothing secret is printed.
set -euo pipefail

[[ $# -eq 2 || $# -eq 3 ]] || { echo "usage: $0 <export.zip> <out.zip> [<out.dmg>]" >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IN_ZIP="$(realpath "$1")"
OUT_ZIP="$(realpath -m "$2")"
OUT_DMG="${3:+$(realpath -m "$3")}"
RCODESIGN="${RCODESIGN:-rcodesign}"
APP_NAME="Better at Gambling.app"
ENTITLEMENTS="$ROOT/tools/macos/entitlements.plist"

TMP="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macos-package.XXXXXX")"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

unzip -q "$IN_ZIP" -d "$TMP/out"
APP="$TMP/out/$APP_NAME"
# The export must hold the game, GodotSteam with the Steam API, and the microphone prompt text.
for f in "Contents/MacOS/Better at Gambling" "Contents/Resources/Better at Gambling.pck" \
	"Contents/Frameworks/libgodotsteam.macos.template_release.universal.dylib" \
	"Contents/Frameworks/libsteam_api.dylib"; do
	[[ -s "$APP/$f" ]] || { echo "::error::$APP_NAME has no $f" >&2; exit 1; }
done
[[ -x "$APP/Contents/MacOS/Better at Gambling" ]] || { echo "::error::game binary is not executable" >&2; exit 1; }
grep -q "<key>NSMicrophoneUsageDescription</key>" "$APP/Contents/Info.plist" \
	|| { echo "::error::Info.plist has no NSMicrophoneUsageDescription" >&2; exit 1; }

missing=()
for name in MACOS_CERT_P12 MACOS_CERT_PASSWORD APPLE_API_KEY_P8 APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_TEAM_ID; do
	[[ -n "${!name:-}" ]] || missing+=("$name")
done

if [[ ${#missing[@]} -eq 0 ]]; then
	SEC="$TMP/secrets"
	mkdir -m 700 "$SEC"
	printf '%s' "$MACOS_CERT_P12" | base64 -d -i > "$SEC/cert.p12"
	# rcodesign only opens legacy-encrypted .p12 files, current Keychain exports use AES; openssl reads
	# both, so rcodesign gets the key and certificates as PEM.
	p12() {
		openssl pkcs12 -in "$SEC/cert.p12" -passin env:MACOS_CERT_PASSWORD "$@" 2>/dev/null \
			|| openssl pkcs12 -legacy -in "$SEC/cert.p12" -passin env:MACOS_CERT_PASSWORD "$@" 2>/dev/null
	}
	p12 -nodes -out "$SEC/signing.pem" || { echo "::error::MACOS_CERT_P12 / MACOS_CERT_PASSWORD: cannot open the .p12" >&2; exit 1; }
	p12 -clcerts -nokeys -out "$SEC/leaf.pem" || { echo "::error::no certificate in MACOS_CERT_P12" >&2; exit 1; }
	subject="$(openssl x509 -in "$SEC/leaf.pem" -noout -subject -nameopt RFC2253)"
	if [[ "$subject" != *"CN=Developer ID Application"* || "$subject" != *"OU=${APPLE_TEAM_ID}"* ]]; then
		echo "::error::MACOS_CERT_P12 is not a 'Developer ID Application' certificate of team APPLE_TEAM_ID" >&2
		exit 1
	fi
	if [[ "$APPLE_API_KEY_P8" == *"BEGIN PRIVATE KEY"* ]]; then
		printf '%s\n' "$APPLE_API_KEY_P8" > "$SEC/AuthKey.p8"
	else
		printf '%s' "$APPLE_API_KEY_P8" | base64 -d -i > "$SEC/AuthKey.p8"
	fi
	"$RCODESIGN" encode-app-store-connect-api-key -o "$SEC/api_key.json" \
		"$APPLE_API_ISSUER_ID" "$APPLE_API_KEY_ID" "$SEC/AuthKey.p8" > /dev/null
	echo "[macos] signing with Developer ID (hardened runtime, timestamp)"
	"$RCODESIGN" sign --pem-file "$SEC/signing.pem" --for-notarization \
		--entitlements-xml-file "$ENTITLEMENTS" "$APP"
	echo "[macos] notarizing (waits for Apple, then staples the ticket)"
	"$RCODESIGN" notary-submit --api-key-file "$SEC/api_key.json" --max-wait-seconds 1200 --staple "$APP"
	rm -rf "$SEC"
	signed=true
else
	if [[ ${#missing[@]} -lt 6 ]]; then
		echo "::warning::macOS signing secrets incomplete (missing: ${missing[*]}); falling back to ad-hoc signing"
	fi
	echo "::notice::macOS build is ad-hoc signed and NOT notarized (Developer ID secrets not set). Players must allow it once in System Settings > Privacy & Security."
	"$RCODESIGN" sign --entitlements-xml-file "$ENTITLEMENTS" "$APP"
	signed=false
fi

mkdir -p "$(dirname "$OUT_ZIP")"
rm -f "$OUT_ZIP"
(cd "$TMP/out" && zip -q -r -y -9 "$OUT_ZIP" "$APP_NAME")
echo "[macos] $(basename "$OUT_ZIP"): $(du -h "$OUT_ZIP" | cut -f1), signed=$signed"
if [[ -n "$OUT_DMG" ]]; then
	command -v genisoimage > /dev/null || { echo "::error::genisoimage is needed to write the .dmg" >&2; exit 1; }
	rm -f "$OUT_DMG"
	genisoimage -quiet -no-cache-inodes -D -l -probe -V "Better at Gambling" -no-pad -r -dir-mode 0755 \
		-apple -o "$OUT_DMG" "$TMP/out"
	# The image must list the app's binary as executable (Rock Ridge keeps the mode bits).
	isoinfo -R -l -i "$OUT_DMG" | grep -q -- "-r-xr-xr-x.* Better at Gambling *$" \
		|| { echo "::error::$(basename "$OUT_DMG") lost the executable bit on the game binary" >&2; exit 1; }
	echo "[macos] $(basename "$OUT_DMG"): $(du -h "$OUT_DMG" | cut -f1)"
fi
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "signed=$signed" >> "$GITHUB_OUTPUT"
exit 0
