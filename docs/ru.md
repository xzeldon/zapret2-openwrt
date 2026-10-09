# zapret2 для OpenWrt: установка, настройка, сборка

Пакеты [bol-van/zapret2](https://github.com/bol-van/zapret2), собранные из апстримных
исходников официальным OpenWrt SDK, и подписанный apk-репозиторий на GitHub Pages.
Только OpenWrt 25.12+ (apk).

| Пакет | Что внутри |
|---|---|
| `zapret2` | nfqws2 динамический, `luajit2`, `libnetfilter-queue` и пр. ставятся из официальных репозиториев OpenWrt |
| `zapret2-static` | статические бинарники (musl, LuaJIT внутри), на роутере нужны только `nftables`, `kmod-nft-queue`, `curl` |
| `zapret2-presets` | готовые сценарии под конкретных провайдеров и утилита `zapret2-preset` |

`zapret2` и `zapret2-static` конфликтуют, ставится один из них. Оба раскладывают
апстримное дерево в `/opt/zapret2` так же, как `install_easy.sh`, и **ничего не делают**
после установки: в апстримном `config` стоит `NFQWS2_ENABLE=0`.

## 1. Подключить репозиторий

```sh
wget -O /etc/apk/keys/zapret2-openwrt.pem https://xzeldon.github.io/zapret2-openwrt/zapret2-openwrt.pem
. /etc/openwrt_release
FEED="https://xzeldon.github.io/zapret2-openwrt/${DISTRIB_RELEASE%.*}/$(cat /etc/apk/arch)/packages.adb"
grep -qxF "$FEED" /etc/apk/repositories.d/customfeeds.list || echo "$FEED" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add zapret2                 # или zapret2-static
```

- Архитектуру берём из `/etc/apk/arch`. `apk --print-arch` на OpenWrt печатает `aarch64`
  вместо `aarch64_cortex-a53`, и путь не найдётся.
- apk доверяет репозиторию по подписи `packages.adb`, поэтому ключ обязателен.
  Без ключа будет `UNTRUSTED signature`.
- Какие ветки и архитектуры собираются, видно на
  [странице репозитория](https://xzeldon.github.io/zapret2-openwrt/).
- После установки postinst OpenWrt сам запускает сервис. С апстримным конфигом это
  создаёт пустую nft-таблицу `inet zapret2` и трафик не трогает.

## 2. Настроить

### Пресетом

```sh
apk add zapret2-presets
zapret2-preset list
zapret2-preset show vn-fpt-steam        # README пресета и что именно он поменяет
zapret2-preset apply vn-fpt-steam
```

`apply` делает бэкап `config` и `ipset/zapret-hosts-user.txt` (`*.bak-<дата>`),
выставляет параметры, кладёт список доменов, делает `enable` и `restart`. В конце
печатает команды для отката.

Пресет привязан к провайдеру: DPI у разных провайдеров разный. Где и когда пресет
проверен, написано в его README.

### Вручную

Конфиг `/opt/zapret2/config`, домены `/opt/zapret2/ipset/zapret-hosts-user.txt`.
Описание параметров есть в [апстримной документации](https://github.com/bol-van/zapret2/tree/master/docs).
Минимальный сценарий «трогать только домены из списка»:

```sh
C=/opt/zapret2/config
set_cfg() { sed -i "s|^#\?$1=.*|$1=$2|" $C; grep -q "^$1=" $C || echo "$1=$2" >> $C; }
set_cfg NFQWS2_ENABLE 1
set_cfg MODE_FILTER hostlist            # <HOSTLIST> в NFQWS2_OPT = zapret-hosts-user.txt
set_cfg NFQWS2_PORTS_TCP 80,443
set_cfg NFQWS2_PORTS_UDP ''
set_cfg NFQWS2_TCP_PKT_OUT 10           # в очередь идут только первые пакеты соединения
set_cfg NFQWS2_TCP_PKT_IN 3
# NFQWS2_OPT многострочный: удалить блок целиком и дописать свой
sed -i '/^NFQWS2_OPT="/,/^"$/d' $C
cat >> $C <<'EOF'
NFQWS2_OPT="
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld
"
EOF
/etc/init.d/zapret2 enable
/etc/init.d/zapret2 restart
```

Если на WAN нет IPv6: `set_cfg DISABLE_IPV6 1`.

### DNS

Обход DPI бесполезен, если DNS провайдера отдаёт заглушку. Во Вьетнаме, например, Steam
резолвится в `127.0.0.1`. Нужен шифрованный DNS на роутере: stubby или https-dns-proxy, в
dnsmasq `noresolv=1` (LuCI: Network → DNS → Resolv & Hosts Files → Ignore resolv file).
Проверка с ПК: `nslookup store.steampowered.com` должен вернуть реальный адрес.

## 3. Проверить

```sh
pgrep -af nfqws2                         # в аргументах --hostlist=/opt/zapret2/ipset/zapret-hosts-user.txt
nft list table inet zapret2 | grep queue # только нужные порты, "ct original packets 1-N", "queue flags bypass"
```

С ПК делаем `curl` на заблокированные адреса. Должен прийти HTTP-код, а не `000`
(connection reset).

Нагрузка: на Cudy TR3000 (MT7981B, 2×A53) при скачивании 100 MB CPU роутера был загружен
на 5–6 % и с zapret2, и без него. В очередь попадают только первые пакеты соединений с
нужными портами, остальной трафик идёт мимо.

## 4. Отладка

| Симптом | Что делать |
|---|---|
| Снова не открывается | Проверить DNS. `grep -i <домен> /opt/zapret2/ipset/zapret-hosts-user-exclude.txt` должен ничего не выводить. Дальше blockcheck2 |
| Часть сервиса работает, часть нет | Не хватает доменов в `zapret-hosts-user.txt`. Добавить их и сделать `restart` |
| Нужен подробный лог | `--debug=@/tmp/nfqws2.log` в начало `NFQWS2_OPT`, `restart`. В логе есть `hostlist check … positive/negative` и что отправлено. После отладки убрать |
| Сломался интернет | `/etc/init.d/zapret2 stop`: таблица удаляется. Если демон упал, `queue … bypass` пропускает пакеты |

### Провайдер поменял DPI: blockcheck2

Сервис нужно остановить, иначе он мешает тесту. На OpenWrt нет `nohup`, поэтому фон через `( … & )`:

```sh
/etc/init.d/zapret2 stop
cd /opt/zapret2
( BATCH=1 IPVS=4 DOMAINS="store.steampowered.com" \
  ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=1 ENABLE_HTTPS_TLS13=0 ENABLE_HTTP3=0 \
  SCANLEVEL=quick ./blockcheck2.sh > /tmp/blockcheck2.log 2>&1 < /dev/null & )
grep -B1 AVAILABLE /tmp/blockcheck2.log | grep '^- '
```

- Ждать конца не обязательно. Остановить можно так: `kill $(pgrep -f "[b]lockcheck2.sh")`.
  На SIGTERM он убирает свою nft-таблицу, а на SIGINT в batch-режиме не реагирует.
- blockcheck делает одну попытку на вариант, и `AVAILABLE` может срабатывать лишь в 70 %
  случаев. Поэтому 2–3 кандидата стоит проверить по 20 запросов и выбрать лучший.
- Начинать лучше с простого. Если DPI не собирает TCP-сегменты, хватает
  `multisplit:pos=1,midsld`.

## 5. Обновление и удаление

```sh
apk update && apk upgrade zapret2         # config и списки — conffiles, сохраняются
diff /opt/zapret2/config.default /opt/zapret2/config   # есть ли новые параметры в апстриме
```

Общий `apk upgrade` на OpenWrt делать не стоит.

Переход между `zapret2` и `zapret2-static`:

```sh
tar -czf /tmp/zapret2-conf.tgz /opt/zapret2/config /opt/zapret2/ipset/*.txt
apk del zapret2 && apk add zapret2-static
tar -xzf /tmp/zapret2-conf.tgz -C / && /etc/init.d/zapret2 restart
```

Удаление:

```sh
/etc/init.d/zapret2 stop; /etc/init.d/zapret2 disable
apk del zapret2 zapret2-static zapret2-presets
rm -rf /opt/zapret2
```

Если стоял `zapret2` из remittor/zapret-openwrt (UCI-конфиг `/etc/config/zapret2`,
`luci-app-zapret2`), его нужно сначала удалить: пакеты называются одинаково, но несовместимы.

```sh
/etc/init.d/zapret2 stop; /etc/init.d/zapret2 disable
apk del luci-app-zapret2 zapret2
rm -rf /opt/zapret2 /etc/config/zapret2 /etc/init.d/zapret2 /etc/hotplug.d/iface/90-zapret2
nft list tables | grep -q zapret2 && nft delete table inet zapret2
```

## 6. Сборка

### Локально

Нужен Linux x86_64 (проверено на Ubuntu 26.04), около 3 ГБ свободного места, обычный
пользователь с sudo (sudo только для `apt-get`).

```sh
git clone https://github.com/xzeldon/zapret2-openwrt && cd zapret2-openwrt
./build.sh                                        # все пакеты под mediatek/filogic
PACKAGES=zapret2 ./build.sh                       # только динамический
TARGET=x86/64 ./build.sh                          # другой target
ZAPRET2_TAG=v1.0.5.2 ./build.sh                   # другой тег апстрима
SIGN_KEY=~/key.pem ./build.sh                     # подписать индекс
```

Результат — готовый каталог репозитория `out/<ветка>/<arch>/`. В нём apk,
`packages.adb` и `SHA256SUMS`. Без `SIGN_KEY` индекс не подписан. Отдельный apk можно
поставить на роутер напрямую: `scp -O` (в dropbear нет sftp), затем
`apk add --allow-untrusted /tmp/zapret2-*.apk`.

Target роутера смотрим на нём: `ubus call system board | grep target`.

### В GitHub Actions

`.github/workflows/build.yml` собирает каждую запись матрицы (`openwrt` + `target`).
- Сборка запускается на push, на PR и вручную; при ручном запуске можно указать тег апстрима.
- На `main` индекс подписывается секретом `APK_SIGN_KEY` в отдельном шаге: во время
  компиляции стороннего кода ключа в окружении нет. Потом сайт пересобирается и
  выкладывается на Pages.
- Тег `v*` дополнительно создаёт GitHub Release с apk.

### Как устроен пакет

- Исходники берутся git'ом с фиксированного коммита (`PKG_SOURCE_VERSION` в
  `packages/zapret2/Makefile`). Собираются `nfqws2`, `mdig`, `ip2net` апстримными Makefile.
- Варианты сделаны механизмом `VARIANT` OpenWrt. Статика собирается с `-static`
  вместо `-pie` (`LDFLAGS_PIE=`) и с `-lgcc_eh`: без него на arm64 не линкуется
  раскрутка стека LuaJIT. LuaJIT для статики берётся из `openresty/luajit2`, тег
  закреплён в Makefile.
- `CFLAGS`/`LDFLAGS` передаются через окружение, а не аргументами make. Апстрим
  делает `CFLAGS += …`, и аргумент командной строки перекрыл бы это.
- Зависимости делятся на два вида:
  - `DEPENDS` — только библиотеки, с которыми линкуется `nfqws2`. Без них не
    собрать. Кроме того, из их метаданных берётся ABI-суффикс: в apk попадает
    `libnetfilter-queue1`, а не `libnetfilter-queue`.
  - `EXTRA_DEPENDS` — то, что нужно только на роутере: `nftables`, `kmod-nft-queue`,
    `curl`. Они просто дописываются в метаданные apk и в SDK не собираются, а это
    около 85 % времени сборки (kmod-ы ядра, mbedtls, curl, nftables). apk в 25.12
    требует для `EXTRA_DEPENDS` ограничение версии, поэтому стоит `(>=0)`.
- `libcap` нужен только при сборке ради заголовка `sys/capability.h`. `capget`/`capset`
  берутся из musl, поэтому на роутере libcap не нужен.
- Conffiles: `/opt/zapret2/config` и пользовательские списки в `/opt/zapret2/ipset/`.

### Грабли

| Симптом | Причина / решение |
|---|---|
| `fatal error: sys/capability.h` | в фидах нет `libcap`; он в `PKG_BUILD_DEPENDS`, `feeds install -p zapret2 -a` ставит его сам |
| SDK собирает linux-firmware, все kmod и занимает 8+ ГБ | по умолчанию в SDK `CONFIG_ALL*=y`, `build.sh` их выключает |
| `feeds install` тянет openldap, python3, bluez… | так `feeds install` обходит необязательные зависимости пакетов из `DEPENDS`; поэтому то, что нужно только на роутере, вынесено в `EXTRA_DEPENDS` |
| `No feed for package 'zlib'` | в `feeds.conf` нет `base`: в SDK 25.12 строка начинается с `src-git --root=package base` |
| `recursive dependency detected!`, `WARNING: … does not exist` при `defconfig` | особенности SDK, не ошибка |
| `Error 1 (ignored)` в логе | не ошибка; падение — это `failed to build` |
| `bad interpreter: /bin/bash^M` | скрипт с CRLF (правился на Windows), `sed -i 's/\r$//'` |
| busybox `sha256sum -c` пишет `FAILED` про файлы, которых нет | проверять только скопированные: `grep <имя> SHA256SUMS \| sha256sum -c -` |
