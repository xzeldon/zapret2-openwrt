# Ready-made, ISP-specific zapret2 scenarios. Files only, architecture independent.
# Nothing is applied on install: the user runs "zapret2-preset apply <name>".
#
# No DEPENDS on zapret2 on purpose: "+zapret2" would force the dynamic variant at
# build-config level, while zapret2-static (PROVIDES:=zapret2) is equally valid.
# The script checks for /opt/zapret2/config at run time and reports a clear error.

include $(TOPDIR)/rules.mk

PKG_NAME:=zapret2-presets
PKG_VERSION:=2026.10.09
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=xzeldon

PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/zapret2-presets
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Zapret2
  TITLE:=Ready-made zapret2 presets
  URL:=https://github.com/xzeldon/zapret2-openwrt
  PKGARCH:=all
endef

define Package/zapret2-presets/description
  ISP-specific zapret2 configurations and the zapret2-preset tool
  (list/show/apply). Presets are installed to /opt/zapret2/presets and are
  never applied automatically.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

# no conffiles: preset files are package-owned reference data
define Package/zapret2-presets/install
	$(INSTALL_DIR) $(1)/opt/zapret2/presets $(1)/usr/bin
	$(CP) $(CURDIR)/files/presets/. $(1)/opt/zapret2/presets/
	$(INSTALL_BIN) $(CURDIR)/files/zapret2-preset $(1)/usr/bin/zapret2-preset
endef

$(eval $(call BuildPackage,zapret2-presets))
