# Steam in Vietnam (FPT Telecom)

Bypasses Steam blocking only for the Steam domains listed in `hosts.txt`.
All other traffic is left untouched (`MODE_FILTER=hostlist`).

## Verification

- ISP: FPT Telecom, Vietnam
- Verified 2026-10-09 on OpenWrt 25.12.5 (Cudy TR3000, mediatek/filogic)
- TLS: 100/100 successful requests; HTTP: 60/60 successful requests

## How it works

FPT's DPI behaves differently for the two protocols:

- TLS (port 443) is blocked by SNI with an injected RST, and the DPI does not
  reassemble TCP segments. A plain `multisplit` of the ClientHello is enough.
- HTTP (port 80, Steam CDN downloads) is blocked by the Host header, and the DPI
  does reassemble in-order segments. So the request is sent out of order
  (`multidisorder`), preceded by a fake request with a bad TCP MD5 option that
  the server ignores.

## Notes

- DNS: the ISP resolver returns a sinkhole for Steam, so DNS must not come from
  it. Use encrypted DNS (e.g. stubby/DoT). This is out of scope of this preset.
- IPv6: the preset does not change `DISABLE_IPV6`. Set `DISABLE_IPV6=1` in
  `/opt/zapret2/config` yourself if your WAN has no IPv6.
- Other Vietnamese ISPs (Viettel, VNPT) may need a different strategy. Use
  `/opt/zapret2/blockcheck2.sh` to find one.

## Usage

    zapret2-preset apply vn-fpt-steam

This backs up `config` and `ipset/zapret-hosts-user.txt`, applies the settings,
installs `hosts.txt` as the user hostlist and restarts zapret2.
