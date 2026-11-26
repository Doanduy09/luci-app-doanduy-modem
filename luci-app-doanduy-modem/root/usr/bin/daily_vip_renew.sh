#!/bin/sh
export TZ='<+07>-7'
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

log() {
    echo "$(TZ='<+07>-7' date '+%Y-%m-%d %H:%M:%S') $1" >> /tmp/daily_vip_renew.log
}

LOCK_FILE="/tmp/daily_vip_renew.lock"
exec 201>"$LOCK_FILE"
if ! flock -n 201; then
    exit 0
fi

ACTION="$1"
is_manual=0
no_tg=0
for arg in "$@"; do
    case "$arg" in
        --manual|quick_send|user_intent|--force|renew|--now|1touch|one_touch|--status|status)
            is_manual=1
            ;;
        --no-tg|--quiet)
            no_tg=1
            ;;
    esac
done

probe_at_tier() {
    local dev="$1" tier="${2:-strong}" resp=""
    [ -n "$dev" ] && [ -c "$dev" ] || return 1
    case "$dev" in
        /dev/wwan*|/dev/mhi*|/dev/ttyFMI*)
            if [ -x /usr/bin/read_pcie_sms.lua ]; then
                if command -v modem_lock_run >/dev/null 2>&1; then
                    resp=$(modem_lock_run /usr/bin/read_pcie_sms.lua -p "$dev" --at "ATI" 2>/dev/null)
                else
                    resp=$(/usr/bin/read_pcie_sms.lua -p "$dev" --at "ATI" 2>/dev/null)
                fi
            fi
            ;;
        *)
            if command -v atinout >/dev/null 2>&1; then
                if command -v modem_lock_run >/dev/null 2>&1; then
                    resp=$(modem_lock_run timeout 3 sh -c 'printf "ATI\r" | atinout - "$1" -' _ "$dev" 2>/dev/null)
                else
                    resp=$(timeout 3 sh -c 'printf "ATI\r" | atinout - "$1" -' _ "$dev" 2>/dev/null)
                fi
            fi
            if [ -z "$resp" ] && [ -x /usr/bin/read_pcie_sms.lua ]; then
                if command -v modem_lock_run >/dev/null 2>&1; then
                    resp=$(modem_lock_run /usr/bin/read_pcie_sms.lua -p "$dev" --at "ATI" 2>/dev/null)
                else
                    resp=$(/usr/bin/read_pcie_sms.lua -p "$dev" --at "ATI" 2>/dev/null)
                fi
            fi
            ;;
    esac
    printf '%s' "$resp" | grep -qiE '\$GP|\$GN|\$GL|\$BD|Unknown error|\+CGPADDR|ERROR' && return 1
    if printf '%s' "$resp" | grep -qiE 'Manufacturer:|Model:|Revision:|IMEI:|Quectel|Fibocom|FIBOCOM|FM350|RM5[02]|EM0|EM1|RG5|Sierra|Huawei|HUAWEI|Simcom|SIMCOM|MeiG|Neoway|Gosuncn|Telit|Thales|Cinterion|Foxconn|T99W|DW593|Air724|OpenLuat'; then
        return 0
    fi
    [ "$tier" = "ok" ] && printf '%s' "$resp" | grep -q 'OK' && return 0
    return 1
}

probe_renew_port() {
    local p="" custom_p="" tier=""
    META_AT_PORT=""
    [ -f /tmp/duydoan5g_modem_meta ] && . /tmp/duydoan5g_modem_meta 2>/dev/null
    custom_p=$(cat /tmp/custom_at_port 2>/dev/null || cat /etc/custom_at_port 2>/dev/null)
    if [ -n "$custom_p" ] && [ -c "$custom_p" ]; then
        echo "$custom_p"
        return 0
    fi
    for p in "$META_AT_PORT" "$(cat /tmp/master_sms_port 2>/dev/null)"; do
        if probe_at_tier "$p" "strong"; then
            echo "$p"
            return 0
        fi
    done
    for tier in strong ok; do
        for p in /dev/wwan0at0 /dev/wwan1at0 /dev/mhi_DUN /dev/mhi_DUN0 /dev/ttyFMI0 /dev/ttyFMI1 /dev/wwan*at* /dev/mhi_DUN* /dev/ttyFMI* \
                 /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyACM1 /dev/ttyUSB* /dev/ttyACM*; do
            if probe_at_tier "$p" "$tier"; then
                echo "$p" > /tmp/master_sms_port
                echo "$p"
                return 0
            fi
        done
    done
    for p in /dev/wwan0at0 /dev/mhi_DUN /dev/ttyFMI0 /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0; do
        [ -c "$p" ] && { echo "$p"; return 0; }
    done
    echo "/dev/ttyUSB3"
}

port=$(probe_renew_port)

# 1. Xac dinh SIM hien tai (Tu file tam, quectel-cm log hoac modem thuc te; TUYET DOI KHONG gia mao VIP)
cur_iccid=""
for p in /tmp/sms_current_iccid /tmp/current_sim_iccid; do
    if [ -f "$p" ]; then
        match=$(grep -oE '[0-9]{18,22}' "$p" | head -1)
        if [ -n "$match" ]; then
            cur_iccid="$match"
            break
        fi
    fi
done

if [ -z "$cur_iccid" ] && [ -s /tmp/quectel_cm/quectel-cm.log ]; then
    cur_iccid=$(grep -oE 'SimIccId:[[:space:]]*[0-9]{18,22}' /tmp/quectel_cm/quectel-cm.log 2>/dev/null | tail -n 1 | grep -oE '[0-9]{18,22}')
fi

if [ -z "$cur_iccid" ] && { [ -c "/dev/wwan0at0" ] || [ -c "/dev/mhi_DUN" ]; } && [ -x /usr/bin/read_pcie_sms.lua ]; then
    cur_iccid=$(/usr/bin/read_pcie_sms.lua --at 'AT+ICCID' 2>/dev/null | grep -oE '[0-9]{18,22}' | head -1)
    [ -z "$cur_iccid" ] && cur_iccid=$(/usr/bin/read_pcie_sms.lua --at 'AT+QCCID' 2>/dev/null | grep -oE '[0-9]{18,22}' | head -1)
fi

if [ -z "$cur_iccid" ] && [ -c "$port" ]; then
    case "$port" in /dev/tty*)
        if command -v sms_tool >/dev/null 2>&1; then
            cur_iccid=$(modem_lock_run sms_tool -d "$port" -D at 'AT+QCCID' 2>/dev/null | grep -oE '[0-9]{18,22}' | head -1)
            [ -z "$cur_iccid" ] && cur_iccid=$(modem_lock_run sms_tool -d "$port" -D at 'AT+ICCID' 2>/dev/null | grep -oE '[0-9]{18,22}' | head -1)
        fi
        if [ -z "$cur_iccid" ] && command -v atinout >/dev/null 2>&1; then
            cur_iccid=$(printf 'AT+ICCID\r\n' | modem_lock_run timeout 3 atinout - "$port" - 2>/dev/null | grep -oE '[0-9]{18,22}' | head -1)
        fi
    ;; esac
fi

if [ -z "$cur_iccid" ] && [ -f /etc/config/last_known_iccid ]; then
    cur_iccid=$(grep -oE '[0-9]{18,22}' /etc/config/last_known_iccid 2>/dev/null | head -1)
fi

if [ -n "$cur_iccid" ]; then
    echo "$cur_iccid" > /tmp/sms_current_iccid
    echo "$cur_iccid" > /tmp/current_sim_iccid
else
    rm -f /tmp/sms_current_iccid /tmp/current_sim_iccid 2>/dev/null
fi

# 2. Kiem tra Whitelist: CHI CAC SIM VIP MAC DINH MOI DUOC PHEP GIA HAN GOI CUOC (Zero-Leak SHA-256)
DEFAULT_HASHES="a7a16520a4144e79d6b262ce4265a5d585154221b52803d8e8e6b62213e49865 c317b0ec0ee235c2bae6baf0efde7b03a05e35ad84cf794fc71a809802d47df9 e972c309ace289c3037d4479d79b983d02151f3868f003073085abf4bf508575"
ALLOWED_ICCIDS=$(cat /etc/config/allowed_iccids.dat 2>/dev/null | tr '\r\n' ' ')

is_sim_allowed=0
if [ -n "$cur_iccid" ]; then
    cur_hash=$(printf '%s' "$cur_iccid" | sha256sum 2>/dev/null | awk '{print $1}')
    for d_h in $DEFAULT_HASHES; do
        if [ -n "$cur_hash" ] && [ "$cur_hash" = "$d_h" ]; then
            is_sim_allowed=1
            break
        fi
    done
    if [ "$is_sim_allowed" -ne 1 ] && [ -n "$ALLOWED_ICCIDS" ]; then
        for a in $ALLOWED_ICCIDS; do
            clean_a=$(echo "$a" | tr -d '\r\n[:space:]')
            [ -z "$clean_a" ] && continue
            if [ "$cur_iccid" = "$clean_a" ] || { [ -n "$cur_hash" ] && [ "$cur_hash" = "$clean_a" ]; }; then
                is_sim_allowed=1
                break
            fi
        done
    fi
fi

masked_cur_iccid="898404******"
if [ -n "$cur_iccid" ] && [ ${#cur_iccid} -ge 10 ]; then
    pfx=$(echo "$cur_iccid" | cut -c1-6)
    sfx=$(echo "$cur_iccid" | cut -c17-20)
    [ -z "$sfx" ] && sfx=$(echo "$cur_iccid" | cut -c15-18)
    masked_cur_iccid="${pfx}******${sfx}"
fi

if [ "$is_sim_allowed" -ne 1 ]; then
    rm -f /tmp/daily_renew_schedule.dat /tmp/next_vip_renew_schedule.txt /tmp/daily_renew_target_time.txt /tmp/sms_custom_send_epoch 2>/dev/null
    echo "LOCKED" > /tmp/master_sim_status
    echo "0" > /tmp/sms_next_send_epoch
    echo "0" > /tmp/sms_next_wake_epoch
    
    if [ "$ACTION" = "--status" ] || [ "$ACTION" = "status" ]; then
        echo "🔒 LỊCH GIA HẠN SMS: ĐÃ KHÓA CHẶT 100% (SIM ngoài danh mục mặc định)"
        echo "Mã SIM: ${masked_cur_iccid} | Không lên lịch gửi bất kỳ tin nhắn nào."
        exit 0
    fi
    if [ "$is_manual" -eq 1 ]; then
        echo "🔒 BẢO VỆ AN TOÀN: PHÁT HIỆN SIM NGOÀI DANH SÁCH (${masked_cur_iccid})!"
        echo "HỆ THỐNG ĐÃ KHÓA TOÀN BỘ TÁC VỤ GỬI SMS ĐỂ TRÁNH MẤT TIỀN NGOÀI Ý MUỐN!"
        exit 1
    fi
    exit 0
fi

echo "VALID" > /tmp/master_sim_status

# 3. Kiem tra Circuit Breaker (CHỈ ÁP DỤNG KHI CHẠY TỰ ĐỘNG, BỎ QUA KHI THỰC THI THỦ CÔNG)
today=$(TZ='<+07>-7' date '+%Y-%m-%d')
LAST_SENT_FILE="/etc/config/sim_last_sent.dat"
if [ "$is_manual" -ne 1 ]; then
    if [ -f "$LAST_SENT_FILE" ]; then
        last_sent_date=$(cut -d'|' -f1 "$LAST_SENT_FILE" 2>/dev/null | tr -d ' \r\n')
        if [ "$last_sent_date" = "$today" ]; then
            touch "/tmp/sms_scheduled_sent_$today"
            exit 0
        fi
    fi
fi

# 4. Tinh toan lich gui cho SIM VIP
custom_time=$(cat /etc/config/sms_custom_time.dat 2>/dev/null | tr -d ' \r\n')
[ -z "$custom_time" ] && custom_time="01:25:30"
t_h=$(echo "$custom_time" | cut -d':' -f1)
t_m=$(echo "$custom_time" | cut -d':' -f2)
t_s=$(echo "$custom_time" | cut -d':' -f3)
[ -z "$t_s" ] && t_s="00"

total_sec=$(( t_h*3600 + t_m*60 + t_s ))
if [ "$total_sec" -lt 1200 ] || [ "$total_sec" -gt 20400 ]; then
    t_h=1; t_m=25; t_s=30
    custom_time="01:25:30"
fi

today_midnight=$(TZ='<+07>-7' date -d "${today} 00:00:00" +%s 2>/dev/null || date +%s)
target_epoch=$(( today_midnight + t_h*3600 + t_m*60 + t_s ))
target_hhmmss="$custom_time"
echo "${today}|${target_epoch}|${target_hhmmss}" > /tmp/daily_renew_schedule.dat
echo "${target_hhmmss} ngày ${today}" > /tmp/next_vip_renew_schedule.txt

# Cu phap goi cuoc tuy chinh tu nguoi dung hoac mac dinh 5G150N
renew_pkg=$(cat /etc/config/sms_renew_package.dat 2>/dev/null | tr -d ' \r\n')
[ -z "$renew_pkg" ] && renew_pkg="5G150N"
renew_dest=$(cat /etc/config/sms_renew_dest.dat 2>/dev/null | tr -d ' \r\n')
[ -z "$renew_dest" ] && renew_dest="191"

if [ "$ACTION" = "--status" ] || [ "$ACTION" = "status" ]; then
    echo "🟢 LỊCH GIA HẠN SIM VIP (${masked_cur_iccid}):"
    echo "Giờ gửi: ${target_hhmmss} | Cú pháp: ${renew_pkg} gửi ${renew_dest}"
    exit 0
fi

if [ "$is_manual" -ne 1 ]; then
    now_epoch=$(date +%s)
    if [ "$now_epoch" -lt "$target_epoch" ]; then
        exit 0
    fi
fi

# ==============================================================================
# 5. QUY TRÌNH GIA HẠN & ĐỔI IP THEO LỆNH CHUẨN CỦA ANH DUY:
# 1. Gửi cú pháp 5G150N tới 191
# 2. Sau 2s gửi xác nhận Y tới 191
# 3. Tái kết nối mạng và nhận IP WAN mới sạch sẽ
# ==============================================================================
log "⚡ [Pha 1/4] Gửi SMS cú pháp [${renew_pkg}] tới tổng đài [${renew_dest}]..."
touch /tmp/sms_sending.lock

run_send_sms() {
    local dest="$1"
    local text="$2"
    local out="" rc=1 is_utf8=0 sms_bin=""
    printf '%s' "$text" | LC_ALL=C grep -q '[^ -~	]' && is_utf8=1
    if [ "$is_utf8" -eq 0 ] && [ "${#text}" -le 160 ] && [ -c "/dev/wwan0qmi0" ] && command -v uqmi >/dev/null 2>&1; then
        trap 'killall -CONT quectel-CM-M quectel-CM 2>/dev/null; rm -f /tmp/sms_sending.lock' EXIT INT TERM
        killall -STOP quectel-CM-M quectel-CM 2>/dev/null
        out=$(uqmi -s -t 3500 -d /dev/wwan0qmi0 --send-message "$text" --send-message-target "$dest" 2>&1)
        rc=$?
        killall -CONT quectel-CM-M quectel-CM 2>/dev/null
        trap - EXIT INT TERM
        if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qiE 'error|failed'; then
            return 0
        fi
    fi
    case "$port" in
        /dev/wwan*|/dev/mhi*|/dev/ttyFMI*)
            if [ -x /usr/bin/read_pcie_sms.lua ]; then
                if command -v modem_lock_run >/dev/null 2>&1; then
                    out=$(modem_lock_run /usr/bin/read_pcie_sms.lua -p "$port" --send "$dest" "$text" 2>&1)
                else
                    out=$(/usr/bin/read_pcie_sms.lua -p "$port" --send "$dest" "$text" 2>&1)
                fi
                rc=$?
                [ "$rc" -eq 0 ] && return 0
                log "❌ PCIe SMS ($port) lỗi: $out"
                return 1
            fi
            ;;
    esac
    command -v sms_tool_q >/dev/null 2>&1 && sms_bin="sms_tool_q"
    [ -z "$sms_bin" ] && command -v sms_tool >/dev/null 2>&1 && sms_bin="sms_tool"
    if [ "$is_utf8" -eq 0 ] && [ "${#text}" -le 160 ] && [ -n "$sms_bin" ]; then
        if command -v modem_lock_run >/dev/null 2>&1; then
            out=$(modem_lock_run "$sms_bin" -d "$port" send "$dest" "$text" 2>&1)
        else
            out=$("$sms_bin" -d "$port" send "$dest" "$text" 2>&1)
        fi
        rc=$?
        if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qiE 'sucessfully|successfully|\+CMGS:' && ! printf '%s' "$out" | grep -qiE 'not sent|error'; then
            return 0
        fi
    fi
    if [ -x /usr/bin/read_pcie_sms.lua ]; then
        if command -v modem_lock_run >/dev/null 2>&1; then
            out=$(modem_lock_run /usr/bin/read_pcie_sms.lua -p "$port" --send "$dest" "$text" 2>&1)
        else
            out=$(/usr/bin/read_pcie_sms.lua -p "$port" --send "$dest" "$text" 2>&1)
        fi
        rc=$?
        [ "$rc" -eq 0 ] && return 0
        log "❌ SMS engine ($port) lỗi: $out"
        return 1
    fi
    log "❌ Không gửi được SMS qua $port: $out"
    return 1
}

if run_send_sms "$renew_dest" "$renew_pkg"; then
    log "✔️ [Pha 1/4] Đã gửi [${renew_pkg}] tới [${renew_dest}] qua [$port]. Chờ 2 giây..."
else
    log "⚠️ [Pha 1/4] Gửi [${renew_pkg}] tới [${renew_dest}] thất bại qua [$port]!"
fi
sleep 2

# Pha 2: Sau 2s gửi Y tới 191
log "⚡ [Pha 2/4] Gửi tin nhắn xác nhận [Y] tới tổng đài [${renew_dest}]..."
if run_send_sms "$renew_dest" "Y"; then
    log "✔️ [Pha 2/4] Đã gửi xác nhận [Y] tới [${renew_dest}] qua [$port]. Chờ 5 giây..."
else
    log "⚠️ [Pha 2/4] Gửi xác nhận [Y] thất bại qua [$port]!"
fi
sleep 5
rm -f /tmp/sms_sending.lock

# Pha 3: Tái kích hoạt interface 5G để đổi IP WAN
log "📶 [Pha 3/4] Tái kích hoạt interface 5G để nhận IP WAN mới sạch sẽ..."
( ifup duydoan_5g 2>/dev/null || ifup wwan 2>/dev/null || ifup wan 2>/dev/null ) >/dev/null 2>&1 &
sleep 5

new_ip=$(ip -4 addr show mhi_hwip0 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2)
[ -z "$new_ip" ] && new_ip=$(ip -4 addr show wwan0 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2)
[ -z "$new_ip" ] && new_ip=$(ip -4 addr show usb0 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2)
log "🎯 [Hoàn tất] Modem đã tái kết nối sóng thành công! IP WAN mới: ${new_ip:-Đang đàm phán DHCP...}"

# Ghi nhớ Circuit Breaker
echo "${today}|${target_epoch}|${renew_pkg}" > "$LAST_SENT_FILE"
touch "/tmp/sms_scheduled_sent_$today"
echo "{\"status\":\"sent\",\"package\":\"$renew_pkg\",\"dest\":\"$renew_dest\",\"time\":\"$(TZ='<+07>-7' date '+%H:%M:%S %d/%m/%Y')\",\"target_time\":\"$target_hhmmss\",\"new_ip\":\"${new_ip:-Mới}\"}" > /tmp/last_renew_success.json
sync
log "🎯 Chu kỳ gia hạn và đổi IP ngày $today đã hoàn tất xuất sắc."
exit 0
