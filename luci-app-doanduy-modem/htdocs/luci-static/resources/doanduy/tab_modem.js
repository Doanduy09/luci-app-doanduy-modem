// [VERIFIED-GOLDEN: luci-mod-tab-modem-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
// Scenario 03 (Modem RF, Band & IMEI) — LuCI Tab 2: Modem 5G, Khóa Băng Tần, Trạm BTS, IMEI & Lệnh AT
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callSendAT          = rpc.declare({ object: 'luci.sms-status', method: 'sendAT', params: ['cmd', 'port'] });
var callSetPort         = rpc.declare({ object: 'luci.sms-status', method: 'setCustomAtPort', params: ['port'] });
var callSetBandLock     = rpc.declare({ object: 'luci.sms-status', method: 'setBandLock', params: ['mode'] });
var callGetCellInfo     = rpc.declare({ object: 'luci.sms-status', method: 'getCellInfo', expect: { } });
var callSetCellLock     = rpc.declare({ object: 'luci.sms-status', method: 'setCellLock', params: ['action'], expect: { } });
var callGetBandState    = rpc.declare({ object: 'luci.sms-status', method: 'getBandState', expect: { } });
var callSetCustomBands  = rpc.declare({ object: 'luci.sms-status', method: 'setCustomBands', params: ['rat', 'lte_bands', 'nr_bands'], expect: { } });
var callSetCard         = rpc.declare({ object: 'luci.sms-status', method: 'setCardMode', params: ['mode', 'iface_name'], expect: { } });
var callRenameInterface = rpc.declare({ object: 'luci.sms-status', method: 'renameInterface', params: ['new_name'], expect: { } });
var callChangeIMEI      = rpc.declare({ object: 'doanduy.rf', method: 'changeIMEI', params: ['imei', 'brand'] });
var callRestoreIMEI     = rpc.declare({ object: 'doanduy.rf', method: 'restoreIMEI', expect: { } });
var callSetTTL          = rpc.declare({ object: 'doanduy.rf', method: 'setTTL', params: ['ttl'] });

return baseclass.extend({
    renderPane: function(ctx) {
        var smsRes = ctx.smsRes || {};
        var portsData = ctx.portsData || {};
        var cellRes = ctx.cellRes || {};
        var rfStatus = ctx.rfStatus || {};
        var activePort = ctx.getActivePort();

        // ---------------- TAB 2: MODEM 5G & BĂNG TẦN ----------------
        // 1. Đổi TTL Né Bóp Băng Thông
        var ttlInput = E('input', { type: 'number', class: 'cbi-input-text', value: String((rfStatus && rfStatus.ttl) ? rfStatus.ttl : 65), style: 'width: 80px; height: 36px; text-align: center; font-weight: 800; border-radius: 6px;' });
        var saveTtlBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px;',
            click: function() {
                var v = parseInt(ttlInput.value) || 65;
                saveTtlBtn.textContent = '⏳ Đang đổi...';
                callSetTTL(v).then(function() {
                    saveTtlBtn.textContent = '🚀 Đổi TTL';
                    ui.addNotification(null, E('p', '✅ Đã đổi TTL sang ' + v + ' thành công!'), 'info');
                }).catch(function(err) {
                    saveTtlBtn.textContent = '🚀 Đổi TTL';
                    ui.addNotification(null, E('p', '❌ Lỗi: ' + err), 'error');
                });
            }
        }, '🚀 Đổi TTL');

        var ttlSection = E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 8px; color: #1e293b;' }, '⚡ Đổi TTL Né Bóp Băng Thông Hotspot:'),
            E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;' }, [
                ttlInput,
                saveTtlBtn,
                E('span', { style: 'font-size: 12px; color: #64748b;' }, '• Mặc định né bóp: 65 (chống nhà mạng phát hiện chia sẻ phát Wi-Fi Hotspot)')
            ])
        ]);

        // 3. Giao thức Interface Modem
        var ifaceSelect = E('select', { class: 'cbi-input-select', style: 'width: 360px; height: 38px; font-weight: 700; border-radius: 6px;' }, [
            E('option', { value: 'wwan_smart|auto' }, '⭐ WWAN Smart Tự Động (Tất Cả Modem 4G/5G, PCIe, USB, Điện thoại)'),
            E('option', { value: 'xmm|wwan0' }, 'Fibocom FM350-GL USB (proto: xmm / wwan0)'),
            E('option', { value: 'mbim|wwan0' }, 'MBIM / Sierra EM919x / PCIe 5G (proto: mbim / wwan0)'),
            E('option', { value: 'quectel|wwan0' }, 'Quectel RM500Q / RM520N (proto: quectel / wwan0)'),
            E('option', { value: 'qmi|wwan0' }, 'QMI / Chuẩn cũ (proto: qmi / wwan0)'),
            E('option', { value: 'modemmanager|wwan0' }, 'ModemManager Tự Động (proto: modemmanager / wwan0)'),
            E('option', { value: 'ecm|usb0' }, 'ECM / Driver chuẩn (proto: dhcp / usb0)'),
            E('option', { value: 'rndis|usb0' }, 'RNDIS / Tethering USB (proto: dhcp / usb0)')
        ]);

        var saveIfaceBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px;',
            click: function() {
                var p = ifaceSelect.value.split('|');
                saveIfaceBtn.textContent = '⏳ Đang áp dụng...';
                callSetCard(p[0], p[1]).then(function(res) {
                    saveIfaceBtn.textContent = '🚀 Áp Dụng Interface';
                    ui.addNotification(null, E('p', (res && res.success === false ? '❌ ' : '✅ ') + ((res && res.message) || ('Đã đổi giao thức interface sang ' + p[0] + ' (' + p[1] + ')!'))), (res && res.success === false) ? 'error' : 'info');
                }).catch(function(err) {
                    saveIfaceBtn.textContent = '🚀 Áp Dụng Interface';
                    ui.addNotification(null, E('p', '❌ Lỗi: ' + err), 'error');
                });
            }
        }, '🚀 Áp Dụng Interface');

        var ifaceSection = E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 8px; color: #1e293b;' }, '🌐 Giao Thức Interface Modem:'),
            E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;' }, [
                ifaceSelect,
                saveIfaceBtn
            ]),
            E('div', { style: 'font-size: 12px; color: #64748b; margin-top: 6px;' }, '• Tự động nhận diện: Sierra Wireless EM919x/EM7565 -> Giao thức MBIM (wwan0) & Cổng AT /dev/ttyUSB0')
        ]);

        // 3.1. Đổi Tên Giao Diện WAN / Modem
        var curIfaceName = (smsRes && smsRes.act_iface) ? smsRes.act_iface : 'duydoan_5g';
        var ifaceNameInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            value: curIfaceName,
            placeholder: 'duydoan_5g',
            style: 'width: 220px; height: 38px; font-weight: 800; border-radius: 6px; font-size: 13.5px;'
        });

        var saveIfaceNameBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px;',
            click: function() {
                var newName = ifaceNameInput.value.trim();
                if (!newName || !/^[a-zA-Z0-9_-]+$/.test(newName)) {
                    alert('Tên interface không hợp lệ (chỉ gồm chữ cái, số, gạch dưới hoặc gạch ngang)!');
                    return;
                }
                saveIfaceNameBtn.textContent = '⏳ Đang lưu...';
                callRenameInterface(newName).then(function() {
                    saveIfaceNameBtn.textContent = '💾 Đổi Tên Interface';
                    ui.addNotification(null, E('p', '✅ Đã đổi tên interface thành [' + newName + '] và đồng bộ Firewall WAN thành công!'), 'info');
                    setTimeout(function() { location.reload(); }, 1500);
                }).catch(function(err) {
                    saveIfaceNameBtn.textContent = '💾 Đổi Tên Interface';
                    ui.addNotification(null, E('p', '❌ Lỗi: ' + err), 'error');
                });
            }
        }, '💾 Đổi Tên Interface');

        var ifaceNameSection = E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 8px; color: #1e293b;' }, '🏷️ Tùy Chỉnh Tên Interface WAN Modem:'),
            E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;' }, [
                ifaceNameInput,
                saveIfaceNameBtn,
                E('span', { style: 'font-size: 12px; color: #64748b;' }, '• Mặc định: duydoan_5g (Tự động gán Firewall WAN và NAT khi đổi tên)')
            ])
        ]);

        // 4. Cổng AT Modem
        var activePortDisplay = E('span', { style: 'font-weight: 800; color: #166534; font-family: monospace;' }, activePort);
        var atPortSelect = E('select', {
            class: 'cbi-input-select',
            style: 'width: 360px; height: 38px; font-weight: 700; border-radius: 6px;',
            change: function(ev) {
                activePort = ev.target.value; ctx.setActivePort(activePort);
                if (activePortDisplay) activePortDisplay.textContent = activePort;
            }
        });
        var availablePorts = (portsData && ((portsData.ports && portsData.ports.length > 0) ? portsData.ports : portsData.available_ports)) || ['/dev/ttyFMI0', '/dev/wwan0at0', '/dev/mhi_DUN', '/dev/ttyUSB3', '/dev/ttyUSB2', '/dev/ttyUSB1', '/dev/ttyUSB0'];
        if (!Array.isArray(availablePorts) || availablePorts.length === 0) availablePorts = ['/dev/ttyFMI0', '/dev/wwan0at0', '/dev/mhi_DUN', '/dev/ttyUSB3', '/dev/ttyUSB2', '/dev/ttyUSB1', '/dev/ttyUSB0'];
        availablePorts.forEach(function(p) {
            var label = p;
            if (p === '/dev/ttyUSB3') label += ' (Fibocom FM350-GL AT Cổng 3 - Chuẩn)';
            else if (p === '/dev/wwan0at0') label += ' (PCIe Fibocom FM350-GL / T700 wwan0at0)';
            else if (p === '/dev/mhi_DUN') label += ' (PCIe Qualcomm MHI / Foxconn)';
            else if (p === '/dev/ttyUSB2') label += ' (Quectel / SIMCOM / MeiG AT)';
            else if (p === '/dev/ttyUSB1') label += ' (Fibocom AT Phụ)';
            else if (p === '/dev/ttyUSB0') label += ' (Sierra EM919x / DM Log)';
            else if (p === '/dev/ttyFMI0') label += ' (PCIe Fibocom FM350-GL ttyFMI0)';
            else if (p === '/dev/ttyFMI1') label += ' (PCIe Fibocom FM350-GL ttyFMI1)';
            atPortSelect.appendChild(E('option', { value: p, selected: (p === activePort) }, label + (p === activePort ? ' (Đang dùng)' : '')));
        });

        var savePortBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 14px; border-radius: 6px;',
            click: function() {
                var chosen = atPortSelect.value;
                activePort = chosen; ctx.setActivePort(activePort);
                if (activePortDisplay) activePortDisplay.textContent = activePort;
                callSetPort(chosen).then(function() {
                    ui.addNotification(null, E('p', '✅ Đã lưu cổng AT: ' + chosen), 'info');
                });
            }
        }, '💾 Lưu Cổng');

        var atPortSection = E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 8px; color: #1e293b;' }, '📍 Cổng AT Modem:'),
            E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 8px;' }, [
                atPortSelect,
                savePortBtn
            ]),
            E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; padding: 8px 12px; border-radius: 6px; font-size: 12px; line-height: 1.6; color: #475569;' }, [
                E('b', {}, '💡 Cổng AT Tiêu Chuẩn: '),
                E('span', {}, '• Fibocom FM350-GL: /dev/ttyUSB3 (USB) | /dev/wwan0at0 (PCIe) | • Quectel/SIMCOM: /dev/ttyUSB2 | • Sierra (EM919x): /dev/ttyUSB0')
            ])
        ]);

        // 5. Đổi IMEI & Khóa Băng Tần
        var imeiPlaceholder = (rfStatus && rfStatus.imei) ? ('IMEI hiện tại: ' + rfStatus.imei) : 'Nhập số IMEI mới (15 số)';
        var imeiInput = E('input', { type: 'text', class: 'cbi-input-text', placeholder: imeiPlaceholder, style: 'width: 260px; height: 38px; font-weight: 800; font-family: monospace; border-radius: 6px;' });
        var genImeiBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px; background: #ffffff; border: 1px solid #cbd5e1;',
            click: function() {
                var prefix = "86428404";
                var body = Math.floor(Math.random() * 900000 + 100000).toString();
                var imei14 = prefix + body;
                var sum = 0;
                for (var i = 0; i < 14; i++) {
                    var n = parseInt(imei14[i]);
                    if (i % 2 !== 0) { n *= 2; if (n > 9) n = (n % 10) + 1; }
                    sum += n;
                }
                var checkDigit = (10 - (sum % 10)) % 10;
                imeiInput.value = imei14 + checkDigit;
            }
        }, '🎲 Tạo IMEI');

        var applyImeiBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px;',
            click: function() {
                var im = imeiInput.value.trim();
                if (!im.match(/^[0-9]{15}$/)) { alert('IMEI phải đủ 15 chữ số!'); return; }
                if (!confirm("Xác nhận đổi IMEI modem sang: " + im + "? Modem sẽ khởi động lại sóng.")) return;
                callChangeIMEI(im, 'auto').then(function(r) {
                    ui.addNotification(null, E('p', r.message || '✅ Đã đổi IMEI thành công!'), r && r.success === false ? 'error' : 'info');
                }).catch(function(err) {
                    ui.addNotification(null, E('p', '❌ Lỗi đổi IMEI: ' + err), 'error');
                });
            }
        }, '📲 Đổi IMEI');

        var restoreImeiBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px; background: #fff7ed; color: #9a3412; border: 1px solid #fed7aa; cursor: pointer;',
            click: function() {
                var orig = (rfStatus && rfStatus.original_imei) ? rfStatus.original_imei : '';
                var msg = orig ? ('Khôi phục lại IMEI gốc (' + orig + ')?') : 'Khôi phục lại IMEI gốc đã sao lưu?';
                if (!confirm(msg)) return;
                callRestoreIMEI().then(function(r) {
                    ui.addNotification(null, E('p', (r && r.message) ? r.message : 'Đã thực hiện khôi phục IMEI gốc!'), (r && r.success) ? 'info' : 'warning');
                }).catch(function(err) {
                    ui.addNotification(null, E('p', '❌ Lỗi khôi phục IMEI: ' + err), 'error');
                });
            }
        }, '🔄 Khôi Phục IMEI Gốc');

        var bandPresetSelect = E('select', { class: 'cbi-input-select', style: 'width: 100%; height: 38px; font-weight: 700; border-radius: 6px; margin-bottom: 10px;' }, [
            E('option', { value: 'auto_carrier' }, '⚡ Tự Động Khóa 5G Theo SIM Đang Dùng (Khuyên dùng)'),
            E('option', { value: 'viettel_5g' }, '🔴 Viettel 5G Max (Khóa n41 Vàng + n78/n28 + LTE B1/B3/B7/B8/B28/B40/B41)'),
            E('option', { value: 'vina_5g' }, '🔵 VinaPhone 5G Max (Khóa n77/n78 + LTE B1/B3/B8)'),
            E('option', { value: 'mobi_5g' }, '🟡 MobiFone 5G Max (Khóa n77/n78 + LTE B1/B3/B7/B8)'),
            E('option', { value: 'wintel_5g' }, '🔴 Wintel 5G Max (Chạy hạ tầng VNPT n77/n78)'),
            E('option', { value: 'vietnamobile' }, '🟠 Vietnamobile 4G (Khóa LTE B3/B8)'),
            E('option', { value: 'reset_all' }, '🔄 Tự Động Mở Rộng (Khôi phục toàn bộ băng tần)')
        ]);

        var applyBandBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px;',
            click: function() {
                var bm = bandPresetSelect.value;
                applyBandBtn.textContent = '⏳ Đang áp dụng...';
                callSetBandLock(bm).then(function(r) {
                    applyBandBtn.textContent = '🔒 Khóa Băng Tần Nhanh';
                    ui.addNotification(null, E('p', (r && r.message) || '✅ Đã áp dụng cấu hình băng tần!'), (r && r.success === false) ? 'error' : 'info');
                }).catch(function(err) {
                    applyBandBtn.textContent = '🔒 Khóa Băng Tần Nhanh';
                    ui.addNotification(null, E('p', '❌ Lỗi khóa băng tần: ' + err), 'error');
                });
            }
        }, '🔒 Khóa Băng Tần Nhanh');

        // 5.1. Manual Band Picker & RAT Selector (Option 1 - v2.2.0)
        var lteBandDefs = [
            { id: '1', label: 'B1 (2100)' },
            { id: '3', label: 'B3 (1800)' },
            { id: '7', label: 'B7 (2600)' },
            { id: '8', label: 'B8 (900)' },
            { id: '28', label: 'B28 (700)' },
            { id: '40', label: 'B40 (2300)' },
            { id: '41', label: 'B41 (2600)' }
        ];
        var nrBandDefs = [
            { id: '28', label: 'n28 (700)' },
            { id: '41', label: 'n41 (2600)' },
            { id: '77', label: 'n77 (3700)' },
            { id: '78', label: 'n78 (3500)' }
        ];
        var lteBandChecks = {};
        var nrBandChecks = {};

        var ratModeSelect = E('select', { class: 'cbi-input-select', style: 'min-width: 260px; height: 36px; font-weight: 700; border-radius: 6px;' }, [
            E('option', { value: 'lte_nr' }, '⚡ 5G + 4G (NSA/SA - Khuyên dùng)'),
            E('option', { value: 'auto' }, '🔄 Tự Động (Auto 5G/4G/3G)'),
            E('option', { value: 'nr_only' }, '🚀 Chỉ 5G SA (NR5G Only)'),
            E('option', { value: 'lte_only' }, '📶 Chỉ 4G LTE (Né 5G yếu)')
        ]);

        function makeBandPill(bandObj, mapObj, accentBg, accentBorder, accentColor) {
            var cb = E('input', { type: 'checkbox', style: 'margin: 0; width: 15px; height: 15px; cursor: pointer;' });
            mapObj[bandObj.id] = cb;
            return E('label', {
                style: 'display: inline-flex; align-items: center; gap: 6px; padding: 5px 11px; border-radius: 6px; font-size: 12.5px; font-weight: 700; cursor: pointer; background: ' + accentBg + '; border: 1.5px solid ' + accentBorder + '; color: ' + accentColor + '; user-select: none;'
            }, [ cb, bandObj.label ]);
        }

        var lteBandWrap = E('div', { style: 'display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 10px;' },
            lteBandDefs.map(function(b) { return makeBandPill(b, lteBandChecks, '#eff6ff', '#bfdbfe', '#1e40af'); })
        );
        var nrBandWrap = E('div', { style: 'display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px;' },
            nrBandDefs.map(function(b) { return makeBandPill(b, nrBandChecks, '#f0fdf4', '#86efac', '#166534'); })
        );
        var bandStateInfo = E('div', { style: 'font-size: 12px; color: #475569; margin-bottom: 10px; font-weight: 600;' },
            '💡 Nhấn "Đọc Band Hiện Tại" để đồng bộ băng tần đang mở từ card WWAN, rồi tick chọn các band muốn ép.'
        );

        var readBandBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px; background: #ffffff; border: 1px solid #cbd5e1; cursor: pointer;',
            click: function() {
                readBandBtn.textContent = '⏳ Đang đọc...';
                callGetBandState().then(function(st) {
                    readBandBtn.textContent = '🔍 Đọc Band Hiện Tại';
                    if (!st || st.success === false) {
                        bandStateInfo.textContent = '⚠️ ' + ((st && st.message) || 'Không đọc được trạng thái band từ modem.');
                        return;
                    }
                    if (st.rat) ratModeSelect.value = st.rat;
                    var lteSet = (st.lte_bands || '').split(',').filter(Boolean);
                    var nrSet = (st.nr_bands || '').split(',').filter(Boolean);
                    Object.keys(lteBandChecks).forEach(function(k) { lteBandChecks[k].checked = (lteSet.indexOf(k) !== -1); });
                    Object.keys(nrBandChecks).forEach(function(k) { nrBandChecks[k].checked = (nrSet.indexOf(k) !== -1); });
                    bandStateInfo.textContent = '📡 Modem [' + (st.vendor || 'auto').toUpperCase() + '] • Chế độ: ' + (st.rat || 'auto') +
                        ' • LTE: [' + (st.lte_bands || 'Auto') + '] • 5G NR: [' + (st.nr_bands || 'Auto') + ']' +
                        (st.supports_custom === false ? ' (Sierra chỉ hỗ trợ đổi RAT)' : '');
                }).catch(function(err) {
                    readBandBtn.textContent = '🔍 Đọc Band Hiện Tại';
                    bandStateInfo.textContent = '❌ Lỗi đọc band: ' + err;
                });
            }
        }, '🔍 Đọc Band Hiện Tại');

        var applyCustomBandBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px;',
            click: function() {
                var rat = ratModeSelect.value;
                var lteSel = Object.keys(lteBandChecks).filter(function(k) { return lteBandChecks[k].checked; });
                var nrSel = Object.keys(nrBandChecks).filter(function(k) { return nrBandChecks[k].checked; });
                if (rat === 'lte_only' && lteSel.length === 0) {
                    alert('Chế độ Chỉ 4G LTE yêu cầu chọn ít nhất 1 băng tần LTE!');
                    return;
                }
                if (rat === 'nr_only' && nrSel.length === 0) {
                    alert('Chế độ Chỉ 5G SA yêu cầu chọn ít nhất 1 băng tần 5G NR!');
                    return;
                }
                if (rat === 'lte_nr' && lteSel.length === 0 && nrSel.length === 0) {
                    alert('Vui lòng chọn ít nhất 1 băng tần LTE hoặc 5G NR (hoặc nhấn Mở Khóa Toàn Bộ)!');
                    return;
                }
                applyCustomBandBtn.textContent = '⏳ Đang khóa...';
                callSetCustomBands(rat, lteSel.join(','), nrSel.join(',')).then(function(r) {
                    applyCustomBandBtn.textContent = '✅ Áp Dụng Band Tự Chọn';
                    var ok = !(r && r.success === false);
                    ui.addNotification(null, E('p', (r && r.message) || 'Đã cập nhật băng tần tùy chọn!'), ok ? 'info' : 'error');
                    if (ok) bandStateInfo.textContent = '✅ ' + r.message;
                }).catch(function(err) {
                    applyCustomBandBtn.textContent = '✅ Áp Dụng Band Tự Chọn';
                    ui.addNotification(null, E('p', '❌ Lỗi áp dụng band: ' + err), 'error');
                });
            }
        }, '✅ Áp Dụng Band Tự Chọn');

        var resetAllBandBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px; background: #fff7ed; color: #9a3412; border: 1px solid #fed7aa; cursor: pointer;',
            click: function() {
                resetAllBandBtn.textContent = '⏳ Đang mở...';
                callSetBandLock('reset_all').then(function(r) {
                    resetAllBandBtn.textContent = '🔄 Mở Khóa Toàn Bộ';
                    ratModeSelect.value = 'auto';
                    Object.keys(lteBandChecks).forEach(function(k) { lteBandChecks[k].checked = false; });
                    Object.keys(nrBandChecks).forEach(function(k) { nrBandChecks[k].checked = false; });
                    ui.addNotification(null, E('p', (r && r.message) || 'Đã khôi phục toàn bộ băng tần!'), (r && r.success === false) ? 'error' : 'info');
                }).catch(function(err) {
                    resetAllBandBtn.textContent = '🔄 Mở Khóa Toàn Bộ';
                    ui.addNotification(null, E('p', '❌ Lỗi: ' + err), 'error');
                });
            }
        }, '🔄 Mở Khóa Toàn Bộ');

        // 5.2. Live Serving Cell Telemetry Card (tận dụng callGetCellInfo sẵn có)
        var cellGridBox = E('div', {});
        function renderCellGrid(ci) {
            ci = ci || {};
            cellGridBox.innerHTML = '';
            var lockStateBadge = ci.is_cell_locked ? E('span', {
                style: 'display: inline-block; padding: 3px 9px; border-radius: 6px; font-size: 11.5px; font-weight: 750; background: #fef3c7; color: #92400e; border: 1px solid #fde68a; margin-bottom: 10px;'
            }, '📌 Đang khóa Cell: ' + (ci.locked_details || 'Active')) : null;
            if (lockStateBadge) cellGridBox.appendChild(lockStateBadge);

            cellGridBox.appendChild(E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 10px;' }, [
                E('div', { style: 'background: #ffffff; border: 1px solid #dbeafe; border-radius: 8px; padding: 10px 12px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 12.5px; color: #1d4ed8; margin-bottom: 4px;' }, '📶 4G LTE Serving Cell (' + (ci.carrier_name || 'N/A') + ')'),
                    E('div', { style: 'font-size: 12px; color: #334155; font-family: monospace; line-height: 1.6;' },
                        'Band: B' + (ci.lte_band || '--') + ' | PCI: ' + (ci.lte_pci || '--') + '\n' +
                        'EARFCN: ' + (ci.lte_earfcn || '--') + ' | Cell ID: ' + (ci.lte_cellid || '--') + '\n' +
                        'RSRP: ' + (ci.lte_rsrp || '--') + ' dBm | SINR: ' + (ci.lte_sinr || '--') + ' dB'
                    )
                ]),
                E('div', { style: 'background: #ffffff; border: 1px solid #bbf7d0; border-radius: 8px; padding: 10px 12px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 12.5px; color: #15803d; margin-bottom: 4px;' }, '🚀 5G NR Serving Cell'),
                    E('div', { style: 'font-size: 12px; color: #334155; font-family: monospace; line-height: 1.6;' },
                        'Band: n' + (ci.nr_band || '--') + ' | PCI: ' + (ci.nr_pci || '--') + '\n' +
                        'NR-ARFCN: ' + (ci.nr_arfcn || '--') + '\n' +
                        'SS-RSRP: ' + (ci.nr_rsrp || '--') + ' dBm | SS-SINR: ' + (ci.nr_sinr || '--') + ' dB'
                    )
                ])
            ]));
        }
        renderCellGrid(cellRes);

        var refreshCellBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px; background: #ffffff; border: 1px solid #cbd5e1; cursor: pointer;',
            click: function() {
                refreshCellBtn.textContent = '⏳ Đang quét...';
                callGetCellInfo().then(function(ci) {
                    refreshCellBtn.textContent = '🔄 Làm Mới Cell';
                    renderCellGrid(ci);
                }).catch(function(err) {
                    refreshCellBtn.textContent = '🔄 Làm Mới Cell';
                    ui.addNotification(null, E('p', '❌ Lỗi đọc thông số Cell: ' + err), 'error');
                });
            }
        }, '🔄 Làm Mới Cell');

        var cellActionChildren = [ refreshCellBtn ];
        if (cellRes && cellRes.supports_cell_lock === true) {
            cellActionChildren.push(E('button', {
                class: 'btn cbi-button cbi-button-action',
                style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px;',
                click: function() {
                    if (!confirm('Khóa cứng vào trạm BTS đang bắt? Lưu ý: nếu trạm bảo trì có thể mất sóng tới khi bấm Mở Khóa.')) return;
                    callSetCellLock('lock').then(function(r) {
                        ui.addNotification(null, E('p', (r && r.message) || 'Đã khóa trạm BTS!'), (r && r.success === false) ? 'error' : 'info');
                        callGetCellInfo().then(renderCellGrid).catch(function() {});
                    });
                }
            }, '📌 Khóa Trạm BTS (Quectel)'));
            cellActionChildren.push(E('button', {
                class: 'btn cbi-button',
                style: 'font-weight: 700; font-size: 12px; padding: 6px 12px; border-radius: 6px; background: #fff7ed; color: #9a3412; border: 1px solid #fed7aa;',
                click: function() {
                    callSetCellLock('unlock').then(function(r) {
                        ui.addNotification(null, E('p', (r && r.message) || 'Đã mở khóa trạm BTS!'), (r && r.success === false) ? 'error' : 'info');
                        callGetCellInfo().then(renderCellGrid).catch(function() {});
                    });
                }
            }, '🔓 Mở Khóa Trạm'));
        } else {
            cellActionChildren.push(E('span', { style: 'font-size: 12px; color: #64748b;' }, '• Card Fibocom/Sierra dùng Chọn Băng Tần Thủ Công phía trên để tối ưu trạm an toàn, không gây kẹt cell.'));
        }

        var cellInfoSection = E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 10px; color: #1e293b;' }, '📡 Thông Số Trạm BTS & Sóng 4G/5G Trực Tiếp:'),
            cellGridBox,
            E('div', { style: 'display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-top: 10px;' }, cellActionChildren)
        ]);

        var atCmdInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            placeholder: 'Nhập lệnh AT (vd: ATI, AT+CSQ, AT+CEREG?, AT+CGDCONT?)...',
            style: 'width: 100%; height: 40px; font-weight: 800; font-family: monospace; border-radius: 6px; margin-bottom: 10px;'
        });

        var atRespBox = E('pre', {
            style: 'background: #0f172a; color: #38bdf8; padding: 16px; border-radius: 8px; font-family: monospace; font-size: 13px; line-height: 1.5; max-height: 360px; overflow-y: auto; white-space: pre-wrap; word-break: break-all;'
        }, 'Ready. Nhập lệnh AT hoặc nhấn "Kiểm Tra ATI" để kiểm tra modem.');

        function executeAtCommand(cmd) {
            var c = (cmd || atCmdInput.value).trim();
            if (!c) { alert('Vui lòng nhập lệnh AT!'); return; }
            atCmdInput.value = c;
            var targetP = atPortSelect.value || activePort;
            atRespBox.textContent = '⏳ Đang gửi: ' + c + ' tới modem qua cổng ' + targetP + '...';
            callSendAT(c, targetP).then(function(r) {
                if (r && r.response) {
                    atRespBox.textContent = r.response;
                } else if (r && r.message) {
                    atRespBox.textContent = 'Phản hồi: ' + r.message;
                } else {
                    atRespBox.textContent = JSON.stringify(r, null, 2);
                }
            }).catch(function(err) {
                atRespBox.textContent = '❌ Lỗi gửi lệnh AT: ' + err;
            });
        }

        var sendAtActionBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 13px; padding: 8px 20px; border-radius: 6px;',
            click: function() { executeAtCommand(); }
        }, '🚀 Gửi Lệnh AT');

        var atiCheckBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 12.5px; padding: 6px 16px; border-radius: 6px; background: #059669; border-color: #059669;',
            click: function() { executeAtCommand('ATI'); }
        }, '🔍 Kiểm Tra ATI (Thông Tin Modem)');

        var atQuickCmds = E('div', { style: 'display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px;' }, [
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #ecfdf5; color: #065f46; border: 1px solid #a7f3d0; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('ATI'); } }, '🔍 ATI (Thông tin modem)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #eff6ff; color: #1e40af; border: 1px solid #bfdbfe; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+CSQ'); } }, '📶 AT+CSQ (Cường độ sóng)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #f8fafc; border: 1px solid #cbd5e1; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+CPIN?'); } }, '📱 AT+CPIN? (Trạng thái SIM)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #f8fafc; border: 1px solid #cbd5e1; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+CEREG?'); } }, '📡 AT+CEREG? (Đăng ký mạng 4G/5G)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #f8fafc; border: 1px solid #cbd5e1; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+CGDCONT?'); } }, '🌐 AT+CGDCONT? (Cấu hình APN)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #f8fafc; border: 1px solid #cbd5e1; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+COPS?'); } }, '⚡ AT+COPS? (Nhà mạng đang kết nối)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #fdf4ff; color: #86198f; border: 1px solid #f0abfc; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+GTCCINFO?'); } }, '🔬 AT+GTCCINFO? (Fibocom Cell/Band)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #fdf4ff; color: #86198f; border: 1px solid #f0abfc; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT+QENG="servingcell"'); } }, '🔬 AT+QENG (Quectel Serving Cell)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #fdf4ff; color: #86198f; border: 1px solid #f0abfc; cursor: pointer; border-radius: 6px;', click: function() { executeAtCommand('AT!GSTATUS?'); } }, '🔬 AT!GSTATUS? (Sierra Status)'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 4px 10px; font-weight: 700; background: #fff1f2; color: #9f1239; border: 1px solid #fecdd3; cursor: pointer; border-radius: 6px;', click: function() { if (confirm("Khởi động lại sóng modem (AT+CFUN=1,1)?")) executeAtCommand('AT+CFUN=1,1'); } }, '🔄 Reset Sóng Modem')
        ]);

        var modemOverviewHeader = E('div', {
            style: 'background: #f0fdf4; border: 1.5px solid #bbf7d0; border-radius: 8px; padding: 14px; margin-bottom: 16px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;'
        }, [
            E('div', {}, [
                E('div', { style: 'font-weight: 800; font-size: 14px; color: #166534;' }, [
                    '🟢 Cổng AT Đang Hoạt Động: ',
                    activePortDisplay
                ]),
                E('div', { style: 'font-size: 12.5px; color: #15803d; margin-top: 3px;' }, '• Tự động kết nối và thẩm định qua lệnh ATI • Sẵn sàng nhận lệnh AT & điều khiển sóng 4G/5G.')
            ]),
            atiCheckBtn
        ]);

        var atTerminalSection = E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-top: 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 6px; color: #1e293b;' }, '💻 Console Gửi Lệnh AT Trực Tiếp:'),
            E('div', { style: 'font-size: 12.5px; color: #64748b; font-weight: 600; margin-bottom: 8px;' }, 'Phím tắt lệnh thông dụng (1-Click gửi ngay):'),
            atQuickCmds,
            atCmdInput,
            E('div', { style: 'display: flex; gap: 8px; margin-bottom: 14px;' }, [ sendAtActionBtn ]),
            atRespBox
        ]);

        var modemTabContent = E('div', { class: 'cbi-section', style: 'display: none; padding: 20px; background: #ffffff; border-radius: 10px; border: 1px solid #e2e8f0;' }, [
            E('h3', { style: 'margin-top: 0; font-size: 18px; font-weight: 800; color: #1e293b; border-bottom: 1px solid #f1f5f9; padding-bottom: 10px;' }, '📶 Modem 5G, Băng Tần & Lệnh AT'),
            modemOverviewHeader,
            ttlSection,
            ifaceSection,
            ifaceNameSection,
            atPortSection,
            E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
                E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 6px; color: #1e293b;' }, '📲 Tự Đổi IMEI Modem (Kháng Chặn & Né Giới Hạn):'),
                E('div', { style: 'display: flex; gap: 8px; align-items: center; flex-wrap: wrap;' }, [ imeiInput, genImeiBtn, applyImeiBtn, restoreImeiBtn ])
            ]),
            E('div', { style: 'border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; background: #fafafa; margin-bottom: 16px;' }, [
                E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 6px; color: #1e293b;' }, '⚡ Khóa Băng Tần 5G/4G Tối Ưu Tốc Độ:'),
                bandPresetSelect,
                applyBandBtn,
                E('div', { style: 'border-top: 1px dashed #cbd5e1; margin: 14px 0 12px 0; padding-top: 12px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 13.5px; margin-bottom: 8px; color: #0f172a;' }, '🎛️ Chọn Chế Độ Mạng & Băng Tần Thủ Công (Band Picker):'),
                    E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 10px;' }, [
                        E('span', { style: 'font-size: 12.5px; font-weight: 700; color: #334155;' }, 'Chế độ RAT:'),
                        ratModeSelect
                    ]),
                    E('div', { style: 'font-size: 12px; font-weight: 750; color: #1e40af; margin-bottom: 5px;' }, '4G LTE Bands:'),
                    lteBandWrap,
                    E('div', { style: 'font-size: 12px; font-weight: 750; color: #166534; margin-bottom: 5px;' }, '5G NR Bands:'),
                    nrBandWrap,
                    bandStateInfo,
                    E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap;' }, [ readBandBtn, applyCustomBandBtn, resetAllBandBtn ])
                ])
            ]),
            cellInfoSection,
            atTerminalSection
        ]);
        var cellLoaded = false;
        modemTabContent._onShow = function() {
            if (!cellLoaded) {
                cellLoaded = true;
                callGetCellInfo().then(renderCellGrid).catch(function() {});
            }
        };
        return modemTabContent;
    }
});
// [/VERIFIED-GOLDEN]
