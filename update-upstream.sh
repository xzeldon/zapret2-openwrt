#!/bin/bash
# Point packages/zapret2/Makefile at the latest bol-van/zapret2 release if it is newer
# than the packaged one. Prints the new tag on stdout when it changed the Makefile,
# nothing otherwise. Needs gh (authenticated) or GH_TOKEN.
#   ./update-upstream.sh            latest release
#   ./update-upstream.sh v1.0.5.2   a given tag
set -euo pipefail

MK=$(cd "$(dirname "$0")" && pwd)/packages/zapret2/Makefile
UP=repos/bol-van/zapret2

tag=${1:-$(gh api "$UP/releases/latest" -q .tag_name)}
ver=${tag#v}
cur=$(sed -n 's/^PKG_VERSION:=//p' "$MK")
newest=$(printf '%s\n%s\n' "$cur" "$ver" | sort -V | tail -1)
if [ "$ver" = "$cur" ] || [ "$newest" != "$ver" ]; then
	echo "zapret2 $cur is up to date (upstream: $tag)" >&2
	exit 0
fi

# a lightweight tag points at the commit, an annotated one at a tag object
read -r type sha < <(gh api "$UP/git/ref/tags/$tag" -q '.object | "\(.type) \(.sha)"')
[ "$type" = tag ] && sha=$(gh api "$UP/git/tags/$sha" -q .object.sha)
[[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "cannot resolve $tag to a commit" >&2; exit 1; }

sed -i -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$ver/" \
	-e "s/^PKG_RELEASE:=.*/PKG_RELEASE:=1/" \
	-e "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$sha/" "$MK"
echo "zapret2 $cur -> $ver ($sha)" >&2
echo "$tag"
