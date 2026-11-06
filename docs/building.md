# Building

You need Linux x86_64 and about 3 GB of free disk space. The author tests on Ubuntu 26.04.
Run the script as a normal user. It uses sudo only for `apt-get`.

```sh
git clone https://github.com/xzeldon/zapret2-openwrt && cd zapret2-openwrt
./build.sh                                   # all packages, default target
```

The first run takes about 2.5 minutes on 4 cores, plus the SDK download. Later runs use the
unpacked SDK again.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `OPENWRT_VER` | `25.12.5` | OpenWrt release of the SDK |
| `TARGET` | `mediatek/filogic` | Router target. `ubus call system board` on the router shows it |
| `PACKAGES` | `zapret2 zapret2-static zapret2-presets` | Packages to build |
| `ZAPRET2_TAG` | version in the Makefile | Another upstream tag, for example `v1.0.5.2` |
| `SIGN_KEY` | unset | EC private key. Without it the index has no signature |
| `WORKDIR`, `OUTDIR`, `DLDIR` | `work/`, `out/`, `work/dl` | Work directories |
| `INSTALL_HOST_DEPS` | `1` | Set to `0` to skip `apt-get` |

## Output

The output is a repository directory, for example `out/25.12/aarch64_cortex-a53/`. It
contains the apk files, `packages.adb` and `SHA256SUMS`.

To test one apk without a repository, copy it to the router and run this command:

```sh
apk add --allow-untrusted ./zapret2-*.apk
```

## What build.sh does

1. It downloads the SDK for `OPENWRT_VER` and `TARGET`. It checks the file against the
   release `sha256sums` and unpacks it to `work/sdk-<ver>-<target>`.
2. It writes a `feeds.conf` with the `base` and `packages` feeds and the `packages/`
   directory of this repository as the feed `zapret2`. Then it installs our packages and
   their build dependencies.
3. It turns off `CONFIG_ALL*`. The SDK turns them on by default and then builds every
   package in the feeds, `linux-firmware` included.
4. It builds the variants one at a time, because they conflict.
5. It opens each apk and checks that `nfqws2` is dynamic or static, as expected.
6. It runs `index.sh`. This writes `packages.adb` and `SHA256SUMS`, and signs the index when
   `SIGN_KEY` is set. Then it reads the index with only the public key, as a router does.

## Why the build is small

`nfqws2` links to `libnetfilter-queue`, `libmnl`, `zlib` and `luajit2`. These packages stay
in `DEPENDS`. The SDK builds them, and their metadata gives the ABI suffix. For this
reason the apk depends on `libnetfilter-queue1` and not on `libnetfilter-queue`.

`nftables`, `kmod-nft-queue` and `curl` run only on the router. They are in
`EXTRA_DEPENDS`. This field writes them to the apk metadata and does not build them. Their
build took about 85% of the CPU time (kernel modules, mbedtls, curl and nftables). With
`EXTRA_DEPENDS`, the SDK tree has only 8 feed packages and takes 1.6 GB after a build.

apk on 25.12 needs a version constraint in `EXTRA_DEPENDS`. For this reason the entries
read `nftables (>=0)` and so on.

`libcap` is a build-only dependency. `nfqws2` needs its `sys/capability.h` header.
`capget` and `capset` come from musl.
