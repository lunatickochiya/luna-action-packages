include $(TOPDIR)/rules.mk

PKG_NAME:=luci-lib-ipkg-compat
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=lunatickochiya

include $(INCLUDE_DIR)/package.mk

define Package/luci-lib-ipkg-compat
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Legacy luci.model.ipkg compatibility shim for apk
  DEPENDS:=+luci-base +luci-compat
  CONFLICTS:=luci-lib-ipkg
  PKGARCH:=all
endef

define Package/luci-lib-ipkg-compat/description
  Provides the opkg-era luci.model.ipkg Lua module backed by apk.
  Older LuCI applications still require this module on OpenWrt 25.12.
endef

define Build/Compile
endef

define Package/luci-lib-ipkg-compat/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model
	$(INSTALL_DATA) ./luasrc/model/ipkg.lua $(1)/usr/lib/lua/luci/model/ipkg.lua
endef

$(eval $(call BuildPackage,luci-lib-ipkg-compat))
