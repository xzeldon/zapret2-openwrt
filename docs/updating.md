# Updating

## Normal update

```sh
apk update
apk list -u | grep zapret       # no output means no update
apk upgrade zapret2 zapret2-presets
/etc/init.d/zapret2 restart
```

New zapret2 releases reach the repository in about 6 hours.

## What the upgrade keeps

The package protects these files:

- `/opt/zapret2/config`
- the user lists in `/opt/zapret2/ipset/`

The package lists them in `/etc/apk/protected_paths.d/zapret2.list`. apk protects only
`/etc` by default, so this list is necessary.

If you changed a protected file and the new package has a different version, apk writes the
new version next to yours. The name ends in `.apk-new`. Your file does not change.

Upstream sometimes adds settings to the config. `config.default` follows the package. To
see the new settings, run this command:

```sh
diff /opt/zapret2/config.default /opt/zapret2/config
```

## Upgrade from a version older than 1.0.7-r2

These versions have no protected list. An upgrade replaces your config and your user lists
with the defaults. apk does not create a `.apk-new` file.

To check the installed version, run `apk list -I zapret2`.

1. Save the files.

   ```sh
   tar -czf /root/zapret2-conf.tgz /opt/zapret2/config /opt/zapret2/ipset/*.txt
   ```

2. Upgrade the packages.
3. Restore the files.

   ```sh
   tar -xzf /root/zapret2-conf.tgz -C /
   ```

4. Restart zapret2.

If you use only a preset, you can run `zapret2-preset apply <name>` after the upgrade
instead.

## Local apk file

If you installed zapret2 from a local `.apk` file, apk pins the package to that file. Then
`apk add zapret2` keeps the local build, also after you add the feed. To change to the feed
version:

1. Save the config.
2. Run `apk del zapret2 && apk add zapret2`.
3. Restore the config.

## Switching between zapret2 and zapret2-static

The two packages conflict. Remove one before you add the other. Save the config first.

```sh
tar -czf /tmp/zapret2-conf.tgz /opt/zapret2/config /opt/zapret2/ipset/*.txt
apk del zapret2 && apk add zapret2-static
tar -xzf /tmp/zapret2-conf.tgz -C / && /etc/init.d/zapret2 restart
```

## Keep the repository key after a sysupgrade

Add `/etc/apk/keys/zapret2-openwrt.pem` to `/etc/sysupgrade.conf`. Without it, a
sysupgrade removes the key.

## Feed path

The feed path is `<release branch>/<package arch>`. An example is
`25.12/aarch64_cortex-a53`. Read the arch from `/etc/apk/arch`.

Do not use `apk --print-arch`. On OpenWrt it prints `aarch64`, and no such directory
exists. The [repository page](https://xzeldon.github.io/zapret2-openwrt/) lists the
branches and archs that CI builds.
