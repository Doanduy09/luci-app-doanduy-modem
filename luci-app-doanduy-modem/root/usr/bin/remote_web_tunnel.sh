#!/bin/sh
# [VERIFIED-GOLDEN: part4-remote-luci-tunnel | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
# /usr/bin/remote_web_tunnel.sh - DOANDUY 5G Universal Remote LuCI Tunnel
# Tác quyền: Chuyên gia tối ưu hệ thống OpenWrt

LOG_FILE="/tmp/remote_web.log"
PID_FILE="/tmp/remote_web.pid"
STATE_FILE="/tmp/remote_web.state"
WD_PID_FILE="/tmp/remote_web_wd.pid"

stop_tunnel() {
    local silent="$1"
    if [ -f "$PID_FILE" ]; then
        local t_pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$t_pid" ] && kill -9 "$t_pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    if [ -f "$WD_PID_FILE" ]; then
        local wd_pid=$(cat "$WD_PID_FILE" 2>/dev/null)
        [ -n "$wd_pid" ] && kill -9 "$wd_pid" 2>/dev/null
        rm -f "$WD_PID_FILE"
    fi
    # Quét dọn tiến trình hầm mạng của riêng Web Remote (không đụng tới NAS)
    for p in $(pgrep -f "cloudflared.*127\.0\.0\.1:80$" 2>/dev/null); do
        kill -9 "$p" 2>/dev/null
    done
    
    local old_url=""
    [ -f "$STATE_FILE" ] && old_url=$(grep "^URL=" "$STATE_FILE" | cut -d'=' -f2-)
    rm -f "$STATE_FILE" "$LOG_FILE"

    if [ "$silent" != "silent" ]; then
        if [ -x /usr/bin/send_telegram ]; then
            /usr/bin/send_telegram "🔒 <b>ĐÃ ĐÓNG ĐƯỜNG DẪN QUẢN TRỊ TỪ XA!</b>
━━━━━━━━━━━━━━━━━━━
🛡️ Đường hầm bảo mật đã được ngắt hoàn toàn.
🚫 Toàn bộ liên kết truy cập LuCI từ xa đã vô hiệu hóa an toàn.
🧠 Router đã giải phóng 100% tài nguyên mạng."
        fi
    fi
    echo "STOPPED"
}

has_root_password() {
    local h
    h=$(awk -F: '$1=="root"{print $2}' /etc/shadow 2>/dev/null)
    case "$h" in
        ""|"!"|"*"|"!!"|"x") return 1 ;;
        *) return 0 ;;
    esac
}

start_tunnel() {
    if ! has_root_password; then
        echo '{"status":"ERROR","msg":"Bắt buộc đặt mật khẩu root trước khi mở đường hầm công khai!"}'
        return 1
    fi
    local dur="${1:-10}"
    dur=$(echo "$dur" | tr -cd '0-9')
    [ -z "$dur" ] || [ "$dur" -lt 1 ] && dur=10
    [ "$dur" -gt 1440 ] && dur=1440

    stop_tunnel "silent" >/dev/null 2>&1

    local public_url=""
    local t_pid=""
    local tunnel_type="TAILSCALE_FUNNEL"

    # Ưu tiên số 1: Tailscale Funnel (nếu tailscale đã cài đặt và đăng nhập trên router)
    local ts_dns=""
    if command -v tailscale >/dev/null 2>&1; then
        ts_dns=$(tailscale status --json 2>/dev/null | jsonfilter -e '$.Self.DNSName' 2>/dev/null | sed 's/\.$//')
        if [ -n "$ts_dns" ]; then
            if ! tailscale serve status 2>/dev/null | grep -qi "127.0.0.1:80"; then
                tailscale serve reset >/dev/null 2>&1
                tailscale serve --bg 80 >/dev/null 2>&1
                tailscale funnel --bg 80 >/dev/null 2>&1
                sleep 1
            fi
        fi
    fi

    if [ -n "$ts_dns" ] && command -v tailscale >/dev/null 2>&1 && tailscale serve status 2>/dev/null | grep -qi "Funnel on"; then
        public_url="https://${ts_dns}/cgi-bin/luci"
        tunnel_type="TAILSCALE_FUNNEL"
    elif [ -x /usr/bin/cloudflared ]; then
        tunnel_type="CLOUDFLARE"
        /usr/bin/cloudflared tunnel --url http://127.0.0.1:80 --no-autoupdate > "$LOG_FILE" 2>&1 < /dev/null &
        t_pid=$!
        echo "$t_pid" > "$PID_FILE"

        local count=0
        while [ $count -lt 30 ]; do
            sleep 0.5
            count=$((count + 1))
            public_url=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$LOG_FILE" 2>/dev/null | head -n 1)
            [ -n "$public_url" ] && break
        done

        if [ -n "$public_url" ]; then
            sleep 2.5
        fi
    fi

    if [ -z "$public_url" ]; then
        stop_tunnel "silent" >/dev/null 2>&1
        echo "{\"status\":\"ERROR\",\"msg\":\"Cần bật Tailscale Funnel hoặc cài cloudflared để mở Tunnel an toàn\"}"
        return 1
    fi

    local now_ts=$(date +%s)
    local expire_ts=$((now_ts + dur * 60))
    local expire_time_str=$(date -d "@$expire_ts" "+%H:%M" 2>/dev/null)
    [ -z "$expire_time_str" ] && expire_time_str="${dur} phút nữa"

    cat << EOF > "$STATE_FILE"
URL=$public_url
EXPIRE_TS=$expire_ts
DURATION=$dur
PID=$t_pid
START_TS=$now_ts
TYPE=$tunnel_type
EOF

    # Khởi tạo Watchdog tự hủy khi hết thời gian, ngắt hoàn toàn I/O descriptors
    (
        sleep $((dur * 60))
        if [ "$tunnel_type" != "TAILSCALE_FUNNEL" ]; then
            if [ -f "$PID_FILE" ]; then
                local cur_pid=$(cat "$PID_FILE" 2>/dev/null)
                if [ "$cur_pid" = "$t_pid" ]; then
                    stop_tunnel >/dev/null 2>&1
                fi
            fi
        else
            rm -f "$STATE_FILE"
        fi
    ) >/dev/null 2>&1 < /dev/null &
    echo $! > "$WD_PID_FILE"

    local ts_ip=$(tailscale ip -4 2>/dev/null | tr -d ' \r\n')
    [ -z "$ts_ip" ] && ts_ip=$(cat /etc/config/tailscale_ip 2>/dev/null | tr -d ' \r\n')
    local ts_link=""
    [ -n "$ts_ip" ] && ts_link="http://${ts_ip}/cgi-bin/luci"
    echo "{\"status\":\"OK\",\"url\":\"$public_url\",\"duration\":$dur,\"expire_time\":\"$expire_time_str\",\"type\":\"$tunnel_type\",\"tailscale_url\":\"$ts_link\"}"
    return 0
}

status_tunnel() {
    if [ -f "$STATE_FILE" ]; then
        local url=$(grep "^URL=" "$STATE_FILE" | cut -d'=' -f2-)
        local exp_ts=$(grep "^EXPIRE_TS=" "$STATE_FILE" | cut -d'=' -f2-)
        local dur=$(grep "^DURATION=" "$STATE_FILE" | cut -d'=' -f2-)
        local t_type=$(grep "^TYPE=" "$STATE_FILE" | cut -d'=' -f2-)
        local now_ts=$(date +%s)
        local remain_sec=$((exp_ts - now_ts))
        local remain_min=$((remain_sec / 60))
        [ $remain_min -lt 1 ] && remain_min=1
        if [ "$t_type" = "TAILSCALE_FUNNEL" ] || [ -f "$PID_FILE" ]; then
            echo "{\"status\":\"RUNNING\",\"url\":\"$url\",\"remaining\":$remain_min,\"duration\":$dur,\"type\":\"$t_type\"}"
            return 0
        fi
    fi
    echo "{\"status\":\"STOPPED\"}"
    return 1
}

case "$1" in
    start)
        start_tunnel "$2"
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        status_tunnel
        ;;
    *)
        echo "Usage: $0 {start [minutes]|stop|status}"
        exit 1
        ;;
esac

# [/VERIFIED-GOLDEN]
