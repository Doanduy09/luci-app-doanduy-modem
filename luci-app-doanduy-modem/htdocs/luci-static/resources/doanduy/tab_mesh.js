// DOANDUY Minimalist Centered Multi-Tier Router Mesh Tree & Wi-Fi Sync (v2.7.0)
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callMeshStatus  = rpc.declare({ object: 'doanduy.mesh', method: 'status', expect: { } });
var callMeshSetMode = rpc.declare({ object: 'doanduy.mesh', method: 'setMode', params: ['mode', 'node_ip'], expect: { } });
var callMeshSetWifi = rpc.declare({ object: 'doanduy.mesh', method: 'setWifi', params: ['sync_mode', 'ssid_2g', 'ssid_5g', 'key', 'encryption', 'keep_key'], expect: { } });

function ensureTreeStyles() {
    if (document.getElementById('dd-mesh-tree-css')) return;
    var st = document.createElement('style');
    st.id = 'dd-mesh-tree-css';
    st.textContent = [
        '@keyframes ddWaveArc {',
        '  0%   { opacity: 0.18; transform: scale(0.88); }',
        '  50%  { opacity: 1.00; transform: scale(1.05); }',
        '  100% { opacity: 0.18; transform: scale(0.88); }',
        '}',
        '@keyframes ddRadar {',
        '  0%   { transform: translate(-50%, -50%) scale(0.5); opacity: 0.7; }',
        '  100% { transform: translate(-50%, -50%) scale(1.75); opacity: 0; }',
        '}',
        '.dd-arc-1 { animation: ddWaveArc 1.4s infinite ease-in-out 0.0s; transform-origin: center bottom; }',
        '.dd-arc-2 { animation: ddWaveArc 1.4s infinite ease-in-out 0.25s; transform-origin: center bottom; }',
        '.dd-arc-3 { animation: ddWaveArc 1.4s infinite ease-in-out 0.5s; transform-origin: center bottom; }',
        '.dd-radar-1 {',
        '  position: absolute; left: 50%; top: 48%; width: 120px; height: 120px; border-radius: 50%;',
        '  border: 2px solid #3b82f6; pointer-events: none; animation: ddRadar 2.1s infinite ease-out;',
        '}',
        '.dd-radar-2 {',
        '  position: absolute; left: 50%; top: 48%; width: 120px; height: 120px; border-radius: 50%;',
        '  border: 2px solid #06b6d4; pointer-events: none; animation: ddRadar 2.1s infinite ease-out 1.05s;',
        '}',
        // CSS Sơ đồ cây phân tầng tự động (Chính ở giữa trên -> Các Phụ cùng cấp nằm ngang chung 1 tầng -> Phụ mesh Phụ nằm ở tầng dưới)
        '.dd-tree-stage { display: flex; justify-content: center; padding: 28px 12px 24px; overflow-x: auto; }',
        '.dd-tree ul { padding-top: 26px; position: relative; display: flex; justify-content: center; margin: 0; padding-left: 0; list-style: none; }',
        '.dd-tree li { display: flex; flex-direction: column; align-items: center; text-align: center; list-style-type: none; position: relative; padding: 26px 18px 0 18px; }',
        '.dd-tree > ul { padding-top: 0; }',
        '.dd-tree > ul > li { padding-top: 0; }',
        '.dd-tree li::before, .dd-tree li::after {',
        '  content: ""; position: absolute; top: 0; right: 50%; border-top: 2.5px solid #38bdf8; width: 50%; height: 26px;',
        '}',
        '.dd-tree li::after { right: auto; left: 50%; border-left: 2.5px solid #38bdf8; }',
        '.dd-tree li:only-child::after, .dd-tree li:only-child::before { display: none; }',
        '.dd-tree li:only-child { padding-top: 22px; }',
        '.dd-tree > ul > li:only-child { padding-top: 0; }',
        '.dd-tree li:first-child::before, .dd-tree li:last-child::after { border: 0 none; }',
        '.dd-tree li:last-child::before { border-right: 2.5px solid #38bdf8; border-radius: 0 8px 0 0; }',
        '.dd-tree li:first-child::after { border-radius: 8px 0 0 0; }',
        '.dd-tree ul ul::before {',
        '  content: ""; position: absolute; top: 0; left: 50%; border-left: 2.5px solid #38bdf8; width: 0; height: 26px; transform: translateX(-50%);',
        '}',
        '.dd-tree li:only-child::before {',
        '  display: block; content: ""; position: absolute; top: 0; left: 50%; right: auto; width: 0; height: 22px; border-top: 0; border-left: 2.5px solid #38bdf8; transform: translateX(-50%);',
        '}',
        '.dd-tree > ul > li:only-child::before { display: none; }',
        '.dd-router-node {',
        '  display: flex; flex-direction: column; align-items: center; background: #ffffff; border-radius: 16px;',
        '  padding: 14px 22px 14px; min-width: 196px; border: 2px solid #cbd5e1;',
        '  box-shadow: 0 8px 22px rgba(15, 23, 42, 0.06); position: relative; transition: transform 0.18s ease;',
        '}',
        '.dd-router-node:hover { transform: translateY(-2px); }',
        '.dd-router-node.is-main { border-color: #2563eb; }',
        '.dd-router-node.is-sub  { border-color: #0891b2; }'
    ].join('\n');
    document.head.appendChild(st);
}

function formatMMSS(sec) {
    var s = Math.max(0, parseInt(sec || 0, 10));
    var m = Math.floor(s / 60);
    var r = s % 60;
    return (m < 10 ? '0' + m : '' + m) + ':' + (r < 10 ? '0' + r : '' + r);
}

// Hình ảnh chiếc Router giống nhau sắc nét cho cả Router Chính & Router Phụ + sóng Wi-Fi trên ăng-ten
function createRouterSvg(isPrimary, isSearching, isActive, uid) {
    var wrap = E('div', {
        style: 'position: relative; width: 164px; height: 126px; display: flex; align-items: center; justify-content: center;'
    });

    if (isSearching) {
        wrap.appendChild(E('div', { class: 'dd-radar-1' }));
        wrap.appendChild(E('div', { class: 'dd-radar-2' }));
    }

    var gradStart = isPrimary ? '#1e3a8a' : '#0f766e';
    var gradEnd   = isPrimary ? '#2563eb' : '#06b6d4';
    var waveCol   = isSearching ? '#2563eb' : (isActive ? '#10b981' : '#94a3b8');
    var ledCol    = isActive ? '#22c55e' : '#94a3b8';
    var gid       = 'ddRGrad_' + uid;

    var wavePaths = '';
    if (isSearching || isActive) {
        var c1 = isSearching ? ' class="dd-arc-1"' : '';
        var c2 = isSearching ? ' class="dd-arc-2"' : '';
        var c3 = isSearching ? ' class="dd-arc-3"' : '';
        wavePaths =
            '<g fill="none" stroke="' + waveCol + '" stroke-linecap="round">' +
                '<path' + c1 + ' d="M71 29 Q82 20 93 29" stroke-width="2.8"/>' +
                '<path' + c2 + ' d="M63 21 Q82 8 101 21" stroke-width="2.6"/>' +
                '<path' + c3 + ' d="M55 13 Q82 -3 109 13" stroke-width="2.4"/>' +
                '<circle cx="82" cy="34" r="3" fill="' + waveCol + '" stroke="none"/>' +
            '</g>';
    }

    wrap.innerHTML +=
        '<svg width="164" height="122" viewBox="0 0 164 122" xmlns="http://www.w3.org/2000/svg" style="position: relative; z-index: 2;">' +
            '<defs>' +
                '<linearGradient id="' + gid + '" x1="0%" y1="0%" x2="100%" y2="100%">' +
                    '<stop offset="0%" stop-color="' + gradStart + '"/>' +
                    '<stop offset="100%" stop-color="' + gradEnd + '"/>' +
                '</linearGradient>' +
            '</defs>' +
            wavePaths +
            '<rect x="34" y="28" width="5" height="46" rx="2.5" transform="rotate(-12 36 70)" fill="#1e293b"/>' +
            '<rect x="58" y="22" width="5" height="50" rx="2.5" transform="rotate(-4 60 70)" fill="#1e293b"/>' +
            '<rect x="101" y="22" width="5" height="50" rx="2.5" transform="rotate(4 103 70)" fill="#1e293b"/>' +
            '<rect x="125" y="28" width="5" height="46" rx="2.5" transform="rotate(12 127 70)" fill="#1e293b"/>' +
            '<ellipse cx="82" cy="112" rx="58" ry="6" fill="rgba(15,23,42,0.12)"/>' +
            '<polygon points="30,68 134,68 144,82 20,82" fill="url(#' + gid + ')"/>' +
            '<rect x="20" y="80" width="124" height="24" rx="7" fill="#0f172a"/>' +
            '<rect x="24" y="83" width="116" height="18" rx="5" fill="#1e293b"/>' +
            '<circle cx="38" cy="92" r="3.2" fill="' + ledCol + '"/>' +
            '<circle cx="50" cy="92" r="3.2" fill="' + ledCol + '"/>' +
            '<circle cx="62" cy="92" r="3.2" fill="' + (isSearching ? '#38bdf8' : ledCol) + '"/>' +
            '<circle cx="74" cy="92" r="3.2" fill="' + (isSearching ? '#60a5fa' : '#38bdf8') + '"/>' +
            '<rect x="100" y="88" width="28" height="2.5" rx="1.2" fill="#475569"/>' +
            '<rect x="100" y="93" width="28" height="2.5" rx="1.2" fill="#475569"/>' +
            '<rect x="30" y="104" width="12" height="5" rx="2" fill="#334155"/>' +
            '<rect x="122" y="104" width="12" height="5" rx="2" fill="#334155"/>' +
        '</svg>';

    return wrap;
}

function createVisualNodeBox(opts) {
    var isPrimary = !!opts.isPrimary;
    var badgeGrad = isPrimary
        ? 'linear-gradient(135deg, #1d4ed8, #2563eb)'
        : 'linear-gradient(135deg, #0e7490, #06b6d4)';

    var ipEl = opts.clickableUrl
        ? E('a', {
            href: opts.clickableUrl,
            target: '_blank',
            style: 'font-size: 13px; font-weight: 800; font-family: monospace; color: #0284c7; text-decoration: none; margin-top: 2px;'
        }, (opts.ip || '') + ' ↗')
        : E('div', {
            style: 'font-size: 13px; font-weight: 800; font-family: monospace; color: #475569; margin-top: 2px;'
        }, opts.ip || '192.168.1.1');

    var card = E('div', {
        class: 'dd-router-node ' + (isPrimary ? 'is-main' : 'is-sub')
    }, [
        opts.signal ? E('div', {
            style: 'display: inline-flex; align-items: center; gap: 4px; padding: 2px 9px; border-radius: 999px; background: #ecfdf5; border: 1px solid #6ee7b7; color: #047857; font-size: 11px; font-weight: 800; margin-bottom: -4px;'
        }, '📶 ' + opts.signal) : E('span'),

        createRouterSvg(isPrimary, !!opts.isSearching, opts.isActive !== false, opts.uid || Math.floor(Math.random() * 99999)),

        E('div', {
            style: 'margin-top: -2px; padding: 5px 18px; border-radius: 999px; font-size: 12.5px; font-weight: 900; letter-spacing: 0.5px; color: #ffffff; background: ' + badgeGrad + '; box-shadow: 0 2px 8px rgba(15,23,42,0.18);'
        }, opts.roleText || (isPrimary ? 'ROUTER CHÍNH' : 'ROUTER PHỤ')),

        E('div', {
            style: 'font-size: 14px; font-weight: 800; color: #0f172a; margin-top: 8px;'
        }, opts.model || (isPrimary ? 'Router Chính' : 'Router Phụ')),

        ipEl
    ]);

    if (opts.isCurrent) {
        card.appendChild(E('span', {
            title: 'Thiết bị đang mở trình duyệt',
            style: 'position: absolute; top: 10px; right: 10px; width: 10px; height: 10px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 0 3px #dcfce7;'
        }));
    }

    return card;
}

// Dựng đệ quy các tầng cây Mesh:
// - Cùng gắn vào Router Chính -> Nằm ngang chung Tầng 1
// - Phụ gắn vào Phụ -> Tự động nằm ở Tầng dưới ngay dưới cục Phụ đó
function buildSubtreeLi(nodeData, childrenMap, currentIp, idxSeed) {
    var ip = nodeData.ip || '';
    var li = E('li', {}, [
        createVisualNodeBox({
            isPrimary: !!nodeData.isPrimary,
            isSearching: !!nodeData.isSearching,
            isActive: nodeData.isActive !== false,
            isCurrent: ip === currentIp,
            roleText: nodeData.roleText,
            model: nodeData.model,
            ip: ip,
            signal: nodeData.signal || '',
            clickableUrl: (ip && ip !== currentIp) ? ('http://' + ip) : '',
            uid: idxSeed + '_' + ip.replace(/\./g, '_')
        })
    ]);

    var kids = childrenMap[ip] || [];
    if (kids.length > 0) {
        var ul = E('ul', {});
        kids.forEach(function(child, cIdx) {
            ul.appendChild(buildSubtreeLi(child, childrenMap, currentIp, idxSeed + '_' + cIdx));
        });
        li.appendChild(ul);
    }
    return li;
}

return baseclass.extend({
    renderPane: function() {
        ensureTreeStyles();

        var latestState = null;
        var formDirty = false;
        var uiSyncMode = null;

        var statusPill = E('span', {
            style: 'font-size: 12px; font-weight: 800; padding: 4px 12px; border-radius: 999px; background: #f1f5f9; color: #334155;'
        }, '⏳');

        var btnOn = E('button', {
            class: 'btn cbi-button cbi-button-apply',
            style: 'font-weight: 900; padding: 6px 18px; border-radius: 999px; font-size: 13px;',
            click: function() { toggleMesh('pair'); }
        }, 'Bật');

        var btnOff = E('button', {
            class: 'btn cbi-button cbi-button-reset',
            style: 'font-weight: 900; padding: 6px 18px; border-radius: 999px; font-size: 13px;',
            click: function() { toggleMesh('off'); }
        }, 'Tắt');

        var treeStage = E('div', { class: 'dd-tree-stage' }, '');

        // --- Wi-Fi Mesh Sync / Custom Override Card ---
        var wifiSummaryEl = E('div', {
            style: 'display: flex; flex-wrap: wrap; align-items: center; gap: 8px; font-size: 12.5px; color: #334155;'
        }, 'Đang tải thông tin Wi-Fi...');

        var btnModeMaster = E('button', {
            type: 'button',
            class: 'btn cbi-button',
            style: 'font-weight: 800; padding: 5px 12px; border-radius: 999px; font-size: 12px;',
            click: function() { applyMasterSync(); }
        }, '🔄 Đồng bộ Router Chính (Mặc định)');

        var btnModeCustom = E('button', {
            type: 'button',
            class: 'btn cbi-button',
            style: 'font-weight: 800; padding: 5px 12px; border-radius: 999px; font-size: 12px;',
            click: function() {
                uiSyncMode = 'custom';
                formDirty = true;
                updateWifiPanelVisibility();
            }
        }, '✏️ Tùy chỉnh Wi-Fi riêng');

        var chkSameSsid = E('input', {
            type: 'checkbox',
            checked: false,
            style: 'width: 15px; height: 15px; cursor: pointer;',
            change: function() {
                formDirty = true;
                if (chkSameSsid.checked) {
                    inSsid5g.value = inSsid2g.value;
                    inSsid5g.disabled = true;
                } else {
                    inSsid5g.disabled = false;
                }
            }
        });

        var inSsid2g = E('input', {
            type: 'text',
            maxlength: '32',
            placeholder: 'Tên Wi-Fi 2.4GHz',
            style: 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 8px; font-size: 13px;',
            input: function() {
                formDirty = true;
                if (chkSameSsid.checked) inSsid5g.value = inSsid2g.value;
            }
        });

        var inSsid5g = E('input', {
            type: 'text',
            maxlength: '32',
            placeholder: 'Tên Wi-Fi 5GHz',
            style: 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 8px; font-size: 13px;',
            input: function() { formDirty = true; }
        });

        var selEnc = E('select', {
            style: 'width: 100%; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 8px; font-size: 13px; background: #fff;',
            change: function() {
                formDirty = true;
                inKey.disabled = (selEnc.value === 'none');
            }
        }, [
            E('option', { value: 'psk2' }, 'WPA2-PSK (Khuyên dùng)'),
            E('option', { value: 'psk-mixed' }, 'WPA/WPA2 Hỗn hợp'),
            E('option', { value: 'sae-mixed' }, 'WPA2/WPA3 Hỗn hợp'),
            E('option', { value: 'none' }, 'Không mật khẩu (Open)')
        ]);

        var keyVisible = false;
        var inKey = E('input', {
            type: 'password',
            maxlength: '63',
            placeholder: 'Nhập mật khẩu (8-63 ký tự)',
            style: 'flex: 1; min-width: 0; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 8px; font-size: 13px;',
            input: function() { formDirty = true; }
        });

        var btnToggleKey = E('button', {
            type: 'button',
            class: 'btn cbi-button',
            style: 'padding: 6px 10px; border-radius: 8px; font-size: 12px;',
            click: function() {
                keyVisible = !keyVisible;
                inKey.type = keyVisible ? 'text' : 'password';
                btnToggleKey.textContent = keyVisible ? '🙈' : '👁️';
            }
        }, '👁️');

        var btnSaveWifi = E('button', {
            type: 'button',
            class: 'btn cbi-button cbi-button-apply',
            style: 'font-weight: 800; padding: 7px 18px; border-radius: 10px; font-size: 13px;',
            click: function() { saveCustomWifi(); }
        }, '💾 Lưu & Áp dụng Wi-Fi');

        var customFormBox = E('div', {
            style: 'display: none; margin-top: 12px; padding-top: 12px; border-top: 1px dashed #cbd5e1;'
        }, [
            E('label', { style: 'display: inline-flex; align-items: center; gap: 6px; font-size: 12.5px; font-weight: 700; color: #334155; margin-bottom: 10px; cursor: pointer;' }, [
                chkSameSsid,
                'Dùng chung 1 tên Wi-Fi cho cả 2.4G & 5G'
            ]),
            E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 10px;' }, [
                E('div', {}, [
                    E('div', { style: 'font-size: 11.5px; font-weight: 700; color: #475569; margin-bottom: 4px;' }, 'Tên Wi-Fi 2.4G'),
                    inSsid2g
                ]),
                E('div', {}, [
                    E('div', { style: 'font-size: 11.5px; font-weight: 700; color: #475569; margin-bottom: 4px;' }, 'Tên Wi-Fi 5G'),
                    inSsid5g
                ]),
                E('div', {}, [
                    E('div', { style: 'font-size: 11.5px; font-weight: 700; color: #475569; margin-bottom: 4px;' }, 'Chuẩn bảo mật'),
                    selEnc
                ]),
                E('div', {}, [
                    E('div', { style: 'font-size: 11.5px; font-weight: 700; color: #475569; margin-bottom: 4px;' }, 'Mật khẩu Wi-Fi'),
                    E('div', { style: 'display: flex; gap: 6px;' }, [inKey, btnToggleKey])
                ])
            ]),
            E('div', { style: 'display: flex; justify-content: flex-end; margin-top: 12px;' }, [btnSaveWifi])
        ]);

        var wifiCard = E('div', {
            style: 'margin-top: 8px; border: 1px solid #e2e8f0; border-radius: 12px; padding: 12px 16px; background: #f8fafc;'
        }, [
            E('div', { style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;' }, [
                E('div', { style: 'display: flex; flex-direction: column; gap: 4px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 13.5px; color: #0f172a;' }, '📶 Cấu hình Wi-Fi Mesh'),
                    wifiSummaryEl
                ]),
                E('div', { style: 'display: flex; flex-wrap: wrap; gap: 6px;' }, [btnModeMaster, btnModeCustom])
            ]),
            customFormBox
        ]);

        function updateWifiPanelVisibility() {
            var activeMode = uiSyncMode || (latestState && latestState.wifi && latestState.wifi.sync_mode) || 'master';
            var isCustom = (activeMode === 'custom');
            customFormBox.style.display = isCustom ? 'block' : 'none';
            btnModeMaster.style.background = !isCustom ? '#2563eb' : '#ffffff';
            btnModeMaster.style.color      = !isCustom ? '#ffffff' : '#334155';
            btnModeMaster.style.border     = !isCustom ? '1px solid #2563eb' : '1px solid #cbd5e1';
            btnModeCustom.style.background = isCustom ? '#0891b2' : '#ffffff';
            btnModeCustom.style.color      = isCustom ? '#ffffff' : '#334155';
            btnModeCustom.style.border     = isCustom ? '1px solid #0891b2' : '1px solid #cbd5e1';
        }

        function applyMasterSync() {
            btnModeMaster.disabled = true;
            btnModeCustom.disabled = true;
            callMeshSetWifi('master', '', '', '', '', true).then(function(res) {
                btnModeMaster.disabled = false;
                btnModeCustom.disabled = false;
                if (res && res.success === false) {
                    ui.addNotification(null, E('p', '❌ ' + (res.message || 'Không thể bật đồng bộ Master')), 'error');
                    return;
                }
                uiSyncMode = 'master';
                formDirty = false;
                updateWifiPanelVisibility();
                ui.addNotification(null, E('p', '✅ ' + (res.message || 'Đã chuyển sang đồng bộ theo Router Chính')), 'info');
                setTimeout(refreshMesh, 1200);
            }).catch(function(err) {
                btnModeMaster.disabled = false;
                btnModeCustom.disabled = false;
                ui.addNotification(null, E('p', '❌ ' + err), 'error');
            });
        }

        function saveCustomWifi() {
            var s2 = (inSsid2g.value || '').trim();
            var s5 = chkSameSsid.checked ? s2 : (inSsid5g.value || '').trim();
            var enc = selEnc.value || 'psk2';
            var ky = inKey.value || '';
            var hasExistingKey = !!(latestState && latestState.wifi && latestState.wifi.has_key);

            if (!s2 && !s5) {
                ui.addNotification(null, E('p', '❌ Vui lòng nhập tên Wi-Fi!'), 'error');
                return;
            }
            if (enc !== 'none' && ky.length > 0 && (ky.length < 8 || ky.length > 63)) {
                ui.addNotification(null, E('p', '❌ Mật khẩu Wi-Fi phải từ 8 đến 63 ký tự!'), 'error');
                return;
            }
            if (enc !== 'none' && ky.length === 0 && !hasExistingKey) {
                ui.addNotification(null, E('p', '❌ Vui lòng nhập mật khẩu Wi-Fi (8-63 ký tự)!'), 'error');
                return;
            }

            btnSaveWifi.disabled = true;
            btnSaveWifi.textContent = '⏳ Đang lưu...';
            callMeshSetWifi('custom', s2 || s5, s5 || s2, ky, enc, true).then(function(res) {
                btnSaveWifi.disabled = false;
                btnSaveWifi.textContent = '💾 Lưu & Áp dụng Wi-Fi';
                if (!res || res.success === false) {
                    ui.addNotification(null, E('p', '❌ ' + ((res && res.message) || 'Lưu Wi-Fi thất bại')), 'error');
                    return;
                }
                uiSyncMode = 'custom';
                formDirty = false;
                inKey.value = '';
                ui.addNotification(null, E('p', '✅ ' + res.message), 'info');
                setTimeout(refreshMesh, 1500);
                setTimeout(refreshMesh, 4000);
            }).catch(function(err) {
                btnSaveWifi.disabled = false;
                btnSaveWifi.textContent = '💾 Lưu & Áp dụng Wi-Fi';
                ui.addNotification(null, E('p', '❌ ' + err), 'error');
            });
        }

        function toggleMesh(action) {
            var isOn = (action === 'pair');
            btnOn.disabled = true;
            btnOff.disabled = true;
            statusPill.textContent = isOn ? '⏳ Đang bật Mesh...' : '⏳ Đang tắt Mesh...';
            statusPill.style.background = '#e0f2fe';
            statusPill.style.color = '#0369a1';

            function finish() {
                btnOn.disabled = false;
                btnOff.disabled = false;
            }

            callMeshSetMode(action, '192.168.1.10').then(function(res) {
                finish();
                if (res && res.success === false) {
                    ui.addNotification(null, E('p', '❌ ' + (res.message || 'Thao tác Mesh thất bại')), 'error');
                    refreshMesh();
                    return;
                }
                if (isOn) {
                    statusPill.textContent = '📡 Auto-Mesh Đang Bật (Tự động)';
                    statusPill.style.background = '#dbeafe';
                    statusPill.style.color = '#1d4ed8';
                } else {
                    statusPill.textContent = '⚪ Đã tắt';
                    statusPill.style.background = '#f1f5f9';
                    statusPill.style.color = '#64748b';
                }
                setTimeout(refreshMesh, 1000);
                setTimeout(refreshMesh, 3500);
            }).catch(function(err) {
                finish();
                ui.addNotification(null, E('p', '❌ ' + err), 'error');
                refreshMesh();
            });
        }

        function renderState(st) {
            latestState = st;
            while (treeStage.firstChild) treeStage.removeChild(treeStage.firstChild);

            if (!st || st.success === false) {
                statusPill.textContent = '⚠️ Chưa sẵn sàng';
                return;
            }

            var peers       = Array.isArray(st.peers) ? st.peers : [];
            var role        = st.role || 'searching_node';
            var isSearching = !!st.searching;
            var isAutoIdle  = !!st.auto_idle;
            var remSec      = Number(st.search_remaining) || 0;
            var remTxt      = remSec > 0 ? (' (' + Math.floor(remSec / 60) + 'p' + (remSec % 60 < 10 ? '0' : '') + (remSec % 60) + 's)') : '';
            var isEnabled   = !!st.enabled && !isAutoIdle && role !== 'standalone';

            btnOn.style.opacity  = isEnabled ? '1' : '0.88';
            btnOff.style.opacity = (!isEnabled) ? '0.6' : '1';

            if (role === 'controller' && peers.length > 0) {
                statusPill.textContent = '🟢 Đang kết nối ' + peers.length + ' Router Phụ';
                statusPill.style.background = '#dcfce7';
                statusPill.style.color = '#15803d';
            } else if (role === 'node' && peers.length > 0) {
                statusPill.textContent = '🟢 Đã kết nối Router Chính';
                statusPill.style.background = '#dcfce7';
                statusPill.style.color = '#15803d';
            } else if (isAutoIdle) {
                statusPill.textContent = '⚪ Tự tắt sau 10p (Không có Mesh • Tự bật khi reboot)';
                statusPill.style.background = '#f1f5f9';
                statusPill.style.color = '#64748b';
            } else if (role === 'controller') {
                statusPill.textContent = '📡 Sẵn sàng ghép Mesh' + remTxt;
                statusPill.style.background = '#dbeafe';
                statusPill.style.color = '#1d4ed8';
            } else if (role === 'searching_node' || isSearching) {
                statusPill.textContent = '📡 Đang tìm Router Chính...' + remTxt;
                statusPill.style.background = '#dbeafe';
                statusPill.style.color = '#1d4ed8';
            } else {
                statusPill.textContent = '⚪ Đã tắt';
                statusPill.style.background = '#f1f5f9';
                statusPill.style.color = '#64748b';
            }

            // Update Wi-Fi summary chips & populate form only if user isn't editing
            var w = st.wifi || {};
            var wMode = w.sync_mode || 'master';
            while (wifiSummaryEl.firstChild) wifiSummaryEl.removeChild(wifiSummaryEl.firstChild);
            wifiSummaryEl.appendChild(E('span', {
                style: 'padding: 2px 8px; border-radius: 6px; background: ' + (wMode === 'custom' ? '#cffafe; color: #0e7490;' : '#dbeafe; color: #1d4ed8;') + ' font-weight: 800;'
            }, wMode === 'custom' ? 'Tùy chỉnh riêng' : 'Đồng bộ Chính'));
            wifiSummaryEl.appendChild(E('span', { style: 'font-weight: 700;' }, '2.4G: ' + (w.ssid_2g || '—')));
            wifiSummaryEl.appendChild(E('span', { style: 'font-weight: 700;' }, '5G: ' + (w.ssid_5g || '—')));
            wifiSummaryEl.appendChild(E('span', { style: 'color: #64748b;' }, w.has_key ? ('🔒 ' + (w.encryption || 'psk2')) : '🔓 Mở'));

            if (!formDirty) {
                uiSyncMode = wMode;
                inSsid2g.value = w.ssid_2g || '';
                inSsid5g.value = w.ssid_5g || '';
                var same = !!(w.ssid_2g && w.ssid_2g === w.ssid_5g);
                chkSameSsid.checked = same;
                inSsid5g.disabled = same;
                if (w.encryption) selEnc.value = w.encryption;
                inKey.disabled = (selEnc.value === 'none');
                inKey.placeholder = w.has_key ? 'Để trống nếu giữ mật khẩu hiện tại (8-63 ký tự)' : 'Nhập mật khẩu (8-63 ký tự)';
            }
            updateWifiPanelVisibility();

            var currentIp = st.local_ip || '192.168.1.1';
            var masterIp  = st.master_ip || '192.168.1.1';

            // Nếu máy chưa có mạng đang tự dò sóng (chưa ghép vào 192.168.1.1) -> Hiện đúng 1 hình Router ở chính giữa
            if (role === 'searching_node' && peers.length === 0) {
                var singleTree = E('div', { class: 'dd-tree' }, [
                    E('ul', {}, [
                        E('li', {}, [
                            createVisualNodeBox({
                                isPrimary: false,
                                isSearching: true,
                                isActive: true,
                                isCurrent: true,
                                roleText: 'ĐANG DÒ MESH',
                                model: st.board_model || 'Router DOANDUY',
                                ip: currentIp,
                                uid: 'searching_self'
                            })
                        ])
                    ])
                ]);
                treeStage.appendChild(singleTree);
                return;
            }

            // Gom nhóm các Router Phụ theo tầng (parent_ip) và sắp xếp IP tăng dần .10, .11, .12, .13, .14...
            var validIps = {};
            validIps[masterIp] = true;
            peers.forEach(function(p) {
                if (p && p.ip) validIps[p.ip] = true;
            });

            var sortedPeers = peers.slice().sort(function(a, b) {
                var oa = parseInt(String(a.ip || '0').split('.').pop(), 10) || 0;
                var ob = parseInt(String(b.ip || '0').split('.').pop(), 10) || 0;
                return oa - ob;
            });

            var childrenMap = {};
            sortedPeers.forEach(function(p) {
                if (!p || !p.ip) return;
                var par = (p.parent_ip && validIps[p.parent_ip] && p.parent_ip !== p.ip) ? p.parent_ip : masterIp;
                if (!childrenMap[par]) childrenMap[par] = [];
                childrenMap[par].push({
                    isPrimary: false,
                    isSearching: false,
                    isActive: true,
                    roleText: 'ROUTER PHỤ',
                    model: p.model || 'Router Phụ',
                    ip: p.ip,
                    signal: p.signal || ''
                });
            });

            var rootNode = {
                isPrimary: true,
                isSearching: isSearching && peers.length === 0,
                isActive: isEnabled || !!st.has_internet,
                roleText: 'ROUTER CHÍNH',
                model: (role === 'node' ? st.master_model : st.board_model) || 'Router Chính',
                ip: (role === 'node' ? masterIp : currentIp)
            };

            var rootTree = E('div', { class: 'dd-tree' }, [
                E('ul', {}, [
                    buildSubtreeLi(rootNode, childrenMap, currentIp, 'root')
                ])
            ]);

            treeStage.appendChild(rootTree);
        }

        function refreshMesh() {
            return callMeshStatus().then(renderState).catch(function() {});
        }

        var pane = E('div', { style: 'display: none;' }, [
            E('div', {
                style: 'border: 1px solid #cbd5e1; border-radius: 16px; padding: 16px 20px; background: linear-gradient(180deg, #f8fafc 0%, #ffffff 100%); min-height: 300px;'
            }, [
                // Thanh tiêu đề tối giản: chỉ có Trạng thái bên trái & nút Bật / Tắt ngay trên đầu
                E('div', {
                    style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; padding-bottom: 12px; border-bottom: 1px solid #e2e8f0;'
                }, [
                    E('div', { style: 'display: flex; align-items: center; gap: 10px;' }, [
                        E('span', { style: 'font-weight: 900; font-size: 15.5px; color: #0f172a;' }, '🌐 Auto-Mesh'),
                        statusPill
                    ]),
                    E('div', { style: 'display: flex; align-items: center; gap: 8px;' }, [
                        btnOn,
                        btnOff
                    ])
                ]),
                treeStage,
                wifiCard
            ])
        ]);

        setInterval(function() {
            if (pane.style.display !== 'none' && document.body.contains(pane)) {
                refreshMesh();
            }
        }, 5000);

        pane._onShow = refreshMesh;
        return pane;
    }
});
