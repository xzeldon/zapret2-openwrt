# zapret2-openwrt

This project builds OpenWrt packages of [bol-van/zapret2](https://github.com/bol-van/zapret2).
GitHub Pages hosts them as a signed apk repository. A router installs them with `apk add`.

The packages need OpenWrt 25.12 or later. Earlier releases use opkg.

| Package | Description |
|---|---|
| `zapret2` | zapret2 with `nfqws2` linked to the libraries in the OpenWrt repositories |
| `zapret2-static` | zapret2 with static binaries. It needs only `nftables`, `kmod-nft-queue` and `curl` |
| `zapret2-presets` | Ready-made configs for specific ISPs, and the `zapret2-preset` tool |

`zapret2` and `zapret2-static` conflict. Install only one of them.

## Install

Run these commands on the router.

```sh
wget -O /etc/apk/keys/zapret2-openwrt.pem https://xzeldon.github.io/zapret2-openwrt/zapret2-openwrt.pem
. /etc/openwrt_release
FEED="https://xzeldon.github.io/zapret2-openwrt/${DISTRIB_RELEASE%.*}/$(cat /etc/apk/arch)/packages.adb"
grep -qxF "$FEED" /etc/apk/repositories.d/customfeeds.list || echo "$FEED" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add zapret2        # or: apk add zapret2-static
```

If apk shows `UNTRUSTED signature`, the key is missing. Do the first command again.

The package installs the upstream `config.default` with `NFQWS2_ENABLE=0`. Nothing runs
until you configure it. Do one of these:

- Edit `/opt/zapret2/config`. Use the [upstream docs](https://github.com/bol-van/zapret2/tree/master/docs).
- Apply a preset. See [Presets](#presets).

Then start the service.

```sh
/etc/init.d/zapret2 enable && /etc/init.d/zapret2 restart
```

## Update

```sh
apk update
apk upgrade zapret2 zapret2-presets
/etc/init.d/zapret2 restart
```

Always name the packages. Do not run a plain `apk upgrade` on OpenWrt.

The upgrade keeps your config and your user lists. Versions older than `1.0.7-r2` do not
do this. They replace your config with the defaults. Save your files before you upgrade
from such a version. See [Updating](docs/updating.md).

## Presets

```sh
apk add zapret2-presets
zapret2-preset list
zapret2-preset apply vn-fpt-steam
```

`apply` saves your config, writes the preset settings and restarts zapret2. It prints
the commands to undo the change.

| Preset | For |
|---|---|
| [`vn-fpt-steam`](packages/zapret2-presets/files/presets/vn-fpt-steam/README.md) | Steam in Vietnam on FPT Telecom |

Use a preset only where its README says that it was tested. DPI differs between ISPs.
For more information, see [Presets](docs/presets.md).

## More documentation

- [Updating](docs/updating.md): config safety, update details, switching between packages.
- [Presets](docs/presets.md): how `apply` works, custom domains, how to write a preset.
- [Building](docs/building.md): build the packages on your computer.
- [Maintaining](docs/maintaining.md): CI, new upstream releases, the signing key, file layout.

## License

The packaging is MIT. zapret2 is MIT, by bol-van.
