#!/bin/bash
# Build the zapret2 OpenWrt apk packages with the official OpenWrt SDK
# and lay them out as an apk repository (optionally with a signed index).
#
#   ./build.sh                             all packages for the default target
#   PACKAGES=zapret2 ./build.sh            only the dynamic package
#   TARGET=x86/64 ./build.sh               another router target
#   SIGN_KEY=~/key.pem ./build.sh          sign packages.adb (EC prime256v1 private key, see index.sh)
#
# Result: $OUTDIR/<openwrt branch>/<package arch>/{*.apk,packages.adb,SHA256SUMS}
# e.g.    out/25.12/aarch64_cortex-a53/
set -euo pipefail

# ---- parameters ----
OPENWRT_VER=${OPENWRT_VER:-25.12.5}
TARGET=${TARGET:-mediatek/filogic}                     # on the router: ubus call system board | grep target
PACKAGES=${PACKAGES:-zapret2 zapret2-static zapret2-presets}
ZAPRET2_TAG=${ZAPRET2_TAG:-}                           # e.g. v1.0.5.2; empty = version pinned in packages/zapret2/Makefile
REPO=$(cd "$(dirname "$0")" && pwd)
WORKDIR=${WORKDIR:-$REPO/work}
OUTDIR=${OUTDIR:-$REPO/out}
SIGN_KEY=${SIGN_KEY:-}                                 # passed on to index.sh
INSTALL_HOST_DEPS=${INSTALL_HOST_DEPS:-1}              # 0: skip apt-get
JOBS=${JOBS:-$(nproc)}

SDK_BASE=https://downloads.openwrt.org/releases/$OPENWRT_VER/targets/$TARGET
BRANCH=${OPENWRT_VER%.*}                               # 25.12.5 -> 25.12
SDK=$WORKDIR/sdk-$OPENWRT_VER-${TARGET//\//-}
DLDIR=${DLDIR:-$WORKDIR/dl}                            # source tarballs, shared by all SDKs (CI caches it)
FEED=$WORKDIR/feed

log() { printf '\n== %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

for p in $PACKAGES; do
	case $p in zapret2|zapret2-static|zapret2-presets) ;; *) die "unknown package '$p'";; esac
done
[ -z "$SIGN_KEY" ] || [ -r "$SIGN_KEY" ] || die "SIGN_KEY=$SIGN_KEY is not readable"

if [ "$INSTALL_HOST_DEPS" = 1 ] && command -v apt-get >/dev/null; then
	log "host packages"
	sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
		build-essential clang flex bison g++ gawk gettext git libncurses-dev libssl-dev \
		python3 python3-setuptools rsync swig unzip zlib1g-dev file wget curl zstd xz-utils >/dev/null
fi

mkdir -p "$WORKDIR"
need_gb=3; [ -d "$SDK/staging_dir" ] && need_gb=1
avail_gb=$(df -BG --output=avail "$WORKDIR" | tail -1 | tr -dc 0-9)
[ "$avail_gb" -ge "$need_gb" ] || die "need >= $need_gb GB free in $WORKDIR, have $avail_gb GB"

log "SDK $OPENWRT_VER $TARGET"
SDK_TAR=$(curl -fsS "$SDK_BASE/" | grep -oE 'openwrt-sdk-[^"]+\.tar\.zst' | head -1) || true
[ -n "$SDK_TAR" ] || die "SDK not found at $SDK_BASE"
cd "$WORKDIR"
[ -f "$SDK_TAR" ] || wget -q -c "$SDK_BASE/$SDK_TAR"
curl -fsS "$SDK_BASE/sha256sums" | grep " \*$SDK_TAR\$" | sed 's/ \*/  /' | sha256sum -c - >/dev/null \
	|| die "sha256 mismatch for $SDK_TAR"
if [ ! -d "$SDK" ]; then
	mkdir "$SDK.tmp"
	tar --zstd -xf "$SDK_TAR" -C "$SDK.tmp" --strip-components=1
	mv "$SDK.tmp" "$SDK"
fi
mkdir -p "$DLDIR"
[ -L "$SDK/dl" ] || { rm -rf "$SDK/dl"; ln -s "$DLDIR" "$SDK/dl"; }
cd "$SDK"

log "feeds"
# our packages are a feed of their own; a copy, so a ZAPRET2_TAG override never touches the repo
rm -rf "$FEED" && cp -r "$REPO/packages" "$FEED"
if [ -n "$ZAPRET2_TAG" ]; then
	# annotated tag: the "^{}" line holds the commit; lightweight tag: the plain line
	REFS=$(git ls-remote https://github.com/bol-van/zapret2.git "refs/tags/$ZAPRET2_TAG*")
	ZSHA=$(echo "$REFS" | grep -F "refs/tags/$ZAPRET2_TAG^{}" | cut -f1 || true)
	[ -n "$ZSHA" ] || ZSHA=$(echo "$REFS" | grep -E "refs/tags/$ZAPRET2_TAG\$" | cut -f1 || true)
	[ -n "$ZSHA" ] || die "tag $ZAPRET2_TAG not found in bol-van/zapret2"
	sed -i -e "s/^PKG_VERSION:=.*/PKG_VERSION:=${ZAPRET2_TAG#v}/" \
		-e "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$ZSHA/" "$FEED/zapret2/Makefile"
fi
grep -E '^PKG_(VERSION|SOURCE_VERSION):=' "$FEED/zapret2/Makefile"
# only base + packages from the SDK defaults, plus ours
{ grep -E '^src-git (--root=[^ ]+ )?(base|packages) ' feeds.conf.default; echo "src-link zapret2 $FEED"; } > feeds.conf
./scripts/feeds update -a >"$WORKDIR/feeds.log" 2>&1 || { tail -20 "$WORKDIR/feeds.log"; die "feeds update failed"; }
# installs our packages and, recursively, only the feed packages they depend on
./scripts/feeds install -p zapret2 -a >>"$WORKDIR/feeds.log" 2>&1 || { tail -20 "$WORKDIR/feeds.log"; die "feeds install failed"; }

# .config: nothing but the requested package; the SDK defaults to building everything (CONFIG_ALL*)
select_pkgs() {
	local on=" $* " p
	make defconfig >/dev/null
	sed -i -E '/^(# )?CONFIG_(ALL|ALL_NONSHARED|ALL_KMODS|PACKAGE_zapret2[a-z-]*)[= ]/d' .config
	printf '# CONFIG_%s is not set\n' ALL ALL_NONSHARED ALL_KMODS >> .config
	for p in zapret2 zapret2-static zapret2-presets; do
		case $on in
			*" $p "*) echo "CONFIG_PACKAGE_$p=m" ;;
			*) echo "# CONFIG_PACKAGE_$p is not set" ;;
		esac >> .config
	done
	make defconfig >/dev/null
	for p in "$@"; do grep -q "^CONFIG_PACKAGE_$p=m" .config || die "could not select $p in .config"; done
}

ARCH=
rm -rf bin/packages/*/zapret2
: >"$WORKDIR/build.log"
# zapret2 and zapret2-static conflict, so each variant is configured and built on its own
for PKG in $PACKAGES; do
	case $PKG in zapret2-presets) SRC=zapret2-presets ;; *) SRC=zapret2 ;; esac
	log "build $PKG (log: $WORKDIR/build.log)"
	select_pkgs "$PKG"
	ARCH=$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\(.*\)"$/\1/p' .config)
	make package/$SRC/download V=s >>"$WORKDIR/build.log" 2>&1 || { tail -30 "$WORKDIR/build.log"; die "download of $SRC failed"; }
	if ! make -j"$JOBS" package/$SRC/compile V=s >>"$WORKDIR/build.log" 2>&1; then
		grep -E 'failed to build|No space left|error:|Error [0-9]' "$WORKDIR/build.log" | tail -20
		die "build of $PKG failed, see $WORKDIR/build.log"
	fi
done

log "result"
DEST=$OUTDIR/$BRANCH/$ARCH
rm -rf "$DEST" && mkdir -p "$DEST"
for PKG in $PACKAGES; do
	APK=$(ls bin/packages/"$ARCH"/zapret2/"$PKG"-[0-9]*.apk 2>/dev/null | head -1 || true)
	[ -n "$APK" ] || die "no apk produced for $PKG"
	cp "$APK" "$DEST/"
done
APKTOOL=$SDK/staging_dir/host/bin/apk

# sanity check of what got packaged (build_dir is gone after packaging, so look inside the apks)
X=$(mktemp -d)
for f in "$DEST"/zapret2-[0-9]*.apk "$DEST"/zapret2-static-[0-9]*.apk; do
	[ -f "$f" ] || continue
	rm -rf "${X:?}"/* && "$APKTOOL" extract --allow-untrusted --destination "$X" "$f" >/dev/null
	info=$(file "$X"/opt/zapret2/nfq2/nfqws2)
	echo "$(basename "$f"): ${info#*: }" | cut -c1-160
	case $(basename "$f") in
		zapret2-static-*) echo "$info" | grep -q 'statically linked' || die "nfqws2 in $f is not static" ;;
		*) echo "$info" | grep -q 'dynamically linked' || die "nfqws2 in $f is not dynamic" ;;
	esac
done
rm -rf "$X"

log "index $DEST/packages.adb"
APKTOOL=$APKTOOL "$REPO/index.sh" "$DEST"
echo "BUILD DONE: $DEST"
