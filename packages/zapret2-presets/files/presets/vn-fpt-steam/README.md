# Steam in Vietnam (FPT Telecom)

Gets Steam working through FPT's DPI. zapret2 only touches connections to the Steam
domains in `hosts.txt` (`MODE_FILTER=hostlist`). Other traffic goes through as before.

## Where it was tested

FPT Telecom, Vietnam, on 2026-10-09. OpenWrt 25.12.5 on a Cudy TR3000
(mediatek/filogic). 100 of 100 TLS requests and 60 of 60 HTTP requests to Steam got
through.

## How FPT blocks Steam

FPT's DPI handles the two protocols differently, so each gets its own strategy.

TLS on port 443 gets blocked by SNI. The DPI injects a RST, but it does not reassemble TCP
segments. Splitting the ClientHello with plain `multisplit` is enough.

HTTP on port 80 carries the Steam CDN downloads and gets blocked by the Host header. Here
the DPI does reassemble in-order segments, so `multisplit` fails. The preset sends the
request out of order with `multidisorder`. A fake request with a bad TCP MD5 option goes
first. The DPI reads it, the server throws it away.

## Before you apply it

FPT's DNS answers with a sinkhole for Steam. Bypassing the DPI won't help while the router
asks FPT's resolver. Set up encrypted DNS on the router, for example stubby with DoT.
This preset does not do that for you.

The preset leaves `DISABLE_IPV6` alone. If your WAN has no IPv6, set `DISABLE_IPV6=1` in
`/opt/zapret2/config` yourself.

Viettel and VNPT run different DPI and may need another strategy. Find one with
`/opt/zapret2/blockcheck2.sh`.

## Usage

    zapret2-preset apply vn-fpt-steam

It backs up `config` and `ipset/zapret-hosts-user.txt`, writes the settings, installs
`hosts.txt` as the user hostlist and restarts zapret2.
