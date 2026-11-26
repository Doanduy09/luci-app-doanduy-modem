#!/bin/sh
# [VERIFIED-GOLDEN: part4-ram-soc-device-optimizer | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
# DOANDUY 5G Hardware-Universal Device Optimizer (RAM-Tier + SoC-Aware + Safe Rollback)
. /usr/share/libubox/jshn.sh

OPT_CONF="/etc/sysctl.d/99-doanduy-opt.conf"
LEGACY_CONF="/etc/sysctl.d/99-ram-beast-net.conf"

detect_hw() {
	HW_MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || uname -n)
	HW_ARCH=$(uname -m 2>/dev/null)
	HW_CORES=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
	[ "$HW_CORES" -ge 1 ] 2>/dev/null || HW_CORES=1
	MEM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 262144)
	MEM_FREE_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || awk '/MemFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
	MEM_MB=$((MEM_KB / 1024))
	MEM_AVAIL_MB=$((MEM_FREE_KB / 1024))
	FLASH_AVAIL=$(df -h /overlay 2>/dev/null | awk 'NR==2 {print $4 " / " $2 " (" $5 " used)"}')
	[ -n "$FLASH_AVAIL" ] || FLASH_AVAIL="N/A"

	SOC_TYPE="generic"
	SOC_LABEL="Generic Embedded ($HW_ARCH)"
	if lsmod 2>/dev/null | grep -qE '^qca_nss_drv|^ecm ' || [ -d /sys/kernel/debug/qca-nss-drv ] || [ -d /sys/kernel/debug/ecm ]; then
		SOC_TYPE="qualcomm_ipq_nss"
		SOC_LABEL="Qualcomm IPQ (NSS Hardware Offload)"
	elif [ -d /sys/kernel/debug/ppe ] || lsmod 2>/dev/null | grep -qE 'mtk_ppe|mt7915e|mt7986|mt76'; then
		SOC_TYPE="mediatek_filogic"
		SOC_LABEL="MediaTek Filogic / MTK"
	elif echo "$HW_ARCH" | grep -qE 'x86_64|i[3-6]86'; then
		SOC_TYPE="x86_64"
		SOC_LABEL="x86_64 Router / Mini PC"
	fi

	if [ "$MEM_MB" -le 128 ]; then
		RAM_TIER="Ultra-Low-RAM (<=128MB)"
		CFG_CONNTRACK=8192; CFG_BUF=262144; CFG_RDEF=131072; CFG_MINFREE=2048; CFG_SWAP=10
		CFG_BACKLOG=1000; CFG_SOMAX=512
	elif [ "$MEM_MB" -le 256 ]; then
		RAM_TIER="Low-RAM (129-256MB)"
		CFG_CONNTRACK=16384; CFG_BUF=1048576; CFG_RDEF=131072; CFG_MINFREE=4096; CFG_SWAP=10
		CFG_BACKLOG=2000; CFG_SOMAX=1024
	elif [ "$MEM_MB" -le 768 ]; then
		RAM_TIER="Mid-Tier (256-768MB)"
		CFG_CONNTRACK=65536; CFG_BUF=4194304; CFG_RDEF=262144; CFG_MINFREE=8192; CFG_SWAP=20
		CFG_BACKLOG=16384; CFG_SOMAX=8192
	else
		RAM_TIER="High-Tier (>=1GB)"
		CFG_CONNTRACK=131072; CFG_BUF=8388608; CFG_RDEF=262144; CFG_MINFREE=16384; CFG_SWAP=30
		CFG_BACKLOG=16384; CFG_SOMAX=8192
	fi

	TEMP_C=""
	for tf in /sys/class/thermal/thermal_zone*/temp; do
		[ -r "$tf" ] || continue
		t=$(cat "$tf" 2>/dev/null | tr -cd '0-9')
		[ -n "$t" ] || continue
		[ "$t" -gt 1000 ] && t=$((t / 1000))
		[ "$t" -ge 10 ] && [ "$t" -le 125 ] && { [ -z "$TEMP_C" ] || [ "$t" -gt "$TEMP_C" ]; } && TEMP_C="$t"
	done

	TCP_CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "cubic")
	AVAIL_CC=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "cubic")
	FLOW_SW=$(uci -q get firewall.@defaults[0].flow_offloading || echo 0)
	FLOW_HW=$(uci -q get firewall.@defaults[0].flow_offloading_hw || echo 0)
	ZRAM_MB=$(awk 'NR>1 && $1 ~ /zram/ {sum += $3} END {printf "%d", sum/1024}' /proc/swaps 2>/dev/null || echo 0)
	OPT_APPLIED=0
	[ -f "$OPT_CONF" ] && OPT_APPLIED=1
}

disable_wwan_powersave() {
	local p d cls
	for p in /sys/bus/usb/devices/*/power/control /sys/bus/mhi/devices/*/power/control; do
		[ -w "$p" ] && echo on > "$p" 2>/dev/null || true
	done
	for d in /sys/bus/pci/devices/*; do
		[ -r "$d/class" ] || continue
		cls=$(cat "$d/class" 2>/dev/null)
		case "$cls" in
			0x0d*) [ -w "$d/power/control" ] && echo on > "$d/power/control" 2>/dev/null || true ;;
		esac
	done
	[ -w /sys/module/usbcore/parameters/autosuspend ] && echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null || true
}

cmd_status() {
	detect_hw
	json_init
	json_add_boolean "success" 1
	json_add_string "model" "$HW_MODEL"
	json_add_string "soc_type" "$SOC_TYPE"
	json_add_string "soc_label" "$SOC_LABEL"
	json_add_int "cores" "$HW_CORES"
	json_add_int "mem_total_mb" "$MEM_MB"
	json_add_int "mem_avail_mb" "$MEM_AVAIL_MB"
	json_add_string "ram_tier" "$RAM_TIER"
	json_add_string "flash_info" "$FLASH_AVAIL"
	json_add_string "temp_c" "${TEMP_C:-N/A}"
	json_add_string "tcp_cc" "$TCP_CC"
	json_add_boolean "bbr_supported" "$(echo "$AVAIL_CC" | grep -q bbr && echo 1 || echo 0)"
	json_add_boolean "flow_offload" "$([ "$FLOW_SW" = "1" ] && echo 1 || echo 0)"
	json_add_boolean "flow_offload_hw" "$([ "$FLOW_HW" = "1" ] && echo 1 || echo 0)"
	json_add_int "zram_mb" "${ZRAM_MB:-0}"
	json_add_boolean "optimized" "$OPT_APPLIED"
	json_dump
}

cmd_apply() {
	detect_hw
	mkdir -p /etc/sysctl.d
	local cc="cubic" qdisc="fq_codel"
	if echo "$AVAIL_CC" | grep -qw bbr; then
		cc="bbr"
		lsmod 2>/dev/null | grep -q sch_fq && qdisc="fq"
	fi
	rm -f "$LEGACY_CONF" 2>/dev/null
	cat <<EOF > "$OPT_CONF"
# DOANDUY 5G Hardware-Adaptive Sysctl (${RAM_TIER} / ${SOC_TYPE})
net.netfilter.nf_conntrack_max = ${CFG_CONNTRACK}
net.core.rmem_default = ${CFG_RDEF}
net.core.wmem_default = ${CFG_RDEF}
net.core.rmem_max = ${CFG_BUF}
net.core.wmem_max = ${CFG_BUF}
net.ipv4.tcp_rmem = 4096 131072 ${CFG_BUF}
net.ipv4.tcp_wmem = 4096 65536 ${CFG_BUF}
net.core.netdev_max_backlog = ${CFG_BACKLOG}
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000
net.core.rps_sock_flow_entries = 16384
net.core.somaxconn = ${CFG_SOMAX}
net.core.default_qdisc = ${qdisc}
net.ipv4.tcp_congestion_control = ${cc}
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
vm.min_free_kbytes = ${CFG_MINFREE}
vm.swappiness = ${CFG_SWAP}
vm.vfs_cache_pressure = 60
EOF
	sysctl -p "$OPT_CONF" >/dev/null 2>&1 || true
	disable_wwan_powersave
	# Tự động tắt nft_flow_offload trên Qualcomm IPQ NSS để tránh xung đột qca-nss-ecm gây giật ping
	if [ "$SOC_TYPE" = "qualcomm_ipq_nss" ]; then
		if [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ] || [ "$(uci -q get firewall.@defaults[0].flow_offloading_hw)" = "1" ]; then
			uci -q set firewall.@defaults[0].flow_offloading='0'
			uci -q set firewall.@defaults[0].flow_offloading_hw='0'
			uci commit firewall
			/etc/init.d/firewall reload >/dev/null 2>&1 || true
		fi
	fi
	json_init
	json_add_boolean "success" 1
	json_add_string "message" "Đã áp dụng tối ưu chuẩn [${RAM_TIER} | ${SOC_LABEL}] (BBR/Sysctl/USB-PCIe Power On)!"
	json_dump
}

cmd_offload() {
	detect_hw
	local act="$1"
	if [ "$act" = "on" ] || [ "$act" = "1" ]; then
		if [ "$SOC_TYPE" = "qualcomm_ipq_nss" ]; then
			echo '{"success":false,"message":"Router đang chạy Qualcomm NSS 12.5! Đã chặn bật Flow Offload phần mềm để tránh xung đột NSS."}'
			return 0
		fi
		uci -q set firewall.@defaults[0].flow_offloading='1'
		if [ "$SOC_TYPE" = "mediatek_filogic" ]; then
			uci -q set firewall.@defaults[0].flow_offloading_hw='1'
		fi
		uci commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1
		echo '{"success":true,"message":"Đã BẬT Flow Offload phần cứng/nhân! Lưu ý: có thể bỏ qua ép TTL & MWAN3 trên luồng offload."}'
	else
		uci -q set firewall.@defaults[0].flow_offloading='0'
		uci -q set firewall.@defaults[0].flow_offloading_hw='0'
		uci commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1
		echo '{"success":true,"message":"Đã TẮT Flow Offload (Tương thích 100% ép TTL, MWAN3 & PassWall/VPN)."}'
	fi
}

cmd_reset() {
	rm -f "$OPT_CONF" "$LEGACY_CONF" 2>/dev/null
	sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
	sysctl -p /etc/sysctl.conf >/dev/null 2>&1 || true
	/etc/init.d/sysctl reload >/dev/null 2>&1 || true
	echo '{"success":true,"message":"Đã xóa cấu hình tối ưu và khôi phục sysctl mặc định OpenWrt!"}'
}

case "$1" in
	status) cmd_status ;;
	apply)  cmd_apply ;;
	offload) cmd_offload "$2" ;;
	reset)  cmd_reset ;;
	*)      cmd_status ;;
esac
# [/VERIFIED-GOLDEN]
