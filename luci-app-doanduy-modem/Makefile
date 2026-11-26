#
# Copyright (C) 2026 DOANDUY <doanduy09@gmail.com>
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-doanduy-modem
PKG_VERSION:=2.4.1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=DOANDUY <doanduy09@gmail.com>

LUCI_TITLE:=Quản Trị Modem 5G PCIe & USB, SMS Engine, Auto-Renew, AI Sentinel & Điều Khiển Nhà
LUCI_DEPENDS:=+luci-base +rpcd +ubus +jsonfilter +atinout +curl +ca-bundle +lua +lua-cjson +luci-lib-nixio
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/doanduy_smarthome.json
/etc/config/doanduy_smarthome_keys.json
/etc/duytv_s06_config.json
/etc/config/sentinel_bots.json
/etc/config/sentinel_cameras.conf
/etc/config/allowed_iccids.dat
/etc/config/default_sim_iccid
/etc/config/doanduy_vault
/etc/config/doanduy_vault_multi.json
/etc/config/telegram_bot.conf
/etc/config/original_imei.dat
/etc/config/adshield_status
/etc/config/adshield_family
/etc/config/adshield_custom.conf
/etc/config/sms_custom_time.dat
/etc/config/sms_renew_package.dat
/etc/config/sms_renew_dest.dat
/etc/config/tailscale_authkey
/etc/config/tailscale_hostname
/etc/config/gemini_api.key
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
