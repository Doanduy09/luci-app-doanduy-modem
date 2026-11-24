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

[ -n "$interface" ] || exit 1
case "$mtu" in ''|*[!0-9]*) mtu=1460 ;; esac
[ "$mtu" -lt 1280 ] && mtu=1280
[ "$mtu" -gt 1500 ] && mtu=1500
case "$metric" in ''|*[!0-9]*) metric=10 ;; esac
case "$delay" in ''|*[!0-9]*) delay=0 ;; esac

mkdir -p /var/lock /var/run /tmp/quectel_cm
exec 8>"/var/lock/duydoan5g_dial.lock"
flock -x -w 10 8 || exit 1

LOG_FILE="/tmp/quectel_cm/quectel-cm.log"
PID_FILE="/var/run/duydoan5g.pid"
STOP_REQ=0
CM_PID=""
CM_START=""
UMBIM_ACTIVE=0
UMBIM_TID=""
CTRL_DEV=""
IFNAME=""
NET_DRV=""
MODE=""

stop_cm_graceful() {
    local p="${1:-$CM_PID}" exp="${2:-$CM_START}"
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
    rm -f /tmp/quectel_dialing
    stop_cm_graceful "$CM_PID" "$CM_START"
    if [ "$UMBIM_ACTIVE" = "1" ] && [ -n "$UMBIM_TID" ] && [ -c "$CTRL_DEV" ]; then
        timeout 4 umbim -n -t "$UMBIM_TID" -d "$CTRL_DEV" disconnect >/dev/null 2>&1 || true
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

wake_hardware() {
    local f
    for f in /sys/bus/pci/devices/*/power/control /sys/bus/mhi/devices/*/power/control; do
        [ -f "$f" ] && echo on > "$f" 2>/dev/null || true
    done
    for f in /sys/bus/usb/devices/*/bConfigurationValue; do
        [ -f "$f" ] && [ -z "$(cat "$f" 2>/dev/null)" ] && echo 1 > "$f" 2>/dev/null || true
    done
}

netdev_driver() {
    local drv_path
    drv_path=$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)
    [ -n "$drv_path" ] && echo "${drv_path##*/}"
}

is_real_wwan_netdev() {
    local name="$1" real_path
    [ -n "$name" ] && [ -d "/sys/class/net/$name" ] || return 1
    case "$name" in
        lo|br-*|lan*|wan*|eth0|eth1|wlan*|phy*|mhi_swip*|erspan*|gre*|miireg) return 1 ;;
    esac
    real_path=$(readlink -f "/sys/class/net/$name" 2>/dev/null)
    case "$real_path" in
        */mhi*_IP_SW/*) return 1 ;;
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

resolve_netdev_from_ctrl() {
    local sys_base="$1" fallback_list="$2" real_dir netdir entry name parent_dir cand
    for netdir in "$sys_base/device/net" "$sys_base/net"; do
        [ -d "$netdir" ] || continue
        for entry in "$netdir"/*; do
            [ -e "$entry" ] || continue
            name="${entry##*/}"
            is_real_wwan_netdev "$name" || continue
            echo "$name"
            return 0
        done
    done
    real_dir=$(readlink -f "$sys_base" 2>/dev/null)
    if [ -n "$real_dir" ]; then
        parent_dir="${real_dir%/*}"
        for entry in "$parent_dir/net"/*; do
            [ -e "$entry" ] || continue
            name="${entry##*/}"
            is_real_wwan_netdev "$name" || continue
            echo "$name"
            return 0
        done
    fi
    for cand in $fallback_list; do
        is_real_wwan_netdev "$cand" && { echo "$cand"; return 0; }
    done
    return 1
}

detect_endpoint() {
    while [ "$STOP_REQ" = "0" ]; do
        heal_pcie_mhi_id
        IFNAME=""; CTRL_DEV=""; NET_DRV=""; MODE=""
        local d b net drv cand

        # 1. PCIe MHI QMI FIRST (preferred for Sierra EM919x/Quectel RM520N Raw-IP hardware path)
        for d in /dev/wwan*qmi* /dev/mhi_QMI0; do
            [ -c "$d" ] || continue
            b="${d##*/}"
            net=$(resolve_netdev_from_ctrl "/sys/class/wwan/$b" "mhi_hwip0 rmnet_mhi0.1 rmnet_mhi0 wwan0")
            if is_real_wwan_netdev "$net"; then
                CTRL_DEV="$d"; IFNAME="$net"; NET_DRV=$(netdev_driver "$net"); MODE="cm_qmi"
                return 0
            fi
        done

        # 2. PCIe MHI MBIM (for native MBIM-only PCIe modems such as Foxconn SDX55/T99W175)
        for d in /dev/wwan*mbim* /dev/mhi_MBIM; do
            [ -c "$d" ] || continue
            b="${d##*/}"
            net=$(resolve_netdev_from_ctrl "/sys/class/wwan/$b" "wwan0 mhi_hwip0")
            if is_real_wwan_netdev "$net"; then
                CTRL_DEV="$d"; IFNAME="$net"; NET_DRV=$(netdev_driver "$net"); MODE="cm_mbim"
                return 0
            fi
        done

        # 3. USB QMI / MBIM
        for d in /dev/cdc-wdm*; do
            [ -c "$d" ] || continue
            b="${d##*/}"
            net=$(resolve_netdev_from_ctrl "/sys/class/usbmisc/$b" "wwan0 usb0 eth2")
            if is_real_wwan_netdev "$net"; then
                CTRL_DEV="$d"; IFNAME="$net"; NET_DRV=$(netdev_driver "$net"); MODE="cm_usb"
                return 0
            fi
        done

        # 4. PCIe MediaTek T7xx (Fibocom FM350-GL PCIe)
        for entry in /sys/class/net/*; do
            [ -e "$entry" ] || continue
            net="${entry##*/}"
            is_real_wwan_netdev "$net" || continue
            drv=$(netdev_driver "$net")
            if [ "$drv" = "mtk_t7xx" ]; then
                IFNAME="$net"; NET_DRV="$drv"; MODE="at_dhcp"
                return 0
            fi
        done

        # 5. USB ECM / NCM / RNDIS / Sierra Net / HiLink cellular netdevs
        for entry in /sys/class/net/*; do
            [ -e "$entry" ] || continue
            net="${entry##*/}"
            is_real_wwan_netdev "$net" || continue
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
    [ -c "$port" ] || return 1
    case "$port" in
        /dev/wwan*|/dev/mhi*)
            [ -x /usr/bin/read_pcie_sms.lua ] || return 1
            timeout 4 /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null
            return $?
            ;;
        *)
            ( /usr/bin/flock -x -w 4 9 && printf '%s\r\n' "$cmd" | timeout 2 atinout - "$port" - ) 9>/var/lock/modem_at.lock 2>/dev/null
            return $?
            ;;
    esac
}

stop_competing_dialers() {
    local procs="quectel-CM-M quectel-CM quectel-cm umbim"
    if pidof $procs >/dev/null 2>&1; then
        killall -TERM $procs 2>/dev/null || true
        local i=0
        while [ "$i" -lt 3 ] && pidof $procs >/dev/null 2>&1; do
            sleep 1
            i=$((i + 1))
        done
        pidof $procs >/dev/null 2>&1 && killall -KILL $procs 2>/dev/null || true
    fi
}

AT_PORT=""
ATI_INFO=""

find_working_at_port() {
    AT_PORT=""; ATI_INFO=""
    local p out
    for p in /dev/wwan0at0 /dev/mhi_DUN /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyFMI0; do
        [ -c "$p" ] || continue
        out=$(safe_at_once "$p" "ATI")
        if echo "$out" | grep -qE 'OK|Sierra|Quectel|Fibocom|FM350|Huawei|Simcom|SIMCOM|Meig|Neoway|Gosuncn'; then
            AT_PORT="$p"; ATI_INFO="$out"
            return 0
        fi
    done
    return 1
}

pre_dial_prepare() {
    stop_competing_dialers
    find_working_at_port || return 0
    local cfun_res cpin_res
    cfun_res=$(safe_at_once "$AT_PORT" "AT+CFUN?")
    if echo "$cfun_res" | grep -qE '\+CFUN:[[:space:]]*[04]'; then
        logger -t duydoan5g "Waking modem radio (AT+CFUN=1 on $AT_PORT)"
        safe_at_once "$AT_PORT" "AT+CFUN=1" >/dev/null
        sleep 3
    fi

    if [ -n "$pincode" ] && [ ! -f /var/run/duydoan5g_pin_tried ]; then
        cpin_res=$(safe_at_once "$AT_PORT" "AT+CPIN?")
        if echo "$cpin_res" | grep -qi "SIM PIN"; then
            safe_at_once "$AT_PORT" "AT+CPIN=\"$pincode\"" >/dev/null
            echo "tried" > /var/run/duydoan5g_pin_tried
            sleep 2
        fi
    fi
}

at_dial_activate() {
    [ -c "$AT_PORT" ] || find_working_at_port || return 0
    local pdp_str="IPV4V6" act_cmd=""
    case "$pdptype" in
        ip|ipv4) pdp_str="IP" ;;
        ipv6) pdp_str="IPV6" ;;
    esac
    safe_at_once "$AT_PORT" "AT+CGDCONT=1,\"$pdp_str\",\"$apn\"" >/dev/null
    case "$ATI_INFO" in
        *Quectel*) act_cmd='AT+QNETDEVCTL=3,1,1' ;;
        *Fibocom*|*FIBOCOM*|*FM350*)
            [ "$NET_DRV" = "mtk_t7xx" ] && act_cmd='AT+CGACT=1,1' || act_cmd='AT+GTRNDIS=1,1'
            ;;
        *Sierra*) act_cmd='AT!SCACT=1,1' ;;
        *Huawei*|*HUAWEI*) act_cmd="AT^NDISDUP=1,1,\"$apn\"" ;;
        *Meig*|*MeiG*|*MEIG*) act_cmd='AT$QCRMCALL=1,1,3,2,1' ;;
        *Simcom*|*SIMCOM*) act_cmd='AT$QCRMCALL=1,1' ;;
        *Neoway*) act_cmd='AT$MYUSBNETACT=1,1' ;;
        *Gosuncn*) act_cmd='AT+ZECMCALL=1' ;;
        *) act_cmd='AT+CGACT=1,1' ;;
    esac
    logger -t duydoan5g "Sending AT dial command ($act_cmd) on $AT_PORT"
    safe_at_once "$AT_PORT" "$act_cmd" >/dev/null
    sleep 2
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
        [ -n "$gw4" ] && proto_add_ipv4_route 0.0.0.0 0 "$gw4" "" "$metric"
    fi
    if [ -n "$extra_dns" ]; then
        for d in $extra_dns; do
            [ "$d" = "0.0.0.0" ] || [ -z "$d" ] && continue
            proto_add_dns_server "$d"
            added_dns="$added_dns $d"
        done
    elif [ -f "$LOG_FILE" ]; then
        for d in $(grep -E 'dns[12] = [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$LOG_FILE" 2>/dev/null | tail -n 2 | awk '{print $NF}'); do
            [ "$d" = "0.0.0.0" ] || [ -z "$d" ] && continue
            proto_add_dns_server "$d"
            added_dns="$added_dns $d"
        done
    fi
    for d in 8.8.8.8 1.1.1.1; do
        case " $added_dns " in *" $d "*) ;; *) proto_add_dns_server "$d" ;; esac
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
    local cid4 settings4 v4 m4 gw4 d1 d2
    cid4=$(uqmi -s -d "$CTRL_DEV" -t 2000 --get-client-id wds 2>/dev/null)
    case "$cid4" in ''|*[!0-9]*) return 1 ;; esac

    uqmi -s -d "$CTRL_DEV" -t 5000 --set-client-id "wds,$cid4" --set-ip-family ipv4 \
        --start-network --apn "$apn" --keep-client-id wds >/dev/null 2>&1 || {
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

    rm -f /tmp/quectel_dialing
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

run_umbim_fallback() {
    logger -t duydoan5g "Switching to native umbim fallback on $CTRL_DEV ($IFNAME)"
    stop_competing_dialers
    ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
    ip link set dev "$IFNAME" up 2>/dev/null || true

    local tid=2 tries=0 ok=0 pdp_req="ipv4v6:" mbimconfig
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
    timeout 12 umbim -n -t "$tid" -d "$CTRL_DEV" connect "$pdp_req$apn" >/dev/null 2>&1 || {
        tid=$((tid + 1))
        timeout 12 umbim -n -t "$tid" -d "$CTRL_DEV" connect "$apn" "none" >/dev/null 2>&1 || { UMBIM_ACTIVE=0; return 1; }
    }
    tid=$((tid + 1))
    UMBIM_TID="$tid"
    mbimconfig=$(timeout 8 umbim -n -t "$tid" -d "$CTRL_DEV" config 2>/dev/null)
    UMBIM_TID=$((tid + 1))

    local cidr4 m4 v4 gw4 dns4 cidr6 v6 m6 gw6
    cidr4=$(echo "$mbimconfig" | awk '/ipv4address:/{print $2; exit}')
    v4="${cidr4%/*}"; m4="${cidr4#*/}"; [ "$m4" = "$cidr4" ] && m4=30
    gw4=$(echo "$mbimconfig" | awk '/ipv4gateway:/{print $2; exit}')
    dns4=$(echo "$mbimconfig" | awk '/ipv4dnsserver:/{printf "%s ", $2}')
    cidr6=$(echo "$mbimconfig" | awk '/ipv6address:/{print $2; exit}')
    v6="${cidr6%/*}"; m6="${cidr6#*/}"; [ "$m6" = "$cidr6" ] && m6=64
    gw6=$(echo "$mbimconfig" | awk '/ipv6gateway:/{print $2; exit}')

    [ -n "$v4" ] || [ -n "$v6" ] || {
        timeout 4 umbim -n -t "$UMBIM_TID" -d "$CTRL_DEV" disconnect >/dev/null 2>&1 || true
        UMBIM_ACTIVE=0
        return 1
    }

    rm -f /tmp/quectel_dialing
    publish_netifd_up "$v4" "$m4" "$gw4" "$v6" "$m6" "$gw6" "$dns4"
    logger -t duydoan5g "Connected via umbim fallback! IP: $v4, GW: $gw4, IPv6: $v6"

    while [ "$STOP_REQ" = "0" ] && [ -d "/sys/class/net/$IFNAME" ]; do
        clamp_mtu
        local live4
        live4=$(ip -4 addr show dev "$IFNAME" 2>/dev/null | awk '/inet /{print $2; exit}')
        [ -n "$v4" ] && [ -z "$live4" ] && break
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

rotate_cm_log() {
    [ -f "$LOG_FILE" ] || return 0
    local lines
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then
        tail -n 100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

wake_hardware
detect_endpoint || exit 1
logger -t duydoan5g "Starting 5G supervised dialer on $IFNAME (Mode: $MODE, Driver: ${NET_DRV:-unknown}, Ctrl: ${CTRL_DEV:-none}, APN: $apn)"

pre_dial_prepare

if [ "$MODE" = "at_dhcp" ]; then
    at_dial_activate
    ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
    ip link set dev "$IFNAME" up 2>/dev/null || true
    export INTERFACE="$interface"
    exec /sbin/udhcpc -f -p "$PID_FILE" -i "$IFNAME" -s /lib/netifd/dhcp.script
fi

fail_streak=0
while [ "$STOP_REQ" = "0" ]; do
    [ -d "/sys/class/net/$IFNAME" ] || detect_endpoint || exit 1
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
        set -- -i "$cm_if"
        case "$pdptype" in
            ip|ipv4) set -- "$@" -4 ;;
            ipv6) set -- "$@" -6 ;;
            *) set -- "$@" -4 -6 ;;
        esac
        if [ -n "$apn" ]; then
            set -- "$@" -s "$apn"
            if [ -n "$username" ] && [ -n "$password" ]; then
                case "$auth" in
                    pap|1) auth_code=1 ;;
                    chap|2) auth_code=2 ;;
                    mschapv2|both|3) auth_code=3 ;;
                    *) auth_code=0 ;;
                esac
                set -- "$@" "$username" "$password" "$auth_code"
            fi
        fi
        [ -n "$pincode" ] && set -- "$@" -p "$pincode"
        set -- "$@" -d
        case "$local_qcm" in
            */quectel-CM-M) set -- "$@" -D -M "$metric" ;;
        esac
        set -- "$@" -f "$LOG_FILE"

        ip link set dev "$IFNAME" mtu "$mtu" 2>/dev/null || true
        ip link set dev "$IFNAME" up 2>/dev/null || true
        touch /tmp/quectel_dialing
        : > "$LOG_FILE"

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
                rm -f /tmp/quectel_dialing
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
                touch /tmp/quectel_dialing
            elif [ "$is_up" = "0" ]; then
                connecting_sec=$((connecting_sec + 1))
                if [ "$connecting_sec" -ge 45 ]; then
                    logger -t duydoan5g "Dial handshake stalled 45s on $IFNAME; cycling $local_qcm"
                    stop_cm_graceful "$CM_PID" "$CM_START"
                    break
                fi
            fi

            ticks=$((ticks + 1))
            [ $((ticks % 60)) -eq 0 ] && rotate_cm_log
            [ "$is_up" = "1" ] && sleep 4 || sleep 1
        done

        wait "$CM_PID" 2>/dev/null || true
        CM_PID=""; CM_START=""
        rm -f /tmp/quectel_dialing "$PID_FILE"
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
        if [ "$MODE" = "cm_mbim" ] && [ -x /sbin/umbim ]; then
            run_umbim_fallback
            fail_streak=0
        elif [ "$MODE" = "cm_qmi" ] && command -v uqmi >/dev/null 2>&1; then
            run_uqmi_fallback
            fail_streak=0
        fi
    fi

    [ "$STOP_REQ" = "0" ] || break
    backoff=$((4 + fail_streak * 2))
    [ "$backoff" -gt 15 ] && backoff=15
    sleep "$backoff"
done
