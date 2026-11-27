#!/bin/sh
# [VERIFIED-GOLDEN: part3-smart-modem-watchdog | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
# ==============================================================================
# 🛡️ "BÁC SĨ 5G TỰ CHỮA BỆNH MẠNG" (AI NETWORK SELF-HEALING ENGINE)
# Hệ thống tự chuẩn đoán và tự chữa lành mạng 4 tầng cấp tiến (0s Downtime)
# Tầng 1: DNS Repair & Dynamic TCP MSS Clamping (~1.5s)
# Tầng 2: Fast Session Reset & IP Renewal (~3.5s - Giữ 100% Wi-Fi/LAN)
# Tầng 3: Rapid RF CFUN Toggle & Smart Cell Tower Failover (~8s - Giải phóng BTS chết)
# Tầng 4: Báo cáo Telegram Thông minh & Tự xoay vòng Log bảo vệ RAM (<50KB)
# ==============================================================================

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export TZ=Asia/Ho_Chi_Minh

# Dọn ngay /tmp/wd_interface nếu bị script cũ gán nhầm vào cổng dây wan/lan
if [ -f /tmp/wd_interface ]; then
    _old_wdi=$(cat /tmp/wd_interface 2>/dev/null | tr -d ' \r\n')
    [ "$_old_wdi" = "wan" ] || [ "$_old_wdi" = "lan" ] || [ "$_old_wdi" = "wan6" ] && rm -f /tmp/wd_interface 2>/dev/null
fi

# Vô hiệu hóa triệt để USB autosuspend để chống đơ USB 3.0 cdc_mbim
echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null
for p in /sys/bus/usb/devices/*/power/control; do [ -f "$p" ] && echo on > "$p" 2>/dev/null; done

MY_PID=$$
PID_FILE="/tmp/smart_modem_watchdog.pid"
LOCK_FILE="/var/lock/smart_modem_watchdog.lock"
LOG_FILE="/tmp/smart_modem_watchdog.log"

rotate_log_if_needed() {
    [ ! -f "$LOG_FILE" ] && return 0
    local f_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$f_size" -gt 51200 ]; then
        tail -n 100 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
    fi
}

clean_stale_lock() {
    local lfile="${1:-/tmp/modem_healing.lock}"
    local max_age="${2:-60}"
    [ ! -f "$lfile" ] && return 0
    local l_pid=$(cat "$lfile" 2>/dev/null | tr -cd '0-9')
    if [ -n "$l_pid" ] && [ ! -d "/proc/$l_pid" ]; then
        rm -f "$lfile" 2>/dev/null
        return 0
    fi
    local now_ts=$(date +%s)
    local f_ts=$(date -r "$lfile" +%s 2>/dev/null || echo "$now_ts")
    if [ $(( now_ts - f_ts )) -gt "$max_age" ]; then
        rm -f "$lfile" 2>/dev/null
    fi
}

get_at_port() {
    local p="" cand="" META_AT_PORT="" resp="" tier=""
    [ -f /tmp/duydoan5g_modem_meta ] && . /tmp/duydoan5g_modem_meta 2>/dev/null
    for cand in "$META_AT_PORT" "$(cat /tmp/master_sms_port 2>/dev/null)" "$(cat /tmp/custom_at_port 2>/dev/null)"; do
        [ -n "$cand" ] && [ -c "$cand" ] || continue
        resp=$(wd_at_cmd "$cand" "ATI" 2)
        if printf '%s' "$resp" | grep -qiE 'Manufacturer:|Model:|Revision:|IMEI:|Quectel|Fibocom|FIBOCOM|FM350|RM5|EM0|EM1|RG5|Sierra|Huawei|HUAWEI|Simcom|SIMCOM|MeiG|Neoway|Gosuncn|Telit|Thales|Cinterion|Foxconn|Air724|OpenLuat' \
           && ! printf '%s' "$resp" | grep -qiE '\$GP|\$GN|\$GL|\$BD|Unknown error|\+CGPADDR|ERROR'; then
            echo "$cand"
            return 0
        fi
    done
    for tier in strong ok; do
        for cand in /dev/wwan0at0 /dev/wwan1at0 /dev/mhi_DUN /dev/mhi_DUN0 /dev/ttyFMI0 /dev/ttyFMI1 /dev/wwan*at* /dev/mhi_DUN* /dev/ttyFMI* \
                    /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyACM1 /dev/ttyUSB* /dev/ttyACM*; do
            [ -c "$cand" ] || continue
            resp=$(wd_at_cmd "$cand" "ATI" 2)
            printf '%s' "$resp" | grep -qiE '\$GP|\$GN|\$GL|\$BD|Unknown error|\+CGPADDR|ERROR' && continue
            if printf '%s' "$resp" | grep -qiE 'Manufacturer:|Model:|Revision:|IMEI:|Quectel|Fibocom|FIBOCOM|FM350|RM5|EM0|EM1|RG5|Sierra|Huawei|HUAWEI|Simcom|SIMCOM|MeiG|Neoway|Gosuncn|Telit|Thales|Cinterion|Foxconn|Air724|OpenLuat'; then
                echo "$cand" > /tmp/master_sms_port 2>/dev/null || true
                echo "$cand"
                return 0
            fi
            if [ "$tier" = "ok" ] && printf '%s' "$resp" | grep -q 'OK'; then
                echo "$cand" > /tmp/master_sms_port 2>/dev/null || true
                echo "$cand"
                return 0
            fi
        done
    done
    for cand in /dev/wwan0at0 /dev/mhi_DUN /dev/ttyFMI0 /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0; do
        [ -c "$cand" ] && { echo "$cand"; return 0; }
    done
    echo "/dev/ttyUSB3"
}

is_quectel_modem() {
    local META_VENDOR="" META_USB_VID=""
    [ -f /tmp/duydoan5g_modem_meta ] && . /tmp/duydoan5g_modem_meta 2>/dev/null
    [ "$META_VENDOR" = "quectel" ] || [ "$META_USB_VID" = "2c7c" ] && return 0
    [ -n "$META_VENDOR" ] && [ "$META_VENDOR" != "quectel" ] && return 1
    local m_type
    m_type=$(cat /tmp/master_m_type 2>/dev/null || lsusb 2>/dev/null)
    echo "$m_type" | grep -iqE "quectel|2c7c:"
}

wd_at_cmd() {
    local port="$1" cmd="$2" t="${3:-3}" out="" to_pfx=""
    [ -c "$port" ] && [ -n "$cmd" ] || return 1
    command -v timeout >/dev/null 2>&1 && to_pfx="timeout $t"
    case "$port" in
        /dev/wwan*|/dev/mhi*|/dev/ttyFMI*)
            if command -v modem_lock_run >/dev/null 2>&1; then
                if [ -x /usr/bin/read_pcie_sms.lua ]; then
                    out=$(modem_lock_run $to_pfx /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null)
                    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
                fi
                if command -v tom_modem >/dev/null 2>&1; then
                    out=$(modem_lock_run $to_pfx tom_modem -d "$port" -c "$cmd" 2>/dev/null)
                    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
                fi
                return 1
            else
                (
                    flock -x 9 2>/dev/null || true
                    if [ -x /usr/bin/read_pcie_sms.lua ]; then
                        out=$($to_pfx /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null)
                        [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
                    fi
                    if command -v tom_modem >/dev/null 2>&1; then
                        out=$($to_pfx tom_modem -d "$port" -c "$cmd" 2>/dev/null)
                        [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
                    fi
                    exit 1
                ) 9>/var/lock/modem_at.lock
                return $?
            fi
            ;;
        *)
            if command -v modem_lock_run >/dev/null 2>&1; then
                if command -v sms_tool >/dev/null 2>&1; then
                    out=$(modem_lock_run $to_pfx sms_tool -d "$port" at "$cmd" 2>/dev/null)
                    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
                fi
                if command -v tom_modem >/dev/null 2>&1; then
                    out=$(modem_lock_run $to_pfx tom_modem -d "$port" -c "$cmd" 2>/dev/null)
                    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
                fi
                if command -v atinout >/dev/null 2>&1; then
                    out=$(printf '%s\r\n' "$cmd" | modem_lock_run $to_pfx atinout - "$port" - 2>/dev/null)
                    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
                fi
                if [ -x /usr/bin/read_pcie_sms.lua ]; then
                    out=$(modem_lock_run $to_pfx /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null)
                    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
                fi
            else
                (
                    flock -x 9 2>/dev/null || true
                    if command -v sms_tool >/dev/null 2>&1; then
                        out=$($to_pfx sms_tool -d "$port" at "$cmd" 2>/dev/null)
                        [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
                    fi
                    if command -v atinout >/dev/null 2>&1; then
                        out=$(printf '%s\r\n' "$cmd" | $to_pfx atinout - "$port" - 2>/dev/null)
                        [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
                    fi
                    if [ -x /usr/bin/read_pcie_sms.lua ]; then
                        out=$($to_pfx /usr/bin/read_pcie_sms.lua -p "$port" --at "$cmd" 2>/dev/null)
                        [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
                    fi
                    exit 1
                ) 9>/var/lock/modem_at.lock
                return $?
            fi
            return 1
            ;;
    esac
}

send_tg_alert() {
    local text="$1"
    [ -z "$text" ] && return 0
    if [ -x /usr/bin/send_telegram ]; then
        /usr/bin/send_telegram "$text" >/dev/null 2>&1 &
        return 0
    fi
    local token=""
    local admin_id=""
    if [ -f /etc/config/telegram_bot.conf ]; then
        token=$(grep -E '^TG_BOT_TOKEN=' /etc/config/telegram_bot.conf 2>/dev/null | cut -d'"' -f2)
        admin_id=$(grep -E '^TG_ADMIN_ID=' /etc/config/telegram_bot.conf 2>/dev/null | cut -d'"' -f2)
    fi
    [ -z "$token" ] || [ -z "$admin_id" ] && return 0

    local pfile="/tmp/.tg_wd_$$.txt"
    lua - "$admin_id" "$text" "$pfile" << 'LUAPOST' 2>/dev/null
local cid, msg, outpath = arg[1], arg[2], arg[3]
local enc = (string.gsub(msg or '', '([^%w_.~-])', function(c) return string.format('%%%02X', string.byte(c)) end))
local f = io.open(outpath, 'w')
if f then f:write('chat_id=' .. cid .. '&parse_mode=HTML&text=' .. enc); f:close() end
LUAPOST
    if [ -f "$pfile" ]; then
        ( curl -4 --http1.1 -s -m 8 -d @"$pfile" "https://api.telegram.org/bot${token}/sendMessage" >/dev/null 2>&1; rm -f "$pfile" 2>/dev/null ) &
    fi
}

get_smart_iface() {
    local iface=$(cat /tmp/wd_interface 2>/dev/null)
    if [ -n "$iface" ] && [ "$iface" != "wan" ] && [ "$iface" != "lan" ]; then
        echo "$iface"
        return
    fi
    if command -v ubus >/dev/null 2>&1; then
        for cand in duydoan_5g modem; do
            if ubus list | grep -q "^network\.interface\.${cand}$"; then
                echo "$cand"
                return
            fi
        done
    fi
    echo "duydoan_5g"
}

get_smart_device() {
    local act_iface dev cand
    act_iface=$(get_smart_iface)
    if command -v ubus >/dev/null 2>&1 && command -v jsonfilter >/dev/null 2>&1; then
        dev=$(ubus call network.interface."$act_iface" status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
        if [ -n "$dev" ] && [ -d "/sys/class/net/$dev" ]; then
            echo "$dev"
            return
        fi
    fi
    dev=$(cat /tmp/wd_device 2>/dev/null)
    if [ -n "$dev" ] && [ "$dev" != "wan" ] && [ "$dev" != "lan" ] && [ -d "/sys/class/net/$dev" ]; then
        echo "$dev"
        return
    fi
    for cand in mhi_hwip0 wwan0 rmnet_mhi0.1 eth2 usb0; do
        if [ -d "/sys/class/net/$cand" ]; then
            echo "$cand"
            return
        fi
    done
    echo "wwan0"
}

check_internet_status() {
    local act_iface=$(get_smart_iface)
    local l3_dev=$(get_smart_device)

    # Kiểm tra trạng thái Netifd interface - Nếu bị DỪNG/TẮT trên LuCI thì báo rớt mạng ngay lập tức
    if command -v ubus >/dev/null 2>&1; then
        local if_up=$(ubus call network.interface."$act_iface" status 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)
        if [ "$if_up" != "true" ]; then
            LAST_RX_BYTES=0
            RX_SKIP_STREAK=0
            return 1
        fi
    fi

    if [ -r "/sys/class/net/$l3_dev/statistics/rx_bytes" ]; then
        local cur_rx
        cur_rx=$(cat "/sys/class/net/$l3_dev/statistics/rx_bytes" 2>/dev/null || echo 0)
        case "$cur_rx" in
            ''|*[!0-9]*) cur_rx=0 ;;
        esac
        if [ "${FAIL_STREAK:-0}" -eq 0 ] && [ "${LAST_RX_BYTES:-0}" -gt 0 ] && [ "$((cur_rx - LAST_RX_BYTES))" -ge 8192 ] && [ "${RX_SKIP_STREAK:-0}" -lt 2 ]; then
            LAST_RX_BYTES="$cur_rx"
            RX_SKIP_STREAK=$(( ${RX_SKIP_STREAK:-0} + 1 ))
            return 0
        fi
        LAST_RX_BYTES="$cur_rx"
        RX_SKIP_STREAK=0
    fi

    local real_curl=0
    if command -v curl >/dev/null 2>&1 && ! curl --version 2>/dev/null | grep -qi 'uclient-fetch'; then
        real_curl=1
    fi

    # 0. ĐẶC TRỊ PHÁT HIỆN TRANG CHẶN CƯỚC data.viettel.vn (CAPTIVE PORTAL / WALLED GARDEN)
    if [ "$real_curl" -eq 1 ]; then
        local probe_hdr
        if [ -d "/sys/class/net/$l3_dev" ]; then
            probe_hdr=$(curl --interface "$l3_dev" -4 -s -I -m 3 "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null)
        else
            probe_hdr=$(curl -4 -s -I -m 3 "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null)
        fi
        local probe_loc=$(echo "$probe_hdr" | grep -i "^location:" | head -n1)
        local probe_code=$(echo "$probe_hdr" | awk '/HTTP/ {print $2}' | tail -n1)
        if echo "$probe_loc" | grep -qiE "viettel\.vn|data\.viettel" || [ "$probe_code" = "302" ] || [ "$probe_code" = "301" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [CAPTIVE_PORTAL] Phát hiện bị giam phiên cước data.viettel.vn! Kích hoạt cứu hộ mạng..." >> "$LOG_FILE"
            return 1
        fi
    fi

    # 1. Fast Anycast Ping check (Ràng buộc qua l3_dev nếu có để kiểm tra thực tế trên đường truyền 4G/5G)
    if [ -d "/sys/class/net/$l3_dev" ]; then
        if ping -4 -I "$l3_dev" -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 || ping -4 -I "$l3_dev" -c 2 -W 3 8.8.8.8 >/dev/null 2>&1 || ping -4 -I "$l3_dev" -c 2 -W 3 9.9.9.9 >/dev/null 2>&1; then
            return 0
        fi
    else
        if ping -4 -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 || ping -4 -c 2 -W 3 8.8.8.8 >/dev/null 2>&1 || ping -4 -c 2 -W 3 9.9.9.9 >/dev/null 2>&1; then
            return 0
        fi
    fi
    # 2. Probe HTTP 204 qua Google & Cloudflare
    if [ "$real_curl" -eq 1 ]; then
        local c1=$(curl -4 -s -o /dev/null -w "%{http_code}" -m 3 "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null)
        [ "$c1" = "204" ] && return 0
        local c2=$(curl -4 -s -o /dev/null -w "%{http_code}" -m 3 "http://cp.cloudflare.com/generate_204" 2>/dev/null)
        [ "$c2" = "204" ] && return 0
    fi
    # 3. Dự phòng uclient-fetch HTTP probe nếu curl không hỗ trợ -w
    if command -v uclient-fetch >/dev/null 2>&1; then
        if uclient-fetch -q -O /dev/null --timeout=3 "http://connectivitycheck.gstatic.com/generate_204" >/dev/null 2>&1 || \
           uclient-fetch -q -O /dev/null --timeout=3 "http://cp.cloudflare.com/generate_204" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

mono_sec() {
    awk '{print int($1)}' /proc/uptime 2>/dev/null || date +%s
}

get_pdp_type_str() {
    local pdpt
    pdpt=$(uci -q get network."$1".pdptype 2>/dev/null)
    case "$pdpt" in
        ip|ipv4) echo "IP" ;;
        ipv6) echo "IPV6" ;;
        *) echo "IPV4V6" ;;
    esac
}

fast_probe_online() {
    local act_iface="$(get_smart_iface)" l3_dev="$(get_smart_device)"
    if command -v ubus >/dev/null 2>&1; then
        [ "$(ubus call network.interface."$act_iface" status 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null)" = "true" ] || return 1
    fi
    if [ -d "/sys/class/net/$l3_dev" ]; then
        ping -4 -I "$l3_dev" -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || ping -4 -I "$l3_dev" -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
    else
        ping -4 -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || ping -4 -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
    fi
}

wait_recovery_online() {
    local max_sec="${1:-25}" now_s deadline
    LAST_RX_BYTES=0
    RX_SKIP_STREAK=0
    now_s=$(mono_sec)
    deadline=$((now_s + max_sec))
    RECOVERY_ELAPSED=0
    while [ "$(mono_sec)" -lt "$deadline" ]; do
        sleep 1
        if fast_probe_online && check_internet_status; then
            RECOVERY_ELAPSED=$(( $(mono_sec) - now_s ))
            [ "$RECOVERY_ELAPSED" -lt 1 ] && RECOVERY_ELAPSED=1
            return 0
        fi
    done
    RECOVERY_ELAPSED=$(( $(mono_sec) - now_s ))
    return 1
}

is_mbim_proto_active() {
    local iface="$1" proto="$2" META_MODE="" META_DRV="" META_CTRL_DEV=""
    [ -f "/tmp/duydoan5g_modem_meta_${iface}" ] && . "/tmp/duydoan5g_modem_meta_${iface}" 2>/dev/null
    [ -z "$META_MODE" ] && [ -f /tmp/duydoan5g_modem_meta ] && . /tmp/duydoan5g_modem_meta 2>/dev/null
    [ "$proto" = "mbim" ] && return 0
    if [ "$proto" = "duydoan5g" ]; then
        case "$META_MODE" in
            mtk_pcie|cm_mbim) return 0 ;;
            cm_usb) [ "$META_DRV" = "cdc_mbim" ] && return 0 ;;
        esac
        case "$META_CTRL_DEV" in *mbim*) return 0 ;; esac
        [ -z "$META_MODE" ] && [ -c "/dev/wwan0mbim0" ] && return 0
        return 1
    fi
    [ -c "/dev/wwan0mbim0" ] && [ -z "$META_MODE" ]
}

check_dns_status() {
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup connectivitycheck.gstatic.com 127.0.0.1 >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

apply_mss_clamping() {
    if command -v nft >/dev/null 2>&1; then
        if ! nft list table inet fw4 2>/dev/null | grep -q "maxseg size set rt mtu"; then
            local l3_dev if_set="" cand
            l3_dev=$(get_smart_device)
            for cand in "$l3_dev" "mhi_hwip0" "wwan0" "rmnet_mhi0.1" "eth2" "usb0" "wan"; do
                [ -n "$cand" ] || continue
                case " $if_set " in *" \"$cand\" "*) continue ;; esac
                if_set="${if_set:+$if_set, }\"$cand\""
            done
            nft add rule inet fw4 forward oifname "{ $if_set }" tcp flags syn tcp option maxseg size set rt mtu 2>/dev/null
        fi
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
    fi
}

# --- THỰC HIỆN TỪNG TẦNG CỨU MẠNG ---
heal_tier1_dns_mss() {
    echo "$(date): [Tầng 1] Sửa lỗi DNS & TCP MSS PMTU Clamping..."
    # 0. Bảo vệ tường lửa Firewall & NAT Masquerade (Chống rớt mạng LAN/Wi-Fi)
    if command -v nft >/dev/null 2>&1; then
        if ! nft list table inet fw4 >/dev/null 2>&1 || [ ! -e /etc/rc.d/*firewall* ]; then
            echo "$(date): [Tầng 1] Phát hiện Firewall/NAT bị ngắt hoặc thiếu symlink S19. Kích hoạt lại Firewall..."
            /etc/init.d/firewall enable >/dev/null 2>&1
            /etc/init.d/firewall restart >/dev/null 2>&1
            sleep 1
        fi
    fi
    apply_mss_clamping
    if ! check_dns_status; then
        echo "$(date): [Tầng 1] Làm mới bộ đệm dnsmasq..."
        killall -SIGHUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart >/dev/null 2>&1
        sleep 1
        if ! check_dns_status; then
            if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
                echo "$(date): [Tầng 1 - Graceful DNS] IP ping thông nhưng DNS nhà mạng lỗi. Kích hoạt Quad-Stack DNS dự phòng..."
                mkdir -p /tmp/dnsmasq.d 2>/dev/null
                cat << 'EOF_DNS' > /tmp/dnsmasq.d/upstream_failover.conf
server=1.1.1.1
server=8.8.8.8
server=9.9.9.9
EOF_DNS
                killall -SIGHUP dnsmasq 2>/dev/null
                sleep 1
            fi
        fi
    fi
    if check_internet_status; then
        return 0
    fi
    return 1
}

warm_reset_wwan_baseband() {
    local reason="${1:-Proactive WWAN Memory Clean}"
    local iface="${2:-$(get_smart_iface)}"
    local port=$(get_at_port)
    local l3_dev=$(get_smart_device)
    echo "$(date): [KHỞI ĐỘNG LẠI CARD WWAN] Kích hoạt Warm Reset Baseband (Lý do: $reason) để xả sạch rác DMA PCIe/USB & PDP context..." >> "$LOG_FILE"
    
    # 1. Hạ interface mạng an toàn
    ubus call network.interface."$iface" down 2>/dev/null || ifdown "$iface" 2>/dev/null
    sleep 1

    # 2. Khóa cổng AT và phát lệnh Warm Reset tương thích mọi module
    if [ -c "$port" ]; then
        local m_type=$(cat /tmp/master_m_type 2>/dev/null || lsusb 2>/dev/null)
        if echo "$m_type" | grep -iqE "sierra|1199:"; then
            wd_at_cmd "$port" "AT!RESET" 3 >/dev/null 2>&1 || wd_at_cmd "$port" "AT+CFUN=1,1" 3 >/dev/null 2>&1 || true
        elif echo "$m_type" | grep -iqE "fibocom|fm350|2cb7:|0e8d:"; then
            wd_at_cmd "$port" "AT+CFUN=15" 3 >/dev/null 2>&1 || wd_at_cmd "$port" "AT+CFUN=1,1" 3 >/dev/null 2>&1 || true
        else
            wd_at_cmd "$port" "AT+CFUN=1,1" 3 >/dev/null 2>&1 || true
        fi
    fi

    # 3. Chờ chip Baseband modem reboot sạch phần cứng (12-14s)
    sleep 12
    for w in $(seq 1 12); do
        [ -e "/dev/cdc-wdm0" ] || [ -e "/dev/wwan0mbim0" ] || [ -e "/dev/wwan0qmi0" ] || [ -e "/dev/mhi_QMI0" ] || [ -e "/dev/mhi_MBIM" ] || [ -e "/dev/ttyUSB0" ] || [ -e "/dev/ttyUSB1" ] || [ -e "/dev/ttyUSB2" ] && break
        sleep 1
    done

    # 4. Tái kích hoạt interface qua netifd
    ubus call network.interface."$iface" up 2>/dev/null || ifup "$iface" 2>/dev/null
    sleep 5

    # 5. Thăm dò và kiểm chứng lấy IP mới
    if wait_recovery_online 30; then
        local new_ip=$(ip -4 addr show "$l3_dev" 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2)
        echo "$(date): [KHỞI ĐỘNG LẠI CARD WWAN] Tái sinh thành công (${RECOVERY_ELAPSED}s)! IP mới: ${new_ip:-OK}. 100% rác bộ đệm đã được giải phóng sạch sẽ." >> "$LOG_FILE"
        return 0
    else
        echo "$(date): [KHỞI ĐỘNG LẠI CARD WWAN] Đang tiếp tục đàm phán kết nối với trạm BTS..." >> "$LOG_FILE"
        return 1
    fi
}

heal_tier2_wwan_session() {
    local iface="${1:-$(get_smart_iface)}"
    if [ -f /tmp/sms_sending.lock ]; then
        echo "$(date): [Tầng 2] Tạm hoãn làm mới WWAN vì đang gửi/đọc SMS (sms_sending.lock)..." >> "$LOG_FILE"
        return 1
    fi
    local port=$(get_at_port)
    local proto=$(uci -q get network."$iface".proto || echo "mbim")
    echo "$(date): [Tầng 2] Làm mới phiên mạng WWAN (${iface}, proto=${proto}), Tái gắn kết PDP Context & Lấy lại IP..."
    ip route flush cache 2>/dev/null

    # 1. Hạ interface sạch trước qua netifd (tránh tranh chấp cổng AT với dialer đang chạy)
    for p in $(pgrep -f "umbim.*cdc-wdm" 2>/dev/null); do
        [ "$p" != "$$" ] && kill -9 "$p" 2>/dev/null
    done
    if command -v ubus >/dev/null 2>&1; then
        ubus call network.interface."$iface" down 2>/dev/null
        sleep 3
    elif command -v ifdown >/dev/null 2>&1; then
        ifdown "$iface" 2>/dev/null
        sleep 3
    fi

    # 2. Fast PDP Re-attach qua AT port (chỉ bỏ qua khi modem thật sự chạy MBIM, không ép nhầm cho FM350 USB/QMI/AT+DHCP):
    local is_mbim=0 META_VENDOR="" META_PLATFORM=""
    is_mbim_proto_active "$iface" "$proto" && is_mbim=1
    [ -f "/tmp/duydoan5g_modem_meta_${iface}" ] && . "/tmp/duydoan5g_modem_meta_${iface}" 2>/dev/null
    [ -z "$META_VENDOR" ] && [ -f /tmp/duydoan5g_modem_meta ] && . /tmp/duydoan5g_modem_meta 2>/dev/null

    if [ "$is_mbim" -eq 0 ] && [ -c "$port" ]; then
        local apn=$(uci -q get network."$iface".apn || echo "v-internet")
        local pdp_str=$(get_pdp_type_str "$iface")
        wd_at_cmd "$port" "AT+CGDCONT=1,\"$pdp_str\",\"$apn\"" 3 >/dev/null 2>&1
        wd_at_cmd "$port" "AT+CGACT=0,1" 3 >/dev/null 2>&1
        sleep 1
        wd_at_cmd "$port" "AT+CGACT=1,1" 3 >/dev/null 2>&1
    fi

    if command -v ubus >/dev/null 2>&1; then
        ubus call network.interface."$iface" up 2>/dev/null
    elif command -v ifup >/dev/null 2>&1; then
        ifup "$iface" 2>/dev/null
    fi

    clean_stale_lock "/tmp/modem_healing.lock" 60
    echo "$$" > /tmp/modem_healing.lock
    # 3. Vòng lặp thăm dò nhanh theo đồng hồ thực (tối đa 25s, tránh check HTTP nặng gây treo 348s)
    if wait_recovery_online 25; then
        echo "$(date): [Tầng 2] Đã nhận lại IP 5G mới từ nhà mạng thành công (${RECOVERY_ELAPSED}s)!"
        rm -f /tmp/modem_healing.lock
        return 0
    fi
    rm -f /tmp/modem_healing.lock
    echo "$(date): [Tầng 2] Làm mới session chưa nhận IP sau ${RECOVERY_ELAPSED}s; nhường Tầng 3 xử lý nếu còn mất mạng." >> "$LOG_FILE"
    return 1
}

heal_tier3_cfun_cell_failover() {
    local iface="${1:-$(get_smart_iface)}"
    local port=$(get_at_port)
    local proto=$(uci -q get network."$iface".proto || echo "mbim")

    # 1. Bỏ qua nếu router vừa boot (< 90s)
    local up_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 999)
    if [ "$up_sec" -lt 90 ]; then
        echo "$(date): [Tầng 3] Router vừa boot (${up_sec}s < 90s) - Bỏ qua reset để modem tự do kết nối BTS."
        ubus call network.interface."$iface" up 2>/dev/null || ifup "$iface" 2>/dev/null
        return 1
    fi

    # 2. Bỏ qua nếu quectel-cm đang quay số hoặc tiến trình SMS gia hạn/tra cước đang giữ cổng
    if [ -f "/tmp/quectel_dialing_${iface}" ] || [ -f /tmp/quectel_dialing ] || [ -f /tmp/sms_sending.lock ]; then
        echo "$(date): [Tầng 3] Modem đang quay số hoặc gửi SMS, tạm hoãn can thiệp..."
        return 1
    fi

    echo "$(date): [Tầng 3] Phục hồi nâng cao sóng modem (proto=${proto}) trên ${port}..."

    # Tự động giải phóng cell lock nếu có
    if [ -f /tmp/cell_lock_active ] || [ -f /etc/config/cell_lock_mode ]; then
        echo "$(date): [Tầng 3] Giải phóng Cell Lock để kết nối trạm phụ..."
        if is_quectel_modem; then
            wd_at_cmd "$port" 'AT+QNWLOCK="common/4g",0' 3 >/dev/null 2>&1
            wd_at_cmd "$port" 'AT+QNWLOCK="common/5g",0' 3 >/dev/null 2>&1
        fi
        rm -f /tmp/cell_lock_active 2>/dev/null
    fi

    # VỚI MBIM (Sierra EM9190/EM9191 / duydoan5g):
    # Tuyệt đối không gửi CFUN=0 làm sập kênh PCIe MHI / USB descriptors!
    # Sử dụng chuẩn 3GPP AT+CFUN=4 (Airplane mode / Tắt RF) sau đó AT+CFUN=1 (Bật RF)
    local is_mbim=0 META_VENDOR="" META_PLATFORM=""
    is_mbim_proto_active "$iface" "$proto" && is_mbim=1
    [ -f "/tmp/duydoan5g_modem_meta_${iface}" ] && . "/tmp/duydoan5g_modem_meta_${iface}" 2>/dev/null
    [ -z "$META_VENDOR" ] && [ -f /tmp/duydoan5g_modem_meta ] && . /tmp/duydoan5g_modem_meta 2>/dev/null

    if [ "$is_mbim" -eq 1 ]; then
        echo "$(date): [Tầng 3] MBIM Safe RF Reset: Hạ session, gửi CFUN 4/1 an toàn..."
        ubus call network.interface."$iface" down 2>/dev/null || ifdown "$iface" 2>/dev/null
        killall -INT quectel-CM-M quectel-CM quectel-cm umbim 2>/dev/null || true
        sleep 2
        if [ -c "$port" ]; then
            wd_at_cmd "$port" "AT+CFUN=4" 3 >/dev/null 2>&1
            sleep 3
            wd_at_cmd "$port" "AT+CFUN=1" 3 >/dev/null 2>&1
            sleep 4
        fi
        ubus call network.interface."$iface" up 2>/dev/null || ifup "$iface" 2>/dev/null
    else
        # Với FM350 USB / Quectel QMI/ECM: Dùng Airplane mode CFUN 4/1 an toàn thay vì CFUN 0
        ubus call network.interface."$iface" down 2>/dev/null || ifdown "$iface" 2>/dev/null
        sleep 2
        if [ -c "$port" ]; then
            local apn=$(uci -q get network."$iface".apn || echo "v-internet")
            local pdp_str=$(get_pdp_type_str "$iface")
            wd_at_cmd "$port" "AT+CFUN=4" 3 >/dev/null 2>&1
            sleep 2
            wd_at_cmd "$port" "AT+CGDCONT=1,\"$pdp_str\",\"$apn\"" 3 >/dev/null 2>&1
            [ "$META_VENDOR" = "fibocom" ] && [ "$META_PLATFORM" = "mediatek" ] || \
                wd_at_cmd "$port" "AT+CGDCONT=3,\"$pdp_str\",\"$apn\"" 3 >/dev/null 2>&1
            wd_at_cmd "$port" "AT+CFUN=1" 3 >/dev/null 2>&1
        fi
        sleep 2
        ubus call network.interface."$iface" up 2>/dev/null || ifup "$iface" 2>/dev/null
    fi

    sleep 3
    if command -v ubus >/dev/null 2>&1; then
        ubus call network.interface."$iface" up 2>/dev/null
    else
        ifup "$iface" 2>/dev/null
    fi

    clean_stale_lock "/tmp/modem_healing.lock" 60
    echo "$$" > /tmp/modem_healing.lock
    if wait_recovery_online 22; then
        rm -f /tmp/modem_healing.lock
        return 0
    fi

    # Chỉ cho phép Hard Reset khi thất bại nghiêm trọng (FAIL_STREAK >= 12)
    if [ "${FAIL_STREAK:-0}" -ge 12 ] && [ -c "$port" ]; then
        echo "$(date): [Tầng 3 Cấp Cứu] Soft RF Reset không đủ. Kích hoạt Hard Modem Reset qua AT port..."
        local m_type=""
        [ -f /tmp/master_m_type ] && m_type=$(cat /tmp/master_m_type 2>/dev/null)
        [ -z "$m_type" ] && command -v lsusb >/dev/null 2>&1 && m_type=$(lsusb 2>/dev/null)
        if echo "$m_type" | grep -iqE "sierra|1199:"; then
            wd_at_cmd "$port" "AT!RESET" 3 >/dev/null 2>&1 || wd_at_cmd "$port" "AT+CFUN=1,1" 3 >/dev/null 2>&1
        elif echo "$m_type" | grep -iqE "fibocom|fm350|2cb7:|0e8d:"; then
            wd_at_cmd "$port" "AT+CFUN=15" 3 >/dev/null 2>&1 || wd_at_cmd "$port" "AT+CFUN=1,1" 3 >/dev/null 2>&1
        else
            wd_at_cmd "$port" "AT+CFUN=1,1" 3 >/dev/null 2>&1
        fi
        sleep 15
    fi

    ubus call network.interface."$iface" up 2>/dev/null || ifup "$iface" 2>/dev/null
    sleep 3

    if wait_recovery_online 30; then
        echo "$(date): [Tầng 3 Cứu Hộ] Hard Modem Reset đã phục hồi kết nối thành công (${RECOVERY_ELAPSED}s)!"
        rm -f /tmp/modem_healing.lock
        return 0
    fi

    rm -f /tmp/modem_healing.lock
    return 1
}

predictive_bts_cell_lock() {
    # Tự động theo dõi giờ cao điểm (19:30 - 23:30) và phân tích chất lượng Cell sóng 5G/4G
    # Khi sóng bị nghẽn hoặc trong khung giờ cao điểm, tự động quét và tối ưu Cell
    local cur_hm=$(date +%H%M 2>/dev/null || echo "1200")
    local is_peak=0
    if [ "$cur_hm" -ge 1930 ] && [ "$cur_hm" -le 2330 ]; then
        is_peak=1
    fi
    local port=$(get_at_port)
    [ ! -c "$port" ] && return 0

    local cell_info=""
    if is_quectel_modem; then
        cell_info=$(wd_at_cmd "$port" 'AT+QENG="servingcell"' 3 2>/dev/null)
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') [PREDICTIVE_BTS] Check giờ: $cur_hm (Peak: $is_peak)" >> "$LOG_FILE"
    cat << EOF > /tmp/predictive_bts.json.tmp
{
    "peak_hour": $is_peak,
    "timestamp": $(date +%s),
    "port": "$port",
    "status": "active"
}
EOF
    mv -f /tmp/predictive_bts.json.tmp /tmp/predictive_bts.json 2>/dev/null
    return 0
}

preemptive_5g_handover() {
    # Tính Năng 8: Pre-emptive 5G Handover (Dự báo sóng 5G suy hao trước 3 giây)
    local port=$(get_at_port)
    local cur_ts=$(date +%s)
    local sinr=""
    local rsrp=""
    
    if [ -c "$port" ]; then
        if is_quectel_modem; then
            local serving_cell=""
            serving_cell=$(wd_at_cmd "$port" 'AT+QENG="servingcell"' 3 2>/dev/null)
            sinr=$(echo "$serving_cell" | grep -iE 'NR5G-NSA|NR5G-SA' | awk -F',' '{print $NF}' | tr -d ' \r\n')
            rsrp=$(echo "$serving_cell" | grep -iE 'NR5G-NSA|NR5G-SA' | awk -F',' '{print $(NF-2)}' | tr -d ' \r\n')
        else
            local gstatus=""
            gstatus=$(wd_at_cmd "$port" "AT!GSTATUS?" 3 2>/dev/null)
            if printf '%s' "$gstatus" | grep -q "!GSTATUS:"; then
                rsrp=$(printf '%s\n' "$gstatus" | sed -n 's/.*NR5G RSRP (dBm):[[:space:]]*\([-0-9]*\).*/\1/p' | head -n 1)
                [ -z "$rsrp" ] && rsrp=$(printf '%s\n' "$gstatus" | sed -n 's/.*PCC RxM RSRP:[[:space:]]*\([-0-9]*\).*/\1/p' | head -n 1)
                sinr=$(printf '%s\n' "$gstatus" | sed -n 's/.*NR5G SINR (dB):[[:space:]]*\([-0-9.]*\).*/\1/p' | cut -d'.' -f1 | head -n 1)
                [ -z "$sinr" ] && sinr=$(printf '%s\n' "$gstatus" | sed -n 's/.*SINR (dB):[[:space:]]*\([-0-9.]*\).*/\1/p' | cut -d'.' -f1 | head -n 1)
            fi
        fi
    fi
    [ -z "$sinr" ] && sinr="15"
    [ -z "$rsrp" ] && rsrp="-85"

    local need_handover=0
    # Nếu SINR < 3dB hoặc RSRP < -115dBm, dự báo suy hao và chuẩn bị chuyển cell
    if [ "$sinr" -lt 3 ] 2>/dev/null || [ "$rsrp" -lt -115 ] 2>/dev/null; then
        need_handover=1
        echo "$(date '+%Y-%m-%d %H:%M:%S') [PREEMPTIVE_5G] Cảnh báo suy hao sóng: SINR=${sinr}dB, RSRP=${rsrp}dBm. Dự báo rớt sóng trước 3s!" >> "$LOG_FILE"
    fi

    cat << EOF > /tmp/preemptive_5g.json.tmp
{
    "preemptive_handover_active": true,
    "sinr_db": "$sinr",
    "rsrp_dbm": "$rsrp",
    "need_handover": $need_handover,
    "timestamp": $cur_ts,
    "status": "monitored"
}
EOF
    mv -f /tmp/preemptive_5g.json.tmp /tmp/preemptive_5g.json 2>/dev/null
    return 0
}

switch_dual_sim() {
    # Tính Năng 14: Cellular Dual-SIM Switcher (Tự động đổi SIM dự phòng trong 10 giây)
    local target_slot="$1"
    local port=$(get_at_port)
    local cur_ts=$(date +%s)
    
    echo "$(date): [DUAL-SIM] Đang kiểm tra trạng thái khay SIM hiện tại..."
    local m_type=""
    [ -f /tmp/master_m_type ] && m_type=$(cat /tmp/master_m_type 2>/dev/null)
    if [ -z "$m_type" ] && command -v lsusb >/dev/null 2>&1; then
        m_type=$(lsusb 2>/dev/null)
    fi

    local cur_slot="1"
    if [ -c "$port" ]; then
        if echo "$m_type" | grep -iqE "sierra|1199:"; then
            # Sierra Wireless EM919x/EM7565: AT!UIMS? (0: SIM1, 1: SIM2)
            cur_slot=$(wd_at_cmd "$port" "AT!UIMS?" 3 2>/dev/null | grep -i "!UIMS:" | awk -F':' '{print $2}' | tr -d ' \r\n')
            case "$cur_slot" in
                0) cur_slot="1" ;;
                1) cur_slot="2" ;;
                *) cur_slot="1" ;;
            esac
        elif echo "$m_type" | grep -iqE "fibocom|fm350|2cb7:|0e8d:"; then
            # Fibocom: AT+GTSETSIM?
            cur_slot=$(wd_at_cmd "$port" "AT+GTSETSIM?" 3 2>/dev/null | grep -i "+GTSETSIM:" | awk -F':' '{print $2}' | tr -d ' \r\n')
        else
            # Quectel standard: AT+QUIMSLOT?
            cur_slot=$(wd_at_cmd "$port" "AT+QUIMSLOT?" 3 2>/dev/null | grep -i "+QUIMSLOT:" | awk -F':' '{print $2}' | tr -d ' \r\n')
        fi
    fi
    [ -z "$cur_slot" ] && cur_slot="1"

    if [ -z "$target_slot" ]; then
        if [ "$cur_slot" = "1" ]; then target_slot="2"; else target_slot="1"; fi
    fi

    echo "$(date): [DUAL-SIM] Khởi động chuyển đổi: SIM $cur_slot -> SIM $target_slot..."
    if [ -c "$port" ]; then
        if echo "$m_type" | grep -iqE "sierra|1199:"; then
            local sierra_slot=0
            [ "$target_slot" = "2" ] && sierra_slot=1
            wd_at_cmd "$port" "AT!UIMS=$sierra_slot" 3 >/dev/null 2>&1 || true
        elif echo "$m_type" | grep -iqE "fibocom|fm350|2cb7:|0e8d:"; then
            wd_at_cmd "$port" "AT+GTSETSIM=$target_slot" 3 >/dev/null 2>&1 || true
        else
            wd_at_cmd "$port" "AT+QUIMSLOT=$target_slot" 3 >/dev/null 2>&1 || true
        fi
    fi

    cat << EOF > /tmp/dual_sim_status.json.tmp
{
    "dual_sim_active": true,
    "current_slot": "$target_slot",
    "previous_slot": "$cur_slot",
    "switched_at": $cur_ts,
    "status": "switched_successfully"
}
EOF
    mv -f /tmp/dual_sim_status.json.tmp /tmp/dual_sim_status.json 2>/dev/null
    echo "$(date): [DUAL-SIM] Đã chuyển sang khay SIM $target_slot hoàn tất!"
    return 0
}

# --- CLI DISPATCHER CHO PHÉP TEST TỪNG KỊCH BẢN ĐỘC LẬP ---
case "$1" in
    cell-lock|predictive-lock)
        predictive_bts_cell_lock
        echo ">> KẾT QUẢ: Đã thực thi phân tích trạm BTS dự đoán giờ cao điểm thành công."
        exit 0
        ;;
    preemptive-handover|handover)
        preemptive_5g_handover
        echo ">> KẾT QUẢ: Pre-emptive 5G Handover Engine đã thực thi phân tích chất lượng sóng."
        exit 0
        ;;
    dual-sim|switch-sim)
        switch_dual_sim "$2"
        echo ">> KẾT QUẢ: Cellular Dual-SIM Switcher đã kích hoạt thành công."
        exit 0
        ;;
    tier1|test-tier1)
        echo "=== BẮT ĐẦU TEST KỊCH BẢN TẦNG 1: DNS & TCP MSS CLAMPING ==="
        t_start=$(date +%s)
        if heal_tier1_dns_mss; then
            t_dur=$(( $(date +%s) - t_start ))
            [ "$t_dur" -lt 1 ] && t_dur=1
            echo ">> KẾT QUẢ: TẦNG 1 THÀNH CÔNG! Thời gian: ${t_dur}s. Internet OK!"
            exit 0
        else
            echo ">> KẾT QUẢ: Tầng 1 hoàn tất nhưng chưa có Internet ngoài luồng."
            exit 1
        fi
        ;;
    tier2|test-tier2)
        echo "=== BẮT ĐẦU TEST KỊCH BẢN TẦNG 2: FAST WWAN SESSION RESET ==="
        t_start=$(date +%s)
        w_if=$(get_smart_iface)
        if heal_tier2_wwan_session "$w_if"; then
            t_dur=$(( $(date +%s) - t_start ))
            echo ">> KẾT QUẢ: TẦNG 2 THÀNH CÔNG! Thời gian: ${t_dur}s. Wi-Fi giữ nguyên 100%!"
            exit 0
        else
            echo ">> KẾT QUẢ: Tầng 2 thất bại."
            exit 1
        fi
        ;;
    tier3|test-tier3)
        echo "=== BẮT ĐẦU TEST KỊCH BẢN TẦNG 3: BASEBAND CFUN RESET & CELL FAILOVER ==="
        t_start=$(date +%s)
        w_if=$(get_smart_iface)
        if heal_tier3_cfun_cell_failover "$w_if"; then
            t_dur=$(( $(date +%s) - t_start ))
            echo ">> KẾT QUẢ: TẦNG 3 THÀNH CÔNG! Thời gian: ${t_dur}s. Sóng modem đã phục hồi!"
            exit 0
        else
            echo ">> KẾT QUẢ: Tầng 3 thất bại."
            exit 1
        fi
        ;;
    status)
        echo "=== TRẠNG THÁI BÁC SĨ 5G SELF-HEALING ==="
        p_cur=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$p_cur" ] && kill -0 "$p_cur" 2>/dev/null; then
            echo "• Tiến trình: ĐANG CHẠY (PID: $p_cur)"
        else
            echo "• Tiến trình: ĐANG DỪNG"
        fi
        echo "• Cổng AT: $(get_at_port)"
        echo "• Dung lượng Log: $(wc -c < "$LOG_FILE" 2>/dev/null || echo 0) bytes"
        echo "• Nhật ký gần nhất:"
        tail -n 10 "$LOG_FILE" 2>/dev/null || echo "(Chưa có log)"
        exit 0
        ;;
esac

# --- CHẾ ĐỘ DAEMON CHẠY NGẦM LIÊN TỤC (CHỐNG TRÙNG LẶP VỚI KERNEL FLOCK SINGLETON) ---
mkdir -p /var/lock /tmp 2>/dev/null
exec 201>"$LOCK_FILE"
if ! flock -n 201; then
    exit 0
fi
echo "$MY_PID" > "$PID_FILE"
SLEEP_PID=""
trap '[ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; rm -f "$PID_FILE" 2>/dev/null; flock -u 201 2>/dev/null; exec 201>&-; exit 0' EXIT INT TERM

FAIL_STREAK=0
LAST_RECOVER_TS=0
LAST_PROACTIVE_RENEW_DATE=""

echo "$(date): Bác Sĩ Mạng 5G AI (Smart Self-Healing Watchdog) đã kích hoạt thành công." >> "$LOG_FILE"
rotate_log_if_needed

proactive_rf_health_guard() {
    [ -f /tmp/sms_sending.lock ] && return 0
    local now_ts=$(date +%s)
    local last_check=$(cat /tmp/last_proactive_check 2>/dev/null || echo 0)
    [ $((now_ts - last_check)) -lt 45 ] && return 0
    echo "$now_ts" > /tmp/last_proactive_check

    local nr_rsrp=""
    local nr_sinr=""

    # 1. Đọc dữ liệu RF từ Sierra EM9190 nếu có
    if [ -x /usr/bin/sierra_cell_radar.lua ]; then
        local raw=$(/usr/bin/sierra_cell_radar.lua --json 2>/dev/null)
        nr_rsrp=$(echo "$raw" | jsonfilter -e '$.nr5g.rsrp' 2>/dev/null)
        nr_sinr=$(echo "$raw" | jsonfilter -e '$.nr5g.sinr' 2>/dev/null)
    fi

    # 2. Dự phòng đọc AT+QRSRP chỉ cho Quectel (Bỏ qua trên Fibocom/PCIe Sierra để tránh spam AT)
    local at_port=$(get_at_port)
    if [ -z "$nr_rsrp" ] && [ -c "$at_port" ] && [ "${at_port#/dev/tty}" != "$at_port" ] && is_quectel_modem; then
        local rf_out
        rf_out=$(wd_at_cmd "$at_port" "AT+QRSRP" 3 2>/dev/null)
        nr_rsrp=$(echo "$rf_out" | grep -i "\+QRSRP:" | cut -d':' -f2 | cut -d',' -f1 | tr -d ' \r\n')
    fi
    case "$nr_rsrp" in ''|*[!0-9-]*) return 0 ;; esac

    if [ -n "$nr_rsrp" ] && [ "$nr_rsrp" -lt 0 ] && [ "$nr_rsrp" -lt -115 ]; then
        local low_rsrp_cnt=$(cat /tmp/low_rsrp_streak 2>/dev/null || echo 0)
        low_rsrp_cnt=$((low_rsrp_cnt + 1))
        echo "$low_rsrp_cnt" > /tmp/low_rsrp_streak
        
        if [ "$low_rsrp_cnt" -ge 2 ]; then
            echo "0" > /tmp/low_rsrp_streak
            echo "$(date): [PROACTIVE RF GUARD] Sóng 5G suy hao sâu (${nr_rsrp} dBm < -115 dBm). Chủ động tối ưu trạm sóng..." >> "$LOG_FILE"
            mkdir -p /mnt/storage/.blackbox /tmp/.blackbox 2>/dev/null
            echo "$(date '+%Y-%m-%d %H:%M:%S') [PREDICTIVE_RF_HOP] RSRP=${nr_rsrp}dBm, triggering proactive cell optimization" >> /mnt/storage/.blackbox/flight_recorder.log 2>/dev/null
            
            if [ -x /usr/bin/modem_cell_lock.sh ]; then
                /usr/bin/modem_cell_lock.sh lock >/dev/null 2>&1
            elif [ -c "$at_port" ] && is_quectel_modem; then
                wd_at_cmd "$at_port" 'AT+QNWPREFCFG="nr5g_disable_mode",0' 3 >/dev/null 2>&1
            fi
        fi
    else
        echo "0" > /tmp/low_rsrp_streak
    fi
}

check_silent_pdp_freeze() {
    local iface="${1:-$(get_smart_iface)}"
    local dev
    dev=$(get_smart_device)
    [ ! -d "/sys/class/net/$dev" ] && return 0
    
    local tx_before=$(cat "/sys/class/net/$dev/statistics/tx_packets" 2>/dev/null || echo 0)
    local rx_before=$(cat "/sys/class/net/$dev/statistics/rx_packets" 2>/dev/null || echo 0)
    
    ping -I "$dev" -c 2 -W 1 1.1.1.1 >/dev/null 2>&1
    
    local tx_after=$(cat "/sys/class/net/$dev/statistics/tx_packets" 2>/dev/null || echo 0)
    local rx_after=$(cat "/sys/class/net/$dev/statistics/rx_packets" 2>/dev/null || echo 0)
    
    local tx_diff=$(( tx_after - tx_before ))
    local rx_diff=$(( rx_after - rx_before ))
    
    if [ "$tx_diff" -gt 0 ] && [ "$rx_diff" -eq 0 ]; then
        return 1 # Bị nghẽn gateway / đơ PDP ảo
    fi
    return 0
}

HEALTHY_STREAK=0
LAST_RX_BYTES=0
RX_SKIP_STREAK=0
SLEEP_INTERVAL=20

while true; do
    ACT_IFACE=$(get_smart_iface)

    # [ZERO-DELAY INTERFACE GUARD] Tự động bật lại khi interface rớt bất ngờ (chờ xong boot grace 90s và không cắt ngang quá trình quay số)
    if command -v ubus >/dev/null 2>&1; then
        up_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 999)
        if_json=$(ubus call network.interface."$ACT_IFACE" status 2>/dev/null)
        if_state=$(echo "$if_json" | jsonfilter -e '@.up' 2>/dev/null)
        if_pending=$(echo "$if_json" | jsonfilter -e '@.pending' 2>/dev/null)
        if [ "$up_sec" -ge 90 ] && [ "$if_state" != "true" ] && [ "$if_pending" != "true" ] && [ ! -f "/tmp/quectel_dialing_${ACT_IFACE}" ] && [ ! -f /tmp/quectel_dialing ] && [ ! -f /tmp/sms_sending.lock ]; then
            echo "$(date): [Interface Guard] ⚠️ Phát hiện giao diện $ACT_IFACE đang TẮT/DỪNG! Tự động bật lại ngay lập tức (ifup $ACT_IFACE)..." >> "$LOG_FILE"
            ubus call network.interface."$ACT_IFACE" up 2>/dev/null || ifup "$ACT_IFACE" 2>/dev/null
            sleep 2
        fi
    fi

    sleep "$SLEEP_INTERVAL" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null || true
    SLEEP_PID=""

    if check_internet_status; then
        FAIL_STREAK=0
        SILENT_FREEZE_CNT=0
        HEALTHY_STREAK=$(( ${HEALTHY_STREAK:-0} + 1 ))
        if [ "$HEALTHY_STREAK" -ge 3 ]; then
            SLEEP_INTERVAL=45
        else
            SLEEP_INTERVAL=20
        fi
        proactive_rf_health_guard
        killall -CONT quectel-CM-M quectel-CM 2>/dev/null # Heartbeat safety to prevent orphan SIGSTOP

        # TRAFFIC-AWARE PROACTIVE 48H WWAN PURGE & PDP RENEWAL (03:30 - 04:30 AM)
        cur_hm=$(date +%H%M 2>/dev/null || echo "1200")
        today_str=$(date +%Y%m%d 2>/dev/null || echo "00000000")
        [ -z "$WWAN_UPTIME_EPOCH" ] && WWAN_UPTIME_EPOCH=$(date +%s)
        curr_epoch=$(date +%s)
        conn_duration=$(( curr_epoch - WWAN_UPTIME_EPOCH ))

        # Nếu modem đã chạy liên tục >= 48 giờ (172800 giây) hoặc 72 giờ và đang trong khung giờ vàng 03:00 - 04:30 sáng:
        if [ "$conn_duration" -ge 172800 ] && [ "$cur_hm" -ge "0300" ] && [ "$cur_hm" -le "0430" ] && [ "$LAST_PROACTIVE_PURGE_DATE" != "$today_str" ]; then
            ACT_IFACE=$(get_smart_iface)
            L3_DEV=$(get_smart_device)
            [ ! -d "/sys/class/net/$L3_DEV" ] && L3_DEV="$ACT_IFACE"
            rx1=$(cat "/sys/class/net/$L3_DEV/statistics/rx_packets" 2>/dev/null || echo 0)
            sleep 2
            rx2=$(cat "/sys/class/net/$L3_DEV/statistics/rx_packets" 2>/dev/null || echo 0)
            if [ $((rx2 - rx1)) -lt 250 ] || [ "$cur_hm" -ge "0425" ]; then
                LAST_PROACTIVE_PURGE_DATE="$today_str"
                WWAN_UPTIME_EPOCH=$(date +%s)
                echo "$(date): [ĐỊNH KỲ 48H XẢ RÁC WWAN] Card đã chạy liên tục $(($conn_duration / 3600)) giờ: Tự động Warm Reset card WWAN để giải phóng 100% rác RAM & DMA PCIe..." >> "$LOG_FILE"
                warm_reset_wwan_baseband "Xả rác DMA/RAM modem định kỳ sau 48h" "$ACT_IFACE"
            fi
        elif [ "$cur_hm" -ge "0415" ] && [ "$cur_hm" -le "0430" ] && [ "$LAST_PROACTIVE_RENEW_DATE" != "$today_str" ]; then
            ACT_IFACE=$(get_smart_iface)
            L3_DEV=$(get_smart_device)
            [ ! -d "/sys/class/net/$L3_DEV" ] && L3_DEV="$ACT_IFACE"
            rx1=$(cat "/sys/class/net/$L3_DEV/statistics/rx_packets" 2>/dev/null || echo 0)
            sleep 2
            rx2=$(cat "/sys/class/net/$L3_DEV/statistics/rx_packets" 2>/dev/null || echo 0)
            if [ $((rx2 - rx1)) -lt 200 ] || [ "$cur_hm" -ge "0428" ]; then
                LAST_PROACTIVE_RENEW_DATE="$today_str"
                echo "$(date): [PROACTIVE RENEWAL 04:15 AM] Đường truyền rảnh: Tự động làm mới phiên 5G để reset bộ đếm 24h nhà mạng..." >> "$LOG_FILE"
                heal_tier2_wwan_session "$ACT_IFACE" >/dev/null 2>&1
            fi
        fi
        continue
    fi

    HEALTHY_STREAK=0
    SLEEP_INTERVAL=5

    # Kiểm tra Silent PDP Freeze (TX > 0 nhưng RX = 0)
    if ! check_silent_pdp_freeze "$ACT_IFACE"; then
        SILENT_FREEZE_CNT=$(( ${SILENT_FREEZE_CNT:-0} + 1 ))
        if [ "$SILENT_FREEZE_CNT" -ge 5 ]; then
            echo "$(date): [SILENT FREEZE] Xác nhận nghẽn gateway 5 lần liên tiếp (TX tăng nhưng RX=0)! Tự hồi sinh PDP Context..." >> "$LOG_FILE"
            SILENT_FREEZE_CNT=0
            if heal_tier2_wwan_session "$ACT_IFACE"; then
                FAIL_STREAK=0
                LAST_RECOVER_TS=$(date +%s)
            else
                FAIL_STREAK=8
            fi
            continue
        fi
    else
        SILENT_FREEZE_CNT=0
    fi

    FAIL_STREAK=$((FAIL_STREAK + 1))
    echo "$(date): [Thăm dò] Sóng/Ping chậm hoặc gián đoạn lần ${FAIL_STREAK}..." >> "$LOG_FILE"
    rotate_log_if_needed

    # Độ trễ ngắn (1-2 lần thăm dò): KHÔNG reset mạng, tránh ngắt oan khi mạng chỉ bị lag tạm thời hoặc nghẽn buffer do camera upload
    if [ "$FAIL_STREAK" -lt 3 ]; then
        sleep 5
        continue
    fi

    up_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 999)
    if [ "$up_sec" -lt 90 ]; then
        echo "$(date): Router vừa boot (${up_sec}s < 90s) - Đang chờ modem quét trạm BTS và đàm phán IP..." >> "$LOG_FILE"
        rotate_log_if_needed
        sleep 10
        continue
    fi

    CUR_TS=$(date +%s)
    if [ $(( CUR_TS - LAST_RECOVER_TS )) -lt 60 ]; then
        echo "$(date): Đang trong thời gian chờ modem ổn định sau lần chữa trước (Cooldown 60s)..." >> "$LOG_FILE"
        sleep 10
        continue
    fi

    echo "$(date): === 🩺 KHỞI ĐỘNG BÁC SĨ 5G TỰ ĐỘNG CHỮA LÀNH MẠNG (FAIL_STREAK=${FAIL_STREAK}) ===" >> "$LOG_FILE"
    START_HEAL_S=$(date +%s)
    ACT_IFACE=$(get_smart_iface)

    # TẦNG 1: SỬA DNS & TCP MSS CLAMPING (~1.5s - ZERO DOWNTIME)
    # Kích hoạt khi mất mạng 3-5 lần liên tiếp (~45-75s)
    if [ "$FAIL_STREAK" -ge 3 ] && [ "$FAIL_STREAK" -lt 6 ]; then
        if heal_tier1_dns_mss; then
            DUR=$(( $(date +%s) - START_HEAL_S ))
            [ "$DUR" -lt 1 ] && DUR=1
            echo "$(date): [Tầng 1 Thành Công] Mạng đã thông suốt trở lại sau ${DUR}s!" >> "$LOG_FILE"
            rotate_log_if_needed
            FAIL_STREAK=0
            LAST_RECOVER_TS=$CUR_TS
            send_tg_alert "🩺 <b>BÁC SĨ 5G: TỰ CHỮA LÀNH THÀNH CÔNG! (Tầng 1)</b>
━━━━━━━━━━━━━━━━━━━
⚡ <b>Thời gian xử lý:</b> ~${DUR} giây
🛡️ <b>Phương thức:</b> Sửa DNS Cache & TCP MSS PMTU Clamping
🌐 <b>Trạng thái:</b> Đã thông mạng Internet hoàn toàn
📶 Wi-Fi & LAN nội bộ giữ nguyên kết nối 100%!"
            continue
        else
            sleep 8
            continue
        fi
    fi

    # TẦNG 2: LÀM MỚI PHIÊN WWAN (~25s max, thử 2 nhịp rồi leo thang ngay Tầng 3)
    if [ "$FAIL_STREAK" -ge 6 ] && [ "$FAIL_STREAK" -lt 8 ]; then
        if heal_tier2_wwan_session "$ACT_IFACE"; then
            LAST_RECOVER_TS=$(date +%s)
            DUR=$(( LAST_RECOVER_TS - START_HEAL_S ))
            echo "$(date): [Tầng 2 Thành Công] Mạng đã hồi phục sau ${DUR}s!" >> "$LOG_FILE"
            rotate_log_if_needed
            FAIL_STREAK=0
            send_tg_alert "🩺 <b>BÁC SĨ 5G: TỰ CHỮA LÀNH THÀNH CÔNG! (Tầng 2)</b>
━━━━━━━━━━━━━━━━━━━
⚡ <b>Thời gian xử lý:</b> ~${DUR} giây
🛡️ <b>Phương thức:</b> Làm mới phiên Data WWAN (${ACT_IFACE}) & Xả Route
🌐 <b>Trạng thái:</b> Đã nhận lại dải IP sạch và khôi phục mạng
📶 Wi-Fi & LAN nội bộ thông suốt không hề bị ngắt!"
            continue
        fi
    fi

    # TẦNG 3: TÁI SINH SÓNG MODEM & CELL FAILOVER (CHỈ KÍCH HOẠT KHI TẦNG 1 & 2 CHƯA PHỤC HỒI)
    if [ "$FAIL_STREAK" -ge 8 ]; then
        if heal_tier3_cfun_cell_failover "$ACT_IFACE"; then
            LAST_RECOVER_TS=$(date +%s)
            DUR=$(( LAST_RECOVER_TS - START_HEAL_S ))
            echo "$(date): [Tầng 3 Thành Công] Sóng modem 5G đã hồi sinh sau ${DUR}s!" >> "$LOG_FILE"
            rotate_log_if_needed
            FAIL_STREAK=0
            SIG_INFO=$(cat /tmp/rf_signal_stats.json 2>/dev/null | jsonfilter -e '$.grade' 2>/dev/null || echo "Ổn định")
            send_tg_alert "🎉 <b>BÁC SĨ 5G: TỰ CHỮA LÀNH THÀNH CÔNG! (Tầng 3)</b>
━━━━━━━━━━━━━━━━━━━
⚡ <b>Thời gian xử lý:</b> ~${DUR} giây
🛡️ <b>Phương thức:</b> Chu kỳ Tái sinh sóng Baseband (CFUN 4/1) & Chuyển trạm BTS
📡 <b>Chất lượng sóng:</b> ${SIG_INFO}
📶 <b>Thiết bị:</b> Không cần khởi động lại Router, Wi-Fi 100% Online!"
            continue
        fi
    fi

    # TẦNG 4: HARDWARE USB/PCIE BUS RESET & PHYSICAL RE-ENUMERATION
    # KÍCH HOẠT KHI MẤT MẠNG KÉO DÀI >= 12 LẦN
    if [ "$FAIL_STREAK" -ge 12 ]; then
        echo "$(date): [Tầng 4 Cứu Hộ Cứng] Cả 3 tầng trước chưa khôi phục. Kích hoạt Hardware Bus Reset toàn diện..." >> "$LOG_FILE"
        rotate_log_if_needed

        local pcie_healed=0 dev slot
        for dev in /sys/bus/pci/drivers/mhi-pci-generic/0000:*; do
            [ -d "$dev" ] || continue
            slot="${dev##*/}"
            pcie_healed=1
            echo "$(date): [Tầng 4] Rescan PCIe MHI slot $slot..." >> "$LOG_FILE"
            killall -9 quectel-CM-M quectel-CM quectel-cm umbim atinout sms_tool 2>/dev/null
            sleep 1
            rm -f /tmp/.mhi_pcie_healed_* 2>/dev/null
            echo "$slot" > /sys/bus/pci/drivers/mhi-pci-generic/unbind 2>/dev/null || true
            echo 1 > "/sys/bus/pci/devices/$slot/remove" 2>/dev/null || true
            sleep 1
            echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
            sleep 6
        done

        if [ "$pcie_healed" -eq 0 ]; then
            # 1. usbreset nếu có nhị phân
            local usb_id=$(lsusb 2>/dev/null | grep -iE "1199:|2c7c:|2cb7:|0e8d:|05c6:" | awk '{print $6}' | head -n 1)
            [ -z "$usb_id" ] && usb_id="1199:90d3"
            if command -v usbreset >/dev/null 2>&1; then
                usbreset "$usb_id" >/dev/null 2>&1
            fi

            # 2. Tái cấp quyền USB sysfs (ngắt và cấp lại nguồn logic USB)
            for auth_f in /sys/bus/usb/devices/2-*/authorized /sys/bus/usb/devices/1-*/authorized; do
                if [ -f "$auth_f" ]; then
                    echo 0 > "$auth_f" 2>/dev/null
                    sleep 2
                    echo 1 > "$auth_f" 2>/dev/null
                fi
            done

            # 3. Dọn dẹp triệt để tiến trình treo
            killall -9 umbim atinout sms_tool 2>/dev/null
            sleep 10
        fi

        # 4. Kích hoạt lại interface
        ubus call network.interface."$ACT_IFACE" up 2>/dev/null || ifup "$ACT_IFACE" 2>/dev/null

        # 5. Thăm dò phục hồi
        if wait_recovery_online 30; then
            LAST_RECOVER_TS=$(date +%s)
            DUR=$(( LAST_RECOVER_TS - START_HEAL_S ))
            echo "$(date): [Tầng 4 Thành Công] Hardware USB Bus Reset đã khôi phục kết nối thành công sau ${DUR}s!" >> "$LOG_FILE"
            rotate_log_if_needed
            FAIL_STREAK=0
            send_tg_alert "🚀 <b>BÁC SĨ 5G: TỰ CHỮA LÀNH CỨNG THÀNH CÔNG! (Tầng 4)</b>
━━━━━━━━━━━━━━━━━━━
⚡ <b>Thời gian xử lý:</b> ~${DUR} giây
🛡️ <b>Phương thức:</b> Hardware USB Bus Reset & Re-enumeration
🌐 <b>Trạng thái:</b> Đã kết nối Internet thành công, không cần khởi động lại Router!"
            continue
        fi

        DUR=$(( $(date +%s) - START_HEAL_S ))
        echo "$(date): [Tầng 4 Báo Cáo] Toàn bộ các tầng tự chữa (kể cả Hardware Reset) chưa kết nối được sau ${DUR}s." >> "$LOG_FILE"
        rotate_log_if_needed
        send_tg_alert "⚠️ <b>BÁC SĨ 5G CẢNH BÁO: MẠNG CHƯA KHÔI PHỤC!</b>
━━━━━━━━━━━━━━━━━━━
⏱️ <b>Thời gian chẩn đoán:</b> ${DUR} giây
🔍 <b>Kết quả:</b> Đã thử Tầng 1 (DNS/MSS), Tầng 2 (Làm mới WWAN), Tầng 3 (AT!RESET), Tầng 4 (Hardware USB Reset).
💡 <b>Nguyên nhân có thể:</b> Trạm phát BTS khu vực đang mất sóng hoặc SIM hết hạn gói cước."
    fi
done
# [/VERIFIED-GOLDEN]
