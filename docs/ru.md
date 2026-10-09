# zapret2 для OpenWrt

Пакеты [bol-van/zapret2](https://github.com/bol-van/zapret2), собранные из апстримных
исходников официальным OpenWrt SDK. Они лежат в подписанном apk-репозитории на GitHub
Pages, и роутер ставит их обычным `apk add`. Подходит только OpenWrt 25.12 и новее,
старые релизы работают на opkg.

| Пакет | Что это |
|---|---|
| `zapret2` | nfqws2 с динамической линковкой. `luajit2`, `libnetfilter-queue` и остальное ставятся из официальных репозиториев OpenWrt |
| `zapret2-static` | то же со статическими бинарниками, LuaJIT внутри. На роутере нужны только `nftables`, `kmod-nft-queue` и `curl` |
| `zapret2-presets` | готовые конфиги под конкретных провайдеров и утилита `zapret2-preset` |

`zapret2` и `zapret2-static` конфликтуют, ставится один из них. Оба раскладывают
апстримное дерево в `/opt/zapret2` так же, как это делает `install_easy.sh`.
`/etc/init.d/zapret2` и hotplug-хук сделаны симлинками внутрь этого дерева. Конфиг
апстримный, в нём `NFQWS2_ENABLE=0`, так что после установки zapret2 ничего не делает.

## Подключить репозиторий

```sh
wget -O /etc/apk/keys/zapret2-openwrt.pem https://xzeldon.github.io/zapret2-openwrt/zapret2-openwrt.pem
. /etc/openwrt_release
FEED="https://xzeldon.github.io/zapret2-openwrt/${DISTRIB_RELEASE%.*}/$(cat /etc/apk/arch)/packages.adb"
grep -qxF "$FEED" /etc/apk/repositories.d/customfeeds.list || echo "$FEED" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add zapret2                 # или zapret2-static
```

Архитектуру берём из `/etc/apk/arch`. `apk --print-arch` на OpenWrt печатает `aarch64`
вместо `aarch64_cortex-a53`, и такого каталога в репозитории нет. Какие ветки и
архитектуры собирает CI, видно на [странице репозитория](https://xzeldon.github.io/zapret2-openwrt/).

apk верит репозиторию по подписи `packages.adb`, поэтому без ключа будет
`UNTRUSTED signature`. Чтобы ключ пережил sysupgrade, допишите
`/etc/apk/keys/zapret2-openwrt.pem` в `/etc/sysupgrade.conf`.

После установки OpenWrt сам запускает сервис. С апстримным конфигом это создаёт пустую
nft-таблицу `inet zapret2`, трафик не затрагивается.

Если zapret2 раньше ставился из локального `.apk`, apk привязал его к этому файлу. Тогда
`apk add zapret2` оставит локальную сборку даже с подключённым репозиторием. Сохраните
конфиг, выполните `apk del zapret2 && apk add zapret2` и верните конфиг на место.

## Настроить

### Пресетом

```sh
apk add zapret2-presets
zapret2-preset list
zapret2-preset show vn-fpt-steam        # README пресета и что именно он поменяет
zapret2-preset apply vn-fpt-steam
```

Сама установка пакета ничего не меняет, конфиг трогает только `apply`. Он сохраняет
`config` и `ipset/zapret-hosts-user.txt` в `*.bak-<дата>`, выставляет параметры, кладёт
список доменов и делает `enable` и `restart`. В конце печатает команды для отката.

DPI у провайдеров разный, и пресет точно работает только там, где его проверили. Где и
когда это было, написано в его README.

### Вручную

Конфиг лежит в `/opt/zapret2/config`, список доменов в
`/opt/zapret2/ipset/zapret-hosts-user.txt`. Параметры описаны в
[апстримной документации](https://github.com/bol-van/zapret2/tree/master/docs).
Вот минимальная настройка, при которой zapret2 трогает только домены из списка:

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

Если на WAN нет IPv6, добавьте `set_cfg DISABLE_IPV6 1`.

### DNS

Если DNS провайдера отдаёт заглушку, обход DPI не поможет. Во Вьетнаме, например, Steam
резолвится в `127.0.0.1`. Поднимите на роутере шифрованный DNS, stubby или
https-dns-proxy, и включите в dnsmasq `noresolv=1`. В LuCI это Network → DNS →
Resolv & Hosts Files → Ignore resolv file. Проверка с ПК: `nslookup store.steampowered.com`
должен вернуть настоящий адрес.

## Проверить

```sh
pgrep -af nfqws2                         # в аргументах --hostlist=/opt/zapret2/ipset/zapret-hosts-user.txt
nft list table inet zapret2 | grep queue # только нужные порты, "ct original packets 1-N", "queue flags bypass"
```

С ПК запросите `curl`-ом заблокированные адреса. Должен прийти HTTP-код. `000` означает,
что соединение сбросили.

Нагрузка почти нулевая. На Cudy TR3000 (MT7981B, 2×A53) скачивание 100 MB грузило CPU
роутера на 5-6 % что с zapret2, что без него. В очередь nfqws2 попадают только первые
пакеты соединений на нужные порты, остальной трафик идёт мимо.

## Отладка

| Симптом | Что делать |
|---|---|
| Снова не открывается | Проверить DNS. `grep -i <домен> /opt/zapret2/ipset/zapret-hosts-user-exclude.txt` должен ничего не выводить. Если всё чисто, запустить blockcheck2 |
| Часть сервиса работает, часть нет | В `zapret-hosts-user.txt` не хватает доменов. Добавить их и сделать `restart` |
| Нужен подробный лог | Поставить `--debug=@/tmp/nfqws2.log` в начало `NFQWS2_OPT` и сделать `restart`. В логе видно `hostlist check … positive/negative` и что ушло в сеть. После отладки убрать |
| Пропал интернет | `/etc/init.d/zapret2 stop` удаляет таблицу. Если демон упал сам, правило `queue … bypass` пропустит пакеты мимо него |

### Провайдер поменял DPI

Подобрать новую стратегию поможет blockcheck2. Сервис на время теста остановите, иначе он
мешает. `nohup` на OpenWrt нет, поэтому в фон запускаем через `( … & )`:

```sh
/etc/init.d/zapret2 stop
cd /opt/zapret2
( BATCH=1 IPVS=4 DOMAINS="store.steampowered.com" \
  ENABLE_HTTP=0 ENABLE_HTTPS_TLS12=1 ENABLE_HTTPS_TLS13=0 ENABLE_HTTP3=0 \
  SCANLEVEL=quick ./blockcheck2.sh > /tmp/blockcheck2.log 2>&1 < /dev/null & )
grep -B1 AVAILABLE /tmp/blockcheck2.log | grep '^- '
```

Ждать конца теста не обязательно. Как наберётся несколько `AVAILABLE`, остановите его
командой `kill $(pgrep -f "[b]lockcheck2.sh")`. На SIGTERM он убирает свою nft-таблицу, а
SIGINT в batch-режиме игнорирует.

Одной отметке `AVAILABLE` верить не стоит. blockcheck пробует каждый вариант один раз, а
стратегия может срабатывать в 70 % случаев. Прогоните 2-3 кандидата по 20 запросов и
возьмите лучший.

Начинайте с простого. Если DPI не собирает TCP-сегменты, хватает
`multisplit:pos=1,midsld`.

## Обновить или удалить

```sh
apk update && apk upgrade zapret2         # config и списки это conffiles, они сохранятся
diff /opt/zapret2/config.default /opt/zapret2/config   # появились ли в апстриме новые параметры
```

Обновляйте zapret2 по имени. Общий `apk upgrade` на OpenWrt лучше не запускать.

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

`zapret2` из remittor/zapret-openwrt с UCI-конфигом `/etc/config/zapret2` и
`luci-app-zapret2` сначала нужно удалить. Пакеты называются одинаково, но устроены
по-разному.

```sh
/etc/init.d/zapret2 stop; /etc/init.d/zapret2 disable
apk del luci-app-zapret2 zapret2
rm -rf /opt/zapret2 /etc/config/zapret2 /etc/init.d/zapret2 /etc/hotplug.d/iface/90-zapret2
nft list tables | grep -q zapret2 && nft delete table inet zapret2
```

## Собрать

### Локально

Нужен Linux x86_64 и около 3 ГБ свободного места. Я проверял на Ubuntu 26.04. Запускайте
от обычного пользователя, sudo скрипт берёт только для `apt-get`.

```sh
git clone https://github.com/xzeldon/zapret2-openwrt && cd zapret2-openwrt
./build.sh                                        # все пакеты под mediatek/filogic
PACKAGES=zapret2 ./build.sh                       # только динамический
TARGET=x86/64 ./build.sh                          # другой target
ZAPRET2_TAG=v1.0.5.2 ./build.sh                   # другой тег апстрима
SIGN_KEY=~/key.pem ./build.sh                     # подписать индекс
```

Первый запуск на 4 ядрах идёт около 2,5 минут плюс скачивание SDK. Дальше распакованный
SDK переиспользуется.

На выходе получается готовый каталог репозитория `out/<ветка>/<arch>/` с apk,
`packages.adb` и `SHA256SUMS`. Без `SIGN_KEY` индекс не подписан. Отдельный apk можно
поставить на роутер напрямую. Скопируйте его через `scp -O`, потому что в dropbear нет
sftp, и выполните `apk add --allow-untrusted /tmp/zapret2-*.apk`.

Target роутера показывает `ubus call system board | grep target` на самом роутере.

### В GitHub Actions

`.github/workflows/build.yml` собирает каждую запись матрицы `openwrt` + `target`. Сборка
идёт на каждый push и PR, а вручную можно запустить её с другим тегом апстрима. Прогон
занимает около 4 минут.

На `main` индекс подписывает отдельный шаг секретом `APK_SIGN_KEY`. Шаг сборки
компилирует чужой код и ключа не видит. Потом `site.sh` пересобирает сайт, и workflow
выкладывает его на Pages. Тег `v*` вдобавок создаёт GitHub Release с apk.

### Как устроен пакет

Исходники берутся git'ом с закреплённого коммита, это `PKG_SOURCE_VERSION` в
`packages/zapret2/Makefile`. `nfqws2`, `mdig` и `ip2net` собираются апстримными Makefile.

Варианты сделаны механизмом `VARIANT` OpenWrt. Статика собирается с `-static` вместо
`-pie` (`LDFLAGS_PIE=`) и с `-lgcc_eh`, иначе на arm64 не линкуется раскрутка стека
LuaJIT. LuaJIT для статики берётся из `openresty/luajit2`, тег закреплён в Makefile.

`CFLAGS` и `LDFLAGS` уходят в make через окружение, а не аргументами. Апстрим делает
`CFLAGS += …`, и аргумент командной строки это бы перекрыл.

Зависимости разделены на два вида, и от этого сильно зависит время сборки.
- В `DEPENDS` только библиотеки, с которыми линкуется `nfqws2`. Без них не собрать. Из
  их метаданных SDK берёт ABI-суффикс, поэтому в apk попадает `libnetfilter-queue1`, а
  не `libnetfilter-queue`.
- В `EXTRA_DEPENDS` то, что нужно только на роутере: `nftables`, `kmod-nft-queue`,
  `curl`. Они просто дописываются в метаданные apk, и SDK их не собирает. Раньше на них
  уходило около 85 % процессорного времени сборки: модули ядра, mbedtls, curl, nftables.
  apk в 25.12 требует в `EXTRA_DEPENDS` ограничение версии, поэтому там стоит `(>=0)`.

`libcap` нужен только при сборке, ради заголовка `sys/capability.h`. `capget` и `capset`
есть в musl, так что на роутере libcap не нужен.

Conffiles: `/opt/zapret2/config` и пользовательские списки в `/opt/zapret2/ipset/`.

### Грабли

| Симптом | Причина и решение |
|---|---|
| `fatal error: sys/capability.h` | В дереве SDK нет `libcap`. Он прописан в `PKG_BUILD_DEPENDS`, и `feeds install -p zapret2 -a` ставит его сам |
| SDK собирает linux-firmware и все kmod, занимает 8+ ГБ | В SDK по умолчанию `CONFIG_ALL*=y`. `build.sh` их выключает |
| `feeds install` тянет openldap, python3, bluez… | `feeds install` обходит и необязательные зависимости пакетов из `DEPENDS`. Поэтому всё, что нужно только на роутере, вынесено в `EXTRA_DEPENDS` |
| `No feed for package 'zlib'` | В `feeds.conf` нет `base`. В SDK 25.12 эта строка начинается с `src-git --root=package base` |
| `recursive dependency detected!`, `WARNING: … does not exist` при `defconfig` | Так ведёт себя SDK, это не ошибка |
| `Error 1 (ignored)` в логе | Тоже не ошибка. Настоящее падение выглядит как `failed to build` |
| `bad interpreter: /bin/bash^M` | Скрипт сохранили с CRLF на Windows. Поможет `sed -i 's/\r$//'` |
| busybox `sha256sum -c` пишет `FAILED` про файлы, которых нет | Проверяйте только скопированные: `grep <имя> SHA256SUMS \| sha256sum -c -` |
