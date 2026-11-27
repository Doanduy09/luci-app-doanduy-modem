// DOANDUY Visual Router Topology & 5-Minute Smart Auto-Mesh LuCI Tab (v2.6.2)
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callMeshStatus  = rpc.declare({ object: 'doanduy.mesh', method: 'status', expect: { } });
var callMeshSetMode = rpc.declare({ object: 'doanduy.mesh', method: 'setMode', params: ['mode', 'node_ip'], expect: { } });

function ensureMeshStyles() {
    if (document.getElementById('dd-mesh-anim-style')) return;
    var st = document.createElement('style');
    st.id = 'dd-mesh-anim-style';
    st.textContent = [
        '@keyframes ddWavePulse {',
        '  0%   { opacity: 0.20; transform: scale(0.88); }',
        '  50%  { opacity: 1.00; transform: scale(1.04); }',
        '  100% { opacity: 0.20; transform: scale(0.88); }',
        '}',
        '@keyframes ddRadarRing {',
        '  0%   { transform: translate(-50%, -50%) scale(0.55); opacity: 0.75; }',
        '  100% { transform: translate(-50%, -50%) scale(1.65); opacity: 0; }',
        '}',
        '@keyframes ddLinkFlow {',
        '  0%   { top: 4px; opacity: 0.2; }',
        '  50%  { opacity: 1; }',
        '  100% { top: 54px; opacity: 0.2; }',
        '}',
        '.dd-wifi-arc-1 { animation: ddWavePulse 1.5s infinite ease-in-out 0.0s; transform-origin: center bottom; }',
        '.dd-wifi-arc-2 { animation: ddWavePulse 1.5s infinite ease-in-out 0.25s; transform-origin: center bottom; }',
        '.dd-wifi-arc-3 { animation: ddWavePulse 1.5s infinite ease-in-out 0.5s; transform-origin: center bottom; }',
        '.dd-radar-ring-1 {',
        '  position: absolute; left: 50%; top: 46%; width: 110px; height: 110px; border-radius: 50%;',
        '  border: 2px solid #3b82f6; pointer-events: none; animation: ddRadarRing 2.2s infinite ease-out;',
        '}',
        '.dd-radar-ring-2 {',
        '  position: absolute; left: 50%; top: 46%; width: 110px; height: 110px; border-radius: 50%;',
        '  border: 2px solid #06b6d4; pointer-events: none; animation: ddRadarRing 2.2s infinite ease-out 1.1s;',
        '}',
        '.dd-flow-dot {',
        '  position: absolute; left: -4px; width: 10px; height: 10px; border-radius: 50%;',
        '  background: #10b981; box-shadow: 0 0 8px #10b981; animation: ddLinkFlow 1.6s infinite linear;',
        '}'
    ].join('\n');
    document.head.appendChild(st);
}

function formatMMSS(sec) {
    var s = Math.max(0, parseInt(sec || 0, 10));
    var m = Math.floor(s / 60);
    var r = s % 60;
    return (m < 10 ? '0' + m : '' + m) + ':' + (r < 10 ? '0' + r : '' + r);
}

// Hình vẽ Vector chiếc Router Wi-Fi (Chính hoặc Phụ) kèm cột sóng Wi-Fi phát ra trên ăng-ten
function createRouterIllustration(isPrimary, isSearching, isOnline) {
    var wrap = E('div', {
        style: 'position: relative; width: 156px; height: 126px; display: flex; align-items: center; justify-content: center; flex-shrink: 0;'
    });

    if (isSearching) {
        wrap.appendChild(E('div', { class: 'dd-radar-ring-1' }));
        wrap.appendChild(E('div', { class: 'dd-radar-ring-2' }));
    }

    var bodyGrad1 = isPrimary ? '#1e3a8a' : '#0f766e';
    var bodyGrad2 = isPrimary ? '#2563eb' : '#0ea5e9';
    var antColor  = isPrimary ? '#1e293b' : '#334155';
    var waveColor = isSearching ? '#2563eb' : (isOnline ? '#10b981' : '#94a3b8');
    var ledColor  = isOnline ? '#22c55e' : '#f59e0b';
    var gid       = isPrimary ? 'ddGradMain' : ('ddGradSub' + Math.floor(Math.random() * 10000));

    var waveGroup = '';
    if (isSearching || isOnline) {
        var anim1 = isSearching ? ' class="dd-wifi-arc-1"' : '';
        var anim2 = isSearching ? ' class="dd-wifi-arc-2"' : '';
        var anim3 = isSearching ? ' class="dd-wifi-arc-3"' : '';
        waveGroup =
            '<g fill="none" stroke="' + waveColor + '" stroke-linecap="round">' +
                '<path' + anim1 + ' d="M68 28 Q78 20 88 28" stroke-width="2.8"/>' +
                '<path' + anim2 + ' d="M61 21 Q78 9 95 21" stroke-width="2.6"/>' +
                '<path' + anim3 + ' d="M54 14 Q78 -2 102 14" stroke-width="2.4"/>' +
                '<circle cx="78" cy="33" r="2.8" fill="' + waveColor + '" stroke="none"/>' +
            '</g>';
    }

    wrap.innerHTML +=
        '<svg width="156" height="122" viewBox="0 0 156 122" xmlns="http://www.w3.org/2000/svg" style="position: relative; z-index: 2;">' +
            '<defs>' +
                '<linearGradient id="' + gid + '" x1="0%" y1="0%" x2="100%" y2="100%">' +
                    '<stop offset="0%" stop-color="' + bodyGrad1 + '"/>' +
                    '<stop offset="100%" stop-color="' + bodyGrad2 + '"/>' +
                '</linearGradient>' +
            '</defs>' +
            waveGroup +
            // 4 Râu ăng-ten Router
            '<rect x="30" y="28" width="5" height="46" rx="2.5" transform="rotate(-12 32 70)" fill="' + antColor + '"/>' +
            '<rect x="54" y="22" width="5" height="50" rx="2.5" transform="rotate(-4 56 70)" fill="' + antColor + '"/>' +
            '<rect x="97" y="22" width="5" height="50" rx="2.5" transform="rotate(4 99 70)" fill="' + antColor + '"/>' +
            '<rect x="121" y="28" width="5" height="46" rx="2.5" transform="rotate(12 123 70)" fill="' + antColor + '"/>' +
            // Bóng đổ dưới chân máy
            '<ellipse cx="78" cy="111" rx="56" ry="6" fill="rgba(15,23,42,0.12)"/>' +
            // Thân trên vát cạnh hiện đại
            '<polygon points="26,68 130,68 140,82 16,82" fill="url(#' + gid + ')" opacity="0.92"/>' +
            // Mặt trước Router + dải đèn LED
            '<rect x="16" y="80" width="124" height="24" rx="7" fill="#0f172a"/>' +
            '<rect x="20" y="83" width="116" height="18" rx="5" fill="#1e293b"/>' +
            // Đèn LED Nguồn, 5G, Wi-Fi, Mesh
            '<circle cx="34" cy="92" r="3.2" fill="' + ledColor + '"/>' +
            '<circle cx="46" cy="92" r="3.2" fill="' + ledColor + '"/>' +
            '<circle cx="58" cy="92" r="3.2" fill="' + (isSearching ? '#38bdf8' : ledColor) + '"/>' +
            '<circle cx="70" cy="92" r="3.2" fill="' + (isSearching ? '#60a5fa' : '#38bdf8') + '"/>' +
            // Khe tản nhiệt bên phải mặt máy
            '<rect x="96" y="88" width="28" height="2.5" rx="1.2" fill="#475569"/>' +
            '<rect x="96" y="93" width="28" height="2.5" rx="1.2" fill="#475569"/>' +
            // Chân đế trái/phải
            '<rect x="26" y="104" width="12" height="5" rx="2" fill="#334155"/>' +
            '<rect x="118" y="104" width="12" height="5" rx="2" fill="#334155"/>' +
        '</svg>';

    return wrap;
}

// Hình biểu tượng Cột Sóng Wi-Fi 4 vạch trực quan
function createWifiSignalBadge(signalText) {
    var box = E('span', {
        style: 'display: inline-flex; align-items: center; gap: 6px; padding: 5px 14px; border-radius: 999px; background: #ecfdf5; border: 1.5px solid #6ee7b7; color: #047857; font-size: 12.5px; font-weight: 800; box-shadow: 0 2px 6px rgba(16,185,129,0.14);'
    });
    box.innerHTML =
        '<svg width="18" height="16" viewBox="0 0 24 20" fill="none" stroke="#059669" stroke-width="2.4" stroke-linecap="round">' +
            '<path d="M2 7 C7.5 1.8 16.5 1.8 22 7"/>' +
            '<path d="M5.5 11 C9.2 7.5 14.8 7.5 18.5 11"/>' +
            '<path d="M9 15 C10.8 13.3 13.2 13.3 15 15"/>' +
            '<circle cx="12" cy="18" r="1.6" fill="#059669" stroke="none"/>' +
        '</svg>';
    box.appendChild(document.createTextNode(signalText));
    return box;
}

function metricCell(label, primary, sub) {
    return E('div', {
        style: 'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 9px 12px; min-width: 0;'
    }, [
        E('div', { style: 'font-size: 10.5px; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: 0.3px; margin-bottom: 3px;' }, label),
        E('div', { style: 'font-size: 13px; font-weight: 800; color: #0f172a; word-break: break-word;' }, primary || '—'),
        sub ? E('div', { style: 'font-size: 11.5px; color: #475569; margin-top: 2px; word-break: break-word;' }, sub) : E('span')
    ]);
}

function buildVisualRouterCard(opts) {
    var isPrimary   = !!opts.isPrimary;
    var isSearching = !!opts.isSearching;
    var isOnline    = opts.isOnline !== false;
    var borderCol   = isPrimary ? '#2563eb' : '#0891b2';
    var badgeBg     = isPrimary ? 'linear-gradient(135deg, #1d4ed8, #2563eb)' : 'linear-gradient(135deg, #0e7490, #0891b2)';

    var rightActions = [];
    if (opts.quickMeshBtn) {
        rightActions.push(opts.quickMeshBtn);
    }
    if (opts.isCurrent) {
        rightActions.push(E('span', {
            style: 'display: inline-flex; align-items: center; gap: 5px; padding: 5px 11px; border-radius: 999px; font-size: 11.5px; font-weight: 800; background: #dcfce7; color: #15803d; border: 1px solid #86efac;'
        }, '🟢 Thiết Bị Đang Xem'));
    } else if (opts.url) {
        rightActions.push(E('a', {
            href: opts.url,
            target: '_blank',
            class: 'btn cbi-button cbi-button-apply',
            style: 'padding: 6px 13px; font-size: 12px; font-weight: 800; border-radius: 7px; text-decoration: none;'
        }, '🔗 Mở Quản Trị (' + (opts.ip || '') + ')'));
    }

    return E('div', {
        style: 'background: #ffffff; border: 2px solid ' + borderCol + '; border-radius: 14px; overflow: hidden; box-shadow: 0 6px 18px rgba(15, 23, 42, 0.06);'
    }, [
        E('div', {
            style: 'display: flex; align-items: center; gap: 18px; flex-wrap: wrap; padding: 14px 18px; background: linear-gradient(135deg, #f8fafc 0%, #eff6ff 100%);'
        }, [
            // Cột trái: Hình vẽ chiếc Router + Nhãn lớn ROUTER CHÍNH / ROUTER PHỤ ngay dưới chân máy
            E('div', {
                style: 'display: flex; flex-direction: column; align-items: center; min-width: 164px; margin: 0 auto;'
            }, [
                createRouterIllustration(isPrimary, isSearching, isOnline),
                E('div', {
                    style: 'margin-top: -2px; padding: 5px 16px; border-radius: 999px; font-size: 12.5px; font-weight: 900; letter-spacing: 0.4px; color: #ffffff; background: ' + badgeBg + '; box-shadow: 0 2px 8px rgba(37,99,235,0.25); text-align: center;'
                }, opts.roleLabel || (isPrimary ? 'ROUTER CHÍNH' : 'ROUTER PHỤ'))
            ]),

            // Cột phải: Tên máy + các ô thông số rõ ràng
            E('div', { style: 'flex: 1 1 420px; min-width: 260px;' }, [
                E('div', {
                    style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 10px;'
                }, [
                    E('div', {}, [
                        E('div', { style: 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, [
                            E('span', { style: 'font-size: 17px; font-weight: 900; color: #0f172a;' }, opts.model || 'Router DOANDUY'),
                            opts.hostname ? E('span', {
                                style: 'font-size: 11.5px; font-weight: 800; padding: 2px 8px; border-radius: 5px; background: #dbeafe; color: #1e40af; font-family: monospace;'
                            }, opts.hostname) : E('span')
                        ]),
                        E('div', { style: 'font-size: 12px; color: #475569; margin-top: 2px;' }, opts.subtitle || '')
                    ]),
                    E('div', { style: 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, rightActions)
                ]),
                E('div', {
                    style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(195px, 1fr)); gap: 9px;'
                }, opts.cells || [])
            ])
        ])
    ]);
}

function buildWifiMeshLinkConnector(labelText) {
    return E('div', {
        style: 'display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 4px 0;'
    }, [
        E('div', { style: 'position: relative; width: 2px; height: 22px; background: linear-gradient(180deg, #2563eb, #10b981);' }, [
            E('div', { class: 'dd-flow-dot' })
        ]),
        createWifiSignalBadge(labelText),
        E('div', { style: 'position: relative; width: 2px; height: 22px; background: linear-gradient(180deg, #10b981, #0891b2);' })
    ]);
}

function buildSearchingWaveBanner(countdownNode) {
    var waveSvg = E('div', { style: 'flex-shrink: 0; display: flex; align-items: center;' });
    waveSvg.innerHTML =
        '<svg width="42" height="36" viewBox="0 0 44 36" fill="none" stroke="#2563eb" stroke-linecap="round">' +
            '<path class="dd-wifi-arc-1" d="M15 24 Q22 18 29 24" stroke-width="3"/>' +
            '<path class="dd-wifi-arc-2" d="M10 18 Q22 8 34 18" stroke-width="2.8"/>' +
            '<path class="dd-wifi-arc-3" d="M5 12 Q22 -1 39 12" stroke-width="2.6"/>' +
            '<circle cx="22" cy="29" r="3.5" fill="#2563eb" stroke="none"/>' +
        '</svg>';

    return E('div', {
        style: 'margin-top: 12px; padding: 12px 16px; border-radius: 12px; background: linear-gradient(90deg, #eff6ff 0%, #ecfeff 100%); border: 1.5px dashed #60a5fa; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px;'
    }, [
        E('div', { style: 'display: flex; align-items: center; gap: 12px;' }, [
            waveSvg,
            E('div', {}, [
                E('div', { style: 'font-size: 13.5px; font-weight: 800; color: #1e3a8a;' }, 'Đang phát sóng Wi-Fi & tìm kiếm thiết bị Mesh xung quanh...'),
                E('div', { style: 'font-size: 12px; color: #475569; margin-top: 2px;' }, 'Bật router thứ 2 (không cắm dây mạng) hoặc bấm nút Mesh trên máy kia để tự động ghép làm Router Phụ (192.168.1.10).')
            ])
        ]),
        countdownNode
    ]);
}

return baseclass.extend({
    renderPane: function() {
        ensureMeshStyles();

        var latestState = null;
        var localRemaining = 0;

        var headerBadge = E('span', {
            style: 'font-size: 12px; font-weight: 800; padding: 4px 12px; border-radius: 999px; background: #f1f5f9; color: #334155;'
        }, '⏳ Đang tải sơ đồ...');

        var countdownBadge = E('span', {
            style: 'padding: 6px 13px; border-radius: 999px; background: #1d4ed8; color: #ffffff; font-size: 12.5px; font-weight: 800; font-family: monospace;'
        }, '⏱ Tự tắt sau 05:00');

        var topologyRoot = E('div', {}, '');
        var nodeIpInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            value: '192.168.1.10',
            style: 'width: 140px; height: 36px; font-weight: 800; text-align: center; border-radius: 6px; font-family: monospace;'
        });

        function triggerPairNow() {
            callMeshSetMode('pair', (nodeIpInput.value || '192.168.1.10').trim()).then(function(res) {
                localRemaining = 300;
                ui.addNotification(null, E('p', '📡 ' + ((res && res.message) || 'Đã bật tìm kiếm & ghép nối Mesh trong 5 phút!')), 'info');
                setTimeout(refreshMesh, 1200);
            }).catch(function(err) {
                ui.addNotification(null, E('p', '❌ Lỗi bật Mesh: ' + err), 'error');
            });
        }

        function renderState(st) {
            latestState = st;
            while (topologyRoot.firstChild) topologyRoot.removeChild(topologyRoot.firstChild);

            if (!st || st.success === false) {
                headerBadge.textContent = '⚠️ Chưa đọc được trạng thái Mesh';
                headerBadge.style.background = '#fef2f2';
                headerBadge.style.color = '#b91c1c';
                return;
            }

            var peers       = Array.isArray(st.peers) ? st.peers : [];
            var role        = st.role || 'auto_idle';
            var isSearching = !!st.searching && peers.length === 0;
            localRemaining  = parseInt(st.search_remaining || 0, 10);
            countdownBadge.textContent = '⏱ Tự tắt sau ' + formatMMSS(localRemaining);

            if (role === 'controller' && peers.length > 0) {
                headerBadge.textContent = '🟢 Đã ghép nối ' + peers.length + ' Router Phụ';
                headerBadge.style.background = '#dcfce7';
                headerBadge.style.color = '#15803d';
            } else if (isSearching) {
                headerBadge.textContent = '📡 Đang dò sóng tìm Mesh (' + formatMMSS(localRemaining) + ')';
                headerBadge.style.background = '#dbeafe';
                headerBadge.style.color = '#1d4ed8';
            } else if (role === 'node') {
                headerBadge.textContent = peers.length > 0
                    ? '🟢 Router Phụ đang kết nối Router Chính'
                    : '📡 Router Phụ đang dò sóng Router Chính...';
                headerBadge.style.background = '#dbeafe';
                headerBadge.style.color = '#1d4ed8';
            } else if (role === 'auto_idle') {
                headerBadge.textContent = '💤 Tự tắt dò Mesh sau 5 phút (Chạy Độc Lập)';
                headerBadge.style.background = '#f1f5f9';
                headerBadge.style.color = '#334155';
            } else if (role === 'controller') {
                headerBadge.textContent = '🟢 Đang phát sóng Router Chính';
                headerBadge.style.background = '#dcfce7';
                headerBadge.style.color = '#15803d';
            } else {
                headerBadge.textContent = '⚪ Đang tắt Mesh (Chạy Độc Lập)';
                headerBadge.style.background = '#f1f5f9';
                headerBadge.style.color = '#475569';
            }

            // TRƯỜNG HỢP 1: Đang mở trang trên ROUTER PHỤ (VD: 192.168.1.10)
            // -> Ở TRÊN là hình ROUTER CHÍNH (192.168.1.1), ở DƯỚI là hình ROUTER PHỤ (máy này)
            if (role === 'node') {
                if (peers.length > 0) {
                    var master = peers[0];
                    topologyRoot.appendChild(buildVisualRouterCard({
                        isPrimary: true,
                        isCurrent: false,
                        isSearching: false,
                        isOnline: true,
                        roleLabel: 'ROUTER CHÍNH',
                        ip: master.ip || '192.168.1.1',
                        url: master.url || 'http://192.168.1.1',
                        model: master.model || 'Router Chính (Gateway)',
                        hostname: master.name || 'DOANDUY',
                        subtitle: 'Cấp mạng gốc & quản lý DHCP cho toàn bộ hệ thống' + (master.target ? (' • Chip: ' + master.target) : ''),
                        cells: [
                            metricCell('Địa Chỉ IP & DHCP', (master.ip || '192.168.1.1') + ' • DHCP BẬT', 'MAC: ' + (master.mac || '—')),
                            metricCell('Tín Hiệu Sóng Mesh', master.signal || 'Online', master.link_type || 'Sóng Mesh 5GHz WDS'),
                            metricCell('Sóng Wi-Fi Phát Ra', master.ssids || 'Đồng bộ cụm Mesh', 'Kênh Mesh: ' + (st.channel || '36') + ' (' + (st.htmode || 'HE160') + ')'),
                            metricCell('Thiết Bị & Thời Gian Chạy', (master.clients !== undefined ? (master.clients + ' máy kết nối') : 'Đang hoạt động'), master.uptime ? ('Chạy: ' + master.uptime) : 'Online')
                        ]
                    }));
                    topologyRoot.appendChild(buildWifiMeshLinkConnector((master.link_type || 'Sóng Mesh WDS') + ' • ' + (master.signal || 'Online') + ' • Kênh ' + (st.channel || '36')));
                }

                topologyRoot.appendChild(buildVisualRouterCard({
                    isPrimary: false,
                    isCurrent: true,
                    isSearching: peers.length === 0,
                    isOnline: peers.length > 0,
                    roleLabel: 'ROUTER PHỤ',
                    ip: st.local_ip || '192.168.1.10',
                    model: st.board_model || 'Router DOANDUY',
                    hostname: st.local_name || 'DOANDUY',
                    subtitle: 'Chip: ' + (st.soc_target || 'OpenWrt') + ' • MAC: ' + (st.local_mac || '—'),
                    cells: [
                        metricCell('Địa Chỉ IP Router Phụ', (st.local_ip || '192.168.1.10') + ' • DHCP TẮT', 'IP cứu hộ: ' + (st.rescue_ip || '192.168.1.254')),
                        metricCell('Nguồn Mạng', st.internet_source || 'Đang kết nối Router Chính', 'Tự về 192.168.1.1 nếu hết Mesh'),
                        metricCell('Sóng Wi-Fi Mở Rộng', st.user_ssids || '—', 'Kênh ' + (st.channel || '36') + ' (' + (st.htmode || 'HE160') + ')'),
                        metricCell('Tải Kết Nối & Uptime', (st.client_count || 0) + ' thiết bị đang bắt sóng', 'Chạy liên tục: ' + (st.uptime_str || '—'))
                    ]
                }));
                return;
            }

            // TRƯỜNG HỢP 2: Đang mở trên ROUTER CHÍNH (192.168.1.1) hoặc Độc Lập
            // Nếu đã tự tắt sau 5p (auto_idle / standalone), gắn luôn nút "📡 Bấm Mesh" ngay trên góc thẻ để bấm nhanh 1 chạm!
            var quickBtn = null;
            if (!isSearching && peers.length === 0 && (role === 'auto_idle' || role === 'standalone')) {
                quickBtn = E('button', {
                    class: 'btn cbi-button cbi-button-apply',
                    style: 'font-weight: 800; padding: 5px 13px; border-radius: 999px; font-size: 12px;',
                    click: triggerPairNow
                }, '📡 Bấm Mesh (Tìm 5 Phút)');
            }

            var topLabel = (st.has_internet || role === 'controller')
                ? 'ROUTER CHÍNH'
                : (isSearching ? 'ĐANG TÌM MESH' : 'ROUTER ĐỘC LẬP');

            topologyRoot.appendChild(buildVisualRouterCard({
                isPrimary: true,
                isCurrent: true,
                isSearching: isSearching,
                isOnline: !!st.has_internet || role === 'controller',
                roleLabel: topLabel,
                quickMeshBtn: quickBtn,
                ip: st.local_ip || '192.168.1.1',
                model: st.board_model || 'Router DOANDUY',
                hostname: st.local_name || 'DOANDUY',
                subtitle: 'Chip: ' + (st.soc_target || 'OpenWrt') + ' • MAC: ' + (st.local_mac || '—'),
                cells: [
                    metricCell(
                        'Địa Chỉ IP & DHCP',
                        (st.local_ip || '192.168.1.1') + (st.dhcp_enabled !== false ? ' • DHCP BẬT' : ' • DHCP TẮT'),
                        'IP cứu hộ: ' + (st.rescue_ip || '192.168.1.254')
                    ),
                    metricCell(
                        'Nguồn Internet Gốc',
                        st.internet_source || 'Chưa có mạng gốc',
                        st.wan_ip ? ('WAN IP: ' + st.wan_ip) : 'Có mạng làm Chính • Không mạng làm Phụ'
                    ),
                    metricCell(
                        'Sóng Wi-Fi Đang Phát',
                        st.user_ssids || '—',
                        (role === 'controller')
                            ? ('Sóng Mesh: ' + (st.mesh_ssid || 'DOANDUY_MESH') + ' (Kênh ' + (st.channel || '36') + ')')
                            : 'Sóng dò Mesh đang tắt gọn nhẹ'
                    ),
                    metricCell(
                        'Thiết Bị Đang Nối & Uptime',
                        (st.client_count || 0) + ' thiết bị đang kết nối',
                        'Chạy liên tục: ' + (st.uptime_str || '—')
                    )
                ]
            }));

            // Khi đang trong 5 phút tìm kiếm Mesh và chưa có máy phụ -> Hiện dải sóng Wi-Fi tìm kiếm + đếm ngược 5 phút
            if (isSearching) {
                topologyRoot.appendChild(buildSearchingWaveBanner(countdownBadge));
            }

            // KHU VỰC HÌNH ROUTER PHỤ NẰM Ở DƯỚI: Chỉ hiện khi có kết nối (peers.length > 0), không có kết nối tự ẩn hoàn toàn!
            if (peers.length > 0) {
                topologyRoot.appendChild(buildWifiMeshLinkConnector(
                    'Sóng Wi-Fi Mesh (' + (st.mesh_ssid || 'DOANDUY_MESH') + ' • Kênh ' + (st.channel || '36') + ') • Đang nối ' + peers.length + ' Router Phụ'
                ));

                var subGrid = E('div', {
                    style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(380px, 1fr)); gap: 12px;'
                });

                peers.forEach(function(p, idx) {
                    var subRoleLbl = peers.length > 1 ? ('ROUTER PHỤ #' + (idx + 1)) : 'ROUTER PHỤ';
                    subGrid.appendChild(buildVisualRouterCard({
                        isPrimary: false,
                        isCurrent: false,
                        isSearching: false,
                        isOnline: true,
                        roleLabel: subRoleLbl,
                        ip: p.ip || '192.168.1.10',
                        url: p.url || ('http://' + p.ip),
                        model: p.model || ('Router Phụ #' + (idx + 1)),
                        hostname: p.name || ('NODE-' + (idx + 1)),
                        subtitle: (p.target ? ('Chip: ' + p.target + ' • ') : '') + 'MAC: ' + (p.mac || '—'),
                        cells: [
                            metricCell('Địa Chỉ IP Router Phụ', (p.ip || '192.168.1.10') + ' • DHCP TẮT', 'Đồng bộ IP từ Router Chính'),
                            metricCell('Cường Độ Sóng Mesh', p.signal || 'Online', p.link_type || 'Sóng Mesh 5GHz WDS'),
                            metricCell('Sóng Wi-Fi Mở Rộng', p.ssids || st.user_ssids || 'Đồng bộ theo Router Chính', 'Chuyển vùng mượt 802.11k/v/r'),
                            metricCell('Thiết Bị Kết Nối & Uptime', (p.clients !== undefined ? (p.clients + ' thiết bị bắt sóng') : 'Đang hoạt động'), p.uptime ? ('Chạy: ' + p.uptime) : 'Đang trực tuyến')
                        ]
                    }));
                });

                topologyRoot.appendChild(subGrid);
            }
        }

        function refreshMesh() {
            return callMeshStatus().then(renderState).catch(function() {});
        }

        function runMode(mode, confirmMsg) {
            if (confirmMsg && !confirm(confirmMsg)) return;
            var nip = (nodeIpInput.value || '192.168.1.10').trim();
            callMeshSetMode(mode, nip).then(function(res) {
                ui.addNotification(null, E('p', '✅ ' + ((res && res.message) || 'Đã áp dụng chế độ Mesh!')), 'info');
                setTimeout(refreshMesh, 1800);
            }).catch(function(err) {
                ui.addNotification(null, E('p', '❌ Lỗi Mesh: ' + err), 'error');
            });
        }

        var pane = E('div', { style: 'display: none;' }, [
            E('div', {
                style: 'border: 1px solid #cbd5e1; border-radius: 14px; padding: 16px; background: #f8fafc; margin-bottom: 16px;'
            }, [
                E('div', {
                    style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 14px;'
                }, [
                    E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-weight: 900; font-size: 15.5px; color: #0f172a;' }, '🌐 Sơ Đồ Router Chính & Router Phụ (Auto-Mesh)'),
                        headerBadge
                    ]),
                    E('button', {
                        class: 'btn cbi-button',
                        style: 'font-weight: 750; padding: 6px 14px; border-radius: 7px;',
                        click: refreshMesh
                    }, '🔄 Làm Mới')
                ]),
                topologyRoot
            ]),

            E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 14px; padding: 16px; background: #ffffff; margin-bottom: 16px;' }, [
                E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 10px; color: #1e293b;' }, '⚡ Bảng Điều Khiển Ghép Nối Mesh Thông Minh (Tự Bật 5 Phút Khi Khởi Động Hoặc Khi Bấm Nút):'),
                E('div', { style: 'display: flex; gap: 10px; flex-wrap: wrap; align-items: center; margin-bottom: 12px;' }, [
                    E('button', {
                        class: 'btn cbi-button cbi-button-apply',
                        style: 'font-weight: 900; padding: 9px 18px; border-radius: 8px; font-size: 13.5px;',
                        click: triggerPairNow
                    }, '📡 Bấm Mesh (Tự Động Tìm & Ghép Nối 5 Phút)'),
                    E('button', {
                        class: 'btn cbi-button cbi-button-action',
                        style: 'font-weight: 750; padding: 8px 14px; border-radius: 7px;',
                        click: function() { runMode('controller', 'Giữ cố định máy này luôn phát sóng làm Router Chính (192.168.1.1, không tự tắt sau 5 phút)?'); }
                    }, '👑 Giữ Luôn Router Chính'),
                    E('span', { style: 'font-size: 12.5px; font-weight: 700; color: #475569;' }, 'IP Phụ:'),
                    nodeIpInput,
                    E('button', {
                        class: 'btn cbi-button',
                        style: 'font-weight: 750; padding: 8px 14px; border-radius: 7px; border: 1px solid #93c5fd; color: #1d4ed8;',
                        click: function() { runMode('node', 'Ép thiết bị này làm Router Phụ (IP ' + nodeIpInput.value + ', tắt DHCP, nối tới 192.168.1.1)?'); }
                    }, '📡 Ép Làm Router Phụ'),
                    E('button', {
                        class: 'btn cbi-button cbi-button-reset',
                        style: 'font-weight: 750; padding: 8px 14px; border-radius: 7px;',
                        click: function() { runMode('unmesh', 'Tắt Mesh ngay lập tức và trả thiết bị về IP mặc định 192.168.1.1 + bật lại DHCP?'); }
                    }, '🔌 Tắt Mesh Ngay')
                ]),
                E('div', { style: 'font-size: 12.5px; line-height: 1.65; color: #475569; background: #f8fafc; padding: 10px 13px; border-radius: 8px; border: 1px solid #e2e8f0;' }, [
                    E('div', {}, '• Khi khởi động lên: Mọi router tự động bật phát sóng & tìm kiếm Mesh trong 5 phút (máy có mạng làm Router Chính 192.168.1.1, máy không mạng làm Router Phụ 192.168.1.10).'),
                    E('div', {}, '• Nếu ghép nối thành công: Hình Router Phụ sẽ hiện ngay bên dưới hình Router Chính và giữ kết nối xuyên suốt.'),
                    E('div', {}, '• Sau 5 phút nếu không có thiết bị Mesh nào kết nối: Hệ thống tự động tắt dò Mesh cho nhẹ Wi-Fi; bất kỳ lúc nào cần ghép thêm chỉ cần bấm nút "📡 Bấm Mesh" ở trên.')
                ])
            ])
        ]);

        // Đếm ngược mượt từng giây trên giao diện khi đang dò sóng 5 phút
        setInterval(function() {
            if (pane.style.display === 'none' || !document.body.contains(pane)) return;
            if (latestState && latestState.searching && localRemaining > 0) {
                localRemaining = Math.max(0, localRemaining - 1);
                countdownBadge.textContent = '⏱ Tự tắt sau ' + formatMMSS(localRemaining);
                headerBadge.textContent = '📡 Đang dò sóng tìm Mesh (' + formatMMSS(localRemaining) + ')';
            }
        }, 1000);

        // Đồng bộ trạng thái thực tế từ Router mỗi 5 giây
        setInterval(function() {
            if (pane.style.display !== 'none' && document.body.contains(pane)) {
                refreshMesh();
            }
        }, 5000);

        pane._onShow = refreshMesh;
        return pane;
    }
});
