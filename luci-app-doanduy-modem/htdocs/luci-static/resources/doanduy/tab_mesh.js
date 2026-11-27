// DOANDUY Universal Auto-Mesh Topology LuCI Tab (Chính 192.168.1.1 <-> Phụ 192.168.1.10)
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callMeshStatus  = rpc.declare({ object: 'doanduy.mesh', method: 'status', expect: { } });
var callMeshSetMode = rpc.declare({ object: 'doanduy.mesh', method: 'setMode', params: ['mode', 'node_ip'], expect: { } });

function metricCell(label, primary, sub) {
    return E('div', {
        style: 'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 10px 12px; min-width: 0;'
    }, [
        E('div', { style: 'font-size: 11px; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: 0.3px; margin-bottom: 4px;' }, label),
        E('div', { style: 'font-size: 13.5px; font-weight: 800; color: #0f172a; word-break: break-word;' }, primary || '—'),
        sub ? E('div', { style: 'font-size: 11.5px; color: #475569; margin-top: 2px; word-break: break-word;' }, sub) : E('span')
    ]);
}

function buildDeviceCard(opts) {
    var isPrimary = !!opts.isPrimary;
    var isCurrent = !!opts.isCurrent;
    var borderCol = isPrimary ? '#3b82f6' : '#0ea5e9';
    var headerBg  = isPrimary
        ? 'linear-gradient(135deg, #eff6ff 0%, #f0fdf4 100%)'
        : 'linear-gradient(135deg, #f0f9ff 0%, #f8fafc 100%)';

    var actions = [];
    if (isCurrent) {
        actions.push(E('span', {
            style: 'display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px; border-radius: 999px; font-size: 11.5px; font-weight: 800; background: #dcfce7; color: #15803d; border: 1px solid #86efac;'
        }, '🟢 Máy Đang Xem'));
    } else if (opts.url) {
        actions.push(E('a', {
            href: opts.url,
            target: '_blank',
            class: 'btn cbi-button cbi-button-apply',
            style: 'padding: 5px 12px; font-size: 12px; font-weight: 800; border-radius: 6px; text-decoration: none;'
        }, '🔗 Mở Trang Quản Trị (' + (opts.ip || '') + ')'));
    }

    actions.push(E('span', {
        style: 'display: inline-flex; align-items: center; padding: 4px 11px; border-radius: 999px; font-size: 11.5px; font-weight: 800; '
            + (isPrimary
                ? 'background: #1d4ed8; color: #ffffff;'
                : 'background: #0284c7; color: #ffffff;')
    }, opts.roleBadge || (isPrimary ? '👑 THIẾT BỊ CHÍNH' : '📡 THIẾT BỊ PHỤ')));

    return E('div', {
        style: 'background: #ffffff; border: 1.5px solid ' + borderCol + '; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 14px rgba(15, 23, 42, 0.05);'
    }, [
        E('div', {
            style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; padding: 13px 16px; background: ' + headerBg + '; border-bottom: 1px solid #e2e8f0;'
        }, [
            E('div', { style: 'display: flex; align-items: center; gap: 12px;' }, [
                E('div', {
                    style: 'width: 42px; height: 42px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 21px; background: #ffffff; border: 1px solid #cbd5e1; box-shadow: 0 1px 3px rgba(0,0,0,0.05);'
                }, isPrimary ? '👑' : '📡'),
                E('div', {}, [
                    E('div', { style: 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-size: 15.5px; font-weight: 800; color: #0f172a;' }, opts.model || 'Router DOANDUY'),
                        opts.hostname ? E('span', {
                            style: 'font-size: 11.5px; font-weight: 700; padding: 2px 8px; border-radius: 5px; background: #e2e8f0; color: #334155; font-family: monospace;'
                        }, opts.hostname) : E('span')
                    ]),
                    E('div', { style: 'font-size: 12px; color: #475569; margin-top: 2px;' }, opts.subtitle || '')
                ])
            ]),
            E('div', { style: 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, actions)
        ]),
        E('div', {
            style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(205px, 1fr)); gap: 10px; padding: 14px 16px;'
        }, opts.cells || [])
    ]);
}

function buildConnector(labelText) {
    return E('div', {
        style: 'display: flex; flex-direction: column; align-items: center; justify-content: center; margin: 2px 0;'
    }, [
        E('div', { style: 'width: 2.5px; height: 16px; background: #3b82f6;' }),
        E('div', {
            style: 'padding: 4px 14px; border-radius: 999px; background: #eff6ff; border: 1px solid #93c5fd; color: #1d4ed8; font-size: 12px; font-weight: 800; box-shadow: 0 1px 4px rgba(59,130,246,0.12);'
        }, labelText),
        E('div', { style: 'width: 2.5px; height: 16px; background: #3b82f6;' })
    ]);
}

return baseclass.extend({
    renderPane: function() {
        var headerBadge = E('span', {
            style: 'font-size: 12px; font-weight: 700; padding: 4px 10px; border-radius: 999px; background: #f1f5f9; color: #334155;'
        }, '⏳ Đang tải sơ đồ...');
        var topologyRoot = E('div', {}, '');
        var nodeIpInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            value: '192.168.1.10',
            style: 'width: 145px; height: 36px; font-weight: 800; text-align: center; border-radius: 6px; font-family: monospace;'
        });

        function renderState(st) {
            while (topologyRoot.firstChild) topologyRoot.removeChild(topologyRoot.firstChild);

            if (!st || st.success === false) {
                headerBadge.textContent = '⚠️ Chưa đọc được trạng thái Auto-Mesh';
                headerBadge.style.background = '#fef2f2';
                headerBadge.style.color = '#b91c1c';
                return;
            }

            var peers = Array.isArray(st.peers) ? st.peers : [];
            var role  = st.role || 'standalone';

            if (role === 'controller') {
                headerBadge.textContent = peers.length > 0
                    ? ('🟢 Đang ghép nối ' + peers.length + ' Thiết Bị Phụ')
                    : '🟢 Đang phát sóng Mesh chờ ghép nối';
                headerBadge.style.background = '#dcfce7';
                headerBadge.style.color = '#15803d';
            } else if (role === 'node') {
                headerBadge.textContent = peers.length > 0
                    ? '🟢 Thiết Bị Phụ đã kết nối Router Chính'
                    : '🟡 Thiết Bị Phụ đang dò sóng Router Chính...';
                headerBadge.style.background = peers.length > 0 ? '#dbeafe' : '#fef9c3';
                headerBadge.style.color = peers.length > 0 ? '#1d4ed8' : '#854d0e';
            } else if (role === 'standalone_waiting') {
                headerBadge.textContent = '🔍 Độc lập • Tự động Mesh khi có mạng/sóng';
                headerBadge.style.background = '#f1f5f9';
                headerBadge.style.color = '#334155';
            } else {
                headerBadge.textContent = '⚪ Độc lập (Đã tắt Auto-Mesh)';
                headerBadge.style.background = '#f1f5f9';
                headerBadge.style.color = '#475569';
            }

            // TRƯỜNG HỢP 1: Đang truy cập trực tiếp trên THIẾT BỊ PHỤ (VD: 192.168.1.10)
            // -> Thiết bị chính nằm ở TRÊN (khi đang có kết nối), Thiết bị phụ (máy này) nằm ở DƯỚI
            if (role === 'node') {
                if (peers.length > 0) {
                    var master = peers[0];
                    topologyRoot.appendChild(buildDeviceCard({
                        isPrimary: true,
                        isCurrent: false,
                        ip: master.ip || '192.168.1.1',
                        url: master.url || 'http://192.168.1.1',
                        model: master.model || 'Router Chính (Gateway)',
                        hostname: master.name || 'DOANDUY',
                        roleBadge: '👑 THIẾT BỊ CHÍNH (GATEWAY)',
                        subtitle: 'Cấp phát mạng & DHCP trung tâm cho toàn cụm Mesh' + (master.target ? (' • Nền tảng: ' + master.target) : ''),
                        cells: [
                            metricCell('Địa Chỉ IP & MAC', master.ip || '192.168.1.1', 'MAC: ' + (master.mac || '—') + ' • DHCP: BẬT'),
                            metricCell('Đường Truyền Tới Máy Này', master.signal || 'Online', master.link_type || 'Sóng Mesh WDS'),
                            metricCell('Sóng Wi-Fi Phát Ra', master.ssids || 'Đồng bộ cụm Mesh', 'Backhaul: ' + (st.mesh_ssid || 'DOANDUY_MESH') + ' (Kênh ' + (st.channel || '36') + ')'),
                            metricCell('Trạng Thái Hoạt Động', (master.clients !== undefined ? (master.clients + ' thiết bị kết nối') : 'Đang cấp mạng'), master.uptime ? ('Hoạt động: ' + master.uptime) : 'Gateway Online')
                        ]
                    }));
                    topologyRoot.appendChild(buildConnector('⇅ Liên kết ' + (master.link_type || 'Sóng Mesh WDS') + ' • ' + (master.signal || 'Online') + ' • Kênh ' + (st.channel || '36')));
                }

                topologyRoot.appendChild(buildDeviceCard({
                    isPrimary: false,
                    isCurrent: true,
                    ip: st.local_ip || '192.168.1.10',
                    model: st.board_model || 'Router DOANDUY',
                    hostname: st.local_name || 'DOANDUY',
                    roleBadge: '📡 THIẾT BỊ PHỤ (MESH NODE)',
                    subtitle: 'Nền tảng: ' + (st.soc_target || 'OpenWrt') + ' • Mở rộng vùng phủ sóng từ Router Chính',
                    cells: [
                        metricCell('Địa Chỉ IP & DHCP', st.local_ip || '192.168.1.10', 'DHCP: TẮT (Nhận từ 192.168.1.1) • Cứu hộ: ' + (st.rescue_ip || '192.168.1.254')),
                        metricCell('Nguồn Mạng Hiện Tại', st.internet_source || 'Đang chờ kết nối', 'MAC: ' + (st.local_mac || '—')),
                        metricCell('Sóng Wi-Fi Tại Điểm Phụ', st.user_ssids || '—', 'Kênh đồng bộ: ' + (st.channel || '36') + ' (' + (st.htmode || 'HE160') + ')'),
                        metricCell('Thiết Bị Kết Nối & Uptime', (st.client_count || 0) + ' thiết bị đang bắt sóng', 'Hoạt động: ' + (st.uptime_str || 'Vừa bật'))
                    ]
                }));
                return;
            }

            // TRƯỜNG HỢP 2: Đang xem trên THIẾT BỊ CHÍNH (192.168.1.1) hoặc chế độ ĐỘC LẬP
            // -> Luôn hiện rõ Thiết Bị Chính ở TRÊN; Thiết Bị Phụ ở DƯỚI CHỈ HIỆN KHI CÓ KẾT NỐI (peers.length > 0), không có thì ẨN HOÀN TOÀN
            var mainRoleBadge = (role === 'controller')
                ? '👑 THIẾT BỊ CHÍNH (GATEWAY)'
                : ((role === 'standalone_waiting') ? '🔍 THIẾT BỊ CHờ MESH' : '⚪ THIẾT BỊ ĐỘC LẬP');

            topologyRoot.appendChild(buildDeviceCard({
                isPrimary: true,
                isCurrent: true,
                ip: st.local_ip || '192.168.1.1',
                model: st.board_model || 'Router DOANDUY',
                hostname: st.local_name || 'DOANDUY',
                roleBadge: mainRoleBadge,
                subtitle: 'Nền tảng: ' + (st.soc_target || 'OpenWrt') + ' • MAC: ' + (st.local_mac || '—'),
                cells: [
                    metricCell(
                        'Địa Chỉ IP & Cấp Phát DHCP',
                        (st.local_ip || '192.168.1.1') + (st.dhcp_enabled !== false ? ' • DHCP BẬT' : ' • DHCP TẮT'),
                        'IP cứu hộ cố định: ' + (st.rescue_ip || '192.168.1.254')
                    ),
                    metricCell(
                        'Nguồn Internet Gốc',
                        st.internet_source || 'Chưa có mạng',
                        st.wan_ip ? ('WAN IP: ' + st.wan_ip) : 'Tự động chia sẻ mạng cho cụm Mesh'
                    ),
                    metricCell(
                        'Sóng Wi-Fi & Kênh Mesh',
                        st.user_ssids || '—',
                        role === 'controller'
                            ? ('Backhaul: ' + (st.mesh_ssid || 'DOANDUY_MESH') + ' (Kênh ' + (st.channel || '36') + ' • ' + (st.htmode || 'HE160') + ')')
                            : 'Mesh Backhaul đang tạm nghỉ'
                    ),
                    metricCell(
                        'Tải Kết Nối & Thời Gian Chạy',
                        (st.client_count || 0) + ' thiết bị đang kết nối',
                        'Hoạt động liên tục: ' + (st.uptime_str || 'Vừa bật')
                    )
                ]
            }));

            // KHU VỰC THIẾT BỊ PHỤ NẰM Ở DƯỚI: Chỉ hiện khi thực sự có kết nối (peers.length > 0); không có kết nối sẽ tự ẩn hoàn toàn!
            if (peers.length > 0) {
                topologyRoot.appendChild(buildConnector(
                    '🔗 Đang kết nối ' + peers.length + ' Thiết Bị Phụ qua ' + (st.mesh_ssid || 'DOANDUY_MESH') + ' (Kênh ' + (st.channel || '36') + ')'
                ));

                var subGrid = E('div', {
                    style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 12px;'
                });

                peers.forEach(function(p, idx) {
                    subGrid.appendChild(buildDeviceCard({
                        isPrimary: false,
                        isCurrent: false,
                        ip: p.ip || '',
                        url: p.url || ('http://' + p.ip),
                        model: p.model || ('Thiết Bị Phụ #' + (idx + 1)),
                        hostname: p.name || ('NODE-' + (idx + 1)),
                        roleBadge: '📡 THIẾT BỊ PHỤ #' + (idx + 1),
                        subtitle: (p.target ? ('Nền tảng: ' + p.target + ' • ') : '') + 'MAC: ' + (p.mac || '—'),
                        cells: [
                            metricCell('Địa Chỉ IP Quản Trị', p.ip || '192.168.1.10', 'DHCP: TẮT (Đồng bộ từ Router Chính)'),
                            metricCell('Chất Lượng Liên Kết Mesh', p.signal || 'Online', p.link_type || 'Sóng Mesh 5GHz WDS'),
                            metricCell('Sóng Wi-Fi Mở Rộng', p.ssids || st.user_ssids || 'Đồng bộ theo máy chính', 'Chuyển vùng mượt 802.11k/v/r'),
                            metricCell('Trạng Thái Thiết Bị Phụ', (p.clients !== undefined ? (p.clients + ' thiết bị đang bắt sóng') : 'Đang hoạt động'), p.uptime ? ('Hoạt động: ' + p.uptime) : 'Đang trực tuyến')
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
                setTimeout(refreshMesh, 2500);
            }).catch(function(err) {
                ui.addNotification(null, E('p', '❌ Lỗi Mesh: ' + err), 'error');
            });
        }

        var pane = E('div', { style: 'display: none;' }, [
            E('div', {
                style: 'border: 1px solid #cbd5e1; border-radius: 12px; padding: 16px; background: #f8fafc; margin-bottom: 16px;'
            }, [
                E('div', {
                    style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 14px;'
                }, [
                    E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-weight: 800; font-size: 15px; color: #0f172a;' }, '🌐 Sơ Đồ Thiết Bị Trong Hệ Thống Mesh'),
                        headerBadge
                    ]),
                    E('button', {
                        class: 'btn cbi-button',
                        style: 'font-weight: 700; padding: 6px 14px; border-radius: 6px;',
                        click: refreshMesh
                    }, '🔄 Làm Mới')
                ]),
                topologyRoot
            ]),

            E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 12px; padding: 16px; background: #ffffff; margin-bottom: 16px;' }, [
                E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 10px; color: #1e293b;' }, '⚡ Điều Khiển Auto-Mesh Đa Chip (Tự Động Giữa Mọi Dòng Qualcomm & MediaTek):'),
                E('div', { style: 'display: flex; gap: 10px; flex-wrap: wrap; align-items: center; margin-bottom: 12px;' }, [
                    E('button', {
                        class: 'btn cbi-button cbi-button-apply',
                        style: 'font-weight: 800; padding: 8px 16px; border-radius: 6px;',
                        click: function() { runMode('auto'); }
                    }, '🤖 Bật Auto-Mesh Tự Động (Khuyên Dùng)'),
                    E('button', {
                        class: 'btn cbi-button cbi-button-action',
                        style: 'font-weight: 750; padding: 8px 14px; border-radius: 6px;',
                        click: function() { runMode('controller', 'Đặt thiết bị này làm Router Chính (192.168.1.1, bật DHCP, phát sóng DOANDUY_MESH)?'); }
                    }, '👑 Ép Làm Router Chính (192.168.1.1)'),
                    E('span', { style: 'font-size: 12.5px; font-weight: 700; color: #475569;' }, 'IP Phụ:'),
                    nodeIpInput,
                    E('button', {
                        class: 'btn cbi-button',
                        style: 'font-weight: 750; padding: 8px 14px; border-radius: 6px; border: 1px solid #93c5fd; color: #1d4ed8;',
                        click: function() { runMode('node', 'Chuyển thiết bị này làm Router Phụ (IP ' + nodeIpInput.value + ', tắt DHCP, kết nối tới 192.168.1.1)?'); }
                    }, '📡 Ép Làm Router Phụ'),
                    E('button', {
                        class: 'btn cbi-button cbi-button-reset',
                        style: 'font-weight: 750; padding: 8px 14px; border-radius: 6px;',
                        click: function() { runMode('unmesh', 'Tắt Mesh và khôi phục thiết bị về IP mặc định 192.168.1.1 + bật lại DHCP?'); }
                    }, '🔌 Tắt Mesh (Về Mặc Định 192.168.1.1)')
                ]),
                E('div', { style: 'font-size: 12.5px; line-height: 1.65; color: #475569; background: #f8fafc; padding: 10px 12px; border-radius: 6px; border: 1px solid #e2e8f0;' }, [
                    E('div', {}, '• Khi khởi động: Thiết bị CÓ mạng gốc (5G hoặc dây WAN) tự làm Thiết Bị Chính (192.168.1.1, phát DOANDUY_MESH).'),
                    E('div', {}, '• Thiết bị KHÔNG có mạng khi bắt được sóng DOANDUY_MESH sẽ tự ghép làm Thiết Bị Phụ (192.168.1.10) và tự hiện thẻ nằm ngay bên dưới Thiết Bị Chính.'),
                    E('div', {}, '• Khi tắt Thiết Bị Phụ hoặc ngắt kết nối, thẻ Thiết Bị Phụ tự động ẩn đi; quá 30 giây hết Mesh sẽ tự trả về IP mặc định 192.168.1.1.')
                ])
            ])
        ]);

        // Tự động làm mới mỗi 6 giây khi đang mở tab Auto-Mesh để Thiết Bị Phụ tự hiện/ẩn theo thời gian thực
        setInterval(function() {
            if (pane.style.display !== 'none' && document.body.contains(pane)) {
                refreshMesh();
            }
        }, 6000);

        pane._onShow = refreshMesh;
        return pane;
    }
});
