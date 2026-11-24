#!/bin/sh
# DOANDUY 5G Universal Tailscale Auto-Provisioner & Debian VM Mesh Bridge
. /usr/share/libubox/jshn.sh

LOCK_FILE="/var/run/doanduy_remote_auto.lock"
VAULT_FILE="/etc/config/doanduy_vault"
SECRETS_FILE="/etc/config/router_secrets.conf"
PERS_VAULT="/etc/config/personal_vault.conf"
LEGACY_VAULT="/etc/config/vault.conf"
TS_KEY_FILE="/etc/config/tailscale_authkey"
TS_DIS_FLAG="/etc/config/tailscale_disabled"

mkdir -p /var/run /etc/config /etc/tailscale /var/lib/tailscale 2>/dev/null

exec 202>"$LOCK_FILE"
if [ "$1" = "ensure" ]; then
	flock -n 202 2>/dev/null || exit 0
else
	flock -w 15 202 2>/dev/null || true
fi

read_kv() {
	[ -f "$1" ] || return 0
	local v
	v=$(awk -v k="$2" 'BEGIN{FS="="} {k0=$1; gsub(/^[ \t]+|[ \t]+$/,"",k0); if(k0==k){val=substr($0,index($0,"=")+1); gsub(/\r/,"",val)}} END{printf "%s", val}' "$1" 2>/dev/null)
	case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
	printf '%s' "$v"
}

read_tailscale_key() {
	local val="" v="" f
	for f in "$LEGACY_VAULT" "$SECRETS_FILE" "$PERS_VAULT" "$VAULT_FILE"; do
		[ -f "$f" ] || continue
		v=$(read_kv "$f" TAILSCALE_AUTH_KEY)
		[ -n "$v" ] && val="$v"
	done
	if [ -z "$val" ] && [ -f "$TS_KEY_FILE" ]; then
		val=$(head -n1 "$TS_KEY_FILE" 2>/dev/null | tr -d ' "\r\n\t')
	fi
	printf '%s' "$val"
}

find_ts_bin() {
	local b
	for b in /usr/sbin/tailscale /usr/bin/tailscale $(command -v tailscale 2>/dev/null); do
		[ -x "$b" ] && { printf '%s' "$b"; return 0; }
	done
	return 1
}

ensure_tailscale_binary() {
	mkdir -p /etc/tailscale /var/lib/tailscale /dev/net 2>/dev/null
	[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null

	if [ ! -x /usr/sbin/tailscaled ] && [ ! -x /usr/bin/tailscaled ]; then
		local pkg_f="" fetched_tmp=0 avail_kb=0
		pkg_f=$(ls /tmp/tailscale*.apk /rom/tailscale*.apk /etc/tailscale/tailscale*.apk 2>/dev/null | head -n 1)
		if [ -z "$pkg_f" ] && command -v apk >/dev/null 2>&1; then
			apk update --allow-untrusted >/dev/null 2>&1 || apk update >/dev/null 2>&1
			apk fetch --allow-untrusted -o /tmp tailscale >/dev/null 2>&1 || apk fetch -o /tmp tailscale >/dev/null 2>&1
			pkg_f=$(ls /tmp/tailscale*.apk 2>/dev/null | head -n 1)
			[ -n "$pkg_f" ] && fetched_tmp=1
		fi
		if [ -n "$pkg_f" ] && command -v apk >/dev/null 2>&1; then
			mkdir -p /tmp/ts_ext_tmp
			apk extract --allow-untrusted --destination /tmp/ts_ext_tmp "$pkg_f" >/dev/null 2>&1
			avail_kb=$(df -Pk /overlay 2>/dev/null | awk 'NR==2{print $4}')
			if [ -f /tmp/ts_ext_tmp/usr/sbin/tailscaled ]; then
				if [ "${avail_kb:-0}" -gt 35000 ]; then
					cp -f /tmp/ts_ext_tmp/usr/sbin/tailscaled /usr/sbin/tailscaled
				else
					mkdir -p /tmp/tailscaled_ram
					cp -f /tmp/ts_ext_tmp/usr/sbin/tailscaled /tmp/tailscaled_ram/tailscaled
					chmod +x /tmp/tailscaled_ram/tailscaled
					ln -sf /tmp/tailscaled_ram/tailscaled /usr/sbin/tailscaled
				fi
			fi
			if [ -f /tmp/ts_ext_tmp/usr/sbin/tailscale ] && [ ! -L /tmp/ts_ext_tmp/usr/sbin/tailscale ]; then
				[ "${avail_kb:-0}" -gt 35000 ] && cp -f /tmp/ts_ext_tmp/usr/sbin/tailscale /usr/sbin/tailscale
			fi
			[ -f /tmp/ts_ext_tmp/etc/init.d/tailscale ] && [ ! -f /etc/init.d/tailscale ] && cp -f /tmp/ts_ext_tmp/etc/init.d/tailscale /etc/init.d/tailscale
			rm -rf /tmp/ts_ext_tmp
			[ "$fetched_tmp" = "1" ] && rm -f /tmp/tailscale*.apk 2>/dev/null
		elif command -v opkg >/dev/null 2>&1; then
			opkg update >/dev/null 2>&1
			opkg install --nodeps tailscale >/dev/null 2>&1
		fi
	fi

	[ ! -x /usr/sbin/tailscaled ] && [ -x /usr/bin/tailscaled ] && ln -sf /usr/bin/tailscaled /usr/sbin/tailscaled 2>/dev/null
	[ -x /usr/sbin/tailscaled ] || return 1
	[ -e /usr/sbin/tailscale ] || ln -sf /usr/sbin/tailscaled /usr/sbin/tailscale 2>/dev/null
	[ -e /usr/bin/tailscale ] || ln -sf /usr/sbin/tailscale /usr/bin/tailscale 2>/dev/null
	chmod +x /usr/sbin/tailscaled /usr/sbin/tailscale 2>/dev/null

	if [ -f /etc/init.d/tailscale ] && ! grep -q 'userspace-networking' /etc/init.d/tailscale 2>/dev/null; then
		sed -i '/procd_append_param command --state/a \	if ! [ -d /sys/devices/virtual/misc/tun ] && ! lsmod 2>/dev/null | grep -q '\''^tun '\''; then procd_append_param command --tun=userspace-networking; fi' /etc/init.d/tailscale 2>/dev/null
	fi

	if [ ! -f /etc/init.d/tailscale ]; then
		cat << 'TS_INIT_EOF' > /etc/init.d/tailscale
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=99
STOP=10

start_service() {
	local state_file port std_err std_out fw_mode
	config_load tailscale 2>/dev/null
	config_get_bool std_out "settings" log_stdout 1
	config_get_bool std_err "settings" log_stderr 1
	config_get port "settings" port 41641
	config_get state_file "settings" state_file /etc/tailscale/tailscaled.state
	config_get fw_mode "settings" fw_mode nftables
	mkdir -p /etc/tailscale /var/lib/tailscale /dev/net
	[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null
	[ -x /usr/sbin/tailscaled ] || return 0
	/usr/sbin/tailscaled --cleanup 2>/dev/null
	procd_open_instance
	procd_set_param command /usr/sbin/tailscaled
	procd_set_param env TS_DEBUG_FIREWALL_MODE="$fw_mode"
	procd_append_param env TS_NO_LOGS_NO_SUPPORT=true
	procd_append_param command --port "$port"
	procd_append_param command --state "$state_file"
	if ! [ -d /sys/devices/virtual/misc/tun ] && ! lsmod 2>/dev/null | grep -q '^tun '; then
		procd_append_param command --tun=userspace-networking
	fi
	procd_set_param respawn 3600 5 0
	procd_set_param stdout "$std_out"
	procd_set_param stderr "$std_err"
	procd_close_instance
}

stop_service() {
	[ -x /usr/sbin/tailscaled ] && /usr/sbin/tailscaled --cleanup 2>/dev/null
}
TS_INIT_EOF
		chmod +x /etc/init.d/tailscale 2>/dev/null
	fi

	if [ ! -f /etc/config/tailscale ]; then
		cat << 'TS_CONF_EOF' > /etc/config/tailscale
config settings 'settings'
	option log_stderr '1'
	option log_stdout '1'
	option port '41641'
	option state_file '/etc/tailscale/tailscaled.state'
	option fw_mode 'nftables'
TS_CONF_EOF
	fi
	return 0
}

resolve_hostname() {
	local h mac4 model
	h=$(cat /etc/config/tailscale_hostname 2>/dev/null | tr -d '\r\n ')
	if [ -z "$h" ]; then
		h=$(uci -q get system.@system[0].hostname)
		case "$h" in
			""|OpenWrt|ImmortalWrt|DOANDUY|localhost)
				model=$(cat /tmp/sysinfo/model 2>/dev/null | tr -cs 'a-zA-Z0-9-' '-' | sed 's/^-//;s/-$//')
				mac4=$(cat /sys/class/net/br-lan/address 2>/dev/null | tr -d ':\r\n' | tail -c 5)
				h="${model:-router}-${mac4:-0001}"
				;;
		esac
	fi
	h=$(printf '%s' "$h" | tr -cs 'a-zA-Z0-9-' '-' | sed 's/^-//;s/-$//' | cut -c1-48)
	printf '%s' "${h:-doanduy-router}"
}

resolve_subnet() {
	local saved lan_ip
	saved=$(cat /etc/config/tailscale_subnet 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | head -n 1)
	[ -n "$saved" ] && { printf '%s' "$saved"; return 0; }
	lan_ip=$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d'/' -f1)
	[ -z "$lan_ip" ] && lan_ip=$(ip -4 addr show dev br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
	[ -z "$lan_ip" ] && lan_ip="192.168.1.1"
	printf '%s' "$lan_ip" | awk -F. '{print $1"."$2"."$3".0/24"}'
}

configure_vm_routing() {
	local net_chg=0 fw_chg=0 uh_chg=0 dh_chg=0 ts_zone=""
	if [ "$(uci -q get network.tailscale.device)" != "tailscale0" ]; then
		uci set network.tailscale=interface
		uci set network.tailscale.proto='none'
		uci set network.tailscale.device='tailscale0'
		net_chg=1
	fi
	if [ "$(uci -q get network.tailscale_cgnat.target)" != "100.64.0.0" ]; then
		uci set network.tailscale_cgnat=route
		uci set network.tailscale_cgnat.interface='tailscale'
		uci set network.tailscale_cgnat.target='100.64.0.0'
		uci set network.tailscale_cgnat.netmask='255.192.0.0'
		net_chg=1
	fi
	if [ "$(uci -q get network.tailscale_cgnat6.target)" != "fd7a:115c:a1e0::/48" ]; then
		uci set network.tailscale_cgnat6=route6
		uci set network.tailscale_cgnat6.interface='tailscale'
		uci set network.tailscale_cgnat6.target='fd7a:115c:a1e0::/48'
		net_chg=1
	fi
	[ "$net_chg" = "1" ] && { uci commit network; /etc/init.d/network reload >/dev/null 2>&1 & }

	ts_zone=$(uci show firewall 2>/dev/null | grep -i "\.name='tailscale'" | cut -d'.' -f2 | head -n 1)
	if [ -z "$ts_zone" ]; then
		ts_zone=$(uci add firewall zone)
		uci set "firewall.${ts_zone}.name=tailscale"
		uci set "firewall.${ts_zone}.input=ACCEPT"
		uci set "firewall.${ts_zone}.output=ACCEPT"
		uci set "firewall.${ts_zone}.forward=ACCEPT"
		uci set "firewall.${ts_zone}.masq=1"
		uci set "firewall.${ts_zone}.mtu_fix=1"
		uci set "firewall.${ts_zone}.device=tailscale0"
		uci add_list "firewall.${ts_zone}.network=tailscale" 2>/dev/null
		fw_chg=1
	fi
	if ! uci show firewall 2>/dev/null | grep -q "\.src='tailscale'"; then
		local f1 f2 f3
		f1=$(uci add firewall forwarding); uci set "firewall.${f1}.src=tailscale"; uci set "firewall.${f1}.dest=lan"
		f2=$(uci add firewall forwarding); uci set "firewall.${f2}.src=lan";       uci set "firewall.${f2}.dest=tailscale"
		f3=$(uci add firewall forwarding); uci set "firewall.${f3}.src=tailscale"; uci set "firewall.${f3}.dest=wan"
		fw_chg=1
	fi
	[ "$fw_chg" = "1" ] && { uci commit firewall; /etc/init.d/firewall restart >/dev/null 2>&1 & }

	if [ "$(uci -q get uhttpd.main.rfc1918_filter)" = "1" ]; then
		uci set uhttpd.main.rfc1918_filter='0'
		uci commit uhttpd
		/etc/init.d/uhttpd restart >/dev/null 2>&1 &
	fi
	if [ "$(uci -q get dhcp.@dnsmasq[0].localservice)" != "0" ]; then
		uci set dhcp.@dnsmasq[0].localservice='0'
		uci commit dhcp
		/etc/init.d/dnsmasq reload >/dev/null 2>&1 &
	fi
}

cmd_up() {
	local key_in="$1" enable_funnel="$2" quiet="$3"
	rm -f "$TS_DIS_FLAG" 2>/dev/null
	if ! ensure_tailscale_binary; then
		[ "$quiet" = "1" ] && return 1
		json_init
		json_add_boolean "success" 0
		json_add_string "message" "Không tự tải được gói Tailscale (kiểm tra kết nối 4G/WAN rồi thử lại)."
		json_dump
		return 1
	fi

	local ts_bin
	ts_bin=$(find_ts_bin)
	[ -n "$ts_bin" ] || return 1

	local key="$key_in" prev_key="" is_new=0
	[ -z "$key" ] && key=$(read_tailscale_key)
	prev_key=$(head -n1 "$TS_KEY_FILE" 2>/dev/null | tr -d ' "\r\n\t')

	if [ -n "$key" ]; then
		[ "$key" != "$prev_key" ] && is_new=1
		printf '%s\n' "$key" > "$TS_KEY_FILE"
		chmod 600 "$TS_KEY_FILE"
		touch "$VAULT_FILE"
		sed -i '/^TAILSCALE_AUTH_KEY=/d' "$VAULT_FILE" 2>/dev/null
		printf "TAILSCALE_AUTH_KEY='%s'\n" "$key" >> "$VAULT_FILE"
		chmod 600 "$VAULT_FILE"
	fi

	local hn subnet
	hn=$(resolve_hostname)
	subnet=$(resolve_subnet)

	if [ "$is_new" = "1" ] || [ ! -s /etc/tailscale/tailscaled.state ]; then
		/etc/init.d/tailscale stop >/dev/null 2>&1
		killall -9 tailscaled 2>/dev/null
		rm -f /etc/tailscale/tailscaled.state /var/lib/tailscale/tailscaled.state 2>/dev/null
		/etc/init.d/tailscale enable >/dev/null 2>&1 || true
		/etc/init.d/tailscale start >/dev/null 2>&1
		sleep 2
	elif ! pidof tailscaled >/dev/null 2>&1; then
		/etc/init.d/tailscale enable >/dev/null 2>&1 || true
		/etc/init.d/tailscale start >/dev/null 2>&1
		sleep 2
	fi

	configure_vm_routing

	set -- up "--hostname=$hn" "--advertise-routes=$subnet" --advertise-exit-node --accept-routes=true --accept-dns=false
	[ -n "$key" ] && set -- "$@" "--authkey=$key"
	[ "$is_new" = "1" ] && set -- "$@" --reset
	timeout 15 "$ts_bin" "$@" >/tmp/.ts_up.log 2>&1

	local wait_c=0 ts_ip=""
	while [ "$wait_c" -lt 8 ]; do
		ts_ip=$("$ts_bin" ip -4 2>/dev/null | grep -oE '100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n 1)
		[ -n "$ts_ip" ] && break
		sleep 1
		wait_c=$((wait_c + 1))
	done

	if [ -n "$ts_ip" ]; then
		printf '%s\n' "$ts_ip" > /etc/config/tailscale_ip
		if [ "$enable_funnel" = "1" ] || [ "$enable_funnel" = "true" ]; then
			"$ts_bin" serve --bg 80 >/dev/null 2>&1 || true
			"$ts_bin" funnel --bg 80 >/dev/null 2>&1 &
		fi
		[ "$quiet" = "1" ] && return 0
		json_init
		json_add_boolean "success" 1
		json_add_string "tailscale_ip" "$ts_ip"
		json_add_string "hostname" "$hn"
		json_add_string "subnet" "$subnet"
		json_add_string "message" "Đã tự động cài đặt, nối mạng Tailscale & Debian VM thành công! IP: ${ts_ip} (${hn})"
		json_dump
	else
		[ "$quiet" = "1" ] && return 1
		json_init
		json_add_boolean "success" 0
		json_add_string "message" "Chưa nhận được IP Tailscale. Kiểm tra Auth Key hoặc mạng WAN."
		json_dump
	fi
}

cmd_down() {
	touch "$TS_DIS_FLAG" 2>/dev/null
	local ts_bin
	ts_bin=$(find_ts_bin)
	if [ -n "$ts_bin" ]; then
		"$ts_bin" serve reset >/dev/null 2>&1 || true
		"$ts_bin" down >/dev/null 2>&1 || true
	fi
	/etc/init.d/tailscale stop >/dev/null 2>&1 || true
	/etc/init.d/tailscale disable >/dev/null 2>&1 || true
	json_init
	json_add_boolean "success" 1
	json_add_string "message" "Đã tắt Tailscale an toàn."
	json_dump
}

cmd_ensure() {
	[ -f "$TS_DIS_FLAG" ] && exit 0
	local key ts_bin cur_ip=""
	key=$(read_tailscale_key)
	[ -n "$key" ] || exit 0

	ts_bin=$(find_ts_bin)
	if [ -n "$ts_bin" ] && pidof tailscaled >/dev/null 2>&1; then
		cur_ip=$("$ts_bin" ip -4 2>/dev/null | grep -oE '100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n 1)
		if [ -n "$cur_ip" ]; then
			configure_vm_routing
			exit 0
		fi
	fi

	# Wait up to 30s for WAN readiness on cold boot before pulling/connecting
	local i=0 ready=0
	while [ "$i" -lt 10 ]; do
		if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1; then
			ready=1
			break
		fi
		sleep 3
		i=$((i + 1))
	done
	[ "$ready" = "1" ] || [ -x /usr/sbin/tailscaled ] || exit 0
	cmd_up "$key" "1" "1"
}

case "$1" in
	up)     cmd_up "$2" "$3" "0" ;;
	down)   cmd_down ;;
	ensure) cmd_ensure ;;
	*)      echo "Usage: $0 {up [key] [funnel]|down|ensure}"; exit 1 ;;
esac
