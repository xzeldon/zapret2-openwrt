# Maintaining

## Build workflow

[`.github/workflows/build.yml`](../.github/workflows/build.yml) runs `build.sh` for each
`openwrt`/`target` entry in its matrix. It runs on each push and pull request. You can also
start it by hand with another upstream tag. A run takes about 4 minutes.

On `main`, a separate step signs the index with the `APK_SIGN_KEY` secret. The build step
compiles third-party code and never sees the key. Then `site.sh` builds the whole site, and
the workflow deploys it to GitHub Pages. Pull requests only build.

A `v*` tag also creates a GitHub release with the apk files. Their names start with the arch.

To support another router, add an `openwrt`/`target` entry to the matrix.

Only these changes start a build:

- changes in `packages/`
- changes in the three scripts
- changes in `keys/`
- changes in `build.yml`

A change to the docs does not start a build.

## New zapret2 releases

[`.github/workflows/upstream.yml`](../.github/workflows/upstream.yml) checks the latest
bol-van/zapret2 release every 6 hours. If it is newer than `PKG_VERSION`, the workflow does
these steps:

1. `update-upstream.sh` points the Makefile to the release commit and resets `PKG_RELEASE`
   to 1.
2. The workflow commits the change to `main`.
3. The workflow starts `build.yml`.

About 5 minutes later, routers get the new version with `apk upgrade zapret2`. If the
upstream code does not build, the run fails. Pages keeps the previous version.

A push with `GITHUB_TOKEN` does not start other workflows. For this reason `upstream.yml`
starts the build with `gh workflow run`.

GitHub turns off scheduled workflows in a public repository after 60 days without commits.
The version commits count as commits. This is a problem only if upstream has no release for
two months. Turn the workflow on again in the Actions tab.

To change the version by hand, run `./update-upstream.sh` or
`./update-upstream.sh v1.0.5.2`. Then commit the result.

## Protected files

The `conffiles` list in `packages/zapret2/Makefile` is for sysupgrade only. apk does not use
it. apk protects only `/etc` by default.

For this reason the Makefile also installs `/etc/apk/protected_paths.d/zapret2.list`.
Each file in `conffiles` needs a `+` rule in this list. See `apk-protected_paths(5)`.

## Signing key

apk on OpenWrt 25.12 trusts a repository by the EC prime256v1 signature on `packages.adb`.
The public key is [`keys/zapret2-openwrt.pem`](../keys/zapret2-openwrt.pem). The private key
is the `APK_SIGN_KEY` secret.

To make a new pair, run these commands:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out zapret2-openwrt-apk-sign.pem
openssl ec -in zapret2-openwrt-apk-sign.pem -pubout -out keys/zapret2-openwrt.pem
gh secret set APK_SIGN_KEY < zapret2-openwrt-apk-sign.pem
```

Each router that has the old public key must download the new one.

## File layout

```
packages/zapret2/Makefile          zapret2 and zapret2-static
packages/zapret2-presets/          presets and the zapret2-preset tool
build.sh                           SDK -> packages -> repository directory
index.sh                           packages.adb, its signature and SHA256SUMS
site.sh                            GitHub Pages site from the built repositories
update-upstream.sh                 moves the Makefile to the latest zapret2 release
keys/zapret2-openwrt.pem           public key of the repository
```
