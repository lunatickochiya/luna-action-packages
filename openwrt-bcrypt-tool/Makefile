include $(TOPDIR)/rules.mk

PKG_NAME:=bcrypt-tool
PKG_VERSION:=1.1.9
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/shoenig/bcrypt-tool.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=2c1169f6ce133e95d88f36f1a643d5ef33e23fb77a145e60a9bfe19562c51a34

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Douglas Orend <doug.orend2@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/bcrypt-tool-$(PKG_VERSION)
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/shoenig/bcrypt-tool

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/bcrypt-tool
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=CLI tool for generating and matching bcrypt hashes
  URL:=https://github.com/shoenig/bcrypt-tool
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/bcrypt-tool/description
  bcrypt-tool is a dandy CLI tool for generating and matching bcrypt hashes
endef

define Package/bcrypt-tool/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))

	$(INSTALL_DIR) $(1)/usr/bin/
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/bcrypt-tool $(1)/usr/bin/
endef

$(eval $(call GoBinPackage,bcrypt-tool))
$(eval $(call BuildPackage,bcrypt-tool))
