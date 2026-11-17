include $(TOPDIR)/rules.mk

PKG_NAME:=kai-agent
PKG_SOURCE_TAG:=kaiplus-runtime-v1.0.16
PKG_VERSION:=1.0.16
PKG_RELEASE:=10
PKG_SOURCE:=kai-agent-bundle-$(PKG_SOURCE_TAG).tar.gz
PKG_SOURCE_URL:=https://github.com/istoreos/istoreos-app-hub/releases/download/kai-runtime-v$(PKG_SOURCE_TAG)/
PKG_HASH:=skip
PKG_BUILD_DIR:=$(BUILD_DIR)/kai-agent-bundle-$(PKG_SOURCE_TAG)

PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=System
	TITLE:=KAI OpenCode Agent bundle
	URL:=https://github.com/linkease/kai-skills
endef

define Package/$(PKG_NAME)/description
  Versioned local OpenCode instructions and skills for KAI on iStoreOS.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/share/kai/agent-bundles/$(PKG_SOURCE_TAG)
	$(CP) $(PKG_BUILD_DIR)/agents $(1)/usr/share/kai/agent-bundles/$(PKG_SOURCE_TAG)/
	$(CP) $(PKG_BUILD_DIR)/skills $(1)/usr/share/kai/agent-bundles/$(PKG_SOURCE_TAG)/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/home-prompts.json $(1)/usr/share/kai/agent-bundles/$(PKG_SOURCE_TAG)/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/manifest.json $(1)/usr/share/kai/agent-bundles/$(PKG_SOURCE_TAG)/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/opencode.json $(1)/usr/share/kai/agent-bundles/$(PKG_SOURCE_TAG)/
	$(LN) agent-bundles/$(PKG_SOURCE_TAG) $(1)/usr/share/kai/agent
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
