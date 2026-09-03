# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-tailscale
PKG_VERSION:=1.2.6
PKG_RELEASE:=2

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-tailscale
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Compatibility package for luci-app-tailscale-community
  DEPENDS:=+luci-app-tailscale-community
  PKGARCH:=all
endef

define Package/luci-app-tailscale/description
  Compatibility package that installs the Tailscale LuCI interface without
  replacing files owned by the OpenWrt tailscale package.
endef

define Build/Compile
endef

define Package/luci-app-tailscale/install
	true
endef

$(eval $(call BuildPackage,luci-app-tailscale))
