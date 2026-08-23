# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2024 OpenWrt.org

include $(TOPDIR)/rules.mk

PKG_NAME:=opencode2api
PKG_VERSION:=0.7.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/6Kmfi6HP/opencode2api/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip

PKG_LICENSE:=NOASSERTION
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=OpenWrt Developers <openwrt-devel@lists.openwrt.org>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/6Kmfi6HP/opencode2api
GO_PKG_BUILD_PKG:=github.com/6Kmfi6HP/opencode2api/cmd/opencode2api

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/opencode2api
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=OpenCode zen/go to OpenAI Codex/Anthropic Claude Code API proxy
  URL:=https://github.com/6Kmfi6HP/opencode2api
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/opencode2api/description
  OpenCode zen/go to OpenAI Codex/Anthropic Claude Code API proxy.
  Allows using OpenCode-compatible clients with Codex and Claude Code APIs.
endef

define Package/opencode2api/install
	$(call GoPackage/Package/Install/Bin,$(1))
endef

$(eval $(call GoBinPackage,opencode2api))
$(eval $(call BuildPackage,opencode2api))