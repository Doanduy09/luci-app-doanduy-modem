#!/bin/sh
. /lib/functions.sh
. /lib/netifd/netifd-proto.sh
init_proto "$@"

proto_duydoan5g_init_config() {
	available=1
	no_device=1
	no_proto_task=1
	proto_config_add_string "apn"
	proto_config_add_string "pincode"
	proto_config_add_string "metric"
}

proto_duydoan5g_setup() {
	local interface="$1"
	local apn pincode metric
	json_get_vars apn pincode metric

	[ -z "$apn" ] && apn="v-internet"
	local ifname="wwan0"
	[ -d "/sys/class/net/mhi_hwip0" ] && ifname="mhi_hwip0"

	logger -t duydoan5g "Starting 5G dialing on $ifname (APN: $apn)..."

	# Chờ thiết bị wwan0 và cổng mbim xuất hiện tối đa 30 giây khi router vừa boot
	local dev_ready=0
	for i in $(seq 1 30); do
		if [ -d "/sys/class/net/$ifname" ] && { [ -c "/dev/wwan0mbim0" ] || [ -c "/dev/cdc-wdm0" ]; }; then
			dev_ready=1
			break
		fi
		sleep 1
	done

	if [ "$dev_ready" -ne 1 ]; then
		logger -t duydoan5g "Error: Device $ifname or control port not ready after 30s!"
		proto_notify_error "$interface" NO_DEVICE
		return 1
	fi

	# Kích hoạt link interface UP trước khi chạy công cụ quay số
	ip link set dev "$ifname" up 2>/dev/null || true
	sleep 1

	killall -9 quectel-CM-M quectel-CM 2>/dev/null || true
	sleep 1

	mkdir -p /tmp/quectel_cm
	# Chạy quectel-CM-M chế độ MBIM (-s apn -4 -6). Không dùng -d (QMI) vì Sierra EM9190 là MBIM
	nohup /usr/bin/quectel-CM-M -i "$ifname" -s "$apn" -4 -6 > /tmp/quectel_cm/quectel-cm.log 2>&1 &
	echo $! > /var/run/duydoan5g.pid

	local count=0
	local cur_ip=""
	while [ $count -lt 25 ]; do
		sleep 1
		cur_ip=$(ip -4 addr show dev "$ifname" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
		[ -n "$cur_ip" ] && break
		count=$((count + 1))
	done

	if [ -n "$cur_ip" ]; then
		local mask=$(ip -4 addr show dev "$ifname" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f2)
		local gw=$(ip route show dev "$ifname" 2>/dev/null | grep default | awk '{print $3}')
		local ip6=$(ip -6 addr show dev "$ifname" scope global 2>/dev/null | grep 'inet6 ' | awk '{print $2}' | head -1)

		proto_init_update "$ifname" 1
		proto_add_ipv4_address "$cur_ip" "${mask:-30}"
		[ -n "$gw" ] && proto_add_ipv4_route 0.0.0.0 0 "$gw"
		proto_add_dns_server "8.8.8.8"
		proto_add_dns_server "1.1.1.1"

		if [ -n "$ip6" ]; then
			local ip6_addr=$(echo "$ip6" | cut -d/ -f1)
			local ip6_mask=$(echo "$ip6" | cut -d/ -f2)
			proto_add_ipv6_address "$ip6_addr" "${ip6_mask:-64}"
			proto_add_ipv6_route "::" 0
			proto_add_dns_server "2001:4860:4860::8888"
		fi

		proto_send_update "$interface"
		logger -t duydoan5g "Connected! IP: $cur_ip, GW: $gw, IPv6: $ip6"
	else
		logger -t duydoan5g "Timeout waiting for IP on $ifname"
		proto_notify_error "$interface" NO_IP
	fi
}

proto_duydoan5g_teardown() {
	local interface="$1"
	logger -t duydoan5g "Stopping 5G connection..."
	if [ -f /var/run/duydoan5g.pid ]; then
		kill -9 $(cat /var/run/duydoan5g.pid) 2>/dev/null
		rm -f /var/run/duydoan5g.pid
	fi
	killall -9 quectel-CM-M quectel-CM 2>/dev/null || true
	proto_init_update "*" 0
	proto_send_update "$interface"
}

add_protocol duydoan5g
