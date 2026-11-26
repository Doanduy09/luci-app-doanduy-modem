// [VERIFIED-GOLDEN: part4-luci-smarthome-ui | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callSHStatus    = rpc.declare({ object: 'doanduy.smarthome', method: 'status', expect: { } });
var callSHScan      = rpc.declare({ object: 'doanduy.smarthome', method: 'scanHubs', expect: { } });
var callSHSaveCtrl  = rpc.declare({ object: 'doanduy.smarthome', method: 'saveController', params: ['id', 'kind', 'name', 'room', 'ip', 'mac', 'device_id', 'local_key', 'control_type'], expect: { } });
var callSHRmCtrl    = rpc.declare({ object: 'doanduy.smarthome', method: 'removeController', params: ['id'], expect: { } });
var callSHSearch    = rpc.declare({ object: 'doanduy.smarthome', method: 'searchCatalog', params: ['query', 'category', 'include_online'], expect: { } });
var callSHTestItem  = rpc.declare({ object: 'doanduy.smarthome', method: 'testCatalogItem', params: ['catalog_id', 'irdb_path', 'controller_id', 'dry_run'], expect: { } });
var callSHAdd       = rpc.declare({ object: 'doanduy.smarthome', method: 'addDevice', params: ['driver', 'catalog_id', 'irdb_path', 'controller_id', 'name', 'room', 'category', 'ip', 'mac', 'device_id', 'local_key', 'dp', 'on_url', 'off_url', 'tv_id'], expect: { } });
var callSHRemove    = rpc.declare({ object: 'doanduy.smarthome', method: 'removeDevice', params: ['id'], expect: { } });
var callSHControl   = rpc.declare({ object: 'doanduy.smarthome', method: 'controlDevice', params: ['id', 'op', 'value', 'button', 'dry_run'], expect: { } });
var callSHLearn     = rpc.declare({ object: 'doanduy.smarthome', method: 'learnButton', params: ['id', 'button', 'label'], expect: { } });

var CAT_META = [
    { key: 'all',   icon: '✨', label: 'Tất cả' },
    { key: 'ac',    icon: '❄️', label: 'Máy Lạnh' },
    { key: 'tv',    icon: '📺', label: 'Tivi' },
    { key: 'fan',   icon: '🌀', label: 'Quạt' },
    { key: 'audio', icon: '🔊', label: 'Loa / Amply' },
    { key: 'other', icon: '📦', label: 'Khác / Tự học' },
    { key: 'irdb',  icon: '🌐', label: 'Kho Online 3.200+' }
];

function catIcon(cat) {
    var map = { ac: '❄️', tv: '📺', fan: '🌀', audio: '🔊', light: '💡', plug: '🔌', other: '📦' };
    return map[cat] || '🎛️';
}

function mkBtn(label, style, onClick) {
    return E('button', {
        class: 'btn cbi-button',
        style: 'padding: 6px 11px; border-radius: 7px; font-weight: 700; font-size: 12.5px; cursor: pointer; border: 1px solid #cbd5e1; background: #ffffff; color: #1e293b;' + (style || ''),
        click: onClick
    }, label);
}

function fmtAgo(sec) {
    if (sec === null || sec === undefined || isNaN(sec)) return '';
    var s = Math.max(0, Math.floor(Number(sec)));
    if (s < 5) return 'vừa xong';
    if (s < 60) return s + 's trước';
    if (s < 3600) return Math.floor(s / 60) + 'p trước';
    return Math.floor(s / 3600) + 'g trước';
}

return baseclass.extend({
    renderPane: function() {
        var state = {
            controllers: [],
            devices: [],
            lan_tvs: [],
            rooms: [],
            voice_hub: null,
            roomFilter: 'all',
            cat: 'all',
            includeOnline: true,
            searchTimer: null,
            learnDevices: {},
            showCtrlsPanel: false,
            modalTab: 'ir'
        };

        // =========================================================================
        // 1. HEADER TOOLBAR + ROOM PILLS (Front & Center)
        // =========================================================================
        var roomBar = E('div', { style: 'display: flex; gap: 6px; flex-wrap: wrap; align-items: center;' });
        var addCtaBtn = mkBtn('➕ Thêm Thiết Bị', 'background: #2563eb; color: #ffffff; border-color: #2563eb; padding: 8px 15px; font-size: 13px;', function() {
            openAddModal('ir');
        });
        var toggleCtrlsBtn = mkBtn('📡 Bộ Điều Khiển', 'background: #eff6ff; color: #1d4ed8; border-color: #bfdbfe;', function() {
            state.showCtrlsPanel = !state.showCtrlsPanel;
            ctrlManagerBox.style.display = state.showCtrlsPanel ? 'block' : 'none';
        });

        var headerBar = E('div', {
            style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; padding-bottom: 12px; border-bottom: 1px solid #e2e8f0; margin-bottom: 12px;'
        }, [
            E('div', {}, [
                E('h3', { style: 'margin: 0; font-size: 18px; font-weight: 850; color: #0f172a;' }, '🏠 Thiết Bị Điều Khiển Nhà'),
                E('div', { style: 'font-size: 12px; color: #64748b; margin-top: 2px;' }, 'Điều khiển tập trung Máy lạnh, Quạt, Đèn, Công tắc Wi-Fi, TV LAN, Cục S06 & Mạch Giọng nói ESP32')
            ]),
            E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center;' }, [
                addCtaBtn,
                toggleCtrlsBtn,
                mkBtn('🔄 Làm mới', '', function() { refreshStatus(); })
            ])
        ]);

        // =========================================================================
        // 2. CONNECTED HOME DEVICES GRID (Main First-Read Area — Zero Scroll!)
        // =========================================================================
        var devicesGrid = E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(305px, 1fr)); gap: 12px; margin-top: 10px;' });

        function sendCtrl(devId, op, val, btnId) {
            callSHControl(devId, op || '', val || '', btnId || '', false).then(function(res) {
                if (res && res.device) {
                    for (var i = 0; i < state.devices.length; i++) {
                        if (state.devices[i].id === devId) { state.devices[i] = res.device; break; }
                    }
                    renderDeviceCards();
                }
                if (res && res.message) {
                    ui.addNotification(null, E('p', res.message), res.ok ? 'info' : 'warning');
                }
            }).catch(function(err) {
                ui.addNotification(null, E('p', '❌ Lỗi điều khiển: ' + err), 'error');
            });
        }

        function findCtrlName(cid) {
            for (var i = 0; i < state.controllers.length; i++) {
                if (state.controllers[i].id === cid) return state.controllers[i].name;
            }
            return 'S06 Pro';
        }

        function renderRoomPills() {
            roomBar.innerHTML = '';
            var list = ['all'].concat(state.rooms || []);
            list.forEach(function(rm) {
                var act = (state.roomFilter === rm);
                roomBar.appendChild(mkBtn(rm === 'all' ? '🏡 Tất cả phòng' : ('📍 ' + rm),
                    'font-size: 12px; padding: 5px 11px; border-radius: 999px;' + (act ? 'background: #0f172a; color: #fff; border-color: #0f172a;' : 'background: #ffffff; color: #334155;'),
                    function() { state.roomFilter = rm; renderRoomPills(); renderDeviceCards(); }
                ));
            });
        }

        function renderDeviceCards() {
            devicesGrid.innerHTML = '';
            var visible = (state.devices || []).filter(function(d) {
                return state.roomFilter === 'all' || (d.room || '') === state.roomFilter;
            });
            if (visible.length === 0) {
                devicesGrid.appendChild(E('div', {
                    style: 'grid-column: 1 / -1; padding: 26px; text-align: center; background: #ffffff; border: 1.5px dashed #cbd5e1; border-radius: 10px; color: #475569;'
                }, [
                    E('div', { style: 'font-size: 14px; font-weight: 700; margin-bottom: 8px;' }, 'Chưa có thiết bị nào trong mục này.'),
                    mkBtn('➕ Thêm Thiết Bị Ngay', 'background: #2563eb; color: #fff; border-color: #2563eb;', function() { openAddModal('ir'); })
                ]));
                return;
            }

            visible.forEach(function(dev) {
                var drv = dev.driver || (dev.type === 'ac' ? 'tuya_ir_ac' : 'tuya_ir_remote');
                var subMeta = (dev.room || 'Nhà') + ' • ' + (dev.brand_label || dev.brand || drv);
                if (drv === 'tuya_ir_ac' || drv === 'tuya_ir_remote' || drv === 'custom_ir') {
                    subMeta += ' • qua ' + findCtrlName(dev.controller_id || 's06_default');
                }

                var cardHeader = E('div', { style: 'display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; border-bottom: 1px solid #f1f5f9; padding-bottom: 8px; margin-bottom: 10px;' }, [
                    E('div', {}, [
                        E('div', { style: 'font-weight: 800; font-size: 14.5px; color: #0f172a;' }, catIcon(dev.category) + ' ' + dev.name),
                        E('div', { style: 'font-size: 11.5px; color: #64748b;' }, subMeta)
                    ]),
                    mkBtn('🗑️', 'font-size: 11px; padding: 3px 8px; color: #dc2626; border-color: #fecaca; background: #fef2f2;', function() {
                        if (!confirm('Xóa thiết bị "' + dev.name + '"?')) return;
                        callSHRemove(dev.id).then(function(r) {
                            if (r && Array.isArray(r.devices)) state.devices = r.devices;
                            renderDeviceCards();
                        });
                    })
                ]);

                var bodyNodes = [];
                if (drv === 'tuya_ir_ac' || dev.type === 'ac') {
                    var st = dev.state || { power: false, temp: 26, mode: 'cool', fan: 'auto', swing: false };
                    bodyNodes.push(E('div', { style: 'display: flex; align-items: center; justify-content: space-between; background: #f8fafc; padding: 10px 14px; border-radius: 8px; margin-bottom: 10px;' }, [
                        E('div', {}, [
                            E('div', { style: 'font-size: 26px; font-weight: 850; color: #0284c7; line-height: 1.1;' }, String(st.temp || 26) + '°C'),
                            E('div', { style: 'font-size: 11.5px; color: #64748b; margin-top: 2px;' }, (st.power ? '🟢 Đang BẬT' : '⚪ Đang TẮT') + ' • ' + (st.mode || 'cool').toUpperCase() + ' • Gió ' + (st.fan || 'auto'))
                        ]),
                        E('div', { style: 'display: flex; gap: 6px;' }, [
                            mkBtn('❄️ Bật', st.power ? 'background: #16a34a; color: #fff; border-color: #16a34a;' : '', function() { sendCtrl(dev.id, 'on'); }),
                            mkBtn('🛑 Tắt', !st.power ? 'background: #dc2626; color: #fff; border-color: #dc2626;' : '', function() { sendCtrl(dev.id, 'off'); }),
                            mkBtn('➖', 'font-size: 14px;', function() { sendCtrl(dev.id, 'temp_down'); }),
                            mkBtn('➕', 'font-size: 14px;', function() { sendCtrl(dev.id, 'temp_up'); })
                        ])
                    ]));
                    var qt = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap; margin-bottom: 8px;' });
                    [24, 25, 26, 27, 28].forEach(function(tp) {
                        var actS = (Number(st.temp) === tp && st.power) ? 'background: #2563eb; color: #fff; border-color: #2563eb;' : '';
                        qt.appendChild(mkBtn(tp + '°C', 'font-size: 11.5px; padding: 4px 9px;' + actS, function() { sendCtrl(dev.id, 'set_temp', String(tp)); }));
                    });
                    bodyNodes.push(qt);

                    var mr = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap; margin-bottom: 8px;' });
                    [['cool','❄ Cool'],['dry','💧 Dry'],['fan','🌀 Fan'],['auto','✨ Auto']].forEach(function(pair) {
                        var ms = (st.mode === pair[0]) ? 'background: #0284c7; color: #fff; border-color: #0284c7;' : '';
                        mr.appendChild(mkBtn(pair[1], 'font-size: 11.5px; padding: 4px 8px;' + ms, function() { sendCtrl(dev.id, 'mode', pair[0]); }));
                    });
                    bodyNodes.push(mr);

                    var fr = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap;' });
                    [['low','🍃 Nhẹ'],['med','💨 Vừa'],['high','🌪 Mạnh'],['auto','Gió Auto']].forEach(function(pair) {
                        var fs = (st.fan === pair[0]) ? 'background: #0f766e; color: #fff; border-color: #0f766e;' : '';
                        fr.appendChild(mkBtn(pair[1], 'font-size: 11.5px; padding: 4px 8px;' + fs, function() { sendCtrl(dev.id, 'fan', pair[0]); }));
                    });
                    fr.appendChild(mkBtn(st.swing ? '↕ Đảo: BẬT' : '↕ Đảo gió', st.swing ? 'background: #7c3aed; color: #fff; border-color: #7c3aed;' : '', function() { sendCtrl(dev.id, 'swing'); }));
                    fr.appendChild(mkBtn('🔄 Đổi mã', '', function() { sendCtrl(dev.id, 'next_variant'); }));
                    bodyNodes.push(fr);

                } else if (drv === 'tuya_switch' || drv === 'http_relay') {
                    var swOn = !!(dev.state && dev.state.on);
                    bodyNodes.push(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; background: #f8fafc; padding: 12px 14px; border-radius: 8px; gap: 8px;' }, [
                        E('div', { style: 'font-weight: 800; font-size: 14px; color: ' + (swOn ? '#16a34a' : '#64748b') + ';' }, swOn ? '🟢 ĐANG BẬT' : '⚪ ĐANG TẮT'),
                        E('div', { style: 'display: flex; gap: 6px;' }, [
                            mkBtn('⚡ BẬT', swOn ? 'background: #16a34a; color: #fff; border-color: #16a34a;' : '', function() { sendCtrl(dev.id, 'on'); }),
                            mkBtn('🛑 TẮT', !swOn ? 'background: #dc2626; color: #fff; border-color: #dc2626;' : '', function() { sendCtrl(dev.id, 'off'); }),
                            mkBtn('🔁 Đảo', '', function() { sendCtrl(dev.id, 'toggle'); })
                        ])
                    ]));

                } else if (drv === 'android_tv') {
                    var tvGrid = E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fill, minmax(95px, 1fr)); gap: 6px;' }, [
                        mkBtn('▶ YouTube', 'background: #fef2f2; color: #b91c1c; border-color: #fecaca;', function() { sendCtrl(dev.id, 'cmd', 'mở youtube'); }),
                        mkBtn('📺 DuyTV', 'background: #eff6ff; color: #1d4ed8; border-color: #bfdbfe;', function() { sendCtrl(dev.id, 'cmd', 'mở duytv'); }),
                        mkBtn('🔊 Âm +', '', function() { sendCtrl(dev.id, 'key', '', 'vol_up'); }),
                        mkBtn('🔉 Âm -', '', function() { sendCtrl(dev.id, 'key', '', 'vol_down'); }),
                        mkBtn('🏠 Home', '', function() { sendCtrl(dev.id, 'key', '', 'home'); }),
                        mkBtn('↩ Back', '', function() { sendCtrl(dev.id, 'key', '', 'back'); }),
                        mkBtn('☀ Mở TV', '', function() { sendCtrl(dev.id, 'key', '', 'power'); }),
                        mkBtn('💤 Tắt TV', 'background: #fff1f2; color: #be123c;', function() { sendCtrl(dev.id, 'key', '', 'sleep'); })
                    ]);
                    bodyNodes.push(tvGrid);

                } else {
                    var inLearn = !!state.learnDevices[dev.id];
                    bodyNodes.push(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; gap: 6px; flex-wrap: wrap;' }, [
                        mkBtn(inLearn ? '✅ Xong Học Phím' : '📡 Học / Sửa Phím', inLearn ? 'background: #d97706; color: #fff; border-color: #d97706;' : 'background: #fffbeb; color: #b45309; border-color: #fde68a;', function() {
                            state.learnDevices[dev.id] = !inLearn;
                            renderDeviceCards();
                        }),
                        mkBtn('➕ Thêm Nút Mới', 'font-size: 11.5px;', function() {
                            var lbl = prompt('Nhập tên nút mới (VD: Hẹn giờ 2h, Đèn LED):');
                            if (!lbl || !lbl.trim()) return;
                            ui.addNotification(null, E('p', '📡 Chĩa remote vào S06 Pro bấm nút [' + lbl.trim() + '] trong 12s...'), 'info');
                            callSHLearn(dev.id, '', lbl.trim()).then(function(r) {
                                ui.addNotification(null, E('p', (r && r.message) || 'Xong!'), r && r.ok ? 'info' : 'error');
                                if (r && r.device) {
                                    for (var i = 0; i < state.devices.length; i++) {
                                        if (state.devices[i].id === dev.id) { state.devices[i] = r.device; break; }
                                    }
                                    renderDeviceCards();
                                }
                            });
                        })
                    ]));
                    if (inLearn) {
                        bodyNodes.push(E('div', { style: 'font-size: 11.5px; color: #b45309; margin-bottom: 6px;' }, '👆 Bấm nút bên dưới rồi chĩa remote thật vào cục S06 Pro bấm 1 lần (12s).'));
                    }
                    var kpad = E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); gap: 6px;' });
                    (Array.isArray(dev.buttons) ? dev.buttons : []).forEach(function(btn) {
                        var hasCode = !!(btn.base64 || btn.proto);
                        var bs = inLearn ? 'background: #fff7ed; color: #c2410c; border-color: #fdba74;' : (hasCode ? 'background: #f8fafc; border-color: #86efac;' : 'background: #f8fafc; color: #94a3b8; border-style: dashed;');
                        var bp = inLearn ? '📡 ' : (btn.base64 ? '✅ ' : (btn.proto ? '⚡ ' : '❔ '));
                        kpad.appendChild(mkBtn(bp + btn.label, 'font-size: 12px; padding: 7px 6px;' + bs, function() {
                            if (inLearn) {
                                ui.addNotification(null, E('p', '📡 Chĩa remote vào S06 bấm nút [' + btn.label + '] trong 12s...'), 'info');
                                callSHLearn(dev.id, btn.id, btn.label).then(function(r) {
                                    ui.addNotification(null, E('p', (r && r.message) || 'Xong!'), r && r.ok ? 'info' : 'error');
                                    if (r && r.device) {
                                        for (var i = 0; i < state.devices.length; i++) {
                                            if (state.devices[i].id === dev.id) { state.devices[i] = r.device; break; }
                                        }
                                        renderDeviceCards();
                                    }
                                });
                            } else {
                                sendCtrl(dev.id, '', '', btn.id);
                            }
                        }));
                    });
                    bodyNodes.push(kpad);
                }

                devicesGrid.appendChild(E('div', {
                    style: 'background: #ffffff; border: 1.5px solid #e2e8f0; border-radius: 10px; padding: 14px; box-shadow: 0 1px 3px rgba(0,0,0,0.04);'
                }, [cardHeader].concat(bodyNodes)));
            });
        }

        // =========================================================================
        // 3. CONTROLLER & VOICE STATUS CARDS + COLLAPSIBLE CONTROLLER MANAGER
        // =========================================================================
        var ctrlStrip = E('div', { style: 'margin-top: 14px; padding-top: 12px; border-top: 1px solid #e2e8f0;' });
        var ctrlManagerBox = E('div', { style: 'display: none; background: #ffffff; border: 1px solid #cbd5e1; border-radius: 10px; padding: 14px; margin-top: 10px;' });

        function renderControllers() {
            ctrlStrip.innerHTML = '';
            var ctrls = state.controllers || [];
            var activeCnt = 0;
            ctrls.forEach(function(c) { if (c.live_ok || c.online) activeCnt++; });

            var vh = state.voice_hub || {};
            var vhNodes = [];
            if (vh.ok) {
                var vhText = '🎙️ Voice Hub OpenWrt: 🟢 Sẵn sàng';
                if (vh.stt_ok > 0) vhText += ' • ' + vh.stt_ok + ' câu đã nghe';
                if (vh.last_cmd) {
                    var shortCmd = vh.last_cmd.length > 42 ? (vh.last_cmd.slice(0, 42) + '…') : vh.last_cmd;
                    vhText += ' • Lệnh gần nhất: "' + shortCmd + '"';
                }
                vhNodes.push(E('span', {
                    style: 'font-size: 11.5px; font-weight: 650; color: #0f766e; background: #f0fdfa; border: 1px solid #99f6e4; padding: 3px 9px; border-radius: 999px;'
                }, vhText));
            }

            ctrlStrip.appendChild(E('div', {
                style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px; margin-bottom: 9px;'
            }, [
                E('div', { style: 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, [
                    E('span', { style: 'font-size: 13px; font-weight: 800; color: #0f172a;' }, '📡 Trạng Thái Bộ Điều Khiển & Mạch Giọng Nói'),
                    E('span', {
                        style: 'font-size: 11.5px; font-weight: 750; padding: 2px 8px; border-radius: 999px; background: #dcfce7; color: #15803d;'
                    }, activeCnt + '/' + ctrls.length + ' đang hoạt động')
                ]),
                E('div', { style: 'display: flex; gap: 6px; flex-wrap: wrap; align-items: center;' }, vhNodes)
            ]));

            var cardsGrid = E('div', {
                style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(265px, 1fr)); gap: 10px;'
            });

            ctrls.forEach(function(c) {
                var isVoice = (c.kind === 'esp32_voice');
                var icon = isVoice ? '🎙️' : '📡';
                var ok = !!(c.live_ok || c.online);
                var badgeBg = ok ? '#16a34a' : '#dc2626';
                var badgeTxt = ok ? (c.voice_active ? '🟢 Đang hoạt động • Đang nghe' : '🟢 Đang hoạt động') : '🔴 Ngắt kết nối';
                var cardBg = ok ? '#f0fdf4' : '#fef2f2';
                var cardBorder = ok ? '#86efac' : '#fecaca';

                var metaLine = '📍 ' + (c.room || 'Nhà') + ' • IP: ' + (c.ip || '--');
                var detailLine = '';
                if (isVoice) {
                    if (c.voice_active) {
                        var agoTxt = fmtAgo(c.last_seen_ago_s);
                        detailLine = '🎤 Thu âm trực tuyến (UDP 8995)' + (agoTxt ? (' • Tín hiệu ' + agoTxt) : '');
                        if (c.packets > 0) detailLine += ' • ' + c.packets + ' lượt nói';
                    } else if (ok) {
                        detailLine = '📶 Đã kết nối Wi-Fi LAN • Sẵn sàng nghe lệnh giọng nói';
                    } else {
                        detailLine = '⚠️ Chưa cấp nguồn hoặc mất kết nối Wi-Fi';
                    }
                } else {
                    var env = (c.temp_c !== undefined && c.temp_c !== null) ? ('🌡 ' + c.temp_c + '°C / ' + (c.humidity || '--') + '% • ') : '';
                    detailLine = ok ? (env + 'Kết nối Tuya Local v3.5 ổn định') : '⚠️ Mất kết nối tới cục hồng ngoại S06';
                }

                var subChildren = [
                    E('div', { style: 'font-size: 11.5px; color: #334155; font-weight: 600; margin-top: 5px;' }, metaLine),
                    E('div', { style: 'font-size: 11.5px; color: ' + (ok ? '#15803d' : '#b91c1c') + '; font-weight: 700; margin-top: 3px;' }, detailLine)
                ];
                if (isVoice && c.last_text) {
                    var lt = c.last_text.length > 38 ? (c.last_text.slice(0, 38) + '…') : c.last_text;
                    subChildren.push(E('div', { style: 'font-size: 11px; color: #475569; margin-top: 3px;' }, '💬 Vừa nói: "' + lt + '"'));
                }

                cardsGrid.appendChild(E('div', {
                    style: 'padding: 10px 12px; border-radius: 9px; border: 1.5px solid ' + cardBorder + '; background: ' + cardBg + ';'
                }, [
                    E('div', { style: 'display: flex; justify-content: space-between; align-items: center; gap: 6px; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-size: 13px; font-weight: 800; color: #0f172a;' }, icon + ' ' + c.name),
                        E('span', {
                            style: 'font-size: 11px; font-weight: 800; padding: 2px 8px; border-radius: 999px; background: ' + badgeBg + '; color: #ffffff; white-space: nowrap;'
                        }, badgeTxt)
                    ])
                ].concat(subChildren)));
            });
            ctrlStrip.appendChild(cardsGrid);

            ctrlManagerBox.innerHTML = '';
            ctrlManagerBox.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; flex-wrap: wrap; gap: 8px;' }, [
                E('b', { style: 'font-size: 14px; color: #0f172a;' }, '📡 Danh Sách Cục S06 Pro & Mạch Giọng Nói ESP32-C3'),
                mkBtn('➕ Thêm S06 / Mạch ESP32 Mới', 'background: #2563eb; color: #fff; border-color: #2563eb; font-size: 12px;', function() { openAddModal('ctrl'); })
            ]));
            ctrls.forEach(function(c) {
                var ok = !!(c.live_ok || c.online);
                var keyIn = E('input', { type: 'password', class: 'cbi-input-text', placeholder: c.has_key ? 'Đã lưu Key 16 ký tự (nhập mới nếu muốn đổi)' : 'Nhập Local Key 16 ký tự', style: 'width: 220px; font-size: 12px;' });
                var ipIn = E('input', { type: 'text', class: 'cbi-input-text', value: c.ip || '', style: 'width: 120px; font-size: 12px;' });
                var roomIn = E('input', { type: 'text', class: 'cbi-input-text', value: c.room || '', style: 'width: 110px; font-size: 12px;' });
                ctrlManagerBox.appendChild(E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center; padding: 8px; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 6px; background: #f8fafc;' }, [
                    E('span', { style: 'font-weight: 750; font-size: 12.5px; min-width: 205px;' }, (ok ? '🟢 ' : '🔴 ') + ((c.kind === 'esp32_voice') ? '🎙️ ' : '📡 ') + c.name),
                    ipIn,
                    roomIn,
                    (c.kind === 'tuya_ir') ? keyIn : E('span', { style: 'font-size: 11.5px; color: #64748b;' }, c.status_label || 'UDP Voice Port 8995'),
                    mkBtn('💾 Lưu', 'font-size: 11.5px; padding: 4px 10px;', function() {
                        callSHSaveCtrl(c.id, c.kind, c.name, roomIn.value.trim(), ipIn.value.trim(), c.mac || '', c.device_id || '', keyIn.value.trim(), c.control_type || 1).then(function(r) {
                            keyIn.value = '';
                            ui.addNotification(null, E('p', (r && r.message) || 'Đã lưu!'), r && r.ok ? 'info' : 'error');
                            refreshStatus();
                        });
                    }),
                    (!c.is_default) ? mkBtn('🗑️', 'font-size: 11px; padding: 4px 8px; color: #dc2626;', function() {
                        if (!confirm('Xóa bộ điều khiển "' + c.name + '"?')) return;
                        callSHRmCtrl(c.id).then(function() { refreshStatus(); });
                    }) : E('span', {})
                ]));
            });
        }

        // =========================================================================
        // 4. CLEAN MODAL: ➕ THÊM THIẾT BỊ (4 Drivers in 1 Unified Dialog)
        // =========================================================================
        var modalCard = E('div', {
            style: 'background: #ffffff; border-radius: 12px; width: 95vw; max-width: 760px; max-height: 88vh; overflow-y: auto; padding: 18px; box-shadow: 0 20px 50px rgba(15,23,42,0.35);'
        });
        var modalOverlay = E('div', {
            style: 'display: none; position: fixed; inset: 0; background: rgba(15,23,42,0.55); z-index: 9999; justify-content: center; align-items: center; padding: 12px;',
            click: function(ev) { if (ev.target === modalOverlay) closeModal(); }
        }, [ modalCard ]);

        function closeModal() { modalOverlay.style.display = 'none'; }

        // Tab 1: IR Catalog & IRDB
        var irCtrlSel = E('select', { class: 'cbi-input-select', style: 'min-width: 170px; font-size: 12.5px;' });
        var irNameIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Tên gợi nhớ (tùy chọn)', style: 'flex: 1; min-width: 170px; font-size: 12.5px;' });
        var irRoomIn = E('input', { type: 'text', class: 'cbi-input-text', value: 'Phòng ngủ', placeholder: 'Phòng', style: 'width: 130px; font-size: 12.5px;' });
        var searchInput = E('input', {
            type: 'text', class: 'cbi-input-text',
            placeholder: '🔎 Nhập tên thiết bị hoặc hãng (VD: LG, Daikin, Casper, TV Sony, Quạt Mitsubishi, Loa)...',
            style: 'flex: 1; min-width: 220px; padding: 8px 12px; font-size: 13.5px;',
            input: function() { if (state.searchTimer) clearTimeout(state.searchTimer); state.searchTimer = setTimeout(runSearch, 280); },
            keydown: function(ev) { if (ev.key === 'Enter') { ev.preventDefault(); runSearch(); } }
        });
        var onlineChk = E('input', { type: 'checkbox', checked: true, change: function() { state.includeOnline = !!onlineChk.checked; runSearch(); } });
        var catBar = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap; margin: 8px 0;' });
        var catBtns = {};
        CAT_META.forEach(function(c) {
            var b = mkBtn(c.icon + ' ' + c.label, 'font-size: 11.5px; padding: 4px 9px; border-radius: 999px;', function() {
                state.cat = c.key; updateCatPills(); runSearch();
            });
            catBtns[c.key] = b; catBar.appendChild(b);
        });
        function updateCatPills() {
            CAT_META.forEach(function(c) {
                var el = catBtns[c.key]; if (!el) return;
                el.style.background = (state.cat === c.key) ? '#2563eb' : '#f8fafc';
                el.style.color = (state.cat === c.key) ? '#fff' : '#334155';
                el.style.borderColor = (state.cat === c.key) ? '#2563eb' : '#cbd5e1';
            });
        }
        updateCatPills();

        var resultsBox = E('div', { style: 'max-height: 290px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 8px; background: #f8fafc; padding: 6px;' });
        function renderSearchResults(items) {
            resultsBox.innerHTML = '';
            if (!items || items.length === 0) {
                resultsBox.appendChild(E('div', { style: 'padding: 16px; text-align: center; color: #64748b; font-size: 13px;' }, [
                    'Không thấy mẫu có sẵn. ',
                    mkBtn('➕ Tạo Thẻ Tự Học Phím Ngay', 'margin-left: 8px; background: #0f766e; color: #fff; border-color: #0f766e;', function() {
                        doAddIR('custom_ir', '', irNameIn.value.trim() || searchInput.value.trim() || 'Thiết bị IR mới');
                    })
                ]));
                return;
            }
            items.forEach(function(it) {
                var bg = (it.source === 'builtin') ? '#ecfdf5' : '#eff6ff';
                var col = (it.source === 'builtin') ? '#047857' : '#1d4ed8';
                var btxt = (it.type === 'ac') ? 'Tự động 100%' : ((it.source === 'irdb') ? 'IRDB Online' : 'Mẫu chuẩn');
                resultsBox.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 8px 10px; background: #fff; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 6px; flex-wrap: wrap;' }, [
                    E('div', { style: 'flex: 1; min-width: 190px;' }, [
                        E('div', { style: 'display: flex; align-items: center; gap: 6px; flex-wrap: wrap;' }, [
                            E('span', {}, catIcon(it.category)),
                            E('b', { style: 'font-size: 13px; color: #0f172a;' }, it.name),
                            E('span', { style: 'font-size: 10.5px; font-weight: 700; padding: 1px 6px; border-radius: 999px; background: ' + bg + '; color: ' + col + ';' }, btxt)
                        ]),
                        E('div', { style: 'font-size: 11.5px; color: #64748b;' }, it.subtitle || '')
                    ]),
                    E('div', { style: 'display: flex; gap: 6px;' }, [
                        mkBtn('⚡ Thử', 'background: #fffbeb; color: #b45309; border-color: #fde68a; font-size: 12px;', function() {
                            callSHTestItem(it.source === 'builtin' ? it.id : '', it.irdb_path || '', irCtrlSel.value || 's06_default', false).then(function(r) {
                                ui.addNotification(null, E('p', (r && r.message) || 'Đã gửi!'), r && r.ok ? 'info' : 'warning');
                            });
                        }),
                        mkBtn('➕ Thêm', 'background: #2563eb; color: #fff; border-color: #2563eb; font-size: 12px;', function() {
                            doAddIR(it.source === 'builtin' ? it.id : '', it.irdb_path || '', irNameIn.value.trim());
                        })
                    ])
                ]));
            });
        }
        function doAddIR(cid, ipath, cname) {
            callSHAdd(cid ? '' : 'tuya_ir_remote', cid, ipath, irCtrlSel.value || 's06_default', cname, irRoomIn.value.trim() || 'Phòng ngủ', '', '', '', '', '', '', '', '', '').then(function(r) {
                ui.addNotification(null, E('p', (r && r.message) || 'Đã thêm!'), r && r.ok ? 'info' : 'error');
                if (r && r.ok) { irNameIn.value = ''; closeModal(); refreshStatus(); }
            });
        }
        function runSearch() {
            callSHSearch(searchInput.value.trim(), state.cat, state.includeOnline || state.cat === 'irdb').then(function(r) {
                renderSearchResults((r && r.results) || []);
            });
        }

        var modalTabBtns = {};
        var modalPanes = {};
        function switchModalTab(k) {
            state.modalTab = k;
            Object.keys(modalTabBtns).forEach(function(key) {
                var b = modalTabBtns[key], p = modalPanes[key];
                var act = (key === k);
                b.style.background = act ? '#2563eb' : '#f1f5f9';
                b.style.color = act ? '#fff' : '#334155';
                b.style.borderColor = act ? '#2563eb' : '#cbd5e1';
                p.style.display = act ? 'block' : 'none';
            });
        }

        // Modal Pane 1: IR
        modalPanes.ir = E('div', {}, [
            E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 8px;' }, [
                searchInput, mkBtn('🔍 Tìm', 'background: #2563eb; color: #fff; border-color: #2563eb;', runSearch),
                E('label', { style: 'display: inline-flex; align-items: center; gap: 4px; font-size: 12px;' }, [ onlineChk, 'IRDB Online' ])
            ]),
            catBar,
            E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 8px;' }, [
                irNameIn, irRoomIn, irCtrlSel
            ]),
            resultsBox
        ]);

        // Modal Pane 2: Wi-Fi Switch / Light / Relay
        var swDrvSel = E('select', { class: 'cbi-input-select', style: 'width: 100%;' }, [
            E('option', { value: 'tuya_switch' }, 'Công tắc / Ổ cắm / Đèn Tuya Wi-Fi (Local v3.5)'),
            E('option', { value: 'http_relay' }, 'Công tắc HTTP Relay LAN (Tasmota / ESPHome / ESP32)')
        ]);
        var swCatSel = E('select', { class: 'cbi-input-select', style: 'width: 100%;' }, [
            E('option', { value: 'light' }, '💡 Đèn chiếu sáng'),
            E('option', { value: 'fan' }, '🌀 Quạt bật/tắt'),
            E('option', { value: 'plug' }, '🔌 Ổ cắm thông minh'),
            E('option', { value: 'other' }, '📦 Thiết bị khác')
        ]);
        var swNameIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'VD: Đèn trần phòng ngủ', style: 'width: 100%; box-sizing: border-box;' });
        var swRoomIn = E('input', { type: 'text', class: 'cbi-input-text', value: 'Phòng ngủ', style: 'width: 100%; box-sizing: border-box;' });
        var swIpIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: '192.168.1.x', style: 'width: 100%; box-sizing: border-box;' });
        var swDidIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Tuya Device ID', style: 'width: 100%; box-sizing: border-box;' });
        var swKeyIn = E('input', { type: 'password', class: 'cbi-input-text', placeholder: 'Local Key 16 ký tự', style: 'width: 100%; box-sizing: border-box;' });
        var swDpIn = E('input', { type: 'text', class: 'cbi-input-text', value: '1', placeholder: '1 (nút 1), 2, 3...', style: 'width: 100%; box-sizing: border-box;' });
        var swOnUrlIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'http://192.168.1.x/cm?cmnd=Power%20On', style: 'width: 100%; box-sizing: border-box;' });
        var swOffUrlIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'http://192.168.1.x/cm?cmnd=Power%20Off', style: 'width: 100%; box-sizing: border-box;' });

        var tuyaSwFields = E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 8px; margin-top: 8px;' }, [
            E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'IP LAN Tuya'), swIpIn ]),
            E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Device ID'), swDidIn ]),
            E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Local Key (16 ký tự)'), swKeyIn ]),
            E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Kênh công tắc (DP)'), swDpIn ])
        ]);
        var httpRelFields = E('div', { style: 'display: none; grid-template-columns: 1fr; gap: 8px; margin-top: 8px;' }, [
            E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'URL BẬT (chỉ hỗ trợ IP LAN)'), swOnUrlIn ]),
            E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'URL TẮT (chỉ hỗ trợ IP LAN)'), swOffUrlIn ])
        ]);
        swDrvSel.addEventListener('change', function() {
            var isTuya = (swDrvSel.value === 'tuya_switch');
            tuyaSwFields.style.display = isTuya ? 'grid' : 'none';
            httpRelFields.style.display = isTuya ? 'none' : 'grid';
        });

        modalPanes.wifi = E('div', { style: 'display: none;' }, [
            E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 8px;' }, [
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Giao thức'), swDrvSel ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Loại thiết bị'), swCatSel ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Tên thiết bị'), swNameIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Phòng'), swRoomIn ])
            ]),
            tuyaSwFields, httpRelFields,
            E('div', { style: 'margin-top: 12px;' }, [
                mkBtn('➕ Lưu & Thêm Công Tắc / Đèn', 'background: #2563eb; color: #fff; border-color: #2563eb;', function() {
                    callSHAdd(swDrvSel.value, '', '', '', swNameIn.value.trim(), swRoomIn.value.trim(), swCatSel.value, swIpIn.value.trim(), '', swDidIn.value.trim(), swKeyIn.value.trim(), swDpIn.value.trim(), swOnUrlIn.value.trim(), swOffUrlIn.value.trim(), '').then(function(r) {
                        ui.addNotification(null, E('p', (r && r.message) || 'Xong!'), r && r.ok ? 'info' : 'error');
                        if (r && r.ok) { swNameIn.value = ''; swKeyIn.value = ''; closeModal(); refreshStatus(); }
                    });
                })
            ])
        ]);

        // Modal Pane 3: Scan & Add Controller (S06 / ESP32 Voice)
        var scanModalList = E('div', { style: 'margin-bottom: 10px;' });
        var cKindSel = E('select', { class: 'cbi-input-select', style: 'width: 100%;' }, [
            E('option', { value: 'tuya_ir' }, '📡 Cục Hồng Ngoại S06 / Tuya IR'),
            E('option', { value: 'esp32_voice' }, '🎙️ Mạch Điều Khiển Giọng Nói ESP32-C3')
        ]);
        var cNameIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'VD: S06 Pro Phòng Khách', style: 'width: 100%; box-sizing: border-box;' });
        var cRoomIn = E('input', { type: 'text', class: 'cbi-input-text', value: 'Phòng khách', style: 'width: 100%; box-sizing: border-box;' });
        var cIpIn   = E('input', { type: 'text', class: 'cbi-input-text', placeholder: '192.168.1.x', style: 'width: 100%; box-sizing: border-box;' });
        var cMacIn  = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'MAC (tùy chọn)', style: 'width: 100%; box-sizing: border-box;' });
        var cDidIn  = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Tuya Device ID (với S06)', style: 'width: 100%; box-sizing: border-box;' });
        var cKeyIn  = E('input', { type: 'password', class: 'cbi-input-text', placeholder: 'Local Key 16 ký tự (với S06)', style: 'width: 100%; box-sizing: border-box;' });

        function runLanScanIntoModal() {
            scanModalList.innerHTML = '⏳ Đang quét S06 Pro (cổng 6668) và Mạch Giọng Nói ESP32-C3 trên mạng LAN...';
            callSHScan().then(function(r) {
                scanModalList.innerHTML = '';
                var items = (Array.isArray(r.tuya_devices) ? r.tuya_devices : []).concat(Array.isArray(r.esp32_nodes) ? r.esp32_nodes : []);
                if (items.length === 0) {
                    scanModalList.textContent = 'Không quét thấy thiết bị nào mới trên LAN.';
                    return;
                }
                items.forEach(function(it) {
                    scanModalList.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; padding: 6px 8px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; margin-bottom: 5px;' }, [
                        E('span', { style: 'font-size: 12.5px;' }, (it.kind === 'esp32_voice' ? '🎙️ ' : '📡 ') + it.name + ' • ' + it.ip + ' (' + (it.mac || '') + ')'),
                        mkBtn('Điền thông tin', 'font-size: 11.5px; padding: 3px 9px;', function() {
                            cKindSel.value = it.kind;
                            cNameIn.value = it.name;
                            cIpIn.value = it.ip;
                            cMacIn.value = it.mac || '';
                        })
                    ]));
                });
            });
        }

        modalPanes.ctrl = E('div', { style: 'display: none;' }, [
            E('div', { style: 'margin-bottom: 8px;' }, [ mkBtn('🔍 Quét S06 Pro & Mạch ESP32 Trên LAN', 'background: #eff6ff; color: #1d4ed8; border-color: #bfdbfe;', runLanScanIntoModal) ]),
            scanModalList,
            E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(175px, 1fr)); gap: 8px;' }, [
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Loại mạch / Hub'), cKindSel ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Tên gợi nhớ'), cNameIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Phòng'), cRoomIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'IP LAN'), cIpIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'MAC Address'), cMacIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Tuya Device ID'), cDidIn ])
            ]),
            E('div', { style: 'margin-top: 8px;' }, [ E('div', { style: 'font-size: 11.5px; font-weight: 700;' }, 'Local Key 16 ký tự (chỉ cần với S06 mới)'), cKeyIn ]),
            E('div', { style: 'margin-top: 10px;' }, [
                mkBtn('➕ Thêm Bộ Điều Khiển', 'background: #2563eb; color: #fff; border-color: #2563eb;', function() {
                    callSHSaveCtrl('', cKindSel.value, cNameIn.value.trim(), cRoomIn.value.trim(), cIpIn.value.trim(), cMacIn.value.trim(), cDidIn.value.trim(), cKeyIn.value.trim(), 1).then(function(r) {
                        ui.addNotification(null, E('p', (r && r.message) || 'Xong!'), r && r.ok ? 'info' : 'error');
                        if (r && r.ok) { cKeyIn.value = ''; closeModal(); refreshStatus(); }
                    });
                })
            ])
        ]);

        // Modal Pane 4: Android TVs on LAN
        var tvModalList = E('div', {});
        function renderModalTVs() {
            tvModalList.innerHTML = '';
            if (!state.lan_tvs || state.lan_tvs.length === 0) {
                tvModalList.textContent = 'Chưa thấy Android TV nào được đăng ký với Voice Hub.';
                return;
            }
            state.lan_tvs.forEach(function(t) {
                tvModalList.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; padding: 10px; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 8px; background: #f8fafc;' }, [
                    E('div', {}, [
                        E('b', { style: 'font-size: 13.5px;' }, '📺 ' + t.name),
                        E('div', { style: 'font-size: 12px; color: #64748b;' }, (t.brand || 'Android TV') + ' • IP: ' + t.ip)
                    ]),
                    mkBtn('➕ Thêm Thẻ TV', 'background: #2563eb; color: #fff; border-color: #2563eb;', function() {
                        callSHAdd('android_tv', '', '', '', t.name, (t.name.indexOf('Ngủ') !== -1 ? 'Phòng ngủ' : 'Phòng khách'), 'tv', '', '', '', '', '', '', '', t.id).then(function(r) {
                            ui.addNotification(null, E('p', (r && r.message) || 'Đã thêm TV!'), r && r.ok ? 'info' : 'warning');
                            if (r && r.ok) { closeModal(); refreshStatus(); }
                        });
                    })
                ]));
            });
        }
        modalPanes.tv = E('div', { style: 'display: none;' }, [ tvModalList ]);

        var modalHeader = E('div', { style: 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #e2e8f0; padding-bottom: 10px; margin-bottom: 12px;' }, [
            E('b', { style: 'font-size: 16px; color: #0f172a;' }, '➕ Thêm Thiết Bị Điều Khiển Nhà'),
            mkBtn('✖ Đóng', 'font-size: 12px; padding: 4px 10px;', closeModal)
        ]);
        var modalTabBar = E('div', { style: 'display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 12px;' });
        [
            ['ir', '❄️📺🌀 Hồng Ngoại (S06)'],
            ['wifi', '💡🔌 Đèn / Công Tắc Wi-Fi'],
            ['ctrl', '🎙️📡 Mạch Voice / S06 Mới'],
            ['tv', '📺 Android TV LAN']
        ].forEach(function(pair) {
            var b = mkBtn(pair[1], 'font-size: 12px; padding: 6px 11px;', function() {
                switchModalTab(pair[0]);
                if (pair[0] === 'ctrl') runLanScanIntoModal();
                if (pair[0] === 'tv') renderModalTVs();
            });
            modalTabBtns[pair[0]] = b;
            modalTabBar.appendChild(b);
        });
        modalCard.appendChild(modalHeader);
        modalCard.appendChild(modalTabBar);
        modalCard.appendChild(modalPanes.ir);
        modalCard.appendChild(modalPanes.wifi);
        modalCard.appendChild(modalPanes.ctrl);
        modalCard.appendChild(modalPanes.tv);

        function openAddModal(tabKey) {
            modalOverlay.style.display = 'flex';
            switchModalTab(tabKey || 'ir');
            if (tabKey === 'ir' || !tabKey) runSearch();
            if (tabKey === 'ctrl') runLanScanIntoModal();
            if (tabKey === 'tv') renderModalTVs();
        }

        function refreshStatus() {
            callSHStatus().then(function(res) {
                if (!res || !res.ok) return;
                state.controllers = Array.isArray(res.controllers) ? res.controllers : [];
                state.devices = Array.isArray(res.devices) ? res.devices : [];
                state.lan_tvs = Array.isArray(res.lan_tvs) ? res.lan_tvs : [];
                state.rooms = Array.isArray(res.rooms) ? res.rooms : [];
                state.voice_hub = res.voice_hub || null;

                irCtrlSel.innerHTML = '';
                state.controllers.forEach(function(c) {
                    if (c.kind === 'tuya_ir') {
                        irCtrlSel.appendChild(E('option', { value: c.id }, 'Qua ' + c.name + ' (' + (c.room || '') + ')'));
                    }
                });
                renderRoomPills();
                renderDeviceCards();
                renderControllers();
            }).catch(function() {
                ctrlStrip.innerHTML = '<span style="color:#b91c1c;font-weight:700;">⚠️ Lỗi kết nối RPCD Smart Home</span>';
            });
        }

        var pane = E('div', {
            class: 'cbi-section',
            style: 'display: none; padding: 16px; background: #f8fafc; border-radius: 10px; border: 1px solid #e2e8f0;'
        }, [
            headerBar,
            roomBar,
            devicesGrid,
            ctrlStrip,
            ctrlManagerBox,
            modalOverlay
        ]);

        refreshStatus();
        setInterval(function() {
            if (pane.style.display !== 'none' && !document.hidden && modalOverlay.style.display === 'none' && !state.showCtrlsPanel) {
                refreshStatus();
            }
        }, 15000);
        return pane;
    }
});
// [/VERIFIED-GOLDEN]
