# zapret2-openwrt

OpenWrt apk packages of [bol-van/zapret2](https://github.com/bol-van/zapret2), built from
the upstream sources with the official OpenWrt SDK, and a signed apk repository on GitHub
Pages so a router installs them with `apk add`.

- **Upstream as is.** The package installs the same tree `install_easy.sh` creates on
  OpenWrt (`/opt/zapret2`, init script and iface hotplug hook as symlinks into it) and the
  upstream `config.default`. It does nothing until you configure it.
- **Two builds of the same package**: `zapret2` (nfqws2 linked against `luajit2`,
  `libnetfilter-queue` etc. from the OpenWrt feeds) and `zapret2-static` (fully static
  binaries, LuaJIT built in). Install one of them.
- **Optional presets**: `zapret2-presets` ships ready-made, ISP-specific configurations
  and a `zapret2-preset` tool. Nothing is applied unless you run it.
- Only OpenWrt 25.12+ (apk). Dependencies come from the official OpenWrt repositories.

[Русская документация](docs/ru.md)

## Install on the router

```sh
wget -O /etc/apk/keys/zapret2-openwrt.pem https://xzeldon.github.io/zapret2-openwrt/zapret2-openwrt.pem
. /etc/openwrt_release
FEED="https://xzeldon.github.io/zapret2-openwrt/${DISTRIB_RELEASE%.*}/$(cat /etc/apk/arch)/packages.adb"
grep -qxF "$FEED" /etc/apk/repositories.d/customfeeds.list || echo "$FEED" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add zapret2        # or: apk add zapret2-static
```

The repository path is `<OpenWrt release branch>/<package arch>`. Use `/etc/apk/arch`, not
`apk --print-arch`: the latter prints `aarch64` instead of `aarch64_cortex-a53`.
See the [repository page](https://xzeldon.github.io/zapret2-openwrt/) for the
releases and archs currently built.

Then configure `/opt/zapret2/config` as described in the
[upstream docs](https://github.com/bol-van/zapret2/tree/master/docs), and run
`/etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart`.

Updating: `apk update && apk upgrade zapret2`. `/opt/zapret2/config` and the user lists in
`/opt/zapret2/ipset/` are conffiles and are kept. Do not run a plain `apk upgrade` of the
whole system on OpenWrt.

Switching between `zapret2` and `zapret2-static`: they conflict, so remove one first
(`apk del zapret2 && apk add zapret2-static`); back up `/opt/zapret2/config` and
`/opt/zapret2/ipset/*.txt` before that.

## Presets

```sh
apk add zapret2-presets
zapret2-preset list
zapret2-preset show vn-fpt-steam
zapret2-preset apply vn-fpt-steam       # backs up config and hostlist, then restarts zapret2
```

| Preset | What |
|---|---|
| [`vn-fpt-steam`](packages/zapret2-presets/files/presets/vn-fpt-steam/README.md) | Steam in Vietnam on FPT Telecom |

A preset is a directory in
[`packages/zapret2-presets/files/presets/`](packages/zapret2-presets/files/presets/) with
`README.md` (first line is the title; say which ISP, where and when it was verified),
`preset.conf` (`KEY=VALUE` lines and an optional multi-line `NFQWS2_OPT="…"` block) and an
optional `hosts.txt`. DPI differs between ISPs, so a preset is only known to work where
its README says. PRs with new verified presets are welcome; bump `PKG_VERSION` in
`packages/zapret2-presets/Makefile`.

## Build locally

Needs Linux x86_64 (tested on Ubuntu 26.04) with about 3 GB free, run as a normal user
with sudo (only for `apt-get`).

```sh
git clone https://github.com/xzeldon/zapret2-openwrt && cd zapret2-openwrt
./build.sh                                   # all packages, default target
```

| Variable | Default | |
|---|---|---|
| `OPENWRT_VER` | `25.12.5` | OpenWrt release of the SDK |
| `TARGET` | `mediatek/filogic` | router target, see `ubus call system board` on the router |
| `PACKAGES` | `zapret2 zapret2-static zapret2-presets` | what to build |
| `ZAPRET2_TAG` | (pinned in the Makefile) | build another upstream tag, e.g. `v1.0.5.2` |
| `SIGN_KEY` | — | EC private key; without it the index is unsigned |
| `WORKDIR`, `OUTDIR`, `DLDIR` | `work/`, `out/`, `work/dl` | |
| `INSTALL_HOST_DEPS` | `1` | `0` skips `apt-get` |

The result is a ready repository directory, e.g. `out/25.12/aarch64_cortex-a53/` with the
apks, `packages.adb` and `SHA256SUMS`. To try an apk without a repository:
`apk add --allow-untrusted ./zapret2-*.apk` on the router.

What `build.sh` does:

1. Downloads the SDK for `OPENWRT_VER`/`TARGET`, checks it against the release
   `sha256sums`, unpacks it to `work/sdk-<ver>-<target>` (reused on later runs).
2. Uses only the `base` and `packages` feeds plus `packages/` of this repo as feed
   `zapret2`, and installs from them only the packages zapret2 needs.
3. Turns off the SDK default of building everything (`CONFIG_ALL*`), selects one package
   and builds it; the two variants conflict, so they are built one after another.
4. Checks that `nfqws2` in each apk is dynamic or static as expected, then runs
   `index.sh` to write `packages.adb` (signed when `SIGN_KEY` is set) and `SHA256SUMS`.

## CI and the repository

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs `build.sh` for every
entry of its target matrix on each push, PR and manual run (a manual run can take another
upstream tag).

- On `main`, the index is signed with the `APK_SIGN_KEY` secret in a separate step, so
  the key is never present while third-party sources are compiled. Then the
  whole site is rebuilt and deployed to GitHub Pages with `site.sh`. PRs only build.
- A `v*` tag also creates a GitHub release with the apks (file names prefixed with the arch).

Adding a router target means adding one `openwrt`/`target` entry to the matrix.

### Signing key

apk on OpenWrt 25.12 trusts a repository by the signature of its `packages.adb`
(EC prime256v1). The public key is [`keys/zapret2-openwrt.pem`](keys/zapret2-openwrt.pem);
the private key is the `APK_SIGN_KEY` secret. To create a new pair:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out zapret2-openwrt-apk-sign.pem
openssl ec -in zapret2-openwrt-apk-sign.pem -pubout -out keys/zapret2-openwrt.pem
gh secret set APK_SIGN_KEY < zapret2-openwrt-apk-sign.pem
```

Routers that already have the old public key must download the new one.

## Layout

```
packages/zapret2/Makefile          zapret2 and zapret2-static
packages/zapret2-presets/          presets and the zapret2-preset tool
build.sh                           SDK -> packages -> repository directory
index.sh                           packages.adb (+ signature) and SHA256SUMS
site.sh                            GitHub Pages site from the built repositories
keys/zapret2-openwrt.pem           public key of the repository
```

## License

The packaging in this repository is MIT. zapret2 itself is MIT, by bol-van.
