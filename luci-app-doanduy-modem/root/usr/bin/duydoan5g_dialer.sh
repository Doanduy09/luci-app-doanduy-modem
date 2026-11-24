#!/bin/sh
# DOANDUY 5G Supervised Netifd Dialer (QModem-Grade Lifecycle & MBIM/QMI/DHCP)
. /lib/functions.sh
. /lib/netifd/netifd-proto.sh

interface="$1"
apn="${2:-v-internet}"
pdptype="${3:-ipv4v6}"
mtu="${4:-1460}"
metric="${5:-10}"
pincode="$6"
username="$7"
password="$8"
auth="$9"
shift 9 2>/dev/null || shift $#
delay="${1:-0}"
user_pdp_index="$2"
force_apn="${3:-0}"
user_device="$4"

[ -n "$interface" ] || exit 1
[ -z "$pincode" ] && pincode=$(uci -q get "network.${interface}.pincode" 2>/dev/null)
[ -z "$username" ] && username=$(uci -q get "network.${interface}.username" 2>/dev/null)
[ -z "$password" ] && password=$(uci -q get "network.${interface}.password" 2>/dev/null)
[ -z "$user_device" ] && user_device=$(uci -q get "network.${interface}.device" 2>/dev/null)

sanitize_at_val() { printf '%s' "$1" | tr -d '"\r\n;\\'; }
apn=$(sanitize_at_val "$apn")
username=$(sanitize_at_val "$username")
password=$(sanitize_at_val "$password")
pincode=$(printf '%s' "$pincode" | tr -cd '0-9')
user_device=$(printf '%s' "$user_device" | tr -cd 'a-zA-Z0-9._/-')

case "$mtu" in ''|*[!0-9]*) mtu=1460 ;; esac
[ "$mtu" -lt 1280 ] && mtu=1280
[ "$mtu" -gt 1500 ] && mtu=1500
case "$metric" in ''|*[!0-9]*) metric=10 ;; esac
case "$delay" in ''|*[!0-9]*) delay=0 ;; esac
case "$user_pdp_index" in ''|*[!0-9]*) user_pdp_index="" ;; esac
[ "$force_apn" = "1" ] || force_apn=0

mkdir -p /var/lock /var/run /tmp/quectel_cm
acquire_fd_lock() {
    local fd="$1" secs="${2:-10}" w=0
    command -v flock >/dev/null 2>&1 || return 0
    while [ "$w" -lt "$secs" ]; do
        flock -x -n "$fd" 2>/dev/null && return 0
        sleep 1
        w=$((w + 1))
    done
    return 1
}
exec 8>"/var/lock/duydoan5g_${interface}.lock"
acquire_fd_lock 8 10 || exit 1

if [ "$interface" = "duydoan_5g" ]; then
    LOG_FILE="/tmp/quectel_cm/quectel-cm.log"
else
    LOG_FILE="/tmp/quectel_cm/${interface}.log"
fi
PID_FILE="/var/run/duydoan5g_${interface}.pid"
DIALING_FLAG="/tmp/quectel_dialing_${interface}"
PIN_FLAG="/var/run/duydoan5g_pin_${interface}"
STOP_REQ=0
CM_PID=""
CM_START=""
UDHCPC_PID=""
UDHCPC_START=""
ODHCP6C_PID=""
ODHCP6C_START=""
UMBIM_ACTIVE=0
UMBIM_TID=""
UMBIM_LAST_SIG=""
UMBIM_LAST_V4=""
UMBIM_LAST_V6=""
AT_DIAL_ACTIVE=0
CTRL_DEV=""
IFNAME=""
NET_DRV=""
MODE=""
AT_PORT=""
ATI_INFO=""
USB_VID=""
USB_PID=""
MODEM_VENDOR="unknown"
MODEM_PLATFORM="qualcomm"
MODEM_PDP_IDX="1"

stop_pid_graceful() {
    local p="$1" exp="$2"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 0
    if [ -n "$exp" ] && [ -r "/proc/$p/stat" ]; then
        [ "$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null)" = "$exp" ] || return 0
    fi
    kill -TERM "$p" 2>/dev/null || true
    local w=0
    while [ "$w" -lt 8 ]; do
        kill -0 "$p" 2>/dev/null || return 0
        sleep 1
        w=$((w + 1))
    done
    if [ -n "$exp" ] && [ -r "/proc/$p/stat" ]; then
        [ "$(awk '{print $22}' "/proc/$p/stat" 2>/dev/null)" = "$exp" ] || return 0
    fi
    kill -KILL "$p" 2>/dev/null || true
}

cleanup_and_exit() {
    STOP_REQ=1
    rm -f "$DIALING_FLAG"
    stop_pid_graceful "$CM_PID" "$CM_START"
    stop_pid_graceful "$UDHCPC_PID" "$UDHCPC_START"
    stop_pid_graceful "$ODHCP6C_PID" "$ODHCP6C_START"
    if [ "$UMBIM_ACTIVE" = "1" ] && [ -n "$UMBIM_TID" ] && [ -c "$CTRL_DEV" ]; then
        timeout 4 umbim -n -t "$UMBIM_TID" -d "$CTRL_DEV" disconnect >/dev/null 2>&1 || true
    fi
    if [ "$AT_DIAL_ACTIVE" = "1" ]; then
        at_hangup
    fi
    rm -f "$PID_FILE"
    exit 0
}
trap 'cleanup_and_exit' TERM INT HUP

if [ "$delay" -gt 0 ]; then
    d=0
    while [ "$d" -lt "$delay" ] && [ "$STOP_REQ" = "0" ]; do
        sleep 1
        d=$((d + 1))
    done
fi

bind_usb_option_driver() {
    local opt_new_id="/sys/bus/usb-serial/drivers/option1/new_id"
    [ -w "$opt_new_id" ] || return 0
    local udev udev_real vid pid bound=0
    for udev in /sys/bus/usb/devices/*; do
        [ -r "$udev/idVendor" ] && [ -r "$udev/idProduct" ] || continue
        udev_real=$(readlink -f "$udev" 2>/dev/null)
        [ -d "$udev_real" ] || continue
        vid=$(tr 'A-F' 'a-f' < "$udev/idVendor" 2>/dev/null)
        pid=$(tr 'A-F' 'a-f' < "$udev/idProduct" 2>/dev/null)
        case "${vid}:${pid}" in
            305a:1421|2dee:4d23|2dee:4d38|3466:3301|2c7c:8101|2c7c:0457|3763:3c93|\
            1782:4038|1782:4039|1782:4040|1782:4056|1782:4057|1782:4058|05c6:90d5)
                # Guard: never hijack already-bound DM/GPS/flash serial ports
                if ! find "$udev_real" -maxdepth 3 -name 'ttyUSB*' 2>/dev/null | grep -q .; then
                    logger -t duydoan5g "Binding option1 serial driver for USB ${vid}:${pid}"
                    echo "$vid $pid" > "$opt_new_id" 2>/dev/null && bound=1 || true
                fi
                ;;
        esac
    done
    [ "$bound" = "1" ] && sleep 1
    return 0
}

wake_hardware() {
    local f
    for f in /sys/bus/pci/devices/*/power/control /sys/bus/mhi/devices/*/power/control; do
        [ -f "$f" ] && echo on > "$f" 2>/dev/null || true
    done
    for f in /sys/bus/usb/devices/*/bConfigurationValue; do
        [ -f "$f" ] && [ -z "$(cat "$f" 2>/dev/null)" ] && echo 1 > "$f" 2>/dev/null || true
    done
    bind_usb_option_driver
}

detach_bridge_master() {
    [ -L "/sys/class/net/$IFNAME/master" ] && ip link set dev "$IFNAME" nomaster 2>/dev/null || true
}

netdev_driver() {
    local drv_path
    drv_path=$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)
    [ -n "$drv_path" ] && echo "${drv_path##*/}"
}

is_real_wwan_netdev() {
    local name="$1" real_path drv
    [ -n "$name" ] && [ -d "/sys/class/net/$name" ] || return 1
    case "$name" in
        lo|br-*|lan*|wan*|wlan*|phy*|mhi_swip*|erspan*|gre*|miireg) return 1 ;;
    esac
    real_path=$(readlink -f "/sys/class/net/$name" 2>/dev/null)
    case "$real_path" in
        */mhi*_IP_SW/*) return 1 ;;
    esac
    case "$name" in
        eth*)
            drv=$(netdev_driver "$name")
            case "$drv" in
                qmi_wwan|qmi_wwan_q|cdc_mbim|cdc_ncm|huawei_cdc_ncm|cdc_ether|rndis_host|sierra_net|cdc_subset|ipheth|GobiNet|mhi_net|mtk_t7xx|rmnet_nss)
                    return 0 ;;
                r8152|ax88179_178a|asix|nss-dp|igc|r8169|e1000e|stmmac|mvneta|mvpp2|mtk_soc_eth)
                    return 1 ;;
            esac
            case "$name" in
                eth0|eth1) return 1 ;;
            esac
            ;;
    esac
    return 0
}

heal_pcie_mhi_id() {
    local dev slot sys_sv sys_sd hw_ids hw_sv hw_sd w
    for dev in /sys/bus/pci/drivers/mhi-pci-generic/0000:*; do
        [ -d "$dev" ] && [ -r "$dev/config" ] || continue
        slot="${dev##*/}"
        [ -f "/tmp/.mhi_pcie_healed_${slot}" ] && continue
        sys_sv=$(tr 'A-F' 'a-f' < "$dev/subsystem_vendor" 2>/dev/null)
        sys_sd=$(tr 'A-F' 'a-f' < "$dev/subsystem_device" 2>/dev/null)
        hw_ids=$(hexdump -C -s 44 -n 4 "$dev/config" 2>/dev/null | awk 'NR==1 && NF>=5 {printf "0x%s%s 0x%s%s", tolower($3), tolower($2), tolower($5), tolower($4)}')
        [ -n "$hw_ids" ] || continue
        hw_sv="${hw_ids% *}"
        hw_sd="${hw_ids#* }"
        case "$hw_sv" in 0x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) continue ;; esac
        case "$hw_sd" in 0x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *) continue ;; esac
        [ "$hw_sv" = "0x0000" ] || [ "$hw_sv" = "0xffff" ] && continue
        [ "$hw_sd" = "0x0000" ] || [ "$hw_sd" = "0xffff" ] && continue
        [ "${hw_sv}:${hw_sd}" = "${sys_sv}:${sys_sd}" ] && continue

        touch "/tmp/.mhi_pcie_healed_${slot}"
        logger -t duydoan5g "PCIe MHI $slot Mission-Mode ID ($hw_sv:$hw_sd) differs from boot ID ($sys_sv:$sys_sd); rescanning"
        stop_competing_dialers
        echo "$slot" > /sys/bus/pci/drivers/mhi-pci-generic/unbind 2>/dev/null || true
        echo 1 > "/sys/bus/pci/devices/$slot/remove" 2>/dev/null || true
        sleep 1
        echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
        w=0
        while [ "$w" -lt 8 ] && [ "$STOP_REQ" = "0" ]; do
            if [ -d /sys/class/net/mhi_hwip0 ] || [ -d /sys/class/net/wwan0 ] || [ -d /sys/class/net/rmnet_mhi0 ]; then
                [ -e /dev/wwan0qmi0 ] || [ -e /dev/wwan0mbim0 ] || [ -e /dev/mhi_QMI0 ] && break
            fi
            sleep 1
            w=$((w + 1))
        done
    done
}

pick_mux_or_netdev() {
    local entry="$1" name="$2" sub cname
    for sub in "$entry/net"/* "/sys/class/net/$name/net"/*; do
        [ -e "$sub" ] || continue
        cname="${sub##*/}"
        if is_real_wwan_netdev "$cname"; then
            echo "$cname"
            return 0
        fi
    done
    is_real_wwan_netdev "$name" && { echo "$name"; return 0; }
    return 1
}

resolve_netdev_from_ctrl() {
    local sys_base="$1" fallback_list="$2" real_dir netdir entry name resolved parent_dir cand
    for netdir in "$sys_base/device/net" "$sys_base/net"; do
        [ -d "$netdir" ] || continue
        for entry in "$netdir"/*; do
            [ -e "$entry" ] || continue
            name="${entry##*/}"
            resolved=$(pick_mux_or_netdev "$entry" "$name") && { echo "$resolved"; return 0; }
        done
    done
    real_dir=$(readlink -f "$sys_base" 2>/dev/null)
    if [ -n "$real_dir" ]; then
        parent_dir="${real_dir%/*}"
        for entry in "$parent_dir/net"/*; do
            [ -e "$entry" ] || continue
            name="${entry##*/}"
            resolved=$(pick_mux_or_netdev "$entry" "$name") && { echo "$resolved"; return 0; }
        done
    fi
    for cand in $fallback_list; do
        is_real_wwan_netdev "$cand" && { echo "$cand"; return 0; }
    done
    return 1
}

matches_user_device() {
    [ -z "$user_device" ] && return 0
    [ "$1" = "$user_device" ] || { [ -n "$2" ] && [ "$2" = "$user_device" ]; }
}

detect_endpoint() {
    while [ "$STOP_REQ" = "0" ]; do
        heal_pcie_mhi_id
        IFNAME=""; CTRL_DEV=""; NET_DRV=""; MODE=""
        local entry d b net drv cand

        # 1. PCIe MediaTek T7xx FIRST (Fibocom FM350-GL exposes /dev/wwan*mbim* alongside mtk_t7xx)
        for entry in /sys/class/net/*; do
            [ -e "$entry" ] || continue
            net="${entry##*/}"
            is_real_wwan_netdev "$net" || continue
            drv=$(netdev_driver "$net")
            if [ "$drv" = "mtk_t7xx" ]; then
                for d in /dev/wwan*mbim*; do
                    [ -c "$d" ] && { CTRL_DEV="$d"; break; }
                done
                matches_user_device "$net" "$CTRL_DEV" || continue
                IFNAME="$net"; NET_DRV="$drv"; MODE="mtk_pcie"
                return 0
            fi
        done

        # 2. PCIe MHI QMI (Sierra EM919x, Quectel RM5xxQ/RM520N Raw-IP hardware path)
        for d in /dev/wwan*qmi* /dev/mhi_QMI*; do
            [ -c "$d" ] || continue
            b="${d##*/}"
            net=$(resolve_netdev_from_ctrl "/sys/class/wwan/$b" "mhi_hwip0 rmnet_mhi0.1 rmnet_mhi0 wwan0")
            if is_real_wwan_netdev "$net" && matches_user_device "$net" "$d"; then
                CTRL_DEV="$d"; IFNAME="$net"; NET_DRV=$(netdev_driver "$net"); MODE="cm_qmi"
                return 0
            fi
        done

        # 3. PCIe MHI MBIM (Foxconn T99W175/T99W373/T99W640/DW5930e/SDX55, non-MTK)
        for d in /dev/wwan*mbim* /dev/mhi_MBIM*; do
            [ -c "$d" ] || continue
            b="${d##*/}"
            net=$(resolve_netdev_from_ctrl "/sys/class/wwan/$b" "wwan0 mhi_hwip0")
            if is_real_wwan_netdev "$net" && matches_user_device "$net" "$d"; then
                CTRL_DEV="$d"; IFNAME="$net"; NET_DRV=$(netdev_driver "$net"); MODE="cm_mbim"
                return 0
            fi
        done

        # 4. USB QMI / MBIM / GobiNet
        for d in /dev/cdc-wdm* /dev/qcqmi*; do
            [ -c "$d" ] || continue
            b="${d##*/}"
            case "$d" in
                /dev/qcqmi*) net=$(resolve_netdev_from_ctrl "/sys/class/GobiQMI/$b" "wwan0 eth2 usb0") ;;
                *) net=$(resolve_netdev_from_ctrl "/sys/class/usbmisc/$b" "wwan0 usb0 eth2") ;;
            esac
            if is_real_wwan_netdev "$net" && matches_user_device "$net" "$d"; then
                CTRL_DEV="$d"; IFNAME="$net"; NET_DRV=$(netdev_driver "$net"); MODE="cm_usb"
                return 0
            fi
        done

        # 5. USB ECM / NCM / RNDIS / SierraNet / HiLink / iPhone tether
        for entry in /sys/class/net/*; do
            [ -e "$entry" ] || continue
            net="${entry##*/}"
            is_real_wwan_netdev "$net" || continue
            matches_user_device "$net" "" || continue
            drv=$(netdev_driver "$net")
            case "$drv" in
                cdc_ncm|huawei_cdc_ncm|cdc_ether|rndis_host|sierra_net|cdc_subset|ipheth)
                    IFNAME="$net"; NET_DRV="$drv"; MODE="at_dhcp"
                    return 0
                    ;;
            esac
        done
        for cand in usb0 rndis0 eth2; do
            is_real_wwan_netdev "$cand" || continue
            matches_user_device "$cand" "" || continue
            drv=$(netdev_driver "$cand")
            case "$drv" in
                r8152|ax88179_178a|asix|nss-dp|igc|r8169|e1000e) continue ;;
            esac
            IFNAME="$cand"; NET_DRV="$drv"; MODE="at_dhcp"
            return 0
        done

        sleep 2
    done
    return 1
}

safe_at_once() {
    local port="$1" cmd="$2"
    [ -c "$port" ] && [ -n "$cmd" ] || return 1
    case "$port" in
        /dev/wwan*|/dev/mhi*)
            if [ -x /usr/bin/read_pcie_sms.lua ]; then
                timeout 4 /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null && return 0
            fi
            if command -v tom_modem >/dev/null 2>&1; then
                timeout 4 tom_modem -d "$port" -c "$cmd" 2>/dev/null && return 0
            fi
            if command -v sms_tool >/dev/null 2>&1; then
                timeout 4 sms_tool -d "$port" at "$cmd" 2>/dev/null && return 0
            fi
            return 1
            ;;
        *)
            (
                acquire_fd_lock 9 4 || true
                if command -v stty >/dev/null 2>&1; then
                    stty -F "$port" 115200 raw -echo -echoe -echok -echoctl -echoke -icrnl -onlcr 2>/dev/null || true
                fi
                if command -v atinout >/dev/null 2>&1; then
                    printf '%s\n' "$cmd" | timeout 2 atinout - "$port" - 2>/dev/null && exit 0
                fi
                if command -v tom_modem >/dev/null 2>&1; then
                    timeout 3 tom_modem -d "$port" -c "$cmd" 2>/dev/null && exit 0
                fi
                if command -v sms_tool >/dev/null 2>&1; then
                    timeout 3 sms_tool -d "$port" at "$cmd" 2>/dev/null && exit 0
                fi
                if [ -x /usr/bin/read_pcie_sms.lua ]; then
                    timeout 3 /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null && exit 0
                fi
                exit 1
            ) 9>/var/lock/modem_at.lock 2>/dev/null
            return $?
            ;;
    esac
}

stop_competing_dialers() {
    local procs="quectel-CM-M quectel-CM quectel-cm umbim"
    local p cmd match targets="" cm_if_cmp="$IFNAME" i=0 alive
    if [ -z "$IFNAME" ] && [ -z "$CTRL_DEV" ]; then
        if pidof $procs >/dev/null 2>&1; then
            killall -TERM $procs 2>/dev/null || true
            while [ "$i" -lt 3 ] && pidof $procs >/dev/null 2>&1; do
                sleep 1
                i=$((i + 1))
            done
            pidof $procs >/dev/null 2>&1 && killall -KILL $procs 2>/dev/null || true
        fi
        return 0
    fi
    case "$IFNAME" in
        wwan*_*) cm_if_cmp="${IFNAME%%_*}" ;;
        rmnet*.*) cm_if_cmp="${IFNAME%%.*}" ;;
    esac
    for p in $(pidof $procs 2>/dev/null); do
        cmd=$(tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null)
        match=0
        [ -n "$IFNAME" ] && case "$cmd" in *"$IFNAME"*) match=1 ;; esac
        [ -n "$cm_if_cmp" ] && case "$cmd" in *"$cm_if_cmp"*) match=1 ;; esac
        [ -n "$CTRL_DEV" ] && case "$cmd" in *"$CTRL_DEV"*) match=1 ;; esac
        [ "$match" = "1" ] && targets="$targets $p"
    done
    [ -n "$targets" ] || return 0
    for p in $targets; do kill -TERM "$p" 2>/dev/null || true; done
    while [ "$i" -lt 3 ]; do
        alive=0
        for p in $targets; do kill -0 "$p" 2>/dev/null && alive=1; done
        [ "$alive" = "0" ] && break
        sleep 1
        i=$((i + 1))
    done
    for p in $targets; do kill -KILL "$p" 2>/dev/null || true; done
}

extract_cgpaddr_ipv4() {
    echo "$1" | tr '," ' '\n' | awk '/^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $0 != "0.0.0.0" {print; exit}'
}

extract_cgpaddr_ipv6() {
    echo "$1" | tr '," ' '\n' | awk '/^[0-9A-Fa-f:]+:[0-9A-Fa-f:]+$/ && $0 != "::" {print; exit}'
}

extract_gtdns_ipv4() {
    echo "$1" | tr '," ' '\n' | awk '/^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $0 != "0.0.0.0" {printf "%s ", $0}'
}

read_usb_ids_for_netdev() {
    USB_VID=""; USB_PID=""
    local base="" raw rel d
    for raw in "/sys/class/net/$IFNAME/device" "/sys/class/tty/${AT_PORT##*/}/device"; do
        base=$(readlink -f "$raw" 2>/dev/null)
        [ -d "$base" ] || continue
        for rel in "" "/.." "/../.." "/../../.."; do
            d="${base}${rel}"
            if [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ]; then
                USB_VID=$(tr 'A-F' 'a-f' < "$d/idVendor" 2>/dev/null)
                USB_PID=$(tr 'A-F' 'a-f' < "$d/idProduct" 2>/dev/null)
                return 0
            fi
        done
    done
    return 1
}

find_usb_root_for_netdev() {
    local base rel d
    base=$(readlink -f "/sys/class/net/$IFNAME/device" 2>/dev/null)
    [ -d "$base" ] || return 1
    for rel in "" "/.." "/../.."; do
        d="${base}${rel}"
        if [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ]; then
            readlink -f "$d" 2>/dev/null
            return 0
        fi
    done
    return 1
}

append_unique_port() {
    local p="$1"
    [ -c "$p" ] || return 0
    case " $CAND_PORTS " in
        *" $p "*) ;;
        *) CAND_PORTS="$CAND_PORTS $p" ;;
    esac
}

find_working_at_port() {
    AT_PORT=""; ATI_INFO=""
    local CAND_PORTS=""
    read_usb_ids_for_netdev || true
    local usb_root prio_ifnums="" ifnum ifdir tpath p out cgmm
    usb_root=$(find_usb_root_for_netdev 2>/dev/null || true)

    case "${USB_VID}:${USB_PID}" in
        0e8d:7126|0e8d:7127) prio_ifnums="04 03" ;;
        2c7c:0457) prio_ifnums="02 07" ;;
        2c7c:0800|2c7c:0801|2c7c:0900|2c7c:0125|2c7c:0121|2c7c:0306|2c7c:0512|2c7c:0620|2c7c:030b|2c7c:030e|2c7c:0316|2c7c:0435|2c7c:6005) prio_ifnums="02 03" ;;
        1199:9071|1199:9079|1199:9091|1199:90b1|1199:90d2|1199:90d3) prio_ifnums="02 03" ;;
        2cb7:0104|2cb7:0105|2cb7:0106|2cb7:010a|2cb7:010d|2cb7:0112) prio_ifnums="02 03" ;;
        1e0e:9011) prio_ifnums="04 05" ;;
        1782:4e00) prio_ifnums="00 03" ;;
        305a:1421|305a:1404) prio_ifnums="01" ;;
        2dee:4d23) prio_ifnums="01" ;;
        2dee:4d38) prio_ifnums="03" ;;
        3763:3c93) prio_ifnums="01" ;;
        1782:4038|1782:4039|1782:4040|1782:4056|1782:4057|1782:4058) prio_ifnums="02" ;;
        05c6:90d5) prio_ifnums="02 03 05" ;;
    esac

    if [ -n "$usb_root" ] && [ -d "$usb_root" ]; then
        for ifnum in $prio_ifnums; do
            for ifdir in "$usb_root"/*; do
                [ -r "$ifdir/bInterfaceNumber" ] || continue
                [ "$(cat "$ifdir/bInterfaceNumber" 2>/dev/null)" = "$ifnum" ] || continue
                for tpath in $(find "$ifdir" -maxdepth 3 \( -name 'ttyUSB[0-9]*' -o -name 'ttyACM[0-9]*' \) 2>/dev/null | sort); do
                    append_unique_port "/dev/${tpath##*/}"
                done
            done
        done
        for tpath in $(find "$usb_root" -maxdepth 4 \( -name 'ttyUSB[0-9]*' -o -name 'ttyACM[0-9]*' \) 2>/dev/null | sort); do
            append_unique_port "/dev/${tpath##*/}"
        done
    else
        # Global fallback only for PCIe / non-USB modems to avoid USB/PCIe AT cross-talk
        for p in /dev/wwan0at0 /dev/wwan0at1 /dev/mhi_DUN /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB4 /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyACM1 /dev/ttyFMI0; do
            append_unique_port "$p"
        done
    fi

    for p in $CAND_PORTS; do
        [ -c "$p" ] || continue
        out=$(safe_at_once "$p" "ATI" | head -c 512)
        if echo "$out" | grep -qE '(^|[[:space:]])OK([[:space:]]|$)|Sierra|Quectel|Fibocom|FIBOCOM|FM350|Huawei|HUAWEI|Simcom|SIMCOM|Meig|MeiG|Neoway|Gosuncn|Telit|Thales|Cinterion|Air724|OpenLuat'; then
            AT_PORT="$p"; ATI_INFO="$out"
            case "$ATI_INFO" in
                *Sierra*|*Quectel*|*Fibocom*|*FIBOCOM*|*FM350*|*Huawei*|*HUAWEI*|*Simcom*|*SIMCOM*|*Meig*|*MeiG*|*Neoway*|*Gosuncn*|*Telit*|*Thales*|*Air724*) ;;
                *)
                    cgmm=$(safe_at_once "$p" "AT+CGMM" | head -c 256)
                    [ -n "$cgmm" ] && ATI_INFO="${ATI_INFO} ${cgmm}"
                    ;;
            esac
            echo "$AT_PORT" > /tmp/master_sms_port 2>/dev/null || true
            return 0
        fi
    done
    return 1
}

detect_modem_profile() {
    read_usb_ids_for_netdev || true
    MODEM_VENDOR="unknown"
    MODEM_PLATFORM="qualcomm"
    MODEM_PDP_IDX="1"

    local vinfo="${USB_VID}:${USB_PID}|${NET_DRV}|${ATI_INFO}"
    case "$vinfo" in
        *mtk_t7xx*|0e8d:*|*FM350*|*T700*)
            MODEM_VENDOR="fibocom"
            MODEM_PLATFORM="mediatek"
            [ "$NET_DRV" = "mtk_t7xx" ] && MODEM_PDP_IDX="0" || MODEM_PDP_IDX="1"
            ;;
        2c7c:*|*Quectel*)
            MODEM_VENDOR="quectel"
            case "$ATI_INFO" in
                *RG801*|*RG500H*|*HiSilicon*|*Hisilicon*) MODEM_PLATFORM="hisilicon" ;;
                *RM500U*|*RG500U*|*RG200U*|*EC200U*|*Unisoc*) MODEM_PLATFORM="unisoc" ;;
                *) MODEM_PLATFORM="qualcomm" ;;
            esac
            ;;
        2cb7:*|1508:*|*Fibocom*|*FIBOCOM*)
            MODEM_VENDOR="fibocom"
            case "$ATI_INFO" in
                *FM350*|*T700*|*MTK*)
                    MODEM_PLATFORM="mediatek"
                    [ "$NET_DRV" = "mtk_t7xx" ] && MODEM_PDP_IDX="0" || MODEM_PDP_IDX="1"
                    ;;
                *FG650*|*FM650*|*NL668*|*L610*|*Unisoc*) MODEM_PLATFORM="unisoc" ;;
                *) MODEM_PLATFORM="qualcomm" ;;
            esac
            ;;
        1199:*|*Sierra*)
            MODEM_VENDOR="sierra"
            MODEM_PLATFORM="qualcomm"
            ;;
        413c:*|05c6:*|*Foxconn*|*T99W*|*DW593*)
            MODEM_VENDOR="foxconn"
            MODEM_PLATFORM="qualcomm"
            ;;
        1782:*)
            case "${USB_PID}|${ATI_INFO}" in
                4e00*|*Air724*|*OpenLuat*)
                    MODEM_VENDOR="openluat"
                    MODEM_PLATFORM="unisoc"
                    MODEM_PDP_IDX="5"
                    ;;
                *Fibocom*|*FIBOCOM*|*FM650*|*FG650*|*L610*)
                    MODEM_VENDOR="fibocom"
                    MODEM_PLATFORM="unisoc"
                    ;;
                *MeiG*|*Meig*|*MEIG*|*SRM821*)
                    MODEM_VENDOR="meig"
                    MODEM_PLATFORM="unisoc"
                    ;;
                4038*|4039*|4040*|*Neoway*|*NU313*|*N510*)
                    MODEM_VENDOR="neoway"
                    MODEM_PLATFORM="unisoc"
                    ;;
                *)
                    MODEM_VENDOR="huawei"
                    MODEM_PLATFORM="unisoc"
                    ;;
            esac
            ;;
        12d1:*|12dc:*|3466:*|*Huawei*|*HUAWEI*|*MT5700*|*MH5000*)
            MODEM_VENDOR="huawei"
            MODEM_PLATFORM="hisilicon"
            ;;
        1e0e:*|1a0e:*|*Simcom*|*SIMCOM*)
            MODEM_VENDOR="simcom"
            case "$ATI_INFO" in
                *A7600*|*A7670*|*ASR*) MODEM_PLATFORM="asrmicro" ;;
                *SIM7600*|*SIM7100*) MODEM_PLATFORM="lte" ;;
                *) MODEM_PLATFORM="qualcomm" ;;
            esac
            ;;
        2dee:*|*Meig*|*MeiG*|*SRM8*)
            MODEM_VENDOR="meig"
            MODEM_PLATFORM="qualcomm"
            ;;
        1bc7:*|*Telit*|*FN980*|*FN990*|*LM960*)
            MODEM_VENDOR="telit"
            MODEM_PLATFORM="qualcomm"
            ;;
        305a:*|*Gosuncn*|*GM800*|*GM500*)
            MODEM_VENDOR="gosuncn"
            MODEM_PLATFORM="lte"
            ;;
        1e2d:*|*Thales*|*Cinterion*|*MV31*|*MV32*)
            MODEM_VENDOR="thales"
            MODEM_PLATFORM="qualcomm"
            ;;
        3763:*|*Neoway*)
            MODEM_VENDOR="neoway"
            MODEM_PLATFORM="unisoc"
            ;;
        *Air724*|*OpenLuat*)
            MODEM_VENDOR="openluat"
            MODEM_PLATFORM="unisoc"
            MODEM_PDP_IDX="5"
            ;;
    esac

    [ -n "$user_pdp_index" ] && MODEM_PDP_IDX="$user_pdp_index"
    if [ "$MODE" = "at_dhcp" ] && [ "$MODEM_VENDOR" = "fibocom" ] && [ "$MODEM_PLATFORM" = "mediatek" ]; then
        MODE="fm350_usb"
    fi
}

sync_sim_status() {
    [ -c "$AT_PORT" ] || return 0
    local iccid="" cmd out
    for cmd in "AT+ICCID" "AT+QCCID" "AT+CCID"; do
        out=$(safe_at_once "$AT_PORT" "$cmd" | head -c 256)
        iccid=$(echo "$out" | grep -oE '[0-9]{18,22}' | head -n 1)
        [ -n "$iccid" ] && break
    done
    [ -n "$iccid" ] || return 0
    echo "$iccid" > /tmp/sms_current_iccid 2>/dev/null || true
    if [ -x /usr/bin/sms_security_guardian ]; then
        /usr/bin/sms_security_guardian check >/dev/null 2>&1 || true
    elif [ -f /etc/config/allowed_iccids.dat ]; then
        if grep -qx "$iccid" /etc/config/allowed_iccids.dat 2>/dev/null; then
            echo "VALID" > /tmp/master_sim_status 2>/dev/null || true
        else
            echo "LOCKED" > /tmp/master_sim_status 2>/dev/null || true
        fi
    fi
}

wait_modem_ready() {
    [ -c "$AT_PORT" ] || return 0
    local w=0 cpin_out reg_out cmd
    while [ "$w" -lt 3 ] && [ "$STOP_REQ" = "0" ]; do
        cpin_out=$(safe_at_once "$AT_PORT" "AT+CPIN?")
        echo "$cpin_out" | grep -qiE '\+CPIN:[[:space:]]*READY' && break
        w=$((w + 1))
        [ "$w" -lt 3 ] && sleep 2
    done

    w=0
    while [ "$w" -lt 5 ] && [ "$STOP_REQ" = "0" ]; do
        for cmd in "AT+C5GREG?" "AT+CEREG?" "AT+CREG?"; do
            reg_out=$(safe_at_once "$AT_PORT" "$cmd")
            if echo "$reg_out" | grep -qE '\+(C5GREG|CEREG|CREG):[[:space:]]*[0-9]+,[[:space:]]*(1|5)([^0-9]|$)'; then
                return 0
            fi
        done
        w=$((w + 1))
        [ "$w" -lt 5 ] && sleep 2
    done
    return 0
}

write_modem_meta() {
    local usb_root="" usb_mfg="" usb_prod="" m_model="" m_rev="" m_imei=""
    usb_root=$(find_usb_root_for_netdev 2>/dev/null || true)
    if [ -n "$usb_root" ] && [ -d "$usb_root" ]; then
        [ -r "$usb_root/manufacturer" ] && usb_mfg=$(cat "$usb_root/manufacturer" 2>/dev/null)
        [ -r "$usb_root/product" ] && usb_prod=$(cat "$usb_root/product" 2>/dev/null)
    fi
    if [ -n "$ATI_INFO" ]; then
        m_rev=$(printf '%s\n' "$ATI_INFO" | tr -d '\r' | sed -n 's/.*Revision:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -n 1)
        m_model=$(printf '%s\n' "$ATI_INFO" | tr -d '\r' | awk '
            /^[[:space:]]*Model:[[:space:]]*/ { sub(/^[[:space:]]*Model:[[:space:]]*/, ""); print; exit }
            { line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line) }
            line=="" || line=="ATI" || line=="OK" || line=="ERROR" || line~/^Revision:/ || line~/^Manufacturer:/ { next }
            tolower(line) ~ /^(quectel|fibocom|huawei|sierra|simcom|meig|neoway|gosuncn|telit|thales|cinterion|openluat)$/ { next }
            { print line; exit }
        ')
    fi
    [ -z "$m_model" ] && m_model="$usb_prod"
    if [ "$MODE" != "phone_dhcp" ] && [ -c "$AT_PORT" ]; then
        m_imei=$(safe_at_once "$AT_PORT" "AT+CGSN" | grep -oE '[0-9]{15}' | head -n 1)
    fi
    local safe_q="tr -d '\\047\\042\\015\\012\\073\\134\\140\\044'"
    cat <<EOF > "/tmp/duydoan5g_modem_meta_${interface}"
META_IFACE='$(printf '%s' "$interface" | eval "$safe_q")'
META_IFNAME='$(printf '%s' "$IFNAME" | eval "$safe_q")'
META_DRV='$(printf '%s' "$NET_DRV" | eval "$safe_q")'
META_MODE='$(printf '%s' "$MODE" | eval "$safe_q")'
META_VENDOR='$(printf '%s' "$MODEM_VENDOR" | eval "$safe_q")'
META_PLATFORM='$(printf '%s' "$MODEM_PLATFORM" | eval "$safe_q")'
META_AT_PORT='$(printf '%s' "$AT_PORT" | eval "$safe_q")'
META_CTRL_DEV='$(printf '%s' "$CTRL_DEV" | eval "$safe_q")'
META_USB_VID='$(printf '%s' "$USB_VID" | eval "$safe_q")'
META_USB_PID='$(printf '%s' "$USB_PID" | eval "$safe_q")'
META_MODEL='$(printf '%s' "${m_model:-$usb_mfg}" | eval "$safe_q")'
META_REV='$(printf '%s' "$m_rev" | eval "$safe_q")'
META_IMEI='$(printf '%s' "$m_imei" | eval "$safe_q")'
EOF
    cp -f "/tmp/duydoan5g_modem_meta_${interface}" /tmp/duydoan5g_modem_meta 2>/dev/null || true
}

pre_dial_prepare() {
    stop_competing_dialers
    if [ "$MODE" = "phone_dhcp" ]; then
        MODEM_VENDOR="phone"
        [ "$NET_DRV" = "ipheth" ] && MODEM_PLATFORM="apple_ios" || MODEM_PLATFORM="${NET_DRV:-tether}"
        write_modem_meta
        return 0
    fi
    find_working_at_port || { detect_modem_profile; write_modem_meta; return 0; }
    detect_modem_profile
    sync_sim_status
    local cfun_res cpin_res lte_f lte_p nr_f nr_p nr_scs nr_b
    cfun_res=$(safe_at_once "$AT_PORT" "AT+CFUN?")
    if echo "$cfun_res" | grep -qE '\+CFUN:[[:space:]]*[04]'; then
        logger -t duydoan5g "Waking modem radio (AT+CFUN=1 on $AT_PORT)"
        safe_at_once "$AT_PORT" "AT+CFUN=1" >/dev/null
        sleep 3
    fi

    if [ -n "$pincode" ] && [ ! -f "$PIN_FLAG" ]; then
        cpin_res=$(safe_at_once "$AT_PORT" "AT+CPIN?")
        if echo "$cpin_res" | grep -qi "SIM PIN"; then
            safe_at_once "$AT_PORT" "AT+CPIN=\"$pincode\"" >/dev/null
            echo "tried" > "$PIN_FLAG"
            sleep 2
        fi
    fi

    wait_modem_ready

    if [ "$MODEM_VENDOR" = "quectel" ] && [ -f /etc/config/cell_lock_golden.json ] && command -v jsonfilter >/dev/null 2>&1; then
        lte_f=$(jsonfilter -i /etc/config/cell_lock_golden.json -e '@.lte_freq' 2>/dev/null)
        lte_p=$(jsonfilter -i /etc/config/cell_lock_golden.json -e '@.lte_pci' 2>/dev/null)
        nr_f=$(jsonfilter -i /etc/config/cell_lock_golden.json -e '@.nr_freq' 2>/dev/null)
        nr_p=$(jsonfilter -i /etc/config/cell_lock_golden.json -e '@.nr_pci' 2>/dev/null)
        nr_scs=$(jsonfilter -i /etc/config/cell_lock_golden.json -e '@.nr_scs' 2>/dev/null)
        nr_b=$(jsonfilter -i /etc/config/cell_lock_golden.json -e '@.nr_band' 2>/dev/null)
        [ -n "$lte_f" ] && [ -n "$lte_p" ] && safe_at_once "$AT_PORT" "AT+QNWLOCK=\"common/4g\",1,${lte_f},${lte_p}" >/dev/null
        [ -n "$nr_p" ] && [ -n "$nr_f" ] && safe_at_once "$AT_PORT" "AT+QNWLOCK=\"common/5g\",${nr_p},${nr_f},${nr_scs:-1},${nr_b:-41}" >/dev/null
    fi
    write_modem_meta
}

at_auth_num() {
    case "$auth" in
        pap|1) echo 1 ;;
        chap|2) echo 2 ;;
        mschapv2|both|auto|3) echo 3 ;;
        *) echo 0 ;;
    esac
}

at_dial_activate() {
    [ -c "$AT_PORT" ] || find_working_at_port || return 0
    local cid="$MODEM_PDP_IDX" pdp_str="IPV4V6" cgdcont_cmd="" auth_cmd="" nat_cmd="" act_cmd="" auth_num plmn cnmp
    case "$pdptype" in
        ip|ipv4) pdp_str="IP" ;;
        ipv6) pdp_str="IPV6" ;;
    esac
    auth_num=$(at_auth_num)

    if [ "$MODEM_VENDOR" != "openluat" ]; then
        if ! safe_at_once "$AT_PORT" "AT+COPS?" | grep -qE '\+COPS:[[:space:]]*[0-9]+,[0-9]+,"[^"]+"'; then
            safe_at_once "$AT_PORT" "AT+COPS=0" >/dev/null
        fi
    fi

    case "$MODEM_VENDOR" in
        quectel)
            case "$MODEM_PLATFORM" in
                hisilicon)
                    act_cmd="AT+QNETDEVCTL=1,1,1"
                    ;;
                unisoc)
                    cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
                    act_cmd="AT+QNETDEVCTL=1,$cid,1"
                    ;;
                *)
                    cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
                    if ! safe_at_once "$AT_PORT" 'AT+QCFG="nat"' | grep -qE '\+QCFG:[[:space:]]*"nat",1'; then
                        nat_cmd='AT+QCFG="nat",1'
                    fi
                    act_cmd="AT+QNETDEVCTL=3,$cid,1"
                    ;;
            esac
            ;;
        fibocom)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            if [ "$MODEM_PLATFORM" = "mediatek" ]; then
                act_cmd="AT+CGACT=1,$cid"
                if [ -n "$username$password" ] && [ "$auth_num" != "0" ]; then
                    auth_cmd="AT+CGAUTH=$cid,$auth_num,\"$username\",\"$password\""
                fi
            else
                act_cmd="AT+GTRNDIS=1,$cid"
                if [ -n "$username$password" ] && [ "$auth_num" != "0" ]; then
                    auth_cmd="AT+MGAUTH=$cid,$auth_num,\"$username\",\"$password\""
                fi
            fi
            ;;
        huawei)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            if [ "$MODEM_PLATFORM" = "unisoc" ]; then
                if ! safe_at_once "$AT_PORT" 'AT^SETAUTODIAL?' | grep -qE 'SETAUTODIAL:[[:space:]]*1,'; then
                    act_cmd="AT^SETAUTODIAL=1,4"
                fi
            else
                act_cmd="AT^NDISDUP=1,$cid"
                if [ -n "$username$password" ] && [ "$auth_num" != "0" ]; then
                    plmn=$(safe_at_once "$AT_PORT" "AT+COPS=3,2;+COPS?" | sed -n 's/.*"\([0-9][0-9][0-9][0-9][0-9][0-9]*\)".*/\1/p' | head -n1 | cut -c1-5)
                    [ -n "$plmn" ] || plmn="00000"
                    auth_cmd="AT^AUTHDATA=$cid,$auth_num,$plmn,\"$username\",\"$password\""
                fi
            fi
            ;;
        openluat)
            act_cmd="AT+RNDISCALL=1"
            ;;
        simcom)
            if [ "$MODEM_PLATFORM" = "qualcomm" ]; then
                cgdcont_cmd="AT+CGDCONT=1,\"$pdp_str\",\"$apn\""
                cnmp=$(safe_at_once "$AT_PORT" "AT+CNMP?" | sed -n 's/.*+CNMP:[[:space:]]*\([0-9]*\).*/\1/p' | head -n1)
                act_cmd="AT+CNMP=${cnmp:-2};+CNWINFO=1"
            else
                cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
                act_cmd="AT+CGACT=1,$cid"
            fi
            ;;
        sierra)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            act_cmd="AT!SCACT=1,$cid"
            ;;
        meig)
            cgdcont_cmd="AT+CGDCONT=1,\"$pdp_str\",\"$apn\""
            act_cmd="AT\$QCRMCALL=1,0,3,2,$cid"
            ;;
        neoway)
            cgdcont_cmd="AT+CGDCONT=1,\"$pdp_str\",\"$apn\""
            act_cmd='AT$MYUSBNETACT=0,1'
            ;;
        telit)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            act_cmd="AT#ICMAUTOCONN=1,$cid"
            ;;
        gosuncn)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            act_cmd="AT+ZECMCALL=1"
            ;;
        thales)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            act_cmd="AT^SWWAN=1,$cid"
            ;;
        *)
            cgdcont_cmd="AT+CGDCONT=$cid,\"$pdp_str\",\"$apn\""
            act_cmd="AT+CGACT=1,$cid"
            ;;
    esac

    [ -n "$cgdcont_cmd" ] && safe_at_once "$AT_PORT" "$cgdcont_cmd" >/dev/null
    [ -n "$auth_cmd" ] && safe_at_once "$AT_PORT" "$auth_cmd" >/dev/null
    [ -n "$nat_cmd" ] && safe_at_once "$AT_PORT" "$nat_cmd" >/dev/null
    if [ -n "$act_cmd" ]; then
        logger -t duydoan5g "AT dial ($MODEM_VENDOR/$MODEM_PLATFORM, pdp=$cid): $act_cmd on $AT_PORT"
        safe_at_once "$AT_PORT" "$act_cmd" >/dev/null
    fi
    AT_DIAL_ACTIVE=1
    sleep 2
}

at_hangup() {
    [ -c "$AT_PORT" ] || return 0
    local cid="$MODEM_PDP_IDX" hcmd=""
    case "$MODEM_VENDOR" in
        openluat) return 0 ;;
        huawei)
            [ "$MODEM_PLATFORM" = "unisoc" ] && hcmd="AT^SETAUTODIAL=0" || hcmd="AT^NDISDUP=0,0"
            ;;
        quectel) hcmd="AT+QNETDEVCTL=0,$cid,1" ;;
        fibocom) [ "$MODEM_PLATFORM" = "mediatek" ] && hcmd="AT+CGACT=0,$cid" || hcmd="AT+GTRNDIS=0,$cid" ;;
        meig) hcmd="AT\$QCRMCALL=0,0,3,2,$cid" ;;
        neoway) hcmd='AT$MYUSBNETACT=0,0' ;;
        gosuncn) hcmd="AT+ZECMCALL=0" ;;
        sierra) hcmd="AT!SCACT=0,$cid" ;;
        thales) hcmd="AT^SWWAN=0,$cid" ;;
        *) return 0 ;;
    esac
    safe_at_once "$AT_PORT" "$hcmd" >/dev/null || true
    AT_DIAL_ACTIVE=0
}

clamp_mtu() {
    local cur_mtu
    cur_mtu=$(cat "/sys/class/net/$IFNAME/mtu" 2>/dev/null)
    if [ "$cur_mtu" != "$mtu" ]; then
        ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
    fi
}

publish_netifd_up() {
    local v4="$1" m4="$2" gw4="$3" v6="$4" m6="$5" gw6="$6" extra_dns="$7"
    local d added_dns=""
    clamp_mtu
    proto_init_update "$IFNAME" 1
    if [ -n "$v4" ]; then
        proto_add_ipv4_address "$v4" "${m4:-30}"
        if [ -n "$gw4" ]; then
            proto_add_ipv4_route 0.0.0.0 0 "$gw4" "" "$metric"
        else
            proto_add_ipv4_route 0.0.0.0 0 "" "" "$metric"
        fi
    fi
    if [ -n "$extra_dns" ]; then
        for d in $extra_dns; do
            [ "$d" = "0.0.0.0" ] || [ -z "$d" ] && continue
            case " $added_dns " in *" $d "*) continue ;; esac
            proto_add_dns_server "$d"
            added_dns="$added_dns $d"
        done
    elif [ -f "$LOG_FILE" ]; then
        for d in $(sed -n 's/.*[Dd][Nn][Ss][12][[:space:]]*[=:][[:space:]]*\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\).*/\1/p' "$LOG_FILE" 2>/dev/null | tail -n 2); do
            [ "$d" = "0.0.0.0" ] || [ -z "$d" ] && continue
            case " $added_dns " in *" $d "*) continue ;; esac
            proto_add_dns_server "$d"
            added_dns="$added_dns $d"
        done
    fi
    for d in 8.8.8.8 1.1.1.1; do
        case " $added_dns " in *" $d "*) ;; *) proto_add_dns_server "$d"; added_dns="$added_dns $d" ;; esac
    done
    if [ -n "$v6" ]; then
        proto_add_ipv6_address "$v6" "${m6:-64}"
        proto_add_ipv6_route "::" 0 "$gw6" "$metric"
        proto_add_dns_server "2001:4860:4860::8888"
    fi
    proto_send_update "$interface"
}

run_uqmi_fallback() {
    logger -t duydoan5g "Switching to native uqmi fallback on $CTRL_DEV ($IFNAME)"
    stop_competing_dialers
    ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
    ip link set dev "$IFNAME" up 2>/dev/null || true

    uqmi -s -d "$CTRL_DEV" -t 1000 --wda-set-data-format raw-ip >/dev/null 2>&1 || true
    local cid4 settings4 v4 m4 gw4 d1 d2 u_auth=""
    cid4=$(uqmi -s -d "$CTRL_DEV" -t 2000 --get-client-id wds 2>/dev/null)
    case "$cid4" in ''|*[!0-9]*) return 1 ;; esac

    set -- -s -d "$CTRL_DEV" -t 5000 --set-client-id "wds,$cid4" --set-ip-family ipv4 --start-network --apn "$apn"
    if [ -n "$username" ] && [ -n "$password" ]; then
        case "$auth" in
            pap|chap|both) u_auth="$auth" ;;
            *) u_auth="both" ;;
        esac
        set -- "$@" --auth-type "$u_auth" --username "$username" --password "$password"
    fi
    uqmi "$@" --keep-client-id wds >/dev/null 2>&1 || {
        uqmi -s -d "$CTRL_DEV" -t 1000 --set-client-id "wds,$cid4" --release-client-id wds >/dev/null 2>&1 || true
        return 1
    }
    settings4=$(uqmi -s -d "$CTRL_DEV" -t 2000 --set-client-id "wds,$cid4" --get-current-settings 2>/dev/null)
    v4=$(echo "$settings4" | jsonfilter -e '@.ipv4.ip' 2>/dev/null)
    m4=$(echo "$settings4" | jsonfilter -e '@.ipv4.subnet' 2>/dev/null)
    gw4=$(echo "$settings4" | jsonfilter -e '@.ipv4.gateway' 2>/dev/null)
    d1=$(echo "$settings4" | jsonfilter -e '@.ipv4.dns1' 2>/dev/null)
    d2=$(echo "$settings4" | jsonfilter -e '@.ipv4.dns2' 2>/dev/null)
    if [ -z "$v4" ]; then
        uqmi -s -d "$CTRL_DEV" -t 1000 --set-client-id "wds,$cid4" --release-client-id wds >/dev/null 2>&1 || true
        return 1
    fi

    rm -f "$DIALING_FLAG"
    publish_netifd_up "$v4" "${m4:-255.255.255.252}" "$gw4" "" "" "" "$d1 $d2"
    logger -t duydoan5g "Connected via uqmi fallback! IP: $v4, GW: $gw4"

    while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
        clamp_mtu
        [ "$(uqmi -s -d "$CTRL_DEV" -t 2000 --set-client-id "wds,$cid4" --get-data-status 2>/dev/null)" = '"connected"' ] || break
        sleep 5
    done
    uqmi -s -d "$CTRL_DEV" -t 1000 --set-client-id "wds,$cid4" --stop-network 0xffffffff --release-client-id wds >/dev/null 2>&1 || true
    if [ "$STOP_REQ" = "0" ]; then
        proto_init_update "$IFNAME" 0
        proto_send_update "$interface"
    fi
    return 0
}

publish_umbim_config() {
    local mbimconfig="$1" cidr4 m4="" v4 gw4 dns4 cidr6 v6 m6="" gw6
    cidr4=$(echo "$mbimconfig" | awk '/ipv4address:/{print $2; exit}')
    v4="${cidr4%/*}"
    if [ -n "$v4" ]; then
        m4="${cidr4#*/}"; [ "$m4" = "$cidr4" ] && m4=30
    fi
    gw4=$(echo "$mbimconfig" | awk '/ipv4gateway:/{print $2; exit}')
    dns4=$(echo "$mbimconfig" | awk '/ipv4dnsserver:/{printf "%s ", $2}')
    cidr6=$(echo "$mbimconfig" | awk '/ipv6address:/{print $2; exit}')
    v6="${cidr6%/*}"
    if [ -n "$v6" ]; then
        m6="${cidr6#*/}"; [ "$m6" = "$cidr6" ] && m6=64
    fi
    gw6=$(echo "$mbimconfig" | awk '/ipv6gateway:/{print $2; exit}')
    [ -n "$v4" ] || [ -n "$v6" ] || return 1
    rm -f "$DIALING_FLAG"
    publish_netifd_up "$v4" "$m4" "$gw4" "$v6" "$m6" "$gw6" "$dns4"
    UMBIM_LAST_SIG="${v4:+${v4}/${m4}}|${gw4}|${v6:+${v6}/${m6}}"
    UMBIM_LAST_V4="$v4"
    UMBIM_LAST_V6="$v6"
    return 0
}

run_umbim_fallback() {
    logger -t duydoan5g "Switching to native umbim fallback on $CTRL_DEV ($IFNAME)"
    stop_competing_dialers
    ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
    ip link set dev "$IFNAME" up 2>/dev/null || true

    local tid=2 tries=0 ok=0 pdp_req="ipv4v6:" mbimconfig m_auth="none"
    UMBIM_ACTIVE=1
    while [ "$tries" -lt 3 ] && [ "$STOP_REQ" = "0" ]; do
        timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" caps >/dev/null 2>&1 && { ok=1; break; }
        tid=$((tid + 1)); tries=$((tries + 1)); sleep 1
    done
    [ "$ok" = "1" ] || { UMBIM_ACTIVE=0; return 1; }
    tid=$((tid + 1))

    if [ -n "$pincode" ]; then
        timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" unlock "$pincode" >/dev/null 2>&1 || true
        tid=$((tid + 1))
    fi
    timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" subscriber >/dev/null 2>&1 || { UMBIM_ACTIVE=0; return 1; }
    tid=$((tid + 1))
    tries=0; ok=0
    while [ "$tries" -lt 15 ] && [ "$STOP_REQ" = "0" ]; do
        timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" registration >/dev/null 2>&1
        rc=$?
        tid=$((tid + 1))
        [ "$rc" = "0" ] || [ "$rc" = "4" ] || [ "$rc" = "5" ] && { ok=1; break; }
        tries=$((tries + 1)); sleep 1
    done
    [ "$ok" = "1" ] || { UMBIM_ACTIVE=0; return 1; }
    timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" attach >/dev/null 2>&1 || true
    tid=$((tid + 1))

    case "$pdptype" in ip|ipv4) pdp_req="ipv4:" ;; ipv6) pdp_req="ipv6:" ;; *) pdp_req="ipv4v6:" ;; esac
    case "$auth" in pap|chap|both) m_auth="$auth" ;; *) [ -n "$username$password" ] && m_auth="pap" || m_auth="none" ;; esac
    set -- -n -t "$tid" -d "$CTRL_DEV" connect "$pdp_req$apn"
    [ "$m_auth" != "none" ] && [ -n "$username$password" ] && set -- "$@" "$m_auth" "$username" "$password"
    timeout 12 umbim "$@" >/dev/null 2>&1 || {
        tid=$((tid + 1))
        timeout 12 umbim -n -t "$tid" -d "$CTRL_DEV" connect "$apn" "none" >/dev/null 2>&1 || { UMBIM_ACTIVE=0; return 1; }
    }
    tid=$((tid + 1))
    UMBIM_TID="$tid"
    mbimconfig=$(timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" config 2>/dev/null)
    UMBIM_TID=$((tid + 1))

    publish_umbim_config "$mbimconfig" || {
        timeout 4 umbim -n -t "$UMBIM_TID" -d "$CTRL_DEV" disconnect >/dev/null 2>&1 || true
        UMBIM_ACTIVE=0
        return 1
    }
    logger -t duydoan5g "Connected via umbim fallback ($MODEM_VENDOR/$MODEM_PLATFORM)! Sig: $UMBIM_LAST_SIG"

    while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
        clamp_mtu
        local live4 live6
        live4=$(ip -4 addr show dev "$IFNAME" 2>/dev/null | awk '/inet /{print $2; exit}')
        live6=$(ip -6 addr show dev "$IFNAME" scope global 2>/dev/null | awk '/inet6 /{print $2; exit}')
        [ -n "$UMBIM_LAST_V4" ] && [ -z "$live4" ] && break
        [ -n "$UMBIM_LAST_V6" ] && [ -z "$live6" ] && break
        sleep 5
    done
    if [ "$STOP_REQ" = "0" ]; then
        timeout 4 umbim -n -t "$UMBIM_TID" -d "$CTRL_DEV" disconnect >/dev/null 2>&1 || true
        proto_init_update "$IFNAME" 0
        proto_send_update "$interface"
    fi
    UMBIM_ACTIVE=0
    return 0
}

run_mtk_pcie_dial() {
    [ -c "$CTRL_DEV" ] || [ -z "$AT_PORT" ] || CTRL_DEV=$(echo "$AT_PORT" | sed 's/at/mbim/g')
    if [ ! -c "$CTRL_DEV" ] || ! command -v umbim >/dev/null 2>&1; then
        logger -t duydoan5g "mtk_pcie missing CTRL_DEV=$CTRL_DEV or umbim; falling back to AT+DHCP"
        return 1
    fi
    logger -t duydoan5g "Starting MTK PCIe MBIM dialer on $IFNAME (Ctrl: $CTRL_DEV, APN: $apn)"
    while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
        detach_bridge_master
        ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
        ip link set dev "$IFNAME" up 2>/dev/null || true
        local rf_state mbimconfig prev_sig="" ok_cfg=0
        rf_state=$(timeout 5 umbim -d "$CTRL_DEV" radio 2>/dev/null | sed -n 's/.*swradiostate: *//p')
        [ "$rf_state" = "off" ] && timeout 5 umbim -d "$CTRL_DEV" radio on >/dev/null 2>&1 || true
        timeout 6 umbim -d "$CTRL_DEV" disconnect >/dev/null 2>&1 || true
        sleep 1

        if timeout 12 umbim -d "$CTRL_DEV" connect 0 --apn "${apn:-auto}" >/dev/null 2>&1; then
            mbimconfig=$(timeout 8 umbim -d "$CTRL_DEV" config 2>/dev/null)
            publish_umbim_config "$mbimconfig" && ok_cfg=1
        fi
        if [ "$ok_cfg" = "1" ]; then
            logger -t duydoan5g "MTK PCIe connected! Sig: $UMBIM_LAST_SIG"
            prev_sig="$UMBIM_LAST_SIG"
            while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
                sleep 15
                [ "$STOP_REQ" = "0" ] || break
                mbimconfig=$(timeout 8 umbim -d "$CTRL_DEV" config 2>/dev/null)
                local c4 g4 c6 cur_sig
                c4=$(echo "$mbimconfig" | awk '/ipv4address:/{print $2; exit}')
                g4=$(echo "$mbimconfig" | awk '/ipv4gateway:/{print $2; exit}')
                c6=$(echo "$mbimconfig" | awk '/ipv6address:/{print $2; exit}')
                [ -n "$c4" ] || [ -n "$c6" ] || break
                [ -n "$c4" ] && case "$c4" in */*) ;; *) c4="${c4}/30" ;; esac
                [ -n "$c6" ] && case "$c6" in */*) ;; *) c6="${c6}/64" ;; esac
                cur_sig="${c4}|${g4}|${c6}"
                if [ "$cur_sig" != "$prev_sig" ]; then
                    publish_umbim_config "$mbimconfig" || break
                    prev_sig="$UMBIM_LAST_SIG"
                fi
            done
            if [ "$STOP_REQ" = "0" ]; then
                proto_init_update "$IFNAME" 0
                proto_send_update "$interface"
            fi
        else
            # Fallback to stock OpenWrt umbim transaction mode
            run_umbim_fallback || sleep 5
        fi
    done
}

ensure_dynamic_dhcpv6() {
    case "$pdptype" in ip|ipv4) return 0 ;; esac
    local v6_iface="${interface}_6"
    ubus list 2>/dev/null | grep -qx "network.interface.${v6_iface}" && return 0
    json_init
    json_add_string name "$v6_iface"
    json_add_string ifname "@${interface}"
    json_add_string proto "dhcpv6"
    json_add_string extendprefix "1"
    json_add_string zone "wan"
    json_add_int metric "$metric"
    json_close_object
    ubus call network add_dynamic "$(json_dump)" >/dev/null 2>&1 || true
}

run_fm350_usb_dial() {
    local cid="$MODEM_PDP_IDX" active_cid="$MODEM_PDP_IDX" cgp v4 v6 gw4 dns4 sig last_sig=""
    logger -t duydoan5g "Starting FM350 USB static IP dialer on $IFNAME (pdp=$cid, APN=$apn)"
    while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
        at_dial_activate
        detach_bridge_master
        ip link set dev "$IFNAME" arp off 2>/dev/null || true
        ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
        ip link set dev "$IFNAME" up 2>/dev/null || true
        v4=""; v6=""; active_cid="$cid"
        local t=0
        while [ "$t" -lt 4 ] && [ "$STOP_REQ" = "0" ]; do
            cgp=$(safe_at_once "$AT_PORT" "AT+CGPADDR=$cid")
            v4=$(extract_cgpaddr_ipv4 "$cgp")
            v6=$(extract_cgpaddr_ipv6 "$cgp")
            active_cid="$cid"
            if [ -z "$v4" ] && [ -z "$v6" ] && [ "$cid" != "0" ]; then
                cgp=$(safe_at_once "$AT_PORT" "AT+CGPADDR=0")
                v4=$(extract_cgpaddr_ipv4 "$cgp")
                v6=$(extract_cgpaddr_ipv6 "$cgp")
                [ -n "$v4" ] || [ -n "$v6" ] && active_cid="0"
            fi
            [ -n "$v4" ] || [ -n "$v6" ] && break
            t=$((t + 1)); sleep 2
        done
        if [ -z "$v4" ] && [ -z "$v6" ]; then
            sleep 5
            continue
        fi
        gw4=""; [ -n "$v4" ] && { gw4="${v4%.*}.1"; [ "$gw4" = "$v4" ] && gw4="${v4%.*}.2"; }
        dns4=$(extract_gtdns_ipv4 "$(safe_at_once "$AT_PORT" "AT+GTDNS=$active_cid")")
        if [ -z "$dns4" ]; then
            sleep 1
            dns4=$(extract_gtdns_ipv4 "$(safe_at_once "$AT_PORT" "AT+GTDNS=$active_cid")")
        fi
        last_sig="${v4}|${gw4}|${v6}"
        publish_netifd_up "$v4" "24" "$gw4" "$v6" "64" "" "$dns4"
        [ -z "$v6" ] && ensure_dynamic_dhcpv6
        logger -t duydoan5g "FM350 USB connected! IP: $v4, GW: $gw4, DNS: ${dns4:-fallback}, IPv6: ${v6:-dhcpv6}"

        local miss=0
        while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
            sleep 15
            [ "$STOP_REQ" = "0" ] || break
            detach_bridge_master
            ip link set dev "$IFNAME" arp off 2>/dev/null || true
            clamp_mtu
            cgp=$(safe_at_once "$AT_PORT" "AT+CGPADDR=$active_cid")
            v4=$(extract_cgpaddr_ipv4 "$cgp")
            v6=$(extract_cgpaddr_ipv6 "$cgp")
            if [ -z "$v4" ] && [ -z "$v6" ]; then
                miss=$((miss + 1))
                [ "$miss" -ge 3 ] && break
                continue
            fi
            miss=0
            gw4=""; [ -n "$v4" ] && { gw4="${v4%.*}.1"; [ "$gw4" = "$v4" ] && gw4="${v4%.*}.2"; }
            sig="${v4}|${gw4}|${v6}"
            if [ "$sig" != "$last_sig" ]; then
                dns4=$(extract_gtdns_ipv4 "$(safe_at_once "$AT_PORT" "AT+GTDNS=$active_cid")")
                publish_netifd_up "$v4" "24" "$gw4" "$v6" "64" "" "$dns4"
                [ -z "$v6" ] && ensure_dynamic_dhcpv6
                last_sig="$sig"
            fi
        done
        if [ "$STOP_REQ" = "0" ]; then
            proto_init_update "$IFNAME" 0
            proto_send_update "$interface"
            sleep 3
        fi
    done
}

run_at_dhcp_monitor() {
    [ "$MODE" = "phone_dhcp" ] || at_dial_activate
    detach_bridge_master
    ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
    ip link set dev "$IFNAME" up 2>/dev/null || true

    local check_cid="$MODEM_PDP_IDX" is_auto=0 want_v6=0 pdp_miss=0 cgp v4 v6 cur_sig last_sig="" prev_carrier="" cur_carrier=""
    case "$pdptype" in ip|ipv4) want_v6=0 ;; *) want_v6=1 ;; esac
    if [ "$want_v6" = "1" ] && command -v rdisc6 >/dev/null 2>&1; then
        rdisc6 -1 "$IFNAME" >/dev/null 2>&1 || true
    fi
    [ "$MODEM_VENDOR" = "simcom" ] && [ "$MODEM_PLATFORM" = "qualcomm" ] && check_cid="6"
    [ "$MODEM_VENDOR" = "neoway" ] && check_cid="1"
    if [ "$MODE" = "phone_dhcp" ] || [ "$MODEM_VENDOR" = "openluat" ] || { [ "$MODEM_VENDOR" = "huawei" ] && [ "$MODEM_PLATFORM" = "unisoc" ]; }; then
        is_auto=1
    fi

    while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
        if [ -z "$UDHCPC_PID" ] || ! kill -0 "$UDHCPC_PID" 2>/dev/null; then
            INTERFACE="$interface" /sbin/udhcpc -f -p "$PID_FILE" -i "$IFNAME" -s /lib/netifd/dhcp.script >/dev/null 2>&1 &
            UDHCPC_PID=$!
            UDHCPC_START=$(awk '{print $22}' "/proc/$UDHCPC_PID/stat" 2>/dev/null)
        fi
        if [ "$want_v6" = "1" ] && [ -x /lib/netifd/dhcpv6.script ] && command -v odhcp6c >/dev/null 2>&1; then
            if [ -z "$ODHCP6C_PID" ] || ! kill -0 "$ODHCP6C_PID" 2>/dev/null; then
                INTERFACE="$interface" odhcp6c -s /lib/netifd/dhcpv6.script -Ntry "$IFNAME" >/dev/null 2>&1 &
                ODHCP6C_PID=$!
                ODHCP6C_START=$(awk '{print $22}' "/proc/$ODHCP6C_PID/stat" 2>/dev/null)
            fi
        fi
        sleep 15
        [ "$STOP_REQ" = "0" ] || break
        detach_bridge_master
        clamp_mtu
        cur_carrier=$(cat "/sys/class/net/$IFNAME/carrier" 2>/dev/null || true)
        if [ "$prev_carrier" = "0" ] && [ "$cur_carrier" = "1" ]; then
            logger -t duydoan5g "Carrier recovered on $IFNAME; renewing DHCP"
            [ -n "$UDHCPC_PID" ] && kill -USR1 "$UDHCPC_PID" 2>/dev/null || true
            [ "$want_v6" = "1" ] && command -v rdisc6 >/dev/null 2>&1 && { rdisc6 -1 "$IFNAME" >/dev/null 2>&1 || true; }
        fi
        [ -n "$cur_carrier" ] && prev_carrier="$cur_carrier"
        [ "$is_auto" = "1" ] && continue
        [ -c "$AT_PORT" ] || continue

        cgp=$(safe_at_once "$AT_PORT" "AT+CGPADDR=$check_cid")
        [ -n "$cgp" ] || continue
        v4=$(extract_cgpaddr_ipv4 "$cgp")
        v6=$(extract_cgpaddr_ipv6 "$cgp")
        cur_sig="${v4}|${v6}"
        if [ -z "$v4" ] && [ -z "$v6" ]; then
            pdp_miss=$((pdp_miss + 1))
            [ "$pdp_miss" -lt 3 ] && continue
            pdp_miss=0
            logger -t duydoan5g "PDP $check_cid dropped on $IFNAME; re-dialing AT"
            at_dial_activate
            [ -n "$UDHCPC_PID" ] && kill -USR1 "$UDHCPC_PID" 2>/dev/null || true
            [ "$want_v6" = "1" ] && command -v rdisc6 >/dev/null 2>&1 && { rdisc6 -1 "$IFNAME" >/dev/null 2>&1 || true; }
            last_sig=""
        elif [ -n "$last_sig" ] && [ "$cur_sig" != "$last_sig" ]; then
            pdp_miss=0
            [ -n "$UDHCPC_PID" ] && kill -USR1 "$UDHCPC_PID" 2>/dev/null || true
            [ "$want_v6" = "1" ] && command -v rdisc6 >/dev/null 2>&1 && { rdisc6 -1 "$IFNAME" >/dev/null 2>&1 || true; }
            last_sig="$cur_sig"
        else
            pdp_miss=0
            last_sig="$cur_sig"
        fi
    done
    stop_pid_graceful "$UDHCPC_PID" "$UDHCPC_START"
    stop_pid_graceful "$ODHCP6C_PID" "$ODHCP6C_START"
    UDHCPC_PID=""; UDHCPC_START=""
    ODHCP6C_PID=""; ODHCP6C_START=""
}

rotate_cm_log() {
    [ -f "$LOG_FILE" ] || return 0
    local lines
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then
        tail -n 100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

is_usb_phone_tether() {
    [ "$NET_DRV" = "ipheth" ] && return 0
    [ "$MODE" = "at_dhcp" ] || return 1
    read_usb_ids_for_netdev || true
    local usb_root
    usb_root=$(find_usb_root_for_netdev 2>/dev/null || true)
    [ -n "$usb_root" ] && [ -d "$usb_root" ] || return 1
    if find "$usb_root" -maxdepth 4 \( -name 'ttyUSB*' -o -name 'ttyACM*' -o -name 'cdc-wdm*' \) 2>/dev/null | grep -q .; then
        return 1
    fi
    case "${USB_VID}:${USB_PID}" in
        12d1:14db|12d1:14dc) return 0 ;;
    esac
    case "$USB_VID" in
        0e8d|2c7c|2cb7|1508|1199|12dc|3466|1e0e|1a0e|2dee|1bc7|305a|1e2d|3763|1782|413c|05c6|12d1)
            return 1 ;;
    esac
    return 0
}

run_phone_dhcp_monitor() {
    MODE="phone_dhcp"
    run_at_dhcp_monitor
}

wake_hardware
detect_endpoint || exit 1
if is_usb_phone_tether; then
    MODE="phone_dhcp"
fi
pre_dial_prepare
logger -t duydoan5g "Starting 5G supervised dialer on $IFNAME (Mode: $MODE, Vendor: $MODEM_VENDOR/$MODEM_PLATFORM, PDP: $MODEM_PDP_IDX, AT: ${AT_PORT:-none}, Driver: ${NET_DRV:-unknown}, Ctrl: ${CTRL_DEV:-none}, APN: $apn)"

if [ "$MODE" = "mtk_pcie" ]; then
    run_mtk_pcie_dial && exit 0
    MODE="at_dhcp"
fi

if [ "$MODE" = "fm350_usb" ]; then
    run_fm350_usb_dial
    exit 0
fi

if [ "$MODE" = "phone_dhcp" ]; then
    run_phone_dhcp_monitor
    exit 0
fi

if [ "$MODE" = "at_dhcp" ]; then
    run_at_dhcp_monitor
    exit 0
fi

fail_streak=0
while [ "$STOP_REQ" = "0" ]; do
    if [ ! -d "/sys/class/net/$IFNAME" ]; then
        proto_init_update "$IFNAME" 0
        proto_send_update "$interface"
        logger -t duydoan5g "Interface $IFNAME vanished; re-initializing dialer detection"
        exec 8>&-
        exec /usr/bin/duydoan5g_dialer.sh "$interface" "$apn" "$pdptype" "$mtu" "$metric" "$pincode" "$username" "$password" "$auth" "0" "$user_pdp_index" "$force_apn" "$user_device"
    fi
    local_qcm=""
    for bin in /usr/bin/quectel-CM-M /usr/bin/quectel-CM /usr/bin/quectel-cm; do
        [ -x "$bin" ] && { local_qcm="$bin"; break; }
    done

    if [ -n "$local_qcm" ] && [ "$fail_streak" -lt 3 ]; then
        cm_if="$IFNAME"
        case "$IFNAME" in
            wwan*_*) cm_if="${IFNAME%%_*}" ;;
            rmnet*.*) cm_if="${IFNAME%%.*}" ;;
        esac
        cm_apn="$apn"
        if [ -z "$cm_apn" ] && { [ "$MODE" = "cm_mbim" ] || [ "$NET_DRV" = "cdc_mbim" ]; }; then
            cm_apn="auto"
        fi
        set -- -i "$cm_if"
        case "$pdptype" in
            ip|ipv4) set -- "$@" -4 ;;
            ipv6) set -- "$@" -6 ;;
            *) set -- "$@" -4 -6 ;;
        esac
        [ -n "$user_pdp_index" ] && set -- "$@" -n "$user_pdp_index"
        if [ -n "$cm_apn" ]; then
            set -- "$@" -s "$cm_apn"
            if [ -n "$username" ] && [ -n "$password" ]; then
                q_auth=$(at_auth_num)
                [ "$q_auth" = "0" ] && q_auth="3"
                set -- "$@" "$username" "$password" "$q_auth"
            fi
        fi
        [ -n "$pincode" ] && set -- "$@" -p "$pincode"
        case "$local_qcm" in
            */quectel-CM-M)
                set -- "$@" -d -D -M "$metric"
                if [ "$force_apn" = "1" ] || [ "$MODEM_VENDOR" = "telit" ]; then
                    set -- "$@" -F
                fi
                ;;
            *)
                if [ "$MODE" != "cm_mbim" ] && [ "$NET_DRV" != "cdc_mbim" ]; then
                    set -- "$@" -d
                fi
                ;;
        esac
        set -- "$@" -f "$LOG_FILE"

        detach_bridge_master
        ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
        ip link set dev "$IFNAME" up 2>/dev/null || true
        touch "$DIALING_FLAG"
        : > "$LOG_FILE"
        chmod 600 "$LOG_FILE" 2>/dev/null || true

        "$local_qcm" "$@" </dev/null >/dev/null 2>&1 &
        CM_PID=$!
        CM_START=$(awk '{print $22}' "/proc/$CM_PID/stat" 2>/dev/null)
        echo "$CM_PID" > "$PID_FILE"

        is_up=0
        last_sig=""
        connecting_sec=0
        ticks=0

        while [ "$STOP_REQ" = "0" ] && kill -0 "$CM_PID" 2>/dev/null; do
            clamp_mtu
            cidr4=$(ip -4 addr show dev "$IFNAME" 2>/dev/null | awk '/inet /{print $2; exit}')
            v4="${cidr4%/*}"; m4="${cidr4#*/}"; [ "$m4" = "$cidr4" ] && m4=30
            gw4=$(ip -4 route show dev "$IFNAME" default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
            cidr6=$(ip -6 addr show dev "$IFNAME" scope global 2>/dev/null | awk '/inet6 /{print $2; exit}')
            v6="${cidr6%/*}"; m6="${cidr6#*/}"; [ "$m6" = "$cidr6" ] && m6=64
            gw6=$(ip -6 route show dev "$IFNAME" default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')

            sig="${v4}/${m4}|${gw4}|${v6}/${m6}"
            if { [ -n "$v4" ] || [ -n "$v6" ]; } && [ "$sig" != "$last_sig" ]; then
                rm -f "$DIALING_FLAG"
                publish_netifd_up "$v4" "$m4" "$gw4" "$v6" "$m6" "$gw6" ""
                logger -t duydoan5g "Connected! IP: $v4, GW: $gw4, IPv6: $v6"
                last_sig="$sig"
                is_up=1
                fail_streak=0
                connecting_sec=0
            elif [ "$is_up" = "1" ] && [ -z "$v4" ] && [ -z "$v6" ]; then
                proto_init_update "$IFNAME" 0
                proto_send_update "$interface"
                is_up=0
                last_sig=""
                touch "$DIALING_FLAG"
            elif [ "$is_up" = "0" ]; then
                connecting_sec=$((connecting_sec + 1))
                if [ "$connecting_sec" -ge 45 ]; then
                    logger -t duydoan5g "Dial handshake stalled 45s on $IFNAME; cycling $local_qcm"
                    stop_pid_graceful "$CM_PID" "$CM_START"
                    break
                fi
            fi

            ticks=$((ticks + 1))
            [ $((ticks % 60)) -eq 0 ] && rotate_cm_log
            [ "$is_up" = "1" ] && sleep 4 || sleep 1
        done

        wait "$CM_PID" 2>/dev/null || true
        CM_PID=""; CM_START=""
        rm -f "$DIALING_FLAG" "$PID_FILE"
        [ "$STOP_REQ" = "0" ] || break

        if [ "$is_up" = "1" ]; then
            proto_init_update "$IFNAME" 0
            proto_send_update "$interface"
            fail_streak=0
        else
            fail_streak=$((fail_streak + 1))
        fi
    fi

    if { [ -z "$local_qcm" ] || [ "$fail_streak" -ge 3 ]; } && [ -c "$CTRL_DEV" ]; then
        if [ "$MODE" = "cm_mbim" ] || { [ "$MODE" = "cm_usb" ] && [ "$NET_DRV" = "cdc_mbim" ]; }; then
            if [ -x /sbin/umbim ]; then
                run_umbim_fallback
                fail_streak=0
            fi
        elif [ "$MODE" = "cm_qmi" ] || [ "$MODE" = "cm_usb" ]; then
            if command -v uqmi >/dev/null 2>&1; then
                run_uqmi_fallback
                fail_streak=0
            fi
        fi
    fi

    [ "$STOP_REQ" = "0" ] || break
    backoff=$((4 + fail_streak * 2))
    [ "$backoff" -gt 15 ] && backoff=15
    sleep "$backoff"
done
