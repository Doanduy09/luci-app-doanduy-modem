#
# Copyright (C) 2026 DOANDUY <doanduy09@gmail.com>
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-doanduy-modem
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=DOANDUY <doanduy09@gmail.com>

LUCI_TITLE:=Quản Trị Modem 5G PCIe Sierra EM9190, SMS Engine, Auto-Renew & AI Sentinel
LUCI_DEPENDS:=+luci-base +rpcd +ubus +jsonfilter +kmod-mhi-bus +kmod-mhi-net +atinout
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/sentinel_bots.json
/etc/config/sentinel_cameras.conf
/etc/config/allowed_iccids.dat
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
$(eval $(call BuildPackage,$(PKG_NAME)))
