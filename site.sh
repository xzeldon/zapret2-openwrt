#!/bin/bash
# Turn a directory of built repositories (<branch>/<arch>/...) into the GitHub Pages site:
# adds the public key and an index.html with the setup commands.
#   ./site.sh site https://xzeldon.github.io/zapret2-openwrt
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
SITE=${1:?usage: $0 <site dir> <base url>}
URL=${2:?usage: $0 <site dir> <base url>}
URL=${URL%/}

cp "$REPO/keys/zapret2-openwrt.pem" "$SITE/"
touch "$SITE/.nojekyll"

rows=
for d in "$SITE"/*/*/; do
	[ -f "$d/packages.adb" ] || continue
	branch=$(basename "$(dirname "$d")"); arch=$(basename "$d")
	pkgs=$(cd "$d" && ls ./*.apk | sed 's|^\./||' | tr '\n' ' ')
	rows="$rows<tr><td>$branch</td><td>$arch</td><td><a href=\"$branch/$arch/\">$pkgs</a></td></tr>"
	# plain listing per directory, Pages has no autoindex
	{
		echo "<!doctype html><meta charset=utf-8><title>$branch/$arch</title><pre>"
		(cd "$d" && for f in packages.adb SHA256SUMS ./*.apk; do f=${f#./}; echo "<a href=\"$f\">$f</a>"; done)
		echo "</pre>"
	} > "$d/index.html"
done
[ -n "$rows" ] || { echo "no repositories in $SITE" >&2; exit 1; }

cat > "$SITE/index.html" <<EOF
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>zapret2 for OpenWrt</title>
<style>
body{font:16px/1.5 system-ui,sans-serif;max-width:52rem;margin:2rem auto;padding:0 1rem;color:#222;background:#fff}
pre{background:#f4f4f4;padding:1rem;overflow-x:auto}
table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.3rem .6rem;text-align:left}
@media (prefers-color-scheme:dark){body{color:#ddd;background:#161616}pre{background:#262626}td,th{border-color:#444}a{color:#8ab4f8}}
</style>
<h1>zapret2 for OpenWrt</h1>
<p>apk repository (OpenWrt 25.12+) with <a href="https://github.com/bol-van/zapret2">bol-van/zapret2</a>
built from upstream sources. Source and docs: <a href="https://github.com/${GITHUB_REPOSITORY:-xzeldon/zapret2-openwrt}">GitHub</a>.</p>
<h2>Add the repository on the router</h2>
<pre>wget -O /etc/apk/keys/zapret2-openwrt.pem $URL/zapret2-openwrt.pem
. /etc/openwrt_release
FEED="$URL/\${DISTRIB_RELEASE%.*}/\$(cat /etc/apk/arch)/packages.adb"
grep -qxF "\$FEED" /etc/apk/repositories.d/customfeeds.list || echo "\$FEED" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add zapret2            # or zapret2-static; optional: zapret2-presets</pre>
<h2>Available</h2>
<table><tr><th>OpenWrt</th><th>arch</th><th>packages</th></tr>$rows</table>
</html>
EOF
ls -R "$SITE" | head -40
