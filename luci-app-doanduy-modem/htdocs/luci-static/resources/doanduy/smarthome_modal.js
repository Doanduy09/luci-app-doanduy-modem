// [VERIFIED-GOLDEN: luci-mod-smarthome-modal-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
// Scenario 06 (SmartHome) — Sub-module: Universal Paste-IP Auto-Fingerprint, LAN Scan & 5-Tab Add Modal
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callSHScan      = rpc.declare({ object: 'doanduy.smarthome', method: 'scanHubs', expect: { } });
var callSHProbeIp   = rpc.declare({ object: 'doanduy.smarthome', method: 'probeIp', params: ['ip'], expect: { } });
var callSHScanLan   = rpc.declare({ object: 'doanduy.smarthome', method: 'scanLanSmartDevices', expect: { } });
var callSHSaveCtrl  = rpc.declare({ object: 'doanduy.smarthome', method: 'saveController', params: ['id', 'kind', 'name', 'room', 'ip', 'mac', 'device_id', 'local_key', 'control_type'], expect: { } });
var callSHSearch    = rpc.declare({ object: 'doanduy.smarthome', method: 'searchCatalog', params: ['query', 'category', 'include_online'], expect: { } });
var callSHTestItem  = rpc.declare({ object: 'doanduy.smarthome', method: 'testCatalogItem', params: ['catalog_id', 'irdb_path', 'controller_id', 'dry_run'], expect: { } });
var callSHAdd       = rpc.declare({
    object: 'doanduy.smarthome', method: 'addDevice',
    params: [
        'driver', 'catalog_id', 'irdb_path', 'controller_id',
        'name', 'room', 'category', 'category_label',
        'ip', 'mac', 'device_id', 'local_key', 'dp',
        'on_url', 'off_url', 'tv_id',
        'port', 'shelly_gen', 'channels', 'web_url', 'rtsp_url',
        'actions_json', 'capabilities_json', 'meta_json'
    ],
    expect: { }
});


var CAT_META = [
    { key: 'all',   icon: '✨', label: 'Tất cả' },
    { key: 'ac',    icon: '❄️', label: 'Máy Lạnh' },
    { key: 'tv',    icon: '📺', label: 'Tivi' },
    { key: 'fan',   icon: '🌀', label: 'Quạt' },
    { key: 'audio', icon: '🔊', label: 'Loa / Amply' },
    { key: 'other', icon: '📦', label: 'Khác / Tự học' },
    { key: 'irdb',  icon: '🌐', label: 'Kho Online 3.200+' }
];

var SMART_CATEGORIES = [
    { key: 'light',    icon: '💡', label: 'Đèn thông minh' },
    { key: 'plug',     icon: '🔌', label: 'Ổ cắm / Công tắc' },
    { key: 'security', icon: '🚨', label: 'Chống trộm / Báo động' },
    { key: 'sensor',   icon: '📡', label: 'Cảm biến' },
    { key: 'curtain',  icon: '🪟', label: 'Rèm / Cổng / Cửa cuốn' },
    { key: 'lock',     icon: '🔐', label: 'Khóa thông minh' },
    { key: 'camera',   icon: '📹', label: 'Camera an ninh' },
    { key: 'pump',     icon: '💧', label: 'Máy bơm / Tưới cây' },
    { key: 'ac',       icon: '❄️', label: 'Máy lạnh' },
    { key: 'tv',       icon: '📺', label: 'Tivi' },
    { key: 'fan',      icon: '🌀', label: 'Quạt' },
    { key: 'audio',    icon: '🔊', label: 'Loa / Soundbar' },
    { key: 'custom',   icon: '✨', label: 'Tự đặt loại mới...' }
];

var DRIVER_OPTIONS = [
    { key: 'tasmota',       label: 'Tasmota Wi-Fi (Đèn / Công tắc / Chống trộm)' },
    { key: 'shelly',        label: 'Shelly Gen1/Gen2 Local' },
    { key: 'wled',          label: 'Đèn LED WLED (Bật/Tắt + Độ sáng)' },
    { key: 'yeelight',      label: 'Đèn Yeelight Wi-Fi (TCP 55443)' },
    { key: 'sonoff_diy',    label: 'Sonoff DIY LAN (Port 8081)' },
    { key: 'tuya_switch',   label: 'Thiết bị Tuya Smart LAN (Port 6668 + Local Key)' },
    { key: 'android_tv',    label: 'Android TV / Google TV (LAN)' },
    { key: 'camera_lan',    label: 'Camera An Ninh IP / RTSP / Web' },
    { key: 'smart_actions', label: 'Thiết bị Thông Minh Tùy Biến (Vô hạn nút lệnh)' },
    { key: 'http_relay',    label: 'Công tắc HTTP Relay LAN (2 URL Bật/Tắt)' }
];

function catIcon(cat) {
    var map = {
        ac: '❄️', tv: '📺', fan: '🌀', audio: '🔊',
        light: '💡', plug: '🔌', security: '🚨', sensor: '📡',
        curtain: '🪟', lock: '🔐', camera: '📹', pump: '💧',
        custom: '✨', other: '📦'
    };
    return map[cat] || '🎛️';
}

function buildActionTemplates(cat, ip, port) {
    var host = (ip && ip.trim()) ? ip.trim() : '192.168.1.x';
    var base = 'http://' + host + (port && Number(port) !== 80 ? (':' + port) : '');
    if (cat === 'security') {
        return [
            { id: 'arm',    label: 'Bật Chống Trộm', icon: '🛡️', kind: 'http_get', url: base + '/arm', style: 'success' },
            { id: 'disarm', label: 'Tắt Báo Động',   icon: '🔓', kind: 'http_get', url: base + '/disarm', style: 'neutral' },
            { id: 'sos',    label: 'Hú Còi SOS',     icon: '🚨', kind: 'http_get', url: base + '/sos', style: 'danger' },
            { id: 'ping',   label: 'Kiểm Tra Online', icon: '🩺', kind: 'ping', style: 'info' }
        ];
    }
    if (cat === 'curtain') {
        return [
            { id: 'open',  label: 'Mở Ra',    icon: '🪟', kind: 'http_get', url: base + '/open', style: 'success' },
            { id: 'stop',  label: 'Dừng Lại', icon: '⏸️', kind: 'http_get', url: base + '/stop', style: 'neutral' },
            { id: 'close', label: 'Đóng Lại', icon: '🔒', kind: 'http_get', url: base + '/close', style: 'danger' }
        ];
    }
    if (cat === 'lock') {
        return [
            { id: 'unlock', label: 'Mở Khóa',  icon: '🔓', kind: 'http_get', url: base + '/unlock', style: 'success' },
            { id: 'lock',   label: 'Khóa Lại', icon: '🔐', kind: 'http_get', url: base + '/lock', style: 'danger' },
            { id: 'ping',   label: 'Kiểm Tra', icon: '🩺', kind: 'ping', style: 'info' }
        ];
    }
    return [
        { id: 'on',   label: 'Bật',             icon: '⚡', kind: 'http_get', url: base + '/on', style: 'success' },
        { id: 'off',  label: 'Tắt',             icon: '🛑', kind: 'http_get', url: base + '/off', style: 'danger' },
        { id: 'ping', label: 'Kiểm Tra Online', icon: '🩺', kind: 'ping', style: 'info' }
    ];
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


        function createActionForm(defaultIp, onAdd, onCancel) {
            var baseIp = (defaultIp && defaultIp.trim()) ? defaultIp.trim() : '192.168.1.x';
            var aLabelIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Tên nút (VD: Bật còi, Mở cổng)', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });
            var aIconIn  = E('input', { type: 'text', class: 'cbi-input-text', value: '⚡', placeholder: 'Icon', style: 'width: 100%; box-sizing: border-box; font-size: 12px; text-align: center;' });
            var aKindSel = E('select', { class: 'cbi-input-select', style: 'width: 100%; font-size: 12px;' }, [
                E('option', { value: 'http_get' }, 'HTTP GET (LAN URL)'),
                E('option', { value: 'http_post' }, 'HTTP POST (JSON/Text)'),
                E('option', { value: 'tuya_dp' }, 'Tuya DP (Chân DP thiết bị Tuya)'),
                E('option', { value: 'tcp_send' }, 'TCP Raw (IP + Port + Chuỗi)'),
                E('option', { value: 'udp_send' }, 'UDP Raw (IP + Port + Chuỗi)'),
                E('option', { value: 'open_url' }, 'Mở Trang Web Thiết Bị'),
                E('option', { value: 'ping' }, 'Kiểm Tra Trạng Thái Online')
            ]);
            var aUrlIn   = E('input', { type: 'text', class: 'cbi-input-text', value: 'http://' + baseIp + '/on', placeholder: 'http://192.168.1.x/...', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });
            var aBodyIn  = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'JSON Body / Chuỗi gửi (VD: {"on":true})', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });
            var aIpIn    = E('input', { type: 'text', class: 'cbi-input-text', value: baseIp, placeholder: '192.168.1.x', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });
            var aPortIn  = E('input', { type: 'text', class: 'cbi-input-text', value: '8080', placeholder: 'Port', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });
            var aDpIn    = E('input', { type: 'text', class: 'cbi-input-text', value: '1', placeholder: 'VD: 1, 2, 101', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });
            var aDpValIn = E('input', { type: 'text', class: 'cbi-input-text', value: 'true', placeholder: 'true / false / số / chuỗi', style: 'width: 100%; box-sizing: border-box; font-size: 12px;' });

            var urlWrap  = E('div', { style: 'grid-column: 1 / -1;' }, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Đường dẫn URL (Mạng LAN)'), aUrlIn ]);
            var bodyWrap = E('div', { style: 'display: none; grid-column: 1 / -1;' }, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Nội dung Payload / JSON Body'), aBodyIn ]);
            var netWrap  = E('div', { style: 'display: none; grid-template-columns: 2fr 1fr; gap: 6px; grid-column: 1 / -1;' }, [
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'IP LAN'), aIpIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Port'), aPortIn ])
            ]);
            var dpWrap   = E('div', { style: 'display: none; grid-template-columns: 1fr 2fr; gap: 6px; grid-column: 1 / -1;' }, [
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Mã DP'), aDpIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Giá trị DP'), aDpValIn ])
            ]);

            function syncKindFields() {
                var k = aKindSel.value;
                urlWrap.style.display  = (k === 'http_get' || k === 'http_post' || k === 'open_url') ? 'block' : 'none';
                bodyWrap.style.display = (k === 'http_post' || k === 'tcp_send' || k === 'udp_send') ? 'block' : 'none';
                netWrap.style.display  = (k === 'tcp_send' || k === 'udp_send') ? 'grid' : 'none';
                dpWrap.style.display   = (k === 'tuya_dp') ? 'grid' : 'none';
            }
            aKindSel.addEventListener('change', syncKindFields);
            syncKindFields();

            return E('div', { style: 'background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 10px; margin-top: 8px;' }, [
                E('div', { style: 'display: grid; grid-template-columns: 3fr 1fr 2fr; gap: 6px;' }, [
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Tên nút lệnh'), aLabelIn ]),
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Icon'), aIconIn ]),
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Giao thức'), aKindSel ]),
                    urlWrap, netWrap, dpWrap, bodyWrap
                ]),
                E('div', { style: 'display: flex; gap: 6px; margin-top: 8px; justify-content: flex-end;' }, [
                    mkBtn('Hủy', 'font-size: 11.5px; padding: 4px 10px;', function() { if (onCancel) onCancel(); }),
                    mkBtn('💾 Lưu Nút Lệnh', 'font-size: 11.5px; padding: 4px 12px; background: #2563eb; color: #fff; border-color: #2563eb;', function() {
                        var lbl = aLabelIn.value.trim();
                        if (!lbl) { ui.addNotification(null, E('p', 'Vui lòng nhập tên nút lệnh!'), 'warning'); return; }
                        var k = aKindSel.value;
                        onAdd({
                            id: 'act_' + Date.now(),
                            label: lbl,
                            icon: aIconIn.value.trim() || '⚡',
                            kind: k,
                            url: (k === 'http_get' || k === 'http_post' || k === 'open_url') ? aUrlIn.value.trim() : '',
                            body: (k === 'http_post') ? aBodyIn.value : '',
                            ip: (k === 'tcp_send' || k === 'udp_send') ? aIpIn.value.trim() : '',
                            port: (k === 'tcp_send' || k === 'udp_send') ? (parseInt(aPortIn.value, 10) || 8080) : 0,
                            payload: (k === 'tcp_send' || k === 'udp_send') ? aBodyIn.value : '',
                            dp: (k === 'tuya_dp') ? (aDpIn.value.trim() || '1') : '',
                            dp_val: (k === 'tuya_dp') ? aDpValIn.value.trim() : '',
                            style: 'info'
                        });
                    })
                ])
            ]);
        }


return baseclass.extend({
    catIcon: catIcon,
    mkBtn: mkBtn,
    fmtAgo: fmtAgo,
    createActionForm: createActionForm,

    createAddModal: function(state, refreshStatus) {
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
            callSHAdd(cid ? '' : 'tuya_ir_remote', cid, ipath, irCtrlSel.value || 's06_default', cname, irRoomIn.value.trim() || 'Phòng ngủ', '', '', '', '', '', '', '', '', '', '', 0, 0, 0, '', '', '', '', '').then(function(r) {
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

        // Modal Pane 0: Smart IP Auto-Detect & Unlimited Device Builder
        var autoIpIn = E('input', {
            type: 'text', class: 'cbi-input-text',
            placeholder: 'Dán IP hoặc link thiết bị (VD: 192.168.1.50, 192.168.1.169, http://192.168.1.88:8080)...',
            style: 'flex: 1; min-width: 220px; padding: 8px 12px; font-size: 13.5px; font-weight: 600;',
            keydown: function(ev) { if (ev.key === 'Enter') { ev.preventDefault(); runAutoProbe(); } }
        });
        var autoPreviewBox = E('div', { style: 'display: none; background: #ffffff; border: 1.5px solid #93c5fd; border-radius: 10px; padding: 12px; margin-top: 10px;' });
        var autoScanList = E('div', { style: 'margin-top: 10px; max-height: 250px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 8px; background: #f8fafc; padding: 8px;' },
            E('div', { style: 'font-size: 12px; color: #64748b; text-align: center; padding: 10px;' }, '💡 Dán IP bất kỳ ở trên rồi bấm ⚡ Tự Nhận Diện, hoặc bấm 🔍 Quét Tự Động Cả Mạng LAN.')
        );

        function renderAutoPreview(prof) {
            state.autoDraft = {
                profile: prof,
                actions: Array.isArray(prof.suggested_actions) ? prof.suggested_actions.slice() : [],
                showAddAct: false
            };
            autoPreviewBox.innerHTML = '';
            autoPreviewBox.style.display = 'block';

            var nameIn = E('input', { type: 'text', class: 'cbi-input-text', value: prof.suggested_name || '', style: 'width: 100%; box-sizing: border-box; font-weight: 700;' });
            var roomIn = E('input', { type: 'text', class: 'cbi-input-text', value: prof.suggested_room || 'Phòng khách', style: 'width: 100%; box-sizing: border-box;' });
            var catSel = E('select', { class: 'cbi-input-select', style: 'width: 100%;' });
            SMART_CATEGORIES.forEach(function(c) {
                catSel.appendChild(E('option', { value: c.key, selected: (c.key === (prof.suggested_category || 'custom')) ? 'selected' : null }, c.icon + ' ' + c.label));
            });
            var customCatIn = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Nhập tên loại (VD: Báo cháy, Cửa cuốn, Bể cá...)', style: 'width: 100%; box-sizing: border-box; margin-top: 4px;' });
            var customCatWrap = E('div', { style: 'display: ' + (catSel.value === 'custom' ? 'block' : 'none') + ';' }, [ customCatIn ]);

            var drvSel = E('select', { class: 'cbi-input-select', style: 'width: 100%;' });
            DRIVER_OPTIONS.forEach(function(d) {
                drvSel.appendChild(E('option', { value: d.key, selected: (d.key === prof.suggested_driver) ? 'selected' : null }, d.label));
            });

            var tuyaDidIn = E('input', { type: 'text', class: 'cbi-input-text', value: (prof.meta && prof.meta.tuya_device_id) || '', placeholder: 'Device ID', style: 'width: 100%; box-sizing: border-box;' });
            var tuyaKeyIn = E('input', { type: 'password', class: 'cbi-input-text', placeholder: 'Local Key 16 ký tự', style: 'width: 100%; box-sizing: border-box;' });
            var tuyaDpIn  = E('input', { type: 'text', class: 'cbi-input-text', value: '1', placeholder: '1, 2, 3...', style: 'width: 100%; box-sizing: border-box;' });
            var tuyaBox = E('div', { style: 'display: ' + (drvSel.value === 'tuya_switch' ? 'grid' : 'none') + '; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 8px; margin-top: 8px; background: #fffbeb; border: 1px solid #fde68a; border-radius: 8px; padding: 8px;' }, [
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Tuya Device ID'), tuyaDidIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Local Key (16 ký tự)'), tuyaKeyIn ]),
                E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Kênh (DP)'), tuyaDpIn ])
            ]);

            var actionsListBox = E('div', { style: 'margin-top: 8px;' });
            function drawDraftActions() {
                actionsListBox.innerHTML = '';
                var acts = state.autoDraft.actions;
                actionsListBox.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 6px; margin-bottom: 6px;' }, [
                    E('b', { style: 'font-size: 12px; color: #0f172a;' }, '🎛️ Nút lệnh điều khiển (' + acts.length + ' nút):'),
                    E('div', { style: 'display: flex; gap: 4px; flex-wrap: wrap;' }, [
                        mkBtn('🚨 Chống trộm', 'font-size: 11px; padding: 3px 7px;', function() {
                            catSel.value = 'security'; customCatWrap.style.display = 'none';
                            drvSel.value = 'smart_actions'; tuyaBox.style.display = 'none';
                            state.autoDraft.actions = buildActionTemplates('security', prof.ip, prof.meta && prof.meta.port);
                            drawDraftActions();
                        }),
                        mkBtn('💡 Đèn / Ổ cắm', 'font-size: 11px; padding: 3px 7px;', function() {
                            state.autoDraft.actions = buildActionTemplates('plug', prof.ip, prof.meta && prof.meta.port);
                            drawDraftActions();
                        }),
                        mkBtn('🪟 Cổng / Rèm', 'font-size: 11px; padding: 3px 7px;', function() {
                            catSel.value = 'curtain'; customCatWrap.style.display = 'none';
                            drvSel.value = 'smart_actions'; tuyaBox.style.display = 'none';
                            state.autoDraft.actions = buildActionTemplates('curtain', prof.ip, prof.meta && prof.meta.port);
                            drawDraftActions();
                        }),
                        mkBtn('➕ Thêm Nút Lệnh', 'font-size: 11px; padding: 3px 8px; background: #eff6ff; color: #1d4ed8; border-color: #bfdbfe;', function() {
                            state.autoDraft.showAddAct = !state.autoDraft.showAddAct;
                            drawDraftActions();
                        })
                    ])
                ]));
                if (acts.length > 0) {
                    var chips = E('div', { style: 'display: flex; gap: 6px; flex-wrap: wrap;' });
                    acts.forEach(function(a, idx) {
                        chips.appendChild(E('span', { style: 'display: inline-flex; align-items: center; gap: 5px; background: #f1f5f9; border: 1px solid #cbd5e1; border-radius: 6px; padding: 4px 8px; font-size: 11.5px; font-weight: 650;' }, [
                            (a.icon ? (a.icon + ' ') : '') + a.label + ' [' + a.kind + ']',
                            E('span', {
                                style: 'color: #dc2626; cursor: pointer; font-weight: 800; margin-left: 3px;',
                                click: function() { state.autoDraft.actions.splice(idx, 1); drawDraftActions(); }
                            }, '✕')
                        ]));
                    });
                    actionsListBox.appendChild(chips);
                }
                if (state.autoDraft.showAddAct) {
                    actionsListBox.appendChild(createActionForm(prof.ip, function(newAct) {
                        state.autoDraft.actions.push(newAct);
                        state.autoDraft.showAddAct = false;
                        drawDraftActions();
                    }, function() {
                        state.autoDraft.showAddAct = false;
                        drawDraftActions();
                    }));
                }
            }
            drawDraftActions();

            catSel.addEventListener('change', function() {
                customCatWrap.style.display = (catSel.value === 'custom') ? 'block' : 'none';
                if (drvSel.value === 'smart_actions') {
                    state.autoDraft.actions = buildActionTemplates(catSel.value, prof.ip, prof.meta && prof.meta.port);
                    drawDraftActions();
                }
            });
            drvSel.addEventListener('change', function() {
                tuyaBox.style.display = (drvSel.value === 'tuya_switch') ? 'grid' : 'none';
            });

            var statusTag = prof.already_added
                ? E('span', { style: 'font-size: 11px; font-weight: 750; padding: 2px 8px; border-radius: 999px; background: #fef3c7; color: #b45309;' }, 'Đã lưu: ' + prof.registered_name)
                : E('span', { style: 'font-size: 11px; font-weight: 750; padding: 2px 8px; border-radius: 999px; background: ' + (prof.online ? '#dcfce7; color: #15803d;' : '#f1f5f9; color: #475569;') }, prof.online ? '🟢 Trực tuyến' : '⚪ Chưa thấy phản hồi');

            var portsTxt = (Array.isArray(prof.open_ports) && prof.open_ports.length > 0) ? (' • Cổng mở: ' + prof.open_ports.join(', ')) : '';
            var submitRow = E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-top: 12px;' });
            if (prof.target_type === 'controller') {
                submitRow.appendChild(mkBtn('📡 Thêm / Cập Nhật Vào Bộ Điều Khiển', 'background: #047857; color: #fff; border-color: #047857;', function() {
                    callSHSaveCtrl('', prof.suggested_driver, nameIn.value.trim(), roomIn.value.trim(), prof.ip, prof.mac || '', tuyaDidIn.value.trim(), tuyaKeyIn.value.trim(), 1).then(function(r) {
                        ui.addNotification(null, E('p', (r && r.message) || 'Đã lưu bộ điều khiển!'), r && r.ok ? 'info' : 'error');
                        if (r && r.ok) { closeModal(); refreshStatus(); }
                    });
                }));
            }
            submitRow.appendChild(mkBtn('✅ Xác Nhận Thêm Thiết Bị', 'background: #2563eb; color: #fff; border-color: #2563eb;', function() {
                var meta = prof.meta || {};
                var onU = '', offU = '';
                if (drvSel.value === 'http_relay') {
                    var acts = state.autoDraft.actions;
                    for (var i = 0; i < acts.length; i++) {
                        if (!onU && acts[i].url) onU = acts[i].url;
                        else if (onU && !offU && acts[i].url) offU = acts[i].url;
                    }
                    if (!onU) onU = 'http://' + prof.ip + '/on';
                    if (!offU) offU = 'http://' + prof.ip + '/off';
                }
                callSHAdd(
                    drvSel.value, '', '', '',
                    nameIn.value.trim(), roomIn.value.trim(), catSel.value,
                    (catSel.value === 'custom') ? customCatIn.value.trim() : '',
                    prof.ip, prof.mac || '', tuyaDidIn.value.trim(), tuyaKeyIn.value.trim(), tuyaDpIn.value.trim() || '1',
                    onU, offU, meta.tv_id || '',
                    Number(meta.port) || 0, Number(meta.shelly_gen) || 0, Number(meta.channels) || 1,
                    meta.web_url || '', meta.rtsp_url || '',
                    JSON.stringify(state.autoDraft.actions || []),
                    JSON.stringify(prof.capabilities || []),
                    JSON.stringify(meta)
                ).then(function(r) {
                    ui.addNotification(null, E('p', (r && r.message) || 'Đã thêm!'), r && r.ok ? 'info' : 'error');
                    if (r && r.ok) { closeModal(); refreshStatus(); }
                });
            }));

            autoPreviewBox.appendChild(E('div', {}, [
                E('div', { style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 6px; margin-bottom: 6px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 14px; color: #0f172a;' }, catIcon(prof.suggested_category) + ' ' + (prof.detected_kind || 'Thiết bị LAN')),
                    statusTag
                ]),
                E('div', { style: 'font-size: 11.5px; color: #64748b; margin-bottom: 8px;' }, 'IP: ' + prof.ip + (prof.mac ? (' • MAC: ' + prof.mac) : '') + (prof.hostname ? (' • Host: ' + prof.hostname) : '') + portsTxt),
                E('div', { style: 'background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; padding: 8px 10px; font-size: 12px; color: #1e3a8a; margin-bottom: 10px;' }, [
                    E('b', {}, '✨ Hệ thống đề xuất thiết bị này sẽ làm: '),
                    prof.what_it_can_do || ''
                ]),
                E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(165px, 1fr)); gap: 8px;' }, [
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Tên thiết bị'), nameIn ]),
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Phòng'), roomIn ]),
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Loại thiết bị (Không giới hạn)'), catSel, customCatWrap ]),
                    E('div', {}, [ E('div', { style: 'font-size: 11px; font-weight: 700;' }, 'Giao thức điều khiển'), drvSel ])
                ]),
                tuyaBox,
                actionsListBox,
                submitRow
            ]));
        }

        function runAutoProbe(ipOverride) {
            var target = (typeof ipOverride === 'string' && ipOverride) ? ipOverride : autoIpIn.value.trim();
            if (!target) { ui.addNotification(null, E('p', 'Hãy dán địa chỉ IP của thiết bị vào ô trước!'), 'warning'); return; }
            autoPreviewBox.style.display = 'block';
            autoPreviewBox.innerHTML = '<div style="padding: 12px; color: #2563eb; font-weight: 700;">⏳ Đang kiểm tra ' + target + ' và tự động nhận diện giao thức...</div>';
            callSHProbeIp(target).then(function(r) {
                if (!r || !r.ok || !r.profile) {
                    autoPreviewBox.innerHTML = '<div style="padding: 10px; color: #b91c1c; font-weight: 700;">❌ ' + ((r && r.message) || 'Không kiểm tra được IP này') + '</div>';
                    return;
                }
                renderAutoPreview(r.profile);
            }).catch(function(err) {
                autoPreviewBox.innerHTML = '<div style="padding: 10px; color: #b91c1c; font-weight: 700;">❌ Lỗi kết nối: ' + err + '</div>';
            });
        }

        function runSmartLanScan() {
            autoScanList.innerHTML = '<div style="padding: 12px; color: #047857; font-weight: 700;">🔍 Đang quét toàn bộ mạng LAN (Tuya, Tasmota, Shelly, WLED, Yeelight, TV, Camera, ESP32)...</div>';
            callSHScanLan().then(function(r) {
                autoScanList.innerHTML = '';
                var devs = (r && Array.isArray(r.devices)) ? r.devices : [];
                state.autoScanItems = devs;
                if (devs.length === 0) {
                    autoScanList.appendChild(E('div', { style: 'padding: 12px; text-align: center; color: #64748b; font-size: 12.5px;' }, 'Chưa quét thấy thiết bị IoT mới phản hồi. Bạn vẫn có thể dán thẳng IP của thiết bị vào ô phía trên để thêm bất kỳ loại nào!'));
                    return;
                }
                autoScanList.appendChild(E('div', { style: 'font-size: 11.5px; font-weight: 750; color: #334155; margin-bottom: 6px;' }, 'Tìm thấy ' + devs.length + ' thiết bị trên ' + (r.total_lan_hosts || devs.length) + ' máy LAN (' + (r.scanned_ms || 0) + 'ms):'));
                devs.forEach(function(it) {
                    autoScanList.appendChild(E('div', { style: 'display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 8px 10px; background: #fff; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 5px; flex-wrap: wrap;' }, [
                        E('div', { style: 'flex: 1; min-width: 190px;' }, [
                            E('div', { style: 'font-size: 13px; font-weight: 750; color: #0f172a;' }, catIcon(it.suggested_category) + ' ' + it.suggested_name + (it.already_added ? ' ✅' : '')),
                            E('div', { style: 'font-size: 11.5px; color: #64748b;' }, (it.detected_kind || '') + ' • ' + it.ip + (it.open_ports && it.open_ports.length ? (' [' + it.open_ports.join(',') + ']') : ''))
                        ]),
                        mkBtn('⚡ Chọn Thiết Bị Này', 'background: #2563eb; color: #fff; border-color: #2563eb; font-size: 12px; padding: 5px 10px;', function() {
                            autoIpIn.value = it.ip;
                            renderAutoPreview(it);
                        })
                    ]));
                });
            }).catch(function(err) {
                autoScanList.innerHTML = '<div style="padding: 10px; color: #b91c1c;">❌ Lỗi quét LAN: ' + err + '</div>';
            });
        }

        modalPanes.auto = E('div', {}, [
            E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center;' }, [
                autoIpIn,
                mkBtn('⚡ Tự Nhận Diện', 'background: #2563eb; color: #fff; border-color: #2563eb; padding: 8px 14px;', function() { runAutoProbe(); }),
                mkBtn('🔍 Quét Cả LAN', 'background: #047857; color: #fff; border-color: #047857; padding: 8px 12px;', runSmartLanScan)
            ]),
            autoPreviewBox,
            autoScanList
        ]);

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
                    callSHAdd(swDrvSel.value, '', '', '', swNameIn.value.trim(), swRoomIn.value.trim(), swCatSel.value, '', swIpIn.value.trim(), '', swDidIn.value.trim(), swKeyIn.value.trim(), swDpIn.value.trim(), swOnUrlIn.value.trim(), swOffUrlIn.value.trim(), '', 0, 0, 0, '', '', '', '', '').then(function(r) {
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
                        callSHAdd('android_tv', '', '', '', t.name, (t.name.indexOf('Ngủ') !== -1 ? 'Phòng ngủ' : 'Phòng khách'), 'tv', '', t.ip || '', '', '', '', '', '', '', t.id, 0, 0, 0, '', '', '', '', '').then(function(r) {
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
            ['auto', '✨ Tự Nhận / Dán IP'],
            ['ir', '❄️📺🌀 Hồng Ngoại (S06)'],
            ['wifi', '💡🔌 Đèn / Công Tắc Wi-Fi'],
            ['ctrl', '🎙️📡 Mạch Voice / S06 Mới'],
            ['tv', '📺 Android TV LAN']
        ].forEach(function(pair) {
            var b = mkBtn(pair[1], 'font-size: 12px; padding: 6px 11px;', function() {
                switchModalTab(pair[0]);
                if (pair[0] === 'ir') runSearch();
                if (pair[0] === 'ctrl') runLanScanIntoModal();
                if (pair[0] === 'tv') renderModalTVs();
            });
            modalTabBtns[pair[0]] = b;
            modalTabBar.appendChild(b);
        });
        modalCard.appendChild(modalHeader);
        modalCard.appendChild(modalTabBar);
        modalCard.appendChild(modalPanes.auto);
        modalCard.appendChild(modalPanes.ir);
        modalCard.appendChild(modalPanes.wifi);
        modalCard.appendChild(modalPanes.ctrl);
        modalCard.appendChild(modalPanes.tv);

        function openAddModal(tabKey, triggerAutoScan) {
            modalOverlay.style.display = 'flex';
            var k = tabKey || 'auto';
            switchModalTab(k);
            if (k === 'auto' && triggerAutoScan) runSmartLanScan();
            if (k === 'ir') runSearch();
            if (k === 'ctrl') runLanScanIntoModal();
            if (k === 'tv') renderModalTVs();
        }

        return {
            overlay: modalOverlay,
            open: openAddModal,
            close: closeModal,
            isOpen: function() { return modalOverlay.style.display !== 'none'; },
            syncControllers: function(controllers) {
                irCtrlSel.innerHTML = '';
                (controllers || []).forEach(function(c) {
                    if (c.kind === 'tuya_ir') {
                        irCtrlSel.appendChild(E('option', { value: c.id }, 'Qua ' + c.name + ' (' + (c.room || '') + ')'));
                    }
                });
            }
        };
    }
});
// [/VERIFIED-GOLDEN]
