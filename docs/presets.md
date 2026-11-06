# Presets

```sh
apk add zapret2-presets
zapret2-preset list
zapret2-preset show vn-fpt-steam
zapret2-preset apply vn-fpt-steam
```

Installing the package changes nothing. Only `apply` changes the config.

## What apply does

1. It saves `config` and `ipset/zapret-hosts-user.txt` as `*.bak-<timestamp>`.
2. It writes the preset settings to `config`.
3. It installs the preset hostlist.
4. It enables and restarts zapret2.
5. It prints the commands to undo the change.

## Update a preset

A new `zapret2-presets` package does not change the rules that zapret2 uses. `apply`
copied them into `/opt/zapret2`. To use the new rules, compare the lists and apply again.

```sh
apk upgrade zapret2-presets
diff /opt/zapret2/presets/vn-fpt-steam/hosts.txt /opt/zapret2/ipset/zapret-hosts-user.txt
zapret2-preset apply vn-fpt-steam
```

`apply` replaces `zapret-hosts-user.txt`. A domain that you added by hand stays only in the
`zapret-hosts-user.txt.bak-<timestamp>` backup. Copy it back after you apply.

## Add a domain without a preset

Add the domain to the list. Then restart the service.

```sh
echo newdomain.com >> /opt/zapret2/ipset/zapret-hosts-user.txt
/etc/init.d/zapret2 restart
```

The strategy is in `NFQWS2_OPT` in `/opt/zapret2/config`. Restart the service after you
change it.

## Write a preset

A preset is a directory in
[`packages/zapret2-presets/files/presets/`](../packages/zapret2-presets/files/presets/).
It has these files:

- `README.md`. The first line is the title. Write which ISP, where and when you tested it.
- `preset.conf`. It has `KEY=VALUE` lines. It can have one multi-line `NFQWS2_OPT="..."` block.
- `hosts.txt` (optional). It becomes the user hostlist.

Pull requests with new tested presets are welcome. When you add a preset, increase
`PKG_VERSION` in `packages/zapret2-presets/Makefile`.
