# zapret2-openwrt

OpenWrt packages of [bol-van/zapret2](https://github.com/bol-van/zapret2), built from
upstream sources with the official OpenWrt SDK. GitHub Pages hosts them as a signed apk
repository, so a router installs zapret2 with `apk add`. OpenWrt 25.12 or newer only,
since older releases use opkg.

There are three packages.

| Package | What it is |
|---|---|
| `zapret2` | nfqws2 linked against `luajit2`, `libnetfilter-queue` and friends from the official OpenWrt repositories |
| `zapret2-static` | the same, with static binaries and LuaJIT built in. On the router it needs only `nftables`, `kmod-nft-queue` and `curl` |
| `zapret2-presets` | ready-made configs for specific ISPs and the `zapret2-preset` tool |

`zapret2` and `zapret2-static` conflict, so install one. Both lay out the upstream tree in
`/opt/zapret2` exactly as upstream `install_easy.sh` does, with `/etc/init.d/zapret2` and
the iface hotplug hook as symlinks into it. They ship the upstream `config.default`
unchanged, which has `NFQWS2_ENABLE=0`, so nothing happens until you configure it.

[Документация на русском](docs/ru.md)

## Install on the router

```sh
wget -O /etc/apk/keys/zapret2-openwrt.pem https://xzeldon.github.io/zapret2-openwrt/zapret2-openwrt.pem
. /etc/openwrt_release
FEED="https://xzeldon.github.io/zapret2-openwrt/${DISTRIB_RELEASE%.*}/$(cat /etc/apk/arch)/packages.adb"
grep -qxF "$FEED" /etc/apk/repositories.d/customfeeds.list || echo "$FEED" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add zapret2        # or: apk add zapret2-static
```

The feed path is `<release branch>/<package arch>`, for example `25.12/aarch64_cortex-a53`.
Take the arch from `/etc/apk/arch`. On OpenWrt `apk --print-arch` prints `aarch64`, and
no such directory exists. The [repository page](https://xzeldon.github.io/zapret2-openwrt/)
lists the branches and archs that CI builds.

apk trusts the repository because the key signs `packages.adb`. Without the key you get
`UNTRUSTED signature`. Add `/etc/apk/keys/zapret2-openwrt.pem` to `/etc/sysupgrade.conf`
if you want the key to survive a sysupgrade.

Next, edit `/opt/zapret2/config` following the
[upstream docs](https://github.com/bol-van/zapret2/tree/master/docs), or apply a preset,
and run `/etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart`.

### Updates

```sh
apk update
apk list -u | grep zapret       # empty output means nothing to update
apk upgrade zapret2 zapret2-presets
/etc/init.d/zapret2 restart
```

`/opt/zapret2/config` and the user lists in `/opt/zapret2/ipset/` are conffiles, so an
upgrade keeps your edits. If apk wants to ship a new version of one of them, it puts it
next to yours with a `.apk-new` suffix. Upstream sometimes adds settings to the config,
and `diff /opt/zapret2/config.default /opt/zapret2/config` shows them, since
`config.default` follows the package.

Upgrade zapret2 by name. A plain `apk upgrade` of the whole system is a bad idea on
OpenWrt. New zapret2 releases reach the repository on their own, within about 6 hours.

If you installed zapret2 earlier from a local `.apk` file, apk pins it to that file, and
`apk add zapret2` keeps the local build even after you add the feed. Back up the config,
then run `apk del zapret2 && apk add zapret2` and copy the config back.

### Switching between zapret2 and zapret2-static

They conflict, so remove one before adding the other. Back up the config first.

```sh
tar -czf /tmp/zapret2-conf.tgz /opt/zapret2/config /opt/zapret2/ipset/*.txt
apk del zapret2 && apk add zapret2-static
tar -xzf /tmp/zapret2-conf.tgz -C / && /etc/init.d/zapret2 restart
```

## Presets

```sh
apk add zapret2-presets
zapret2-preset list
zapret2-preset show vn-fpt-steam
zapret2-preset apply vn-fpt-steam       # backs up config and hostlist, then restarts zapret2
```

| Preset | For |
|---|---|
| [`vn-fpt-steam`](packages/zapret2-presets/files/presets/vn-fpt-steam/README.md) | Steam in Vietnam on FPT Telecom |

Installing the package changes nothing. Only `apply` touches the config. It backs up
`config` and `ipset/zapret-hosts-user.txt` to `*.bak-<timestamp>`, writes the preset
settings, installs the preset hostlist, restarts the service and prints the commands to
roll back.

An upgraded `zapret2-presets` does not change the rules zapret2 runs with, because
`apply` copied them into `/opt/zapret2`. Look at what changed and apply again:

```sh
apk upgrade zapret2-presets
diff /opt/zapret2/presets/vn-fpt-steam/hosts.txt /opt/zapret2/ipset/zapret-hosts-user.txt
zapret2-preset apply vn-fpt-steam
```

`apply` overwrites `zapret-hosts-user.txt`. Domains you added by hand survive only in the
`zapret-hosts-user.txt.bak-<timestamp>` backup, so copy them back after applying.

To add a domain without a preset, append it to the list and restart. The strategy lives
in `NFQWS2_OPT` in `/opt/zapret2/config` and also needs a restart after an edit.

```sh
echo newdomain.com >> /opt/zapret2/ipset/zapret-hosts-user.txt
/etc/init.d/zapret2 restart
```

DPI differs from one ISP to the next, so trust a preset only where its README says it was
tested. A preset is a directory in
[`packages/zapret2-presets/files/presets/`](packages/zapret2-presets/files/presets/)
with three files.

- `README.md`. The first line is the title. Say which ISP, where and when you tested it.
- `preset.conf`. `KEY=VALUE` lines and an optional multi-line `NFQWS2_OPT="…"` block.
- `hosts.txt`, optional. It becomes the user hostlist.

PRs with new tested presets are welcome. Bump `PKG_VERSION` in
`packages/zapret2-presets/Makefile` when you add one.

## Build locally

You need Linux x86_64 and about 3 GB of free disk. I test on Ubuntu 26.04. Run it as a
normal user. The script uses sudo only for `apt-get`.

```sh
git clone https://github.com/xzeldon/zapret2-openwrt && cd zapret2-openwrt
./build.sh                                   # all packages, default target
```

A first run takes about 2.5 minutes on 4 cores, plus the SDK download. Later runs reuse
the unpacked SDK.

| Variable | Default | Meaning |
|---|---|---|
| `OPENWRT_VER` | `25.12.5` | OpenWrt release of the SDK |
| `TARGET` | `mediatek/filogic` | router target, `ubus call system board` on the router shows it |
| `PACKAGES` | `zapret2 zapret2-static zapret2-presets` | what to build |
| `ZAPRET2_TAG` | the version pinned in the Makefile | another upstream tag, e.g. `v1.0.5.2` |
| `SIGN_KEY` | unset | EC private key. Without it the index stays unsigned |
| `WORKDIR`, `OUTDIR`, `DLDIR` | `work/`, `out/`, `work/dl` | |
| `INSTALL_HOST_DEPS` | `1` | `0` skips `apt-get` |

The output is a ready repository directory such as `out/25.12/aarch64_cortex-a53/`, with
the apks, `packages.adb` and `SHA256SUMS`. To try a single apk without a repository, copy
it to the router and run `apk add --allow-untrusted ./zapret2-*.apk`.

### What build.sh does

1. Downloads the SDK for `OPENWRT_VER` and `TARGET`, checks it against the release
   `sha256sums` and unpacks it to `work/sdk-<ver>-<target>`.
2. Writes a `feeds.conf` with only the `base` and `packages` feeds, plus this repo's
   `packages/` as the feed `zapret2`. Then it installs our packages and what they need
   to compile.
3. Turns off `CONFIG_ALL*`. The SDK sets them by default and then builds every package
   in the feeds, `linux-firmware` included.
4. Builds the variants one at a time, because they conflict.
5. Opens each apk and checks that `nfqws2` is dynamic or static as it should be.
6. Runs `index.sh`, which writes `packages.adb` and `SHA256SUMS` and signs the index
   when `SIGN_KEY` is set. It then reads the index back with only the public key, the
   way a router would.

### Why the build is small

`nfqws2` links against `libnetfilter-queue`, `libmnl`, `zlib` and `luajit2`. Those stay in
`DEPENDS`. The SDK builds them, and their metadata gives the ABI suffix, so the apk
depends on `libnetfilter-queue1` and not on `libnetfilter-queue`.

`nftables`, `kmod-nft-queue` and `curl` only run on the router. They go in
`EXTRA_DEPENDS`, which writes them into the apk metadata without building them. Building
them took about 85% of the CPU time: kernel modules, mbedtls, curl and nftables. With
`EXTRA_DEPENDS` only 8 feed packages end up in the SDK tree, and the SDK takes 1.6 GB
after a build. apk on 25.12 requires a version constraint in `EXTRA_DEPENDS`, so they
read `nftables (>=0)` and so on.

`libcap` is a build-only dependency. nfqws2 needs its `sys/capability.h` header, while
`capget` and `capset` come from musl.

## CI and the Pages repository

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs `build.sh` for each
entry of its `openwrt`/`target` matrix. It runs on every push and PR, and you can start it
by hand with another upstream tag. A run takes about 4 minutes.

On `main` a separate step signs the index with the `APK_SIGN_KEY` secret. The build step
compiles third-party code and never sees the key. After that `site.sh` rebuilds the whole
site and the workflow deploys it to GitHub Pages. PRs only build. A `v*` tag also creates
a GitHub release with the apks, their file names prefixed with the arch.

To support another router, add an `openwrt`/`target` entry to the matrix.

Only changes under `packages/`, the three scripts, `keys/` or `build.yml` itself start a
build. Editing docs does not.

### New zapret2 releases

[`.github/workflows/upstream.yml`](.github/workflows/upstream.yml) checks the latest
bol-van/zapret2 release every 6 hours. When it is newer than `PKG_VERSION`,
`update-upstream.sh` points the Makefile at the release commit and resets `PKG_RELEASE`
to 1. The workflow commits that to `main` and starts `build.yml`, and about 5 minutes
later routers get the new version from `apk upgrade zapret2`. If upstream breaks the
build, the run fails and Pages keeps serving the previous version.

A push made with `GITHUB_TOKEN` does not trigger other workflows, which is why
`upstream.yml` starts the build with `gh workflow run`. GitHub turns off scheduled
workflows in a public repo after 60 days without commits. The bump commits count, so
this only bites if upstream goes quiet for two months. Re-enable it in the Actions tab.

To bump by hand, run `./update-upstream.sh` or `./update-upstream.sh v1.0.5.2` and commit.

### Signing key

apk on OpenWrt 25.12 trusts a repository by the EC prime256v1 signature on its
`packages.adb`. The public half is [`keys/zapret2-openwrt.pem`](keys/zapret2-openwrt.pem),
the private half is the `APK_SIGN_KEY` secret. To make a new pair:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out zapret2-openwrt-apk-sign.pem
openssl ec -in zapret2-openwrt-apk-sign.pem -pubout -out keys/zapret2-openwrt.pem
gh secret set APK_SIGN_KEY < zapret2-openwrt-apk-sign.pem
```

Every router with the old public key has to download the new one.

## Layout

```
packages/zapret2/Makefile          zapret2 and zapret2-static
packages/zapret2-presets/          presets and the zapret2-preset tool
build.sh                           SDK -> packages -> repository directory
index.sh                           packages.adb, its signature and SHA256SUMS
site.sh                            GitHub Pages site from the built repositories
update-upstream.sh                 moves the Makefile to the latest zapret2 release
keys/zapret2-openwrt.pem           public key of the repository
```

## License

The packaging here is MIT. zapret2 itself is MIT, by bol-van.
