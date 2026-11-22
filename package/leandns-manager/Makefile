#
# Copyright (C) 2026 LeanDNS contributors
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=leandns-manager
PKG_VERSION:=1.0.1
PKG_RELEASE:=1

PKG_MAINTAINER:=LeanDNS <leandns@local>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/leandns-manager
  SECTION:=net
  CATEGORY:=Network
  TITLE:=LeanDNS lightweight smart DNS manager
  DEPENDS:=+dnsmasq +uhttpd +uhttpd-mod-ubus +rpcd +rpcd-mod-ucode +libubus +libuci
  PKGARCH:=all
endef

define Package/leandns-manager/description
  Lightweight AdGuard-like DNS management UI for OpenWrt.
  Uses dnsmasq and adblock-lean. Designed for 64MB RAM devices
  such as ASUS RT-AC750L (asus_rt-ac1200-v2).
endef

define Package/leandns-manager/conffiles
/etc/config/leandns
/etc/leandns/hosts
/etc/leandns/allow.list
/etc/leandns/block.list
/etc/adblock-lean/config
endef

define Build/Compile
endef

define Package/leandns-manager/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/etc/leandns
	$(INSTALL_DIR) $(1)/etc/adblock-lean
	$(INSTALL_DIR) $(1)/usr/lib/adblock-lean
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DIR) $(1)/usr/libexec/leandns
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/www
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_DIR) $(1)/www/leandns
	$(INSTALL_DIR) $(1)/www/leandns/css
	$(INSTALL_DIR) $(1)/www/leandns/js

	$(INSTALL_BIN) ./files/www/cgi-bin/luci $(1)/www/cgi-bin/luci
	$(INSTALL_BIN) ./files/www/cgi-bin/leandns-fw-upload $(1)/www/cgi-bin/leandns-fw-upload
	$(INSTALL_CONF) ./files/etc/config/leandns $(1)/etc/config/leandns



	$(INSTALL_BIN) ./files/etc/init.d/leandns $(1)/etc/init.d/leandns
	$(INSTALL_BIN) ./files/etc/init.d/leandns-stats $(1)/etc/init.d/leandns-stats
	$(INSTALL_BIN) ./files/etc/init.d/leandns-discover $(1)/etc/init.d/leandns-discover
	$(INSTALL_BIN) ./files/etc/init.d/adblock-lean $(1)/etc/init.d/adblock-lean
	$(INSTALL_DIR) $(1)/etc/rc.d
	$(LN) ../init.d/adblock-lean $(1)/etc/rc.d/S99adblock-lean
	$(LN) ../init.d/adblock-lean $(1)/etc/rc.d/K04adblock-lean
	$(INSTALL_BIN) ./files/etc/uci-defaults/99-leandns $(1)/etc/uci-defaults/99-leandns
	$(INSTALL_DATA) ./files/etc/leandns/hosts $(1)/etc/leandns/hosts
	$(INSTALL_DATA) ./files/etc/leandns/allow.list $(1)/etc/leandns/allow.list
	$(INSTALL_DATA) ./files/etc/leandns/block.list $(1)/etc/leandns/block.list
	$(INSTALL_DATA) ./files/etc/leandns/version $(1)/etc/leandns/version
	$(INSTALL_DATA) ./files/etc/adblock-lean/config $(1)/etc/adblock-lean/config
	$(INSTALL_DATA) ./files/etc/adblock-lean/config $(1)/etc/adblock-lean/config.mini
	$(INSTALL_DATA) ./files/etc/adblock-lean/abl-reg.md5 $(1)/etc/adblock-lean/abl-reg.md5
	$(INSTALL_DATA) ./files/etc/adblock-lean/VERSION $(1)/etc/adblock-lean/VERSION
	$(INSTALL_DATA) ./files/usr/lib/adblock-lean/abl-lib.sh $(1)/usr/lib/adblock-lean/abl-lib.sh
	$(INSTALL_DATA) ./files/usr/lib/adblock-lean/abl-process.sh $(1)/usr/lib/adblock-lean/abl-process.sh
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/leandns.json $(1)/usr/share/rpcd/acl.d/leandns.json
	$(INSTALL_DATA) ./files/usr/share/rpcd/ucode/leandns.uc $(1)/usr/share/rpcd/ucode/leandns.uc
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/leandns $(1)/usr/libexec/rpcd/leandns
	$(INSTALL_BIN) ./files/usr/sbin/leandns-discoverd $(1)/usr/sbin/leandns-discoverd
	$(INSTALL_BIN) ./files/usr/libexec/leandns/apply-dns.sh $(1)/usr/libexec/leandns/apply-dns.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/apply-network.sh $(1)/usr/libexec/leandns/apply-network.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/upstream-list.sh $(1)/usr/libexec/leandns/upstream-list.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/adblock-ctl.sh $(1)/usr/libexec/leandns/adblock-ctl.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/backup.sh $(1)/usr/libexec/leandns/backup.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/status.sh $(1)/usr/libexec/leandns/status.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/stats-ctl.sh $(1)/usr/libexec/leandns/stats-ctl.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/firmware-ctl.sh $(1)/usr/libexec/leandns/firmware-ctl.sh
	$(INSTALL_BIN) ./files/usr/libexec/leandns/www-root.sh $(1)/usr/libexec/leandns/www-root.sh
	$(INSTALL_BIN) ./files/usr/bin/leandns-validate $(1)/usr/bin/leandns-validate
	$(INSTALL_DATA) ./files/etc/leandns/upstream.list $(1)/etc/leandns/upstream.list
	$(CP) ./files/www/leandns/* $(1)/www/leandns/
	$(CP) -a ./files/www/index.html ./files/www/css ./files/www/js $(1)/www/
endef

define Package/leandns-manager/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/usr/libexec/leandns/www-root.sh >/dev/null 2>&1 || true
	/etc/init.d/leandns enable >/dev/null 2>&1 || true
	/etc/init.d/leandns-stats enable >/dev/null 2>&1 || true
	/etc/init.d/leandns-discover enable >/dev/null 2>&1 || true
	/etc/init.d/leandns-discover restart >/dev/null 2>&1 || true
	/etc/init.d/leandns-stats restart >/dev/null 2>&1 || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}
exit 0
endef

define Package/leandns-manager/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/leandns-stats stop >/dev/null 2>&1 || true
	/etc/init.d/leandns-stats disable >/dev/null 2>&1 || true
	/etc/init.d/leandns-discover stop >/dev/null 2>&1 || true
	/etc/init.d/leandns-discover disable >/dev/null 2>&1 || true
	/etc/init.d/leandns stop >/dev/null 2>&1 || true
	/etc/init.d/leandns disable >/dev/null 2>&1 || true
	for f in /www/index.html /www/css /www/js; do
		[ -L "$$f" ] || continue
		case "$$(readlink "$$f")" in
			leandns|leandns/*) rm -f "$$f" ;;
		esac
	done
	if [ -f /www/cgi-bin/luci ] && grep -q 'LeanDNS: luci-base' /www/cgi-bin/luci; then
		rm -f /www/cgi-bin/luci
	fi
}
exit 0
endef



$(eval $(call BuildPackage,leandns-manager))
