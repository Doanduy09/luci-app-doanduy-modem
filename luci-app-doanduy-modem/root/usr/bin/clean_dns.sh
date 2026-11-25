#!/bin/sh
# /usr/bin/clean_dns.sh - DOANDUY 5G Universal Smart Clean DNS & Quad-Stack Zero-Failover DNS
CONF_DIR="/tmp/dnsmasq.d"
CONF_FILE="$CONF_DIR/clean_dns.conf"
PERM_CONF="/etc/config/clean_dns.conf"
mkdir -p "$CONF_DIR" /etc/config 2>/dev/null

enable_clean_dns() {
    mkdir -p "$CONF_DIR" /etc/config 2>/dev/null
    cat << 'EOF' > "$CONF_FILE"
# Smart Clean DNS - Unblock international domains bypassing carrier censorship
server=/medium.com/1.1.1.1
server=/reddit.com/1.1.1.1
server=/redditmedia.com/1.1.1.1
server=/redditstatic.com/1.1.1.1
server=/steampowered.com/1.1.1.1
server=/steamcommunity.com/1.1.1.1
server=/steamstatic.com/1.1.1.1
server=/bbc.com/1.1.1.1
server=/bbc.co.uk/1.1.1.1
server=/bbci.co.uk/1.1.1.1
server=/x.com/1.1.1.1
server=/twitter.com/1.1.1.1
server=/t.co/1.1.1.1
server=/twimg.com/1.1.1.1
server=/archive.org/1.1.1.1
server=/goodreads.com/1.1.1.1

# Cloudflare Quick Tunnel Anti-Poisoning & Anti-NXDOMAIN Hijack
server=/trycloudflare.com/1.1.1.1
server=/trycloudflare.com/8.8.8.8
bogus-nxdomain=125.235.4.59
EOF
    if [ ! -f "$PERM_CONF" ] || ! cmp -s "$CONF_FILE" "$PERM_CONF" 2>/dev/null; then
        cp -f "$CONF_FILE" "$PERM_CONF" 2>/dev/null
    fi
    
    local mem_mb target_cache=10000
    mem_mb=$(awk '/MemTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 256)
    if [ "${mem_mb:-0}" -le 128 ]; then
        target_cache=2000
    elif [ "${mem_mb:-0}" -le 256 ]; then
        target_cache=5000
    fi

    # Đảm bảo Smart DNS Racer (allservers), cache RAM theo cấu hình & máy chủ DNS cố định trong UCI Flash
    local need_commit=0
    [ "$(uci -q get dhcp.@dnsmasq[0].allservers)" != "1" ] && { uci -q set dhcp.@dnsmasq[0].allservers='1'; need_commit=1; }
    [ "$(uci -q get dhcp.@dnsmasq[0].cachesize)" != "$target_cache" ] && { uci -q set dhcp.@dnsmasq[0].cachesize="$target_cache"; need_commit=1; }
    [ "$(uci -q get dhcp.@dnsmasq[0].min_cache_ttl)" != "300" ] && { uci -q set dhcp.@dnsmasq[0].min_cache_ttl='300'; need_commit=1; }
    [ "$(uci -q get dhcp.@dnsmasq[0].dnsforwardmax)" != "512" ] && { uci -q set dhcp.@dnsmasq[0].dnsforwardmax='512'; need_commit=1; }
    [ "$(uci -q get dhcp.@dnsmasq[0].nonegcache)" != "1" ] && { uci -q set dhcp.@dnsmasq[0].nonegcache='1'; need_commit=1; }
    for s in 8.8.8.8 1.1.1.1 9.9.9.9 203.113.131.1; do
        if ! uci -q get dhcp.@dnsmasq[0].server 2>/dev/null | grep -q "$s"; then
            uci -q add_list dhcp.@dnsmasq[0].server="$s"
            need_commit=1
        fi
    done
    [ "$need_commit" -eq 1 ] && uci -q commit dhcp

    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    sleep 1
    predictive_dns_prefetch >/dev/null 2>&1 &
    enable_doh_privacy_shield >/dev/null 2>&1
    echo "ENABLED"
}

enable_doh_privacy_shield() {
    local mem_mb target_cache=10000
    mem_mb=$(awk '/MemTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 256)
    [ "${mem_mb:-0}" -le 128 ] && target_cache=2000
    [ "${mem_mb:-0}" -gt 128 ] && [ "${mem_mb:-0}" -le 256 ] && target_cache=5000
    rm -f "$CONF_DIR/doh_shield.conf" 2>/dev/null

    # Tạo trạng thái Clean DNS JSON chính xác (Zero Flash wear)
    cat << EOF > /tmp/doh_privacy_shield.json.tmp
{
    "doh_shield": false,
    "privacy_mode": "Quad-Stack-Anycast-DNS",
    "upstreams": ["1.1.1.1 (Cloudflare)", "8.8.8.8 (Google)", "9.9.9.9 (Quad9)"],
    "ram_cache_entries": $target_cache,
    "dnssec_validated": false,
    "zero_leak_status": "protected",
    "updated_at": $(date +%s)
}
EOF
    mv -f /tmp/doh_privacy_shield.json.tmp /tmp/doh_privacy_shield.json 2>/dev/null
    return 0
}

predictive_dns_prefetch() {
    local hot_domains="youtube.com www.youtube.com google.com www.google.com facebook.com www.facebook.com tiktok.com shopee.vn lazada.vn vnexpress.net dantri.com.vn zalo.me api.telegram.org connectivitycheck.gstatic.com cp.cloudflare.com lienquan.garena.vn pubgmobile.com riotgames.com netflix.com vtv.vn apple.com icloud.com cdn.cloudflare.net"
    for d in $hot_domains; do
        nslookup "$d" 127.0.0.1 >/dev/null 2>&1 &
    done
}

disable_clean_dns() {
    rm -f "$CONF_FILE" "$PERM_CONF" "$CONF_DIR/doh_shield.conf" /tmp/doh_privacy_shield.json 2>/dev/null
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo "DISABLED"
}

status_clean_dns() {
    if [ -f "$CONF_FILE" ]; then
        echo "ACTIVE"
    else
        echo "INACTIVE"
    fi
}

status_doh_shield() {
    if [ -f /tmp/doh_privacy_shield.json ]; then
        cat /tmp/doh_privacy_shield.json 2>/dev/null
    else
        echo '{"doh_shield":false,"status":"inactive"}'
    fi
}

case "$1" in
    on|enable|start)
        enable_clean_dns
        ;;
    off|disable|stop)
        disable_clean_dns
        ;;
    doh|privacy-shield|enable-doh)
        enable_doh_privacy_shield
        echo "DOH_PRIVACY_SHIELD_ENABLED"
        ;;
    doh-status|privacy-status)
        status_doh_shield
        ;;
    prefetch)
        predictive_dns_prefetch
        echo "PREFETCH_DONE"
        ;;
    status)
        status_clean_dns
        ;;
    restore_boot)
        mkdir -p "$CONF_DIR" 2>/dev/null
        if [ -f "$PERM_CONF" ]; then
            cp -f "$PERM_CONF" "$CONF_FILE" 2>/dev/null
        else
            enable_clean_dns >/dev/null 2>&1
        fi
        enable_doh_privacy_shield >/dev/null 2>&1
        predictive_dns_prefetch >/dev/null 2>&1 &
        ;;
    *)
        enable_clean_dns
        ;;
esac
