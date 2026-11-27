// DOANDUY Universal Auto-Mesh LuCI Tab (Chính 192.168.1.1 <-> Phụ 192.168.1.10)
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callMeshStatus  = rpc.declare({ object: 'doanduy.mesh', method: 'status', expect: { } });
var callMeshSetMode = rpc.declare({ object: 'doanduy.mesh', method: 'setMode', params: ['mode', 'node_ip'], expect: { } });

return baseclass.extend({
    renderPane: function() {
        var statusBadge = E('div', { style: 'font-weight: 800; font-size: 14px; color: #0f172a;' }, '⏳ Đang kiểm tra trạng thái Auto-Mesh...');
        var subMeta     = E('div', { style: 'font-size: 12.5px; color: #475569; margin-top: 4px;' }, '');
        var peersBox    = E('div', { style: 'margin-top: 12px;' }, '');
        var nodeIpInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            value: '192.168.1.10',
            style: 'width: 145px; height: 36px; font-weight: 800; text-align: center; border-radius: 6px; font-family: monospace;'
        });

        function renderState(st) {
            if (!st || st.success === false) {
                statusBadge.textContent = '⚠️ Chưa đọc được trạng thái Auto-Mesh';
                return;
            }
            statusBadge.textContent = st.role_display || 'Auto-Mesh Sẵn Sàng';
            statusBadge.style.color = (st.role === 'controller') ? '#15803d' : ((st.role === 'node') ? '#1d4ed8' : '#334155');
            subMeta.textContent = '🌐 Nguồn mạng: ' + (st.internet_source || 'N/A')
                + '  |  📍 IP hiện tại: ' + (st.local_ip || '192.168.1.1')
                + ' (Cứu hộ: ' + (st.rescue_ip || '192.168.1.254') + ')'
                + '  |  📡 Sóng Backhaul: ' + (st.mesh_ssid || 'DOANDUY_MESH') + ' (Kênh ' + (st.channel || '36') + ')';

            while (peersBox.firstChild) peersBox.removeChild(peersBox.firstChild);
            var peers = Array.isArray(st.peers) ? st.peers : [];
            if (peers.length === 0) {
                peersBox.appendChild(E('div', {
                    style: 'padding: 10px 12px; border-radius: 6px; background: #f8fafc; border: 1px dashed #cbd5e1; color: #64748b; font-size: 12.5px;'
                }, 'Chưa có thiết bị Mesh phụ nào đang ghép nối (khi bật thêm router thứ 2 không cắm mạng, thiết bị đó sẽ tự động bắt sóng DOANDUY_MESH và nhận IP 192.168.1.10).'));
            } else {
                var tbl = E('table', { class: 'table', style: 'border: 1px solid #e2e8f0; border-radius: 8px;' }, [
                    E('tr', { class: 'tr table-titles' }, [
                        E('th', { class: 'th' }, 'Thiết Bị Trong Cụm Mesh'),
                        E('th', { class: 'th' }, 'Địa Chỉ IP'),
                        E('th', { class: 'th' }, 'MAC'),
                        E('th', { class: 'th' }, 'Tín Hiệu'),
                        E('th', { class: 'th' }, 'Truy Cập')
                    ])
                ]);
                peers.forEach(function(p) {
                    tbl.appendChild(E('tr', { class: 'tr' }, [
                        E('td', { class: 'td', style: 'font-weight: 700;' }, p.name || 'Router Mesh'),
                        E('td', { class: 'td', style: 'font-family: monospace; font-weight: 700;' }, p.ip || ''),
                        E('td', { class: 'td', style: 'font-family: monospace;' }, p.mac || ''),
                        E('td', { class: 'td', style: 'color: #16a34a; font-weight: 700;' }, p.signal || 'Online'),
                        E('td', { class: 'td' }, [
                            E('a', { href: p.url || ('http://' + p.ip), target: '_blank', class: 'btn cbi-button', style: 'padding: 3px 10px; font-size: 12px;' }, '🔗 Mở Web')
                        ])
                    ]));
                });
                peersBox.appendChild(tbl);
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
            E('div', { style: 'border: 1px solid #bfdbfe; border-radius: 10px; padding: 16px; background: linear-gradient(135deg, #eff6ff 0%, #f8fafc 100%); margin-bottom: 16px;' }, [
                E('div', { style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;' }, [
                    E('div', {}, [ statusBadge, subMeta ]),
                    E('button', {
                        class: 'btn cbi-button',
                        style: 'font-weight: 700; padding: 6px 14px; border-radius: 6px;',
                        click: refreshMesh
                    }, '🔄 Làm Mới')
                ]),
                peersBox
            ]),

            E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 10px; padding: 16px; background: #ffffff; margin-bottom: 16px;' }, [
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
                    E('div', {}, '• Quy tắc tự động khi khởi động: Thiết bị CÓ mạng (5G hoặc dây WAN) tự làm Router Chính (192.168.1.1, phát DOANDUY_MESH).'),
                    E('div', {}, '• Thiết bị KHÔNG có mạng khi quét thấy sóng DOANDUY_MESH sẽ tự động làm Router Phụ, đổi IP sang 192.168.1.10 (nếu trùng tự lên .11, .12) và tắt DHCP.'),
                    E('div', {}, '• Khi tắt Router Chính hoặc hết Mesh quá 30 giây, Router Phụ tự động hoàn trả về IP mặc định 192.168.1.1 và bật lại DHCP.')
                ])
            ])
        ]);

        pane._onShow = refreshMesh;
        return pane;
    }
});
