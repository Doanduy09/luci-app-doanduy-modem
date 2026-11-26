// [VERIFIED-GOLDEN: luci-mod-tab-sentinel-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
// Scenario 04 (Telegram, AI Sentinel & Remote) — LuCI Tab 3: Kho Key Đa Tài Khoản, Bot, Camera & Tailscale/WAN
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callSetSentinelConfig = rpc.declare({ object: 'doanduy.vault', method: 'save', params: ['tg_bot_token', 'tg_admin_id', 'tg_owner_name', 'emergency_phone', 'gemini_api_key', 'tailscale_auth_key', 'cloud_remote', 'telegram_bots', 'gemini_keys', 'tailscale_keys', 'cameras'] });
var callLoadVaultKeys     = rpc.declare({ object: 'doanduy.vault', method: 'get', expect: { } });
var callTestTelegram      = rpc.declare({ object: 'doanduy.vault', method: 'testTelegram', params: ['token', 'chat_id', 'name'], expect: { } });
var callRemoteStatus      = rpc.declare({ object: 'doanduy.remote', method: 'status', expect: { } });
var callTailscaleUp       = rpc.declare({ object: 'doanduy.remote', method: 'tailscaleUp', params: ['authkey', 'enable_funnel'], expect: { } });
var callTailscaleDown     = rpc.declare({ object: 'doanduy.remote', method: 'tailscaleDown', expect: { } });
var callToggleWanPort     = rpc.declare({ object: 'doanduy.remote', method: 'toggleWanPort', params: ['service', 'enable', 'port'], expect: { } });
var callStartTunnel       = rpc.declare({ object: 'doanduy.remote', method: 'startTunnel', params: ['duration'], expect: { } });
var callStopTunnel        = rpc.declare({ object: 'doanduy.remote', method: 'stopTunnel', expect: { } });

return baseclass.extend({
    renderPane: function(ctx) {
        var sentinelConfig = ctx.sentinelConfig || {};
        var remoteState = ctx.remoteState || {};

        // ---------------- TAB 3: TELEGRAM BOT, AI SENTINEL, MULTI-KEY VAULT & REMOTE ACCESS ----------------
        var teleOwnerInput = E('input', { type: 'text', class: 'cbi-input-text', value: sentinelConfig.tg_owner_name || 'Anh Duy', placeholder: 'Tên chủ sở hữu (vd: Anh Duy)', style: 'width: 100%; height: 38px; font-weight: 700; border-radius: 6px; margin-bottom: 10px;' });
        var emgPhoneInput = E('input', { type: 'text', class: 'cbi-input-text', value: sentinelConfig.emergency_phone || '', placeholder: 'SĐT khẩn cấp gọi/nhắn tin báo động (vd: 0912345678)', style: 'width: 100%; height: 38px; font-weight: 700; border-radius: 6px; margin-bottom: 10px;' });
        var cloudRemoteInput = E('input', { type: 'text', class: 'cbi-input-text', value: sentinelConfig.cloud_remote || '', placeholder: 'Tên Remote Cloud Rclone (vd: gdrive, onedrive)', style: 'width: 100%; height: 38px; font-weight: 700; border-radius: 6px; margin-bottom: 10px;' });

        function createMultiKeyManager(opts) {
            var items = (Array.isArray(opts.initial) && opts.initial.length > 0)
                ? opts.initial.map(function(x) { return { label: x.label || '', key: x.key || '' }; })
                : (opts.fallbackKey ? [{ label: opts.defaultPrefix + ' #1', key: opts.fallbackKey }] : [{ label: opts.defaultPrefix + ' #1', key: '' }]);
            var box = E('div', { style: 'display: flex; flex-direction: column; gap: 10px; margin-bottom: 12px;' });

            function redraw() {
                box.innerHTML = '';
                items.forEach(function(item, idx) {
                    var lblInput = E('input', {
                        type: 'text',
                        class: 'cbi-input-text',
                        value: item.label || (opts.defaultPrefix + ' #' + (idx + 1)),
                        placeholder: opts.labelPlaceholder,
                        style: 'width: 210px; height: 38px; font-weight: 750; border-radius: 6px; font-size: 13px;'
                    });
                    lblInput.addEventListener('input', function() {
                        items[idx].label = lblInput.value.trim();
                        if (opts.onChange) opts.onChange();
                    });

                    var keyInput = E('input', {
                        type: 'password',
                        class: 'cbi-input-text',
                        value: item.key || '',
                        placeholder: opts.keyPlaceholder,
                        style: 'flex: 1; min-width: 220px; height: 38px; font-weight: 700; font-family: monospace; border-radius: 6px; font-size: 12.5px;'
                    });
                    keyInput.addEventListener('input', function() {
                        items[idx].key = keyInput.value.trim();
                        if (opts.onChange) opts.onChange();
                    });

                    var toggleVisBtn = E('button', {
                        class: 'btn cbi-button',
                        style: 'font-size: 12px; font-weight: 700; padding: 6px 10px; border-radius: 6px; background: #f8fafc; border: 1px solid #cbd5e1; cursor: pointer;',
                        click: function() {
                            keyInput.type = (keyInput.type === 'password') ? 'text' : 'password';
                        }
                    }, '👁️');

                    var delBtn = E('button', {
                        class: 'btn cbi-button',
                        style: 'font-size: 12px; font-weight: 750; padding: 6px 12px; border-radius: 6px; background: #fee2e2; color: #b91c1c; border: 1px solid #fca5a5; cursor: pointer;',
                        click: function() {
                            if (items.length <= 1) {
                                items[0] = { label: opts.defaultPrefix + ' #1', key: '' };
                            } else {
                                items.splice(idx, 1);
                            }
                            redraw();
                            if (opts.onChange) opts.onChange();
                        }
                    }, '🗑️ Xóa');

                    box.appendChild(E('div', { style: 'display: flex; align-items: center; gap: 8px; background: #ffffff; padding: 10px 12px; border-radius: 8px; border: 1px solid #e2e8f0; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-weight: 750; font-size: 13px; color: #1e293b; min-width: 90px;' }, opts.icon + ' #' + (idx + 1) + ':'),
                        lblInput,
                        keyInput,
                        toggleVisBtn,
                        delBtn
                    ]));
                });
            }
            redraw();

            var addBtn = E('button', {
                class: 'btn cbi-button',
                style: 'font-size: 12.5px; font-weight: 750; padding: 7px 16px; border-radius: 6px; background: #eff6ff; color: #1d4ed8; border: 1.5px solid #93c5fd; cursor: pointer; display: inline-flex; align-items: center; gap: 6px;',
                click: function() {
                    items.push({ label: opts.defaultPrefix + ' #' + (items.length + 1), key: '' });
                    redraw();
                    if (opts.onChange) opts.onChange();
                }
            }, opts.addLabel);

            return {
                getItems: function() { return items; },
                setItems: function(arr, fb) {
                    if (Array.isArray(arr) && arr.length > 0) {
                        items = arr.map(function(x) { return { label: x.label || '', key: x.key || '' }; });
                    } else if (fb) {
                        items = [{ label: opts.defaultPrefix + ' #1', key: fb }];
                    } else {
                        items = [{ label: opts.defaultPrefix + ' #1', key: '' }];
                    }
                    redraw();
                },
                section: E('div', { style: 'border: 1px solid #f1f5f9; border-radius: 8px; padding: 16px; background: #fafafa; margin-bottom: 16px;' }, [
                    E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; flex-wrap: wrap; gap: 8px;' }, [
                        E('div', { style: 'font-weight: 800; font-size: 14.5px; color: #0f172a;' }, opts.title),
                        addBtn
                    ]),
                    E('div', { style: 'font-size: 12px; color: #64748b; margin-bottom: 10px;' }, opts.hint),
                    box
                ])
            };
        }

        // Quản Lý Camera IP Sentinel Mở Rộng Không Giới Hạn (Chỉ Cần Nhập IP Camera)
        var cameraList = [];
        if (sentinelConfig.cameras && Array.isArray(sentinelConfig.cameras) && sentinelConfig.cameras.length > 0) {
            cameraList = sentinelConfig.cameras.slice();
        } else {
            if (sentinelConfig.cam1_rtsp) cameraList.push(sentinelConfig.cam1_rtsp);
            if (sentinelConfig.cam2_rtsp) cameraList.push(sentinelConfig.cam2_rtsp);
            if (sentinelConfig.cam_cong_rtsp) cameraList.push(sentinelConfig.cam_cong_rtsp);
            if (cameraList.length === 0) {
                cameraList = ['192.168.1.100'];
            }
        }

        var cameraListContainer = E('div', { style: 'display: flex; flex-direction: column; gap: 10px; margin-bottom: 12px;' });

        function renderCameraList() {
            cameraListContainer.innerHTML = '';
            cameraList.forEach(function(camVal, idx) {
                var camInput = E('input', {
                    type: 'text',
                    class: 'cbi-input-text',
                    value: camVal || '',
                    placeholder: 'Nhập IP Camera (vd: 192.168.1.' + (100 + idx) + ') hoặc link RTSP',
                    style: 'flex: 1; height: 38px; font-weight: 700; border-radius: 6px; font-size: 13px;'
                });
                camInput.addEventListener('input', function() {
                    cameraList[idx] = camInput.value.trim();
                });

                var delBtn = E('button', {
                    class: 'btn cbi-button',
                    style: 'font-size: 12px; font-weight: 750; padding: 6px 12px; border-radius: 6px; background: #fee2e2; color: #b91c1c; border: 1px solid #fca5a5; cursor: pointer;',
                    click: function() {
                        if (cameraList.length <= 1) {
                            cameraList[0] = '';
                            renderCameraList();
                            return;
                        }
                        cameraList.splice(idx, 1);
                        renderCameraList();
                    }
                }, '🗑️ Xóa');

                var row = E('div', { style: 'display: flex; align-items: center; gap: 10px; background: #ffffff; padding: 8px 12px; border-radius: 6px; border: 1px solid #e2e8f0;' }, [
                    E('span', { style: 'font-weight: 750; font-size: 13px; color: #1e293b; min-width: 110px;' }, '📹 Camera #' + (idx + 1) + ':'),
                    camInput,
                    delBtn
                ]);
                cameraListContainer.appendChild(row);
            });
        }
        renderCameraList();

        var addCameraBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-size: 12.5px; font-weight: 750; padding: 7px 16px; border-radius: 6px; background: #f0fdf4; color: #166534; border: 1.5px solid #86efac; cursor: pointer; display: inline-flex; align-items: center; gap: 6px;',
            click: function() {
                var nextIp = '192.168.1.' + (100 + cameraList.length);
                cameraList.push(nextIp);
                renderCameraList();
            }
        }, '➕ Thêm Camera IP Mới');

        // Quản Lý Telegram Bot Không Giới Hạn (Đa Kênh / Đa Tài Khoản)
        var telegramBotsList = [];
        if (sentinelConfig.telegram_bots && Array.isArray(sentinelConfig.telegram_bots) && sentinelConfig.telegram_bots.length > 0) {
            telegramBotsList = sentinelConfig.telegram_bots.slice();
        } else {
            telegramBotsList = [
                { name: 'Bot Chính (Master)', token: sentinelConfig.tg_bot_token || '', chat_id: sentinelConfig.tg_admin_id || '' }
            ];
        }

        var telegramBotsContainer = E('div', { style: 'display: flex; flex-direction: column; gap: 10px; margin-bottom: 12px;' });

        function renderTelegramBotsList() {
            telegramBotsContainer.innerHTML = '';
            telegramBotsList.forEach(function(bot, idx) {
                var botNameInput = E('input', {
                    type: 'text',
                    class: 'cbi-input-text',
                    value: bot.name || ('Bot #' + (idx + 1)),
                    placeholder: 'Tên Bot / Mục Đích (vd: Bot Chính, Bot Báo Cháy)',
                    style: 'width: 210px; height: 38px; font-weight: 750; border-radius: 6px; font-size: 13px;'
                });
                botNameInput.addEventListener('input', function() {
                    telegramBotsList[idx].name = botNameInput.value.trim();
                });

                var botTokenInput = E('input', {
                    type: 'password',
                    class: 'cbi-input-text',
                    value: bot.token || '',
                    placeholder: 'Telegram Bot Token (vd: 7123456789:AAH...)',
                    style: 'flex: 2; min-width: 200px; height: 38px; font-weight: 700; font-family: monospace; border-radius: 6px; font-size: 12.5px;'
                });
                botTokenInput.addEventListener('input', function() {
                    telegramBotsList[idx].token = botTokenInput.value.trim();
                });

                var botChatIdInput = E('input', {
                    type: 'text',
                    class: 'cbi-input-text',
                    value: bot.chat_id || '',
                    placeholder: 'Chat ID / Group ID (vd: 123456789 hoặc -100...)',
                    style: 'flex: 1; min-width: 140px; height: 38px; font-weight: 700; font-family: monospace; border-radius: 6px; font-size: 12.5px;'
                });
                botChatIdInput.addEventListener('input', function() {
                    telegramBotsList[idx].chat_id = botChatIdInput.value.trim();
                });

                var visBtn = E('button', {
                    class: 'btn cbi-button',
                    style: 'font-size: 12px; font-weight: 700; padding: 6px 10px; border-radius: 6px; background: #f8fafc; border: 1px solid #cbd5e1; cursor: pointer;',
                    click: function() { botTokenInput.type = (botTokenInput.type === 'password') ? 'text' : 'password'; }
                }, '👁️');

                var testBtn = E('button', {
                    class: 'btn cbi-button',
                    style: 'font-size: 11.5px; font-weight: 700; padding: 6px 12px; border-radius: 6px; background: #eff6ff; color: #1d4ed8; border: 1px solid #bfdbfe; cursor: pointer; white-space: nowrap;',
                    click: function(ev) {
                        var curT = botTokenInput.value.trim();
                        var curC = botChatIdInput.value.trim();
                        var curN = botNameInput.value.trim() || ('Bot #' + (idx + 1));
                        if (!curT || !curC) {
                            alert('Vui lòng nhập Token và Chat ID trước khi test!');
                            return;
                        }
                        ev.target.textContent = '⏳ Đang gửi...';
                        ev.target.disabled = true;
                        callTestTelegram(curT, curC, curN).then(function(res) {
                            ev.target.textContent = '⚡ Test Bot';
                            ev.target.disabled = false;
                            if (res && res.success) {
                                ui.addNotification(null, E('p', '✅ ' + (res.message || 'Gửi tin test Telegram thành công!')), 'info');
                            } else {
                                ui.addNotification(null, E('p', '❌ ' + ((res && res.message) || 'Gửi Telegram thất bại!')), 'error');
                            }
                        }).catch(function(err) {
                            ev.target.textContent = '⚡ Test Bot';
                            ev.target.disabled = false;
                            ui.addNotification(null, E('p', '❌ Lỗi test Telegram: ' + err), 'error');
                        });
                    }
                }, '⚡ Test Bot');

                var delBtn = E('button', {
                    class: 'btn cbi-button',
                    style: 'font-size: 12px; font-weight: 750; padding: 6px 12px; border-radius: 6px; background: #fee2e2; color: #b91c1c; border: 1px solid #fca5a5; cursor: pointer;',
                    click: function() {
                        if (telegramBotsList.length <= 1) {
                            telegramBotsList[0] = { name: 'Bot Chính (Master)', token: '', chat_id: '' };
                            renderTelegramBotsList();
                            return;
                        }
                        telegramBotsList.splice(idx, 1);
                        renderTelegramBotsList();
                    }
                }, '🗑️ Xóa');

                telegramBotsContainer.appendChild(E('div', { style: 'display: flex; align-items: center; gap: 8px; background: #ffffff; padding: 10px 12px; border-radius: 8px; border: 1px solid #e2e8f0; flex-wrap: wrap;' }, [
                    E('span', { style: 'font-weight: 750; font-size: 13px; color: #1e293b; min-width: 85px;' }, '🤖 Bot #' + (idx + 1) + ':'),
                    botNameInput,
                    botTokenInput,
                    botChatIdInput,
                    visBtn,
                    testBtn,
                    delBtn
                ]));
            });
        }
        renderTelegramBotsList();

        var addTelegramBotBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-size: 12.5px; font-weight: 750; padding: 7px 16px; border-radius: 6px; background: #eff6ff; color: #1d4ed8; border: 1.5px solid #93c5fd; cursor: pointer; display: inline-flex; align-items: center; gap: 6px;',
            click: function() {
                telegramBotsList.push({
                    name: 'Bot #' + (telegramBotsList.length + 1),
                    token: '',
                    chat_id: ''
                });
                renderTelegramBotsList();
            }
        }, '➕ Thêm Telegram Bot Mới');

        var remoteBodyContainer = E('div', {});
        var geminiMgr = createMultiKeyManager({
            title: '🧠 Danh Sách Google Gemini AI API Key (Nhiều Tài Khoản / Không Giới Hạn)',
            hint: '💡 Thêm nhiều API Key từ các tài khoản Google khác nhau để dự phòng hạn mức khi chạy AI Sentinel.',
            defaultPrefix: 'Gemini Key',
            icon: '🧠',
            labelPlaceholder: 'Tên tài khoản / Ghi chú',
            keyPlaceholder: 'Google Gemini API Key (vd: AIza...)',
            addLabel: '➕ Thêm Gemini Key Mới',
            initial: sentinelConfig.gemini_keys,
            fallbackKey: sentinelConfig.gemini_api_key
        });
        var tailscaleMgr = createMultiKeyManager({
            title: '🛡️ Danh Sách Tailscale Auth Key (Nhiều Tài Khoản VPN / Không Giới Hạn)',
            hint: '💡 Lưu nhiều Tailscale Auth Key từ nhiều tailnet/tài khoản khác nhau và chọn nhanh ở mục Kết Nối Từ Xa bên dưới.',
            defaultPrefix: 'Tailscale Account',
            icon: '🛡️',
            labelPlaceholder: 'Tên tailnet / Tài khoản',
            keyPlaceholder: 'Tailscale Auth Key (vd: tskey-auth-...)',
            addLabel: '➕ Thêm Tailscale Key Mới',
            initial: sentinelConfig.tailscale_keys,
            fallbackKey: sentinelConfig.tailscale_auth_key,
            onChange: function() { if (typeof syncTsSelectOptions === 'function') syncTsSelectOptions(); }
        });

        // ---------------- KẾT NỐI TỪ XA HỢP NHẤT TRONG TAB 4 ----------------
        var tsSelect = E('select', { class: 'cbi-input-select', style: 'min-width: 220px; height: 36px; font-weight: 700; border-radius: 6px;' });
        var tsCustomInput = E('input', { type: 'password', class: 'cbi-input-text', placeholder: 'Hoặc dán Tailscale Auth Key khác...', style: 'min-width: 240px; height: 36px; border-radius: 6px;' });

        function syncTsSelectOptions() {
            var prev = tsSelect.value;
            tsSelect.innerHTML = '';
            var keys = tailscaleMgr.getItems().filter(function(x) { return (x.key || '').trim() !== ''; });
            if (keys.length === 0) {
                tsSelect.appendChild(E('option', { value: '' }, '-- Dùng Key mặc định trong Vault --'));
            } else {
                keys.forEach(function(x, i) {
                    var lbl = (x.label || ('Tailscale #' + (i + 1))) + ' (***' + x.key.slice(-4) + ')';
                    tsSelect.appendChild(E('option', { value: x.key }, lbl));
                });
            }
            if (prev) tsSelect.value = prev;
        }
        syncTsSelectOptions();

        function notifyRemote(r) {
            ui.addNotification(null, E('p', (r && (r.message || r.msg)) ? (r.message || r.msg) : 'Hoàn tất!'), (r && r.success) ? 'info' : 'error');
        }

        function refreshRemotePanel() {
            return callRemoteStatus().then(function(st) {
                remoteState = st || {};
                renderRemotePanel(remoteState);
            }).catch(function() {});
        }

        function renderRemotePanel(st) {
            st = st || {};
            syncTsSelectOptions();
            var funnelChk = E('input', { type: 'checkbox', checked: !!st.tailscale_funnel });
            var luciPortInput = E('input', { type: 'number', class: 'cbi-input-text', value: String(st.wan_luci_port || 80), min: '1', max: '65535', style: 'width: 90px; height: 34px; text-align: center; font-weight: 700;' });
            var sshPortInput = E('input', { type: 'number', class: 'cbi-input-text', value: String(st.wan_ssh_port || 22), min: '1', max: '65535', style: 'width: 90px; height: 34px; text-align: center; font-weight: 700;' });
            var tunDurInput = E('input', { type: 'number', class: 'cbi-input-text', value: '15', min: '1', max: '1440', style: 'width: 85px; height: 34px; text-align: center; font-weight: 700;' });
            var tunnelLinkNode = st.tunnel_url
                ? E('a', { href: st.tunnel_url, target: '_blank', style: 'font-weight: 700; color: #2563eb;' }, st.tunnel_url)
                : E('span', { style: 'color: #64748b;' }, 'Chưa mở');

            remoteBodyContainer.innerHTML = '';
            var children = [];
            if (st.has_root_password === false) {
                children.push(E('div', { style: 'background: #fef3c7; border: 1px solid #f59e0b; color: #92400e; padding: 10px 14px; border-radius: 8px; font-weight: 700; font-size: 13px;' }, '⚠️ Router chưa đặt mật khẩu root! Hãy vào Hệ thống -> Quản trị đặt mật khẩu trước khi bật Funnel HTTPS, Tunnel hoặc mở cổng WAN.'));
            }
            children.push(
                E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 14px;' }, [
                    E('div', { style: 'font-weight: 750; color: #0f172a; margin-bottom: 6px;' }, '1️⃣ Tailscale VPN & Kết Nối Máy Ảo Debian: ' + (st.tailscale_installed ? (st.tailscale_up ? ('🟢 Đang kết nối (' + (st.tailscale_ip || '-') + (st.tailscale_dns ? (' | ' + st.tailscale_dns) : '') + ')') : '🟡 Đã cài sẵn (Chưa bật)') : '⚙️ Chưa có sẵn binary — tự động tải, cài đặt & nối máy ảo khi bấm hoặc khi có Key trong Vault')),
                    E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center;' }, [
                        tsSelect,
                        tsCustomInput,
                        E('label', { style: 'display: inline-flex; align-items: center; gap: 5px; font-weight: 600;' }, [ funnelChk, 'Bật Funnel HTTPS' ]),
                        E('button', {
                            class: 'btn cbi-button cbi-button-apply',
                            click: function(ev) {
                                var chosenKey = tsCustomInput.value.trim() || tsSelect.value.trim();
                                var btn = ev.target;
                                btn.disabled = true;
                                btn.textContent = '⏳ Đang cài & kết nối...';
                                return callTailscaleUp(chosenKey, funnelChk.checked).then(function(r) {
                                    btn.disabled = false;
                                    btn.textContent = '🚀 Tự Cài & Kết Nối Tailscale';
                                    notifyRemote(r);
                                    refreshRemotePanel();
                                }).catch(function(err) {
                                    btn.disabled = false;
                                    btn.textContent = '🚀 Tự Cài & Kết Nối Tailscale';
                                    ui.addNotification(null, E('p', '❌ Lỗi: ' + err), 'error');
                                });
                            }
                        }, '🚀 Tự Cài & Kết Nối Tailscale'),
                        E('button', {
                            class: 'btn cbi-button cbi-button-reset',
                            click: function() { return callTailscaleDown().then(function(r) { notifyRemote(r); refreshRemotePanel(); }); }
                        }, '⏹️ Tắt Tailscale')
                    ])
                ]),
                E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px;' }, [
                    E('div', { style: 'font-weight: 750; color: #0f172a;' }, '2️⃣ Tự Mở Port Firewall WAN (LuCI / SSH — Nhớ đặt mật khẩu root trước khi mở!):'),
                    E('div', { style: 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap;' }, [
                        E('span', { style: 'min-width: 130px; font-weight: 600;' }, 'Web LuCI WAN:'),
                        luciPortInput,
                        E('span', { style: 'font-weight: 700; color: ' + (st.wan_luci_open ? '#16a34a' : '#64748b') + ';' }, st.wan_luci_open ? '🟢 Đang MỞ' : '⚪ Đang ĐÓNG'),
                        E('button', {
                            class: 'btn cbi-button ' + (st.wan_luci_open ? 'cbi-button-reset' : 'cbi-button-apply'),
                            click: function() { return callToggleWanPort('luci', !st.wan_luci_open, parseInt(luciPortInput.value, 10) || 80).then(function(r) { notifyRemote(r); refreshRemotePanel(); }); }
                        }, st.wan_luci_open ? '🔒 Đóng Port Web' : '🔓 Mở Port Web')
                    ]),
                    E('div', { style: 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap;' }, [
                        E('span', { style: 'min-width: 130px; font-weight: 600;' }, 'SSH Terminal WAN:'),
                        sshPortInput,
                        E('span', { style: 'font-weight: 700; color: ' + (st.wan_ssh_open ? '#16a34a' : '#64748b') + ';' }, st.wan_ssh_open ? '🟢 Đang MỞ' : '⚪ Đang ĐÓNG'),
                        E('button', {
                            class: 'btn cbi-button ' + (st.wan_ssh_open ? 'cbi-button-reset' : 'cbi-button-apply'),
                            click: function() { return callToggleWanPort('ssh', !st.wan_ssh_open, parseInt(sshPortInput.value, 10) || 22).then(function(r) { notifyRemote(r); refreshRemotePanel(); }); }
                        }, st.wan_ssh_open ? '🔒 Đóng Port SSH' : '🔓 Mở Port SSH')
                    ])
                ]),
                E('div', { style: 'background: #ffffff; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 14px;' }, [
                    E('div', { style: 'font-weight: 750; color: #0f172a; margin-bottom: 6px;' }, [
                        '3️⃣ Đường Hầm Tạm Thời (Tunnel): ',
                        E('span', { style: 'font-weight: 600;' }, (st.tunnel_status || 'STOPPED') + (st.tunnel_type ? (' (' + st.tunnel_type + ', còn ~' + (st.tunnel_remaining || 0) + ' phút)') : '') + '  |  '),
                        tunnelLinkNode
                    ]),
                    E('div', { style: 'display: flex; gap: 8px; align-items: center; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-weight: 600;' }, 'Thời lượng (phút):'),
                        tunDurInput,
                        E('button', {
                            class: 'btn cbi-button cbi-button-apply',
                            click: function() {
                                return callStartTunnel(parseInt(tunDurInput.value, 10) || 15).then(function(r) {
                                    if (r && r.url) ui.addNotification(null, E('p', '✅ Đã mở Tunnel: ' + r.url), 'info');
                                    else ui.addNotification(null, E('p', (r && r.msg) || 'Không thể khởi tạo Tunnel!'), 'error');
                                    refreshRemotePanel();
                                });
                            }
                        }, '🌐 Mở Tunnel Tạm Thời'),
                        E('button', {
                            class: 'btn cbi-button cbi-button-reset',
                            click: function() { return callStopTunnel().then(function(r) { notifyRemote(r); refreshRemotePanel(); }); }
                        }, '⏹️ Đóng Tunnel')
                    ])
                ])
            );
            remoteBodyContainer.appendChild(E('div', { style: 'display: flex; flex-direction: column; gap: 12px;' }, children));
        }
        renderRemotePanel(remoteState);

        var saveAllSentinelBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 13px; padding: 9px 22px; border-radius: 6px;',
            click: function() {
                var t_own = teleOwnerInput.value.trim() || 'Anh Duy';
                var t_emg = emgPhoneInput.value.trim();
                var t_cl = cloudRemoteInput.value.trim();

                var cleanCameras = [];
                cameraList.forEach(function(c) {
                    var s = (c || '').trim();
                    if (s) cleanCameras.push(s);
                });

                var cleanBots = [];
                telegramBotsList.forEach(function(b) {
                    var n = (b.name || '').trim();
                    var t = (b.token || '').trim();
                    var c = (b.chat_id || '').trim();
                    if (t && c) cleanBots.push({ name: n, token: t, chat_id: c });
                });

                var cleanGemini = [];
                geminiMgr.getItems().forEach(function(g, i) {
                    var k = (g.key || '').trim();
                    var l = (g.label || '').trim() || ('Gemini #' + (i + 1));
                    if (k) cleanGemini.push({ label: l, key: k });
                });

                var cleanTailscale = [];
                tailscaleMgr.getItems().forEach(function(t, i) {
                    var k = (t.key || '').trim();
                    var l = (t.label || '').trim() || ('Tailscale #' + (i + 1));
                    if (k) cleanTailscale.push({ label: l, key: k });
                });

                var t_tok = cleanBots.length > 0 ? cleanBots[0].token : '';
                var t_adm = cleanBots.length > 0 ? cleanBots[0].chat_id : '';
                var t_gem = cleanGemini.length > 0 ? cleanGemini[0].key : '';
                var t_ts = cleanTailscale.length > 0 ? cleanTailscale[0].key : '';

                saveAllSentinelBtn.textContent = '⏳ Đang lưu cấu hình...';
                callSetSentinelConfig(t_tok, t_adm, t_own, t_emg, t_gem, t_ts, t_cl, cleanBots, cleanGemini, cleanTailscale, cleanCameras).then(function(r) {
                    saveAllSentinelBtn.textContent = '💾 Lưu Toàn Bộ Kho Key, Sentinel & Từ Xa';
                    syncTsSelectOptions();
                    ui.addNotification(null, E('p', (r && r.message) || '✅ Đã lưu toàn bộ Kho Key đa tài khoản thành công!'), 'info');
                }).catch(function(err) {
                    saveAllSentinelBtn.textContent = '💾 Lưu Toàn Bộ Kho Key, Sentinel & Từ Xa';
                    ui.addNotification(null, E('p', '❌ Lỗi lưu cấu hình: ' + err), 'error');
                });
            }
        }, '💾 Lưu Toàn Bộ Kho Key, Sentinel & Từ Xa');

        var loadVaultBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 750; font-size: 13px; padding: 9px 18px; border-radius: 6px; background: #f0fdf4; color: #166534; border: 1.5px solid #86efac; cursor: pointer;',
            click: function() {
                loadVaultBtn.textContent = '⏳ Đang nạp Vault...';
                callLoadVaultKeys().then(function(r) {
                    loadVaultBtn.textContent = '⚡ Nạp Lại Toàn Bộ Key Từ Vault';
                    if (r && r.success) {
                        if (r.tg_owner_name) teleOwnerInput.value = r.tg_owner_name;
                        emgPhoneInput.value = r.emergency_phone || '';
                        cloudRemoteInput.value = r.cloud_remote || '';
                        if (r.cameras && Array.isArray(r.cameras) && r.cameras.length > 0) {
                            cameraList = r.cameras.slice();
                            renderCameraList();
                        }
                        if (r.telegram_bots && Array.isArray(r.telegram_bots) && r.telegram_bots.length > 0) {
                            telegramBotsList = r.telegram_bots.slice();
                        } else if (r.tg_bot_token || r.tg_admin_id) {
                            telegramBotsList = [{ name: 'Bot Chính (Master)', token: r.tg_bot_token || '', chat_id: r.tg_admin_id || '' }];
                        }
                        renderTelegramBotsList();
                        geminiMgr.setItems(r.gemini_keys, r.gemini_api_key);
                        tailscaleMgr.setItems(r.tailscale_keys, r.tailscale_auth_key);
                        syncTsSelectOptions();
                        ui.addNotification(null, E('p', '✅ Đã nạp đầy đủ Key đa tài khoản từ Vault an toàn!'), 'info');
                    } else {
                        ui.addNotification(null, E('p', '⚠️ Chưa tìm thấy dữ liệu Vault trên thiết bị.'), 'warning');
                    }
                }).catch(function(err) {
                    loadVaultBtn.textContent = '⚡ Nạp Lại Toàn Bộ Key Từ Vault';
                    ui.addNotification(null, E('p', '❌ Lỗi nạp Vault: ' + err), 'error');
                });
            }
        }, '⚡ Nạp Lại Toàn Bộ Key Từ Vault');

        var sentinelTabContent = E('div', { class: 'cbi-section', style: 'display: none; padding: 20px; background: #ffffff; border-radius: 10px; border: 1px solid #e2e8f0;' }, [
            E('h3', { style: 'margin-top: 0; font-size: 18px; font-weight: 800; color: #1e293b; border-bottom: 1px solid #f1f5f9; padding-bottom: 10px;' }, '🤖 Telegram, AI Sentinel, Kho Key Đa Tài Khoản & Kết Nối Từ Xa'),
            E('div', { style: 'border: 1px solid #f1f5f9; border-radius: 8px; padding: 16px; background: #fafafa; margin-bottom: 14px;' }, [
                E('div', { style: 'font-weight: 800; font-size: 14.5px; margin-bottom: 12px; color: #0f172a; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px;' }, '🔑 Thông Tin Chủ Sở Hữu & Hệ Thống (Zero-Leak Vault):'),
                E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px;' }, [
                    E('div', {}, [
                        E('div', { style: 'font-weight: 750; font-size: 13px; margin-bottom: 4px; color: #334155;' }, '👑 Tên Router / Chủ Sở Hữu:'),
                        teleOwnerInput
                    ]),
                    E('div', {}, [
                        E('div', { style: 'font-weight: 750; font-size: 13px; margin-bottom: 4px; color: #334155;' }, '📞 SĐT Khẩn Cấp Báo Động (SMS/Call):'),
                        emgPhoneInput
                    ]),
                    E('div', {}, [
                        E('div', { style: 'font-weight: 750; font-size: 13px; margin-bottom: 4px; color: #334155;' }, '☁️ Rclone Cloud Storage Remote:'),
                        cloudRemoteInput
                    ])
                ])
            ]),
            E('div', { style: 'border: 1px solid #f1f5f9; border-radius: 8px; padding: 16px; background: #fafafa; margin-bottom: 16px;' }, [
                E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; flex-wrap: wrap; gap: 8px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 14.5px; color: #0f172a;' }, '🤖 Quản Lý Telegram Bot & Tài Khoản Cảnh Báo (Không Giới Hạn):'),
                    addTelegramBotBtn
                ]),
                E('div', { style: 'font-size: 12px; color: #64748b; margin-bottom: 10px;' }, '💡 Hỗ trợ thêm nhiều Bot / Chat ID độc lập cho từng mục đích hoặc từng nhóm quản trị.'),
                telegramBotsContainer
            ]),
            geminiMgr.section,
            tailscaleMgr.section,
            E('div', { style: 'border: 1px solid #f1f5f9; border-radius: 8px; padding: 16px; background: #fafafa; margin-bottom: 16px;' }, [
                E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px; flex-wrap: wrap; gap: 8px;' }, [
                    E('div', { style: 'font-weight: 800; font-size: 14.5px; color: #0f172a;' }, '📹 Quản Lý Camera IP Sentinel (Mở Rộng Không Giới Hạn):'),
                    addCameraBtn
                ]),
                E('div', { style: 'font-size: 12px; color: #64748b; margin-bottom: 10px;' }, '💡 Chỉ cần nhập địa chỉ IP của Camera (ví dụ: 192.168.1.100) hoặc link luồng RTSP.'),
                cameraListContainer
            ]),
            E('div', { style: 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-bottom: 18px;' }, [
                saveAllSentinelBtn,
                loadVaultBtn
            ]),
            E('div', { style: 'border: 1px solid #dbeafe; border-radius: 8px; padding: 16px; background: #f8fafc;' }, [
                E('div', { style: 'font-weight: 800; font-size: 15px; color: #0f172a; margin-bottom: 12px; border-bottom: 1px solid #e2e8f0; padding-bottom: 6px;' }, '🌐 Kết Nối Từ Xa, Tailscale & Mở Port An Toàn'),
                remoteBodyContainer
            ])
        ]);
        return sentinelTabContent;
    }
});
// [/VERIFIED-GOLDEN]
