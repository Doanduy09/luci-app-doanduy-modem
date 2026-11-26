#!/bin/sh
# [VERIFIED-GOLDEN: part3-netifd-proto-duydoan5g | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
. /lib/functions.sh
. /lib/netifd/netifd-proto.sh
init_proto "$@"

proto_duydoan5g_init_config() {
	available=1
	no_device=1
	proto_config_add_string "apn"
	proto_config_add_string "pincode"
	proto_config_add_string "username"
	proto_config_add_string "password"
	proto_config_add_string "auth"
	proto_config_add_string "pdptype"
	proto_config_add_int "mtu"
	proto_config_add_int "delay"
	proto_config_add_string "pdp_index"
	proto_config_add_boolean "force_apn"
	proto_config_add_string "device"
	proto_config_add_defaults
}

proto_duydoan5g_setup() {
	local interface="$1"
	local apn pincode username password auth pdptype mtu delay metric pdp_index force_apn device
	json_get_vars apn pincode username password auth pdptype mtu delay metric pdp_index force_apn device

	[ -z "$apn" ] && apn="v-internet"
	[ -z "$pdptype" ] && pdptype="ipv4v6"
	[ -z "$mtu" ] && mtu="1460"
	[ -z "$metric" ] && metric="10"
	[ -z "$delay" ] && delay="0"
	[ -z "$force_apn" ] && force_apn="0"

	logger -t duydoan5g "Launching supervised 5G dialer for $interface (APN: $apn, PDP: $pdptype, MTU: $mtu)"
	proto_run_command "$interface" /usr/bin/duydoan5g_dialer.sh \
		"$interface" "$apn" "$pdptype" "$mtu" "$metric" "" "" "" "$auth" "$delay" "$pdp_index" "$force_apn" "$device"
}

proto_duydoan5g_teardown() {
	local interface="$1"
	logger -t duydoan5g "Gracefully stopping 5G dialer for $interface..."
	proto_kill_command "$interface" 15
	local w=0 pid=""
	while [ "$w" -lt 6 ]; do
		pid=$(cat "/var/run/duydoan5g_${interface}.pid" 2>/dev/null)
		[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || break
		sleep 1
		w=$((w + 1))
	done
	rm -f "/var/run/duydoan5g_${interface}.pid" "/tmp/quectel_dialing_${interface}" /var/run/duydoan5g.pid /tmp/quectel_dialing
}

add_protocol duydoan5g
# [/VERIFIED-GOLDEN]
