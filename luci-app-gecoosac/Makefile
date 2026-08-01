# Copyright (C) 2024 Openwrt.org
#
# This is free software, licensed under the GNU Affero General Public License v3.0 only.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-gecoosac

LUCI_TITLE:=LuCI Support for gecoosac
LUCI_DEPENDS:=+luci-base +gecoosac
LUCI_PKGARCH:=all
PKG_LICENSE:=AGPL-3.0-only

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
