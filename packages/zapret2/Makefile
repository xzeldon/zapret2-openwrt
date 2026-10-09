# OpenWrt package for bol-van/zapret2 built straight from upstream sources.
# Installs the same layout as upstream install_easy.sh does on OpenWrt:
# /opt/zapret2 tree, /etc/init.d/zapret2 and the iface hotplug hook as symlinks into it.
#
# Two variants of the same package:
#   zapret2         nfqws2 linked dynamically against luajit2/libnetfilter-queue/... from the feed (default)
#   zapret2-static  nfqws2/mdig/ip2net fully static (musl), LuaJIT built from source here;
#                   runtime needs only nftables + kmod-nft-queue

include $(TOPDIR)/rules.mk

PKG_NAME:=zapret2
PKG_VERSION:=1.0.5.2
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/bol-van/zapret2.git
PKG_SOURCE_VERSION:=6b6c63e3385fa73f8af3be4a69171e947f5a319d
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=docs/LICENSE.txt
PKG_MAINTAINER:=bol-van

# static variant links these from staging without depending on them at runtime;
# libcap only for the sys/capability.h header (capget/capset come from musl)
PKG_BUILD_DEPENDS:=libnetfilter-queue libmnl zlib libcap

LUAJIT_TAG:=v2.1-20260914
LUAJIT_TGZ:=luajit2-$(LUAJIT_TAG).tar.gz

include $(INCLUDE_DIR)/package.mk

ZAPRET_DIR:=/opt/zapret2

# Tools zapret2 only runs on the router. EXTRA_DEPENDS puts them into the apk
# metadata without making the SDK build them (curl, nftables and the kernel
# modules are most of the build time otherwise). apk on 25.12 requires a version
# constraint here, hence ">=0". Libraries nfqws2 links against stay in DEPENDS:
# they are needed at build time and give the ABI suffix (libnetfilter-queue1).
RUNTIME_DEPENDS:=nftables (>=0), kmod-nft-queue (>=0), curl (>=0)

define Package/zapret2/Default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Zapret2
  URL:=https://github.com/bol-van/zapret2
endef

define Package/zapret2
$(call Package/zapret2/Default)
  TITLE:=zapret2 DPI circumvention (dynamic)
  VARIANT:=dynamic
  DEFAULT_VARIANT:=1
  DEPENDS:=+libnetfilter-queue +libmnl +zlib +luajit2
  EXTRA_DEPENDS:=$(RUNTIME_DEPENDS)
endef

define Package/zapret2-static
$(call Package/zapret2/Default)
  TITLE:=zapret2 DPI circumvention (static binaries)
  VARIANT:=static
  PROVIDES:=zapret2
  CONFLICTS:=zapret2
  EXTRA_DEPENDS:=$(RUNTIME_DEPENDS)
endef

define Package/zapret2/description
  nfqws2, mdig, ip2net and the upstream OpenWrt init scripts,
  laid out under /opt/zapret2 the way upstream install_easy.sh does it.
  Configure in /opt/zapret2/config. Does nothing until NFQWS2_ENABLE=1.
endef
Package/zapret2-static/description=$(Package/zapret2/description)

define Package/zapret2/conffiles
$(ZAPRET_DIR)/config
$(ZAPRET_DIR)/ipset/zapret-hosts-user.txt
$(ZAPRET_DIR)/ipset/zapret-hosts-user-exclude.txt
$(ZAPRET_DIR)/ipset/zapret-hosts-user-ipban.txt
$(ZAPRET_DIR)/ipset/zapret-ip-user.txt
$(ZAPRET_DIR)/ipset/zapret-ip-user-exclude.txt
$(ZAPRET_DIR)/ipset/zapret-ip-user-ipban.txt
endef
Package/zapret2-static/conffiles=$(Package/zapret2/conffiles)

define Download/luajit2
  URL:=https://github.com/openresty/luajit2/archive/refs/tags
  URL_FILE:=$(LUAJIT_TAG).tar.gz
  FILE:=$(LUAJIT_TGZ)
  HASH:=a658a5596230c1564295b34303d64dee708956744de622f762e6a503b1a89236
endef
$(eval $(call Download,luajit2))

# Flags go through the environment, not make arguments: upstream Makefiles do
# "CFLAGS += -std=gnu99 ...", and a command-line CFLAGS would override that.
ifeq ($(BUILD_VARIANT),static)
  LUAJIT_DIR:=$(PKG_BUILD_DIR)/luajit
  LUA_FLAGS:=LUA_CFLAGS="-I$(LUAJIT_DIR)/src" LUA_LIB="$(LUAJIT_DIR)/src/libluajit.a"
  # -static instead of -pie; libgcc_eh carries the unwinder LuaJIT needs on arm64
  BUILD_ENV:=$(TARGET_CONFIGURE_OPTS) CFLAGS="$(TARGET_CFLAGS) -static" \
	LDFLAGS="$(TARGET_LDFLAGS) -static -lgcc_eh"
  MAKE_VARS:=LDFLAGS_PIE=
else
  LUA_FLAGS:=LUA_CFLAGS="-I$(STAGING_DIR)/usr/include/luajit-2.1" \
	LUA_LIB="-L$(STAGING_DIR)/usr/lib -lluajit-5.1"
  BUILD_ENV:=$(TARGET_CONFIGURE_OPTS) CFLAGS="$(TARGET_CFLAGS)" LDFLAGS="$(TARGET_LDFLAGS)"
  MAKE_VARS:=
endif

# LuaJIT builds host tools (minilua, buildvm) that must match the target word size
ifeq ($(CONFIG_ARCH_64BIT),)
  LUAJIT_HOST_BITS:=-m32
endif

define Build/Prepare
	$(call Build/Prepare/Default)
	$(if $(LUAJIT_DIR), \
		mkdir -p $(LUAJIT_DIR) && \
		$(TAR) -xzf $(DL_DIR)/$(LUAJIT_TGZ) --strip-components=1 -C $(LUAJIT_DIR))
endef

define Build/Compile
	$(if $(LUAJIT_DIR), \
		$(MAKE) $(PKG_JOBS) -C $(LUAJIT_DIR) \
			HOST_CC="$(HOSTCC) $(HOST_CFLAGS) $(LUAJIT_HOST_BITS)" \
			CROSS="$(TARGET_CROSS)" \
			TARGET_SYS=Linux \
			TARGET_CFLAGS="$(TARGET_CFLAGS)" \
			BUILDMODE=static)
	$(BUILD_ENV) $(MAKE) -C $(PKG_BUILD_DIR)/nfq2 $(LUA_FLAGS) $(MAKE_VARS)
	$(BUILD_ENV) $(MAKE) -C $(PKG_BUILD_DIR)/mdig $(MAKE_VARS)
	$(BUILD_ENV) $(MAKE) -C $(PKG_BUILD_DIR)/ip2net $(MAKE_VARS)
endef

define Package/zapret2/install
	# same set of files as copy_openwrt() in upstream install_easy.sh
	$(INSTALL_DIR) $(1)$(ZAPRET_DIR)/nfq2 $(1)$(ZAPRET_DIR)/mdig $(1)$(ZAPRET_DIR)/ip2net
	$(INSTALL_DIR) $(1)$(ZAPRET_DIR)/init.d $(1)$(ZAPRET_DIR)/tmp $(1)$(ZAPRET_DIR)/files
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/nfq2/nfqws2 $(1)$(ZAPRET_DIR)/nfq2/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mdig/mdig $(1)$(ZAPRET_DIR)/mdig/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ip2net/ip2net $(1)$(ZAPRET_DIR)/ip2net/
	$(CP) $(PKG_BUILD_DIR)/files/fake $(1)$(ZAPRET_DIR)/files/
	$(CP) $(PKG_BUILD_DIR)/common $(1)$(ZAPRET_DIR)/
	$(CP) $(PKG_BUILD_DIR)/ipset $(1)$(ZAPRET_DIR)/
	$(CP) $(PKG_BUILD_DIR)/blockcheck2.d $(1)$(ZAPRET_DIR)/
	$(CP) $(PKG_BUILD_DIR)/lua $(1)$(ZAPRET_DIR)/
	$(CP) $(PKG_BUILD_DIR)/init.d/openwrt $(1)$(ZAPRET_DIR)/init.d/
	$(CP) $(PKG_BUILD_DIR)/init.d/custom.d.examples.linux $(1)$(ZAPRET_DIR)/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/blockcheck2.sh $(1)$(ZAPRET_DIR)/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/config.default $(1)$(ZAPRET_DIR)/config.default
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/config.default $(1)$(ZAPRET_DIR)/config
	# user lists: exclude starts as upstream default (local nets only), the rest empty
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ipset/zapret-hosts-user-exclude.txt.default \
		$(1)$(ZAPRET_DIR)/ipset/zapret-hosts-user-exclude.txt
	touch $(1)$(ZAPRET_DIR)/ipset/zapret-hosts-user.txt
	touch $(1)$(ZAPRET_DIR)/ipset/zapret-hosts-user-ipban.txt
	touch $(1)$(ZAPRET_DIR)/ipset/zapret-ip-user.txt
	touch $(1)$(ZAPRET_DIR)/ipset/zapret-ip-user-exclude.txt
	touch $(1)$(ZAPRET_DIR)/ipset/zapret-ip-user-ipban.txt
	# init script and iface hook are symlinks, as install_easy.sh makes them;
	# the init script finds ZAPRET_BASE through "readlink /etc/init.d/zapret2"
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/hotplug.d/iface
	$(LN) $(ZAPRET_DIR)/init.d/openwrt/zapret2 $(1)/etc/init.d/zapret2
	$(LN) $(ZAPRET_DIR)/init.d/openwrt/90-zapret2 $(1)/etc/hotplug.d/iface/90-zapret2
endef
Package/zapret2-static/install=$(Package/zapret2/install)

$(eval $(call BuildPackage,zapret2))
$(eval $(call BuildPackage,zapret2-static))
