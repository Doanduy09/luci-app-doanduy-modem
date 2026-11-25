'use strict';
'require baseclass';
'require rpc';
'require ui';

var callSHStatus   = rpc.declare({ object: 'doanduy.smarthome', method: 'status', expect: { } });
var callSHScan     = rpc.declare({ object: 'doanduy.smarthome', method: 'scanHubs', expect: { } });
var callSHSaveHub  = rpc.declare({ object: 'doanduy.smarthome', method: 'saveHubConfig', params: ['ip', 'mac', 'device_id', 'local_key', 'control_type'], expect: { } });
var callSHSearch   = rpc.declare({ object: 'doanduy.smarthome', method: 'searchCatalog', params: ['query', 'category', 'include_online'], expect: { } });
var callSHTestItem = rpc.declare({ object: 'doanduy.smarthome', method: 'testCatalogItem', params: ['catalog_id', 'irdb_path', 'dry_run'], expect: { } });
var callSHAdd      = rpc.declare({ object: 'doanduy.smarthome', method: 'addDevice', params: ['catalog_id', 'irdb_path', 'name', 'room'], expect: { } });
var callSHRemove   = rpc.declare({ object: 'doanduy.smarthome', method: 'removeDevice', params: ['id'], expect: { } });
var callSHControl  = rpc.declare({ object: 'doanduy.smarthome', method: 'controlDevice', params: ['id', 'op', 'value', 'button', 'dry_run'], expect: { } });
var callSHLearn    = rpc.declare({ object: 'doanduy.smarthome', method: 'learnButton', params: ['id', 'button', 'label'], expect: { } });

var CAT_META = [
    { key: 'all',   icon: '✨', label: 'Tất cả' },
    { key: 'ac',    icon: '❄️', label: 'Máy Lạnh' },
    { key: 'tv',    icon: '📺', label: 'Tivi' },
    { key: 'fan',   icon: '🌀', label: 'Quạt' },
    { key: 'audio', icon: '🔊', label: 'Loa / Amply' },
    { key: 'other', icon: '📦', label: 'Khác / Tự học' },
    { key: 'irdb',  icon: '🌐', label: 'Kho Online (3.200+)' }
];

function catIcon(cat) {
    for (var i = 0; i < CAT_META.length; i++) {
        if (CAT_META[i].key === cat) return CAT_META[i].icon;
    }
    return '📱';
}

function mkBtn(label, style, onClick) {
    return E('button', {
        class: 'btn cbi-button',
        style: 'padding: 6px 11px; border-radius: 7px; font-weight: 700; font-size: 12.5px; cursor: pointer; border: 1px solid #cbd5e1; background: #ffffff; color: #1e293b;' + (style || ''),
        click: onClick
    }, label);
}

return baseclass.extend({
    renderPane: function() {
        var state = {
            hub: {},
            devices: [],
            lan_tvs: [],
            cat: 'all',
            includeOnline: true,
            searchTimer: null,
            learnDevices: {}
        };

        // --- CARD 1: HUB S06 PRO ---
        var hubBadge = E('span', {
            style: 'padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 750; background: #f1f5f9; color: #334155; border: 1px solid #cbd5e1;'
        }, '⏳ Đang kiểm tra S06 Pro...');

        var hubMetaDiv = E('div', { style: 'font-size: 12.5px; color: #475569; margin-top: 6px;' }, '...');
        var scanResultsBox = E('div', { style: 'display: none; margin-top: 10px; padding: 10px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px;' });

        var hubIpIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: '192.168.1.130', style: 'width: 100%; box-sizing: border-box;' });
        var hubMacIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: '20:f1:b2:fa:76:27', style: 'width: 100%; box-sizing: border-box;' });
        var hubIdIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Tuya Device ID', style: 'width: 100%; box-sizing: border-box;' });
        var hubKeyIn = E('input', { type: 'password', class: 'cbi-input-text', placeholder: 'Nhập Local Key 16 ký tự (chỉ nhập khi cần đổi)', style: 'width: 100%; box-sizing: border-box;' });
        var hubCtIn = E('select', { class: 'cbi-input-select', style: 'width: 100%; box-sizing: border-box;' }, [
            E('option', { value: '1' }, 'Type 1 — S06 Pro (DP 201/202)'),
            E('option', { value: '2' }, 'Type 2 — Một số S06/ZS06 (DP 1-13)')
        ]);

        var cfgBox = E('div', { style: 'display: none; margin-top: 12px; padding: 12px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px;' }, [
            E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 10px;' }, [
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700; margin-bottom: 3px;' }, 'IP LAN S06 Pro'), hubIpIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700; margin-bottom: 3px;' }, 'MAC (Tự dò IP)'), hubMacIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700; margin-bottom: 3px;' }, 'Device ID'), hubIdIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11.5px; font-weight: 700; margin-bottom: 3px;' }, 'Loại giao thức DP'), hubCtIn ])
            ]),
            E('div', { style: 'margin-top: 10px;' }, [
                E('div', { style: 'font-size: 11.5px; font-weight: 700; margin-bottom: 3px;' }, 'Local Key (16 ký tự — ẩn hoàn toàn để bảo mật)'),
                hubKeyIn
            ]),
            E('div', { style: 'margin-top: 10px; display: flex; gap: 8px;' }, [
                mkBtn('💾 Lưu Cấu Hình Hub', 'background: #2563eb; color: #fff; border-color: #2563eb;', function() {
                    callSHSaveHub(
                        hubIpIn.value.trim(),
                        hubMacIn.value.trim(),
                        hubIdIn.value.trim(),
                        hubKeyIn.value.trim(),
                        parseInt(hubCtIn.value, 10) || 1
                    ).then(function(r) {
                        hubKeyIn.value = '';
                        ui.addNotification(null, E('p', (r && r.message) || 'Đã lưu Hub!'), r && r.ok ? 'info' : 'error');
                        refreshStatus();
                    });
                })
            ])
        ]);

        var hubCard = E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 14px 16px; margin-bottom: 14px;' }, [
            E('div', { style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px;' }, [
                E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap;' }, [
                    E('span', { style: 'font-weight: 800; font-size: 15px; color: #0f172a;' }, '📡 Hub Hồng Ngoại Tuya S06 Pro (Local LAN)'),
                    hubBadge
                ]),
                E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap;' }, [
                    mkBtn('🔍 Quét Hub LAN', 'background: #eff6ff; color: #1d4ed8; border-color: #bfdbfe;', function() {
                        scanResultsBox.style.display = 'block';
                        scanResultsBox.innerHTML = '⏳ Đang quét các thiết bị Tuya cổng 6668 trong mạng LAN...';
                        callSHScan().then(function(res) {
                            scanResultsBox.innerHTML = '';
                            var hubs = (res && Array.isArray(res.hubs)) ? res.hubs : [];
                            if (hubs.length === 0) {
                                scanResultsBox.appendChild(E('div', { style: 'font-size: 12.5px; color: #64748b;' }, 'Không thấy thiết bị nào mở cổng Tuya 6668 trên LAN.'));
                                return;
                            }
                            hubs.forEach(function(h) {
                                scanResultsBox.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px dashed #e2e8f0;' }, [
                                    E('span', { style: 'font-size: 12.5px; font-weight: 600;' }, (h.is_current ? '🟢 ' : '📡 ') + h.name + ' • ' + h.ip + ' (' + h.mac + ')'),
                                    mkBtn(h.is_current ? 'Đang dùng' : 'Chọn Hub này', 'font-size: 11.5px; padding: 4px 10px;', function() {
                                        hubIpIn.value = h.ip;
                                        hubMacIn.value = h.mac;
                                        callSHSaveHub(h.ip, h.mac, '', '', 1).then(function() { refreshStatus(); });
                                    })
                                ]));
                            });
                        });
                    }),
                    mkBtn('⚙️ Cài đặt / Key', '', function() {
                        cfgBox.style.display = (cfgBox.style.display === 'none') ? 'block' : 'none';
                    }),
                    mkBtn('🔄 Làm mới', '', function() { refreshStatus(); })
                ])
            ]),
            hubMetaDiv,
            scanResultsBox,
            cfgBox
        ]);

        // --- CARD 2: TÌM KIẾM & THÊM THIẾT BỊ ---
        var searchInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            placeholder: '🔎 Nhập tên thiết bị hoặc hãng: LG, Daikin, Casper, TV Sony, Quạt Mitsubishi, Loa...',
            style: 'flex: 1; min-width: 240px; padding: 9px 12px; font-size: 13.5px; border-radius: 8px; border: 1.5px solid #cbd5e1;',
            input: function() {
                if (state.searchTimer) clearTimeout(state.searchTimer);
                state.searchTimer = setTimeout(runSearch, 280);
            },
            keydown: function(ev) {
                if (ev.key === 'Enter') { ev.preventDefault(); runSearch(); }
            }
        });

        var onlineChk = E('input', {
            type: 'checkbox',
            checked: true,
            change: function() {
                state.includeOnline = !!onlineChk.checked;
                runSearch();
            }
        });

        var customNameIn = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            placeholder: 'Tên gợi nhớ (tùy chọn, VD: Quạt phòng ngủ)',
            style: 'flex: 1; min-width: 190px; font-size: 12.5px;'
        });

        var roomSelect = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            value: 'Phòng ngủ',
            placeholder: 'Phòng (VD: Phòng ngủ)',
            style: 'width: 150px; font-size: 12.5px;'
        });

        var catBar = E('div', { style: 'display: flex; gap: 6px; flex-wrap: wrap; margin: 10px 0;' });
        var catBtns = {};
        CAT_META.forEach(function(c) {
            var b = mkBtn(c.icon + ' ' + c.label, 'font-size: 12px; padding: 5px 10px; border-radius: 999px;', function() {
                state.cat = c.key;
                updateCatPills();
                runSearch();
            });
            catBtns[c.key] = b;
            catBar.appendChild(b);
        });

        function updateCatPills() {
            CAT_META.forEach(function(c) {
                var el = catBtns[c.key];
                if (!el) return;
                if (state.cat === c.key) {
                    el.style.background = '#2563eb';
                    el.style.color = '#ffffff';
                    el.style.borderColor = '#2563eb';
                } else {
                    el.style.background = '#f8fafc';
                    el.style.color = '#334155';
                    el.style.borderColor = '#cbd5e1';
                }
            });
        }
        updateCatPills();

        var resultsBox = E('div', {
            style: 'max-height: 330px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 8px; background: #f8fafc; padding: 6px;'
        }, '⏳ Đang tải danh mục thiết bị...');

        function renderSearchResults(items) {
            resultsBox.innerHTML = '';
            if (!items || items.length === 0) {
                resultsBox.appendChild(E('div', { style: 'padding: 18px; text-align: center; color: #64748b; font-size: 13px;' }, [
                    'Không tìm thấy mẫu sẵn khớp từ khóa. ',
                    mkBtn('➕ Thêm Thiết Bị Tự Học Phím Ngay', 'margin-left: 8px; background: #0f766e; color: #fff; border-color: #0f766e;', function() {
                        doAddItem('custom_ir', '', customNameIn.value.trim() || searchInput.value.trim() || 'Thiết bị IR mới');
                    })
                ]));
                return;
            }
            items.forEach(function(it) {
                var badgeBg = (it.source === 'builtin') ? '#ecfdf5' : '#eff6ff';
                var badgeCol = (it.source === 'builtin') ? '#047857' : '#1d4ed8';
                var badgeTxt = (it.type === 'ac') ? 'Tự động 100%' : ((it.source === 'irdb') ? 'IRDB Online' : 'Mẫu chuẩn');

                var row = E('div', {
                    style: 'display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 9px 10px; background: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 6px; flex-wrap: wrap;'
                }, [
                    E('div', { style: 'flex: 1; min-width: 200px;' }, [
                        E('div', { style: 'display: flex; align-items: center; gap: 6px; flex-wrap: wrap;' }, [
                            E('span', { style: 'font-size: 15px;' }, catIcon(it.category)),
                            E('span', { style: 'font-weight: 750; font-size: 13.5px; color: #0f172a;' }, it.name),
                            E('span', { style: 'font-size: 11px; font-weight: 700; padding: 2px 7px; border-radius: 999px; background: ' + badgeBg + '; color: ' + badgeCol + ';' }, badgeTxt)
                        ]),
                        E('div', { style: 'font-size: 12px; color: #64748b; margin-top: 2px;' }, it.subtitle || '')
                    ]),
                    E('div', { style: 'display: flex; gap: 6px;' }, [
                        mkBtn('⚡ Thử', 'background: #fffbeb; color: #b45309; border-color: #fde68a;', function() {
                            ui.addNotification(null, E('p', '📡 Đang bắn thử tín hiệu qua S06 Pro tới: ' + it.name + '...'), 'info');
                            callSHTestItem(it.source === 'builtin' ? it.id : '', it.irdb_path || '', false).then(function(res) {
                                ui.addNotification(null, E('p', (res && res.message) || 'Đã gửi lệnh thử!'), res && res.ok ? 'info' : 'warning');
                            });
                        }),
                        mkBtn('➕ Thêm', 'background: #2563eb; color: #ffffff; border-color: #2563eb;', function() {
                            doAddItem(it.source === 'builtin' ? it.id : '', it.irdb_path || '', customNameIn.value.trim());
                        })
                    ])
                ]);
                resultsBox.appendChild(row);
            });
        }

        function doAddItem(catalogId, irdbPath, customName) {
            callSHAdd(catalogId, irdbPath, customName, roomSelect.value.trim() || 'Phòng ngủ').then(function(res) {
                ui.addNotification(null, E('p', (res && res.message) || 'Đã thêm!'), res && res.ok ? 'info' : 'error');
                if (res && res.ok) {
                    customNameIn.value = '';
                    if (res.devices) { state.devices = res.devices; renderDeviceCards(); }
                    else refreshStatus();
                }
            });
        }

        function runSearch() {
            var q = searchInput.value.trim();
            var online = state.includeOnline || state.cat === 'irdb';
            callSHSearch(q, state.cat, online).then(function(res) {
                renderSearchResults((res && res.results) || []);
            }).catch(function(err) {
                resultsBox.innerHTML = '❌ Lỗi tìm kiếm: ' + err;
            });
        }

        var searchCard = E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 14px 16px; margin-bottom: 14px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 15px; color: #0f172a; margin-bottom: 10px;' }, '🔍 Tìm Kiếm & Thêm Thiết Bị Điều Khiển (Máy lạnh, TV, Quạt, Loa, Kho IRDB)'),
            E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center;' }, [
                searchInput,
                mkBtn('🔍 Tìm', 'background: #2563eb; color: #fff; border-color: #2563eb; padding: 9px 16px;', runSearch),
                E('label', { style: 'display: inline-flex; align-items: center; gap: 5px; font-size: 12.5px; font-weight: 600; color: #334155; cursor: pointer;' }, [
                    onlineChk, 'Kho Online 3.200+'
                ])
            ]),
            catBar,
            E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 10px;' }, [
                customNameIn, roomSelect
            ]),
            resultsBox
        ]);

        // --- CARD 3: THIẾT BỊ ĐÃ THÊM ---
        var devicesGrid = E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(310px, 1fr)); gap: 14px;' });
        var tvStrip = E('div', { style: 'margin-top: 12px; font-size: 12px; color: #64748b;' });

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
            });
        }

        function renderDeviceCards() {
            devicesGrid.innerHTML = '';
            if (!state.devices || state.devices.length === 0) {
                devicesGrid.appendChild(E('div', { style: 'padding: 20px; text-align: center; color: #64748b; background: #f8fafc; border-radius: 8px; border: 1px dashed #cbd5e1;' }, 'Chưa có thiết bị nào. Hãy tìm và bấm ➕ Thêm ở khung phía trên!'));
                return;
            }
            state.devices.forEach(function(dev) {
                var header = E('div', { style: 'display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; border-bottom: 1px solid #f1f5f9; padding-bottom: 8px; margin-bottom: 10px;' }, [
                    E('div', {}, [
                        E('div', { style: 'font-weight: 800; font-size: 14.5px; color: #0f172a;' }, catIcon(dev.category) + ' ' + dev.name),
                        E('div', { style: 'font-size: 11.5px; color: #64748b;' }, (dev.room || 'Phòng') + ' • ' + (dev.brand_label || dev.brand || dev.type))
                    ]),
                    mkBtn('🗑️ Xóa', 'font-size: 11px; padding: 3px 8px; color: #dc2626; border-color: #fecaca; background: #fef2f2;', function() {
                        if (!confirm('Xóa thiết bị "' + dev.name + '"?')) return;
                        callSHRemove(dev.id).then(function(r) {
                            if (r && r.devices) state.devices = r.devices;
                            renderDeviceCards();
                        });
                    })
                ]);

                var bodyNodes = [];
                if (dev.type === 'ac') {
                    var st = dev.state || { power: false, temp: 26, mode: 'cool', fan: 'auto', swing: false };
                    var pwrStyle = st.power ? 'background: #16a34a; color: #fff; border-color: #16a34a;' : '';
                    var offStyle = !st.power ? 'background: #dc2626; color: #fff; border-color: #dc2626;' : '';
                    bodyNodes.push(E('div', { style: 'display: flex; align-items: center; justify-content: space-between; background: #f8fafc; padding: 10px 14px; border-radius: 8px; margin-bottom: 10px;' }, [
                        E('div', {}, [
                            E('div', { style: 'font-size: 26px; font-weight: 850; color: #0284c7; line-height: 1.1;' }, String(st.temp || 26) + '°C'),
                            E('div', { style: 'font-size: 11.5px; color: #64748b; margin-top: 2px;' }, (st.power ? '🟢 Đang BẬT' : '⚪ Đang TẮT') + ' • ' + (st.mode || 'cool').toUpperCase() + ' • Gió ' + (st.fan || 'auto'))
                        ]),
                        E('div', { style: 'display: flex; gap: 6px;' }, [
                            mkBtn('❄️ Bật', pwrStyle, function() { sendCtrl(dev.id, 'on'); }),
                            mkBtn('🛑 Tắt', offStyle, function() { sendCtrl(dev.id, 'off'); }),
                            mkBtn('➖', 'font-size: 14px;', function() { sendCtrl(dev.id, 'temp_down'); }),
                            mkBtn('➕', 'font-size: 14px;', function() { sendCtrl(dev.id, 'temp_up'); })
                        ])
                    ]));

                    var quickTemps = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap; margin-bottom: 8px;' });
                    [24, 25, 26, 27, 28].forEach(function(tp) {
                        var actStyle = (Number(st.temp) === tp && st.power) ? 'background: #2563eb; color: #fff; border-color: #2563eb;' : '';
                        quickTemps.appendChild(mkBtn(tp + '°C', 'font-size: 11.5px; padding: 4px 9px;' + actStyle, function() { sendCtrl(dev.id, 'set_temp', String(tp)); }));
                    });
                    bodyNodes.push(quickTemps);

                    var modeRow = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap; margin-bottom: 8px;' });
                    [['cool','❄ Cool'],['dry','💧 Dry'],['fan','🌀 Fan'],['auto','✨ Auto']].forEach(function(pair) {
                        var mStyle = (st.mode === pair[0]) ? 'background: #0284c7; color: #fff; border-color: #0284c7;' : '';
                        modeRow.appendChild(mkBtn(pair[1], 'font-size: 11.5px; padding: 4px 8px;' + mStyle, function() { sendCtrl(dev.id, 'mode', pair[0]); }));
                    });
                    bodyNodes.push(modeRow);

                    var fanRow = E('div', { style: 'display: flex; gap: 5px; flex-wrap: wrap;' });
                    [['low','🍃 Nhẹ'],['med','💨 Vừa'],['high','🌪 Mạnh'],['auto','Gió Auto']].forEach(function(pair) {
                        var fStyle = (st.fan === pair[0]) ? 'background: #0f766e; color: #fff; border-color: #0f766e;' : '';
                        fanRow.appendChild(mkBtn(pair[1], 'font-size: 11.5px; padding: 4px 8px;' + fStyle, function() { sendCtrl(dev.id, 'fan', pair[0]); }));
                    });
                    fanRow.appendChild(mkBtn(st.swing ? '↕ Đảo: BẬT' : '↕ Đảo gió', st.swing ? 'background: #7c3aed; color: #fff; border-color: #7c3aed;' : '', function() { sendCtrl(dev.id, 'swing'); }));
                    fanRow.appendChild(mkBtn('🔄 Đổi mã', '', function() { sendCtrl(dev.id, 'next_variant'); }));
                    bodyNodes.push(fanRow);
                } else {
                    var inLearn = !!state.learnDevices[dev.id];
                    var ctrlBar = E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; gap: 6px; flex-wrap: wrap;' }, [
                        mkBtn(inLearn ? '✅ Xong Học Phím' : '📡 Học / Sửa Phím', inLearn ? 'background: #d97706; color: #fff; border-color: #d97706;' : 'background: #fffbeb; color: #b45309; border-color: #fde68a;', function() {
                            state.learnDevices[dev.id] = !inLearn;
                            renderDeviceCards();
                        }),
                        mkBtn('➕ Thêm Nút Mới', 'font-size: 11.5px;', function() {
                            var lbl = prompt('Nhập tên nút mới (VD: Hẹn giờ 2h, Đèn LED, Chế độ ngủ):');
                            if (!lbl || !lbl.trim()) return;
                            ui.addNotification(null, E('p', '📡 Chĩa remote thật vào S06 Pro và bấm nút [' + lbl.trim() + '] trong 12 giây...'), 'info');
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
                    ]);
                    bodyNodes.push(ctrlBar);

                    if (inLearn) {
                        bodyNodes.push(E('div', { style: 'font-size: 11.5px; color: #b45309; margin-bottom: 8px;' }, '👆 Bấm vào nút cần học bên dưới, rồi chĩa remote thật vào S06 Pro bấm 1 cái (trong 12s).'));
                    }

                    var kpad = E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fill, minmax(105px, 1fr)); gap: 6px;' });
                    (Array.isArray(dev.buttons) ? dev.buttons : []).forEach(function(btn) {
                        var hasCode = !!(btn.base64 || btn.proto);
                        var bStyle = inLearn
                            ? 'background: #fff7ed; color: #c2410c; border-color: #fdba74;'
                            : (hasCode ? 'background: #f8fafc; color: #0f172a; border-color: #86efac;' : 'background: #f8fafc; color: #94a3b8; border-style: dashed;');
                        var bPrefix = inLearn ? '📡 ' : (btn.base64 ? '✅ ' : (btn.proto ? '⚡ ' : '❔ '));
                        kpad.appendChild(mkBtn(bPrefix + btn.label, 'font-size: 12px; padding: 7px 6px;' + bStyle, function() {
                            if (inLearn) {
                                ui.addNotification(null, E('p', '📡 Chĩa remote vào S06 Pro và bấm nút [' + btn.label + '] trong 12s...'), 'info');
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
                }, [header].concat(bodyNodes)));
            });
        }

        var devicesCard = E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 14px 16px;' }, [
            E('div', { style: 'font-weight: 800; font-size: 15px; color: #0f172a; margin-bottom: 12px;' }, '🎛️ Thiết Bị Thông Minh Đã Kết Nối (Bấm Là Chạy Local LAN)'),
            devicesGrid,
            tvStrip
        ]);

        function refreshStatus() {
            callSHStatus().then(function(res) {
                if (!res || !res.ok) return;
                state.hub = res.hub || {};
                state.devices = res.devices || [];
                state.lan_tvs = res.lan_tvs || [];

                var h = state.hub;
                var env = (h.temp_c !== null && h.temp_c !== undefined) ? (' • 🌡 ' + h.temp_c + '°C / ' + (h.humidity || '--') + '%') : '';
                if (h.live_ok) {
                    hubBadge.style.background = '#ecfdf5';
                    hubBadge.style.color = '#047857';
                    hubBadge.style.borderColor = '#a7f3d0';
                    hubBadge.textContent = '🟢 LAN OK' + env;
                } else if (h.has_key) {
                    hubBadge.style.background = '#fffbeb';
                    hubBadge.style.color = '#b45309';
                    hubBadge.style.borderColor = '#fde68a';
                    hubBadge.textContent = '🟡 Có Key (Chưa phản hồi)' + env;
                } else {
                    hubBadge.style.background = '#fef2f2';
                    hubBadge.style.color = '#b91c1c';
                    hubBadge.style.borderColor = '#fecaca';
                    hubBadge.textContent = '🔴 Thiếu Local Key';
                }
                hubMetaDiv.textContent = 'IP: ' + (h.ip || '?') + ' • MAC: ' + (h.mac || '?') + ' • Control Type: ' + (h.control_type || 1) + ' • Hãng giọng nói hiện tại: ' + String(h.ac_brand || 'lg2').toUpperCase();
                hubIpIn.value = h.ip || '';
                hubMacIn.value = h.mac || '';
                hubIdIn.value = h.device_id || '';
                hubCtIn.value = String(h.control_type || 1);

                renderDeviceCards();
                if (state.lan_tvs.length > 0) {
                    tvStrip.textContent = '📺 TV LAN đang đồng bộ cùng Voice Hub: ' + state.lan_tvs.map(function(t) { return t.name + ' (' + t.ip + ')'; }).join(' • ');
                }
            }).catch(function(err) {
                hubBadge.style.background = '#fef2f2';
                hubBadge.style.color = '#b91c1c';
                hubBadge.textContent = '⚠️ Lỗi kết nối RPCD';
            });
        }

        var pane = E('div', {
            class: 'cbi-section',
            style: 'display: none; padding: 16px; background: #f8fafc; border-radius: 10px; border: 1px solid #e2e8f0;'
        }, [
            E('h3', { style: 'margin-top: 0; font-size: 18px; font-weight: 800; color: #1e293b; border-bottom: 1px solid #e2e8f0; padding-bottom: 10px;' }, '🏠 Thiết Bị Thông Minh Local LAN (Tuya S06 Pro Universal IR + Voice Hub)'),
            hubCard,
            searchCard,
            devicesCard
        ]);

        refreshStatus();
        runSearch();
        return pane;
    }
});
