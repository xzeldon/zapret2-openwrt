#!/bin/bash
# Write packages.adb and SHA256SUMS for a directory of apks, signed when SIGN_KEY is set.
# Kept apart from build.sh so CI hands the signing key only to this step, not to the build
# of third-party sources.
#
#   ./index.sh out/25.12/aarch64_cortex-a53
#   SIGN_KEY=~/key.pem ./index.sh out/25.12/aarch64_cortex-a53
#
# APKTOOL: host apk binary; defaults to the one in an SDK under ./work (as left by build.sh).
# The package arch for the read-back check is the directory name.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
DIR=$(cd "${1:?usage: $0 <dir with apks>}" && pwd)
ARCH=$(basename "$DIR")
SIGN_KEY=${SIGN_KEY:-}
APKTOOL=${APKTOOL:-$(ls "$REPO"/work/sdk-*/staging_dir/host/bin/apk 2>/dev/null | head -1 || true)}

die() { echo "ERROR: $*" >&2; exit 1; }
[ -x "$APKTOOL" ] || die "no host apk binary; run build.sh first or set APKTOOL"
ls "$DIR"/*.apk >/dev/null 2>&1 || die "no apks in $DIR"
OPENSSL=$(dirname "$APKTOOL")/openssl; [ -x "$OPENSSL" ] || OPENSSL=openssl

cd "$DIR"
rm -f packages.adb
if [ -n "$SIGN_KEY" ]; then
	K=$(mktemp -d)
	trap 'rm -rf "$K"' EXIT
	"$OPENSSL" ec -in "$SIGN_KEY" -pubout -out "$K/zapret2-openwrt.pem" 2>/dev/null \
		|| die "SIGN_KEY is not an EC private key"
	cmp -s "$K/zapret2-openwrt.pem" "$REPO/keys/zapret2-openwrt.pem" \
		|| echo "WARNING: SIGN_KEY does not match keys/zapret2-openwrt.pem; routers using that key will reject this index"
	"$APKTOOL" mkndx --allow-untrusted --keys-dir "$K" --sign "$SIGN_KEY" --output packages.adb ./*.apk
	# read the index back the way a router does: public key only, no --allow-untrusted
	R=$K/root
	mkdir -p "$R/etc/apk" "$R/lib/apk/db"; echo "$ARCH" > "$R/etc/apk/arch"; touch "$R/etc/apk/world"
	"$APKTOOL" --root "$R" --keys-dir "$K" --repository "$DIR/packages.adb" \
		--no-cache --force-no-chroot update > "$K/check" 2>&1 || true
	cat "$K/check"
	if grep -q UNTRUSTED "$K/check" || ! grep -q '^OK: [1-9]' "$K/check"; then
		die "signed index does not verify"
	fi
else
	"$APKTOOL" mkndx --allow-untrusted --output packages.adb ./*.apk
	echo "NOTE: index is unsigned (no SIGN_KEY); a router needs --allow-untrusted to use it"
fi
sha256sum ./*.apk | sed 's| \./| |' > SHA256SUMS
ls -l
