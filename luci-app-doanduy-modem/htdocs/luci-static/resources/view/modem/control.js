// Standalone View for Modem 5G Utilities in Stock or Any Theme
'use strict';
'require view';
'require rpc';
'require ui';
'require poll';
'require doanduy.smarthome as smarthome';

// RPC Declarations
var callSMSInfo = rpc.declare({ object: 'luci.sms-status', method: 'getSMSInfo', expect: { } });
var callFetchSMS = rpc.declare({ object: 'luci.sms-status', method: 'fetchSMSNow', expect: { } });
var callDeleteAllSMS = rpc.declare({ object: 'luci.sms-status', method: 'deleteAllSMS', expect: { } });
var callDeleteSingleSMS = rpc.declare({ object: 'luci.sms-status', method: 'deleteSingleSMS', params: ['indices', 'storage'], expect: { } });
var callSendSMS = rpc.declare({ object: 'luci.sms-status', method: 'sendSMS', params: ['target', 'msg'] });
var callSendAT = rpc.declare({ object: 'luci.sms-status', method: 'sendAT', params: ['cmd', 'port'] });
var callSetPort = rpc.declare({ object: 'luci.sms-status', method: 'setCustomAtPort', params: ['port'] });
var callGetPorts = rpc.declare({ object: 'luci.sms-status', method: 'getAvailablePorts', expect: { } });
var callCheckDataBalance = rpc.declare({ object: 'luci.sms-status', method: 'checkDataBalance', expect: { } });
var callSetBandLock = rpc.declare({ object: 'luci.sms-status', method: 'setBandLock', params: ['mode'] });
var callGetCellInfo = rpc.declare({ object: 'luci.sms-status', method: 'getCellInfo', expect: { } });
var callSetCellLock = rpc.declare({ object: 'luci.sms-status', method: 'setCellLock', params: ['action'], expect: { } });
var callGetBandState = rpc.declare({ object: 'luci.sms-status', method: 'getBandState', expect: { } });
var callSetCustomBands = rpc.declare({ object: 'luci.sms-status', method: 'setCustomBands', params: ['rat', 'lte_bands', 'nr_bands'], expect: { } });
var callSetCustomSchedule = rpc.declare({ object: 'luci.sms-status', method: 'setCustomSchedule', params: ['datetime'] });
var callSimGetState = rpc.declare({ object: 'doanduy.sim', method: 'getState', expect: { } });
var callSimSaveTime = rpc.declare({ object: 'doanduy.sim', method: 'saveTime', params: ['time'], expect: { } });
var callSimSavePackage = rpc.declare({ object: 'doanduy.sim', method: 'savePackage', params: ['package', 'dest'], expect: { } });
var callSimTestSendNow = rpc.declare({ object: 'doanduy.sim', method: 'testSendNow', expect: { } });

var callChangeIMEI = rpc.declare({ object: 'doanduy.rf', method: 'changeIMEI', params: ['imei', 'brand'] });
var callRestoreIMEI = rpc.declare({ object: 'doanduy.rf', method: 'restoreIMEI', expect: { } });
var callRfStatus = rpc.declare({ object: 'doanduy.rf', method: 'getStatus', expect: { } });
var callSetTelegramToken = rpc.declare({ object: 'doanduy.vault', method: 'save', params: ['tg_bot_token', 'tg_admin_id', 'tg_owner_name'] });
var callGetSentinelConfig = rpc.declare({ object: 'doanduy.vault', method: 'get', expect: { } });
var callSetSentinelConfig = rpc.declare({ object: 'doanduy.vault', method: 'save', params: ['tg_bot_token', 'tg_admin_id', 'tg_owner_name', 'emergency_phone', 'gemini_api_key', 'tailscale_auth_key', 'cloud_remote', 'telegram_bots', 'gemini_keys', 'tailscale_keys', 'cameras'] });
var callLoadVaultKeys = rpc.declare({ object: 'doanduy.vault', method: 'get', expect: { } });
var callTestTelegram = rpc.declare({ object: 'doanduy.vault', method: 'testTelegram', params: ['token', 'chat_id', 'name'], expect: { } });

var callRemoteStatus = rpc.declare({ object: 'doanduy.remote', method: 'status', expect: { } });
var callTailscaleUp = rpc.declare({ object: 'doanduy.remote', method: 'tailscaleUp', params: ['authkey', 'enable_funnel'], expect: { } });
var callTailscaleDown = rpc.declare({ object: 'doanduy.remote', method: 'tailscaleDown', expect: { } });
var callToggleWanPort = rpc.declare({ object: 'doanduy.remote', method: 'toggleWanPort', params: ['service', 'enable', 'port'], expect: { } });
var callStartTunnel = rpc.declare({ object: 'doanduy.remote', method: 'startTunnel', params: ['duration'], expect: { } });
var callStopTunnel = rpc.declare({ object: 'doanduy.remote', method: 'stopTunnel', expect: { } });

var callSetTTL = rpc.declare({ object: 'doanduy.rf', method: 'setTTL', params: ['ttl'] });
var callSetCard = rpc.declare({ object: 'luci.sms-status', method: 'setCardMode', params: ['mode', 'iface_name'], expect: { } });
var callRenameInterface = rpc.declare({ object: 'luci.sms-status', method: 'renameInterface', params: ['new_name'], expect: { } });

function parseAndRenderSMS(rawText) {
    if (!rawText || typeof rawText !== 'string' || (!rawText.match(/MSG:\s*[0-9]+/i) && !rawText.match(/Tin nhắn\s*#[0-9]+/i))) {
        return [ E('div', { style: 'padding: 24px; text-align: center; color: #475569; font-size: 14px; background: #f8fafc; border-radius: 10px; border: 1px dashed #cbd5e1;' }, '📭 Hộp thư trống hoặc chưa có tin nhắn mới.') ];
    }
    var lines = rawText.split('\n'), rawMessages = [], curMsg = null, curStorage = 'Router (ME)';
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i], trimmed = line.trim();
        if (/\[.*(SIM|\(SM\)).*\]/i.test(trimmed)) { curStorage = 'Thẻ SIM (SM)'; continue; }
        else if (/\[.*(ROUTER|MODEM|\(ME\)|\(MT\)).*\]/i.test(trimmed)) { curStorage = 'Router (ME)'; continue; }

        var pcieMatch = trimmed.match(/^\[\s*Tin nhắn\s*#([0-9]+)\s*từ\s*([^(\]]+)\s*\(([^)]*)\)\s*\]/i);
        if (pcieMatch) {
            if (curMsg) rawMessages.push(curMsg);
            curMsg = {
                id: pcieMatch[1].trim(),
                storage: curStorage,
                from: pcieMatch[2].trim(),
                datetime: pcieMatch[3].trim(),
                refNum: '',
                segIndex: 1,
                segTotal: 1,
                contentLines: []
            };
            continue;
        }

        if (trimmed.match(/^MSG:\s*[0-9]+/i)) {
            if (curMsg) rawMessages.push(curMsg);
            curMsg = {
                id: trimmed.replace(/^MSG:\s*/i, '').trim(),
                storage: curStorage,
                from: 'Không xác định',
                datetime: '',
                refNum: '',
                segIndex: 1,
                segTotal: 1,
                contentLines: []
            };
            continue;
        }
        if (!curMsg) continue;
        if (trimmed.match(/^From:\s*/i)) curMsg.from = trimmed.replace(/^From:\s*/i, '').trim();
        else if (trimmed.match(/^Date\/Time:\s*/i)) curMsg.datetime = trimmed.replace(/^Date\/Time:\s*/i, '').trim();
        else if (trimmed.match(/^Reference number:\s*/i)) curMsg.refNum = trimmed.replace(/^Reference number:\s*/i, '').trim();
        else if (trimmed.match(/^SMS segment\s*[0-9]+/i)) {
            var segMatch = trimmed.match(/^SMS segment\s*([0-9]+)(?:\s*(?:of|\/)\s*([0-9]+))?/i);
            if (segMatch) {
                curMsg.segIndex = parseInt(segMatch[1]);
                curMsg.segTotal = segMatch[2] ? parseInt(segMatch[2]) : 3;
            }
        } else { curMsg.contentLines.push(line); }
    }
    if (curMsg) rawMessages.push(curMsg);

    // Grouping & Merging Multipart SMS
    var mergedMap = {}, standaloneList = [];
    rawMessages.forEach(function(m) {
        m.body = m.contentLines.join(' ')
            .replace(/^SMS segment\s*[0-9]*\s*(?:of\s*[0-9]+)?/i, '')
            .replace(/(\w+)-\s+(\w+)/g, '$1$2')
            .replace(/\s+/g, ' ')
            .trim();

        var ts = 0;
        if (m.datetime) {
            var dtParts = m.datetime.replace(/,/g, ' ').split(/\s+/);
            if (dtParts.length >= 2) {
                var dParts = dtParts[0].split(/[\/\-]/);
                var tParts = dtParts[1].split(':');
                if (dParts.length === 3 && tParts.length >= 2) {
                    var yr, mo, da;
                    if (parseInt(dParts[0]) > 1000) {
                        yr = parseInt(dParts[0]);
                        mo = parseInt(dParts[1]) - 1;
                        da = parseInt(dParts[2]);
                    } else {
                        yr = parseInt(dParts[2]) > 50 ? 1900 + parseInt(dParts[2]) : 2000 + parseInt(dParts[2]);
                        mo = parseInt(dParts[0]) - 1;
                        da = parseInt(dParts[1]);
                    }
                    var hr = parseInt(tParts[0]);
                    var mi = parseInt(tParts[1]);
                    var sc = parseInt(tParts[2] || 0);
                    ts = new Date(yr, mo, da, hr, mi, sc).getTime();
                }
            }
        }
        if (!ts) ts = parseInt(m.id) || 0;
        m.ts = ts;

        var key = '';
        if (m.refNum) {
            key = m.from + '_' + m.refNum;
        } else if (m.segTotal > 1) {
            key = m.from + '_tot' + m.segTotal;
        }

        if (key) {
            if (!mergedMap[key]) {
                mergedMap[key] = { from: m.from, storage: m.storage, datetime: m.datetime, ts: m.ts, parts: {}, rawIds: [] };
            }
            if (m.body && !/^SMS segment\s*[0-9]*$/i.test(m.body)) {
                mergedMap[key].parts[m.segIndex] = m.body;
            }
            mergedMap[key].rawIds.push(m.id);
            if (m.ts > mergedMap[key].ts) {
                mergedMap[key].ts = m.ts;
                mergedMap[key].datetime = m.datetime;
            }
        } else if (m.body && !/^SMS segment\s*[0-9]*$/i.test(m.body)) {
            var cleanText = m.body.replace(/\\n/g, '\n').replace(/\\r/g, '').replace(/\\"/g, '"').trim();
            standaloneList.push({ from: m.from, storage: m.storage, datetime: m.datetime, ts: m.ts, rawIds: [m.id], fullBody: cleanText });
        }
    });

    var finalSMSList = [];
    Object.keys(mergedMap).forEach(function(k) {
        var item = mergedMap[k];
        var sortedIndices = Object.keys(item.parts).sort(function(a, b) { return parseInt(a) - parseInt(b); });
        var full = '';
        sortedIndices.forEach(function(idx) {
            full = (full ? full + '\n' : '') + item.parts[idx];
        });
        item.fullBody = full.replace(/\\n/g, '\n').replace(/\\r/g, '').replace(/\\"/g, '"').trim();
        finalSMSList.push(item);
    });

    standaloneList.forEach(function(s) { finalSMSList.push(s); });
    finalSMSList.sort(function(a, b) { return b.ts - a.ts; });

    if (finalSMSList.length === 0) {
        return [ E('div', { style: 'padding: 24px; text-align: center; color: #475569; font-size: 14px; background: #f8fafc; border-radius: 10px; border: 1px dashed #cbd5e1;' }, '📭 Hộp thư trống hoặc chưa có tin nhắn mới.') ];
    }

    var cards = [];
    finalSMSList.forEach(function(item) {
        var isSim = (item.storage && item.storage.indexOf('SIM') !== -1);
        var badgeColor = isSim ? '#2563eb' : '#d97706';
        var badgeBg = isSim ? '#eff6ff' : '#fffbeb';
        var badgeBorder = isSim ? '#bfdbfe' : '#fde68a';
        var badgeIcon = isSim ? '📱' : '💾';
        var badgeText = isSim ? 'Thẻ SIM (SM)' : 'Router (ME)';

        var row = E('div', {
            style: 'background: #ffffff; border: 1.5px solid #e2e8f0; border-radius: 10px; padding: 14px 18px; display: flex; flex-direction: column; gap: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); margin-bottom: 8px;'
        }, [
            E('div', { style: 'display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px;' }, [
                E('div', { style: 'display: flex; align-items: center; gap: 8px;' }, [
                    E('span', {
                        style: 'display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: 6px; font-size: 11.5px; font-weight: 750; background: ' + badgeBg + '; color: ' + badgeColor + '; border: 1px solid ' + badgeBorder + ';'
                    }, [ badgeIcon + ' ' + badgeText ]),
                    E('span', { style: 'font-weight: 850; font-size: 14px; color: #0f172a;' }, 'Từ: ' + item.from)
                ]),
                E('span', { style: 'font-size: 12px; color: #64748b; font-weight: 600;' }, item.datetime || 'Vừa xong')
            ]),
            E('div', {
                style: 'font-size: 13.5px; color: #1e293b; line-height: 1.6; white-space: pre-wrap; word-break: break-word; background: #f8fafc; padding: 12px 14px; border-radius: 6px; border: 1px solid #f1f5f9; font-weight: 550;'
            }, item.fullBody || '(Không có nội dung)'),
            E('div', { style: 'display: flex; justify-content: flex-end; gap: 8px;' }, [
                E('button', {
                    class: 'btn cbi-button',
                    style: 'font-size: 11.5px; padding: 3px 10px; font-weight: 700; border-radius: 6px; background: #f1f5f9; color: #334155; border: 1px solid #cbd5e1; cursor: pointer;',
                    click: function() {
                        var textToCopy = item.fullBody || '';
                        if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
                            navigator.clipboard.writeText(textToCopy).then(function() {
                                ui.addNotification(null, E('p', '📋 Đã sao chép nội dung tin nhắn!'), 'info');
                            });
                        } else {
                            var ta = document.createElement('textarea');
                            ta.value = textToCopy;
                            document.body.appendChild(ta);
                            ta.select();
                            document.execCommand('copy');
                            document.body.removeChild(ta);
                            ui.addNotification(null, E('p', '📋 Đã sao chép nội dung tin nhắn!'), 'info');
                        }
                    }
                }, '📋 Sao Chép'),
                E('button', {
                    class: 'btn cbi-button cbi-button-remove',
                    style: 'font-size: 11.5px; padding: 3px 10px; font-weight: 700; border-radius: 6px;',
                    click: function(ev) {
                        var idStr = item.rawIds.join(',');
                        var storeCode = isSim ? 'SM' : 'ME';
                        if (!confirm('Xóa tin nhắn này (' + idStr + ')?')) return;
                        callDeleteSingleSMS(idStr, storeCode).then(function() {
                            row.remove();
                            var box = document.getElementById('modem-ctrl-sms-inbox');
                            if (box) callFetchSMS().then(function(rep) { box.innerHTML = ''; parseAndRenderSMS(rep.inbox || '').forEach(function(n) { box.appendChild(n); }); });
                        });
                    }
                }, '🗑️ Xóa')
            ])
        ]);
        cards.push(row);
    });
    return cards;
}

return view.extend({
    title: _('Tiện Ích 5G & Quản Trị Modem'),

    load: function() {
        return Promise.all([
            callSMSInfo().catch(function() { return {}; }),
            callGetPorts().catch(function() { return {}; }),
            callGetCellInfo().catch(function() { return {}; }),
            callSimGetState().catch(function() { return {}; }),
            callGetSentinelConfig().catch(function() { return {}; }),
            callRemoteStatus().catch(function() { return {}; }),
            callRfStatus().catch(function() { return {}; })
        ]);
    },

    render: function(data) {
        var smsRes = data[0] || {};
        var portsData = data[1] || {};
        var cellRes = data[2] || {};
        var simMgrData = data[3] || {};
        var sentinelConfig = data[4] || {};
        var remoteState = data[5] || {};
        var rfStatus = data[6] || {};

        var activePort = (portsData && portsData.current_port && portsData.current_port.indexOf('/dev/') !== -1)
            ? portsData.current_port
            : ((smsRes && smsRes.port && smsRes.port.indexOf('/dev/') !== -1)
                ? smsRes.port
                : '/dev/wwan0at0');
        var currentTab = 'sms';

        var tabButtons = [
            { id: 'tab-btn-sms', key: 'sms', icon: '📬', title: 'Quản Lý SIM & Tin Nhắn SMS' },
            { id: 'tab-btn-modem', key: 'modem', icon: '📶', title: 'Modem 5G, Băng Tần & Lệnh AT' },
            { id: 'tab-btn-sentinel', key: 'sentinel', icon: '🤖', title: 'Telegram, AI & Từ Xa' },
            { id: 'tab-btn-smarthome', key: 'smarthome', icon: '🏠', title: 'Thiết Bị Điều Khiển Nhà' }
        ];

        var tabPanes = {};

        function switchSubTab(targetKey) {
            currentTab = targetKey;
            tabButtons.forEach(function(b) {
                var btnEl = document.getElementById(b.id);
                var paneEl = tabPanes[b.key];
                if (btnEl && paneEl) {
                    if (b.key === targetKey) {
                        btnEl.style.background = '#2563eb';
                        btnEl.style.color = '#ffffff';
                        btnEl.style.borderColor = '#2563eb';
                        paneEl.style.display = 'block';
                    } else {
                        btnEl.style.background = '#ffffff';
                        btnEl.style.color = '#334155';
                        btnEl.style.borderColor = '#cbd5e1';
                        paneEl.style.display = 'none';
                    }
                }
            });
        }

        var navBar = E('div', {
            style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 20px; padding-bottom: 12px; border-bottom: 2px solid #e2e8f0;'
        });

        tabButtons.forEach(function(b) {
            var btn = E('button', {
                id: b.id,
                class: 'btn',
                style: 'display: flex; align-items: center; gap: 6px; padding: 9px 18px; font-weight: 750; font-size: 13.5px; border-radius: 8px; border: 1.5px solid #cbd5e1; cursor: pointer; transition: all 0.2s; background: #ffffff; color: #334155;',
                click: function() { switchSubTab(b.key); }
            }, [ E('span', { style: 'font-size: 16px;' }, b.icon), b.title ]);
            navBar.appendChild(btn);
        });

        // ---------------- TAB 1: QUẢN LÝ SIM & SMS ----------------
        var isMasked = true;
        var activeIccidFull = simMgrData.active_iccid || '';
        var activeIccidMasked = simMgrData.masked_iccid || (activeIccidFull ? activeIccidFull.substring(0, 6) + '******' + activeIccidFull.substring(activeIccidFull.length - 4) : 'Chưa nhận diện');
        /* ==============================================================================
   === LOCKED: VERIFIED BY DOANDUY - DO NOT MODIFY ===
   QUY CHUẨN ĐIỀU KIỆN SIM HỢP LỆ TRÊN CONTROL.JS:
   NẾU KHÔNG CÓ SIM HOẶC SIM NGOÀI DANH MỤC -> isWhitelisted = false -> ẨN 100% CẤU HÌNH TỰ ĐỘNG!
   ============================================================================== */
        var hasValidIccid = !!(simMgrData.active_iccid && simMgrData.active_iccid !== 'Chưa phát hiện' && simMgrData.active_iccid !== 'Chua phat hien' && simMgrData.active_iccid.trim() !== '');
        var isWhitelisted = (typeof simMgrData.is_whitelisted === 'boolean') ? !!(simMgrData.is_whitelisted && hasValidIccid) : !!(smsRes && smsRes.is_authenticated === 1 && hasValidIccid);

        var iccidTextSpan = E('span', {
            id: 'modem-active-iccid-span',
            style: 'font-size: 13px; font-weight: 750; font-family: monospace; background: #f1f5f9; padding: 4px 10px; border-radius: 4px; border: 1px solid #cbd5e1;'
        }, activeIccidMasked);

        var toggleMaskBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-size: 11.5px; padding: 3px 8px; font-weight: 600;',
            click: function() {
                isMasked = !isMasked;
                iccidTextSpan.textContent = isMasked ? activeIccidMasked : activeIccidFull;
            }
        }, '👁️ Hiện/Ẩn Số');

        // BẢO MẬT TUYỆT ĐỐI THEO LỆNH ANH DUY:
        // SIM NGOÀI DANH MỤC: ẨN HOÀN TOÀN MỤC HẸN GIỜ GỬI TIN NHẮN & LỊCH GIA HẠN!
        var scheduleSectionNode;
        if (isWhitelisted) {
            var currentSchedTime = simMgrData.schedule_time || '01:25:30';
            var nextEpoch = parseInt(simMgrData.next_send_epoch || 0);

            var countdownSpan = E('span', {
                style: 'font-size: 12.5px; font-weight: 750; color: #d97706; background: #fffbeb; padding: 4px 10px; border-radius: 6px; border: 1px solid #fef3c7;'
            }, '⏳ Đang tính toán...');

            function updateLiveCountdown() {
                var nowE = Math.floor(Date.now() / 1000);
                if (nextEpoch > nowE) {
                    var diff = nextEpoch - nowE;
                    var ch = Math.floor(diff / 3600);
                    var cm = Math.floor((diff % 3600) / 60);
                    var cs = diff % 60;
                    countdownSpan.textContent = '⏳ Còn ' + ch + 'h ' + cm + 'p ' + cs + 's';
                } else {
                    countdownSpan.textContent = '✅ Đã đến giờ gửi hôm nay';
                }
            }
            updateLiveCountdown();
            setInterval(updateLiveCountdown, 1000);

            var schedTimeInput = E('input', {
                type: 'text',
                class: 'cbi-input-text',
                value: currentSchedTime,
                placeholder: '01:25:30',
                style: 'width: 105px; height: 36px; text-align: center; font-weight: 800; font-family: monospace; border-radius: 6px; font-size: 13.5px;'
            });

            var saveSchedBtn = E('button', {
                class: 'btn cbi-button cbi-button-action',
                style: 'font-size: 12.5px; font-weight: 750; padding: 6px 16px; border-radius: 6px;',
                click: function() {
                    var val = schedTimeInput.value.trim();
                    if (!val.match(/^[0-9]{2}:[0-9]{2}:[0-9]{2}$/)) {
                        alert('Định dạng giờ phải là HH:MM:SS (ví dụ 01:25:30)!');
                        return;
                    }
                    saveSchedBtn.textContent = '⏳ Đang lưu...';
                    callSimSaveTime(val)
                        .then(function(res) {
                            saveSchedBtn.textContent = '💾 Lưu Giờ Gửi';
                            if (res && res.status === 'success') {
                                ui.addNotification(null, E('p', '✅ ' + res.message), 'info');
                                if (res.next_send_epoch) {
                                    nextEpoch = parseInt(res.next_send_epoch);
                                    updateLiveCountdown();
                                }
                            } else {
                                ui.addNotification(null, E('p', '❌ ' + ((res && res.message) || 'Lỗi')), 'error');
                            }
                        }).catch(function(err) {
                            saveSchedBtn.textContent = '💾 Lưu Giờ Gửi';
                            ui.addNotification(null, E('p', '❌ Lỗi: ' + err), 'error');
                        });
                }
            }, '💾 Lưu Giờ Gửi');

            var schedPkgInput = E('input', {
                type: 'text',
                class: 'cbi-input-text',
                value: simMgrData.sms_package || '5G150N',
                placeholder: '5G150N',
                style: 'width: 100px; height: 36px; text-align: center; font-weight: 800; border-radius: 6px; font-size: 13.5px;'
            });

            var schedDestInput = E('input', {
                type: 'text',
                class: 'cbi-input-text',
                value: simMgrData.sms_recipient || '191',
                placeholder: '191',
                style: 'width: 70px; height: 36px; text-align: center; font-weight: 800; border-radius: 6px; font-size: 13.5px;'
            });

            var savePkgBtn = E('button', {
                class: 'btn cbi-button cbi-button-action',
                style: 'font-size: 12.5px; font-weight: 750; padding: 6px 14px; border-radius: 6px;',
                click: function() {
                    var pkg = schedPkgInput.value.trim();
                    var dest = schedDestInput.value.trim();
                    if (!pkg || !dest) return alert('Vui lòng nhập cú pháp và số nhận!');
                    savePkgBtn.textContent = '⏳ Đang lưu...';
                    callSimSavePackage(pkg, dest)
                        .then(function(res) {
                            savePkgBtn.textContent = '💾 Lưu Cú Pháp';
                            if (res && res.status === 'success') {
                                ui.addNotification(null, E('p', '✅ ' + res.message), 'info');
                            } else {
                                ui.addNotification(null, E('p', '❌ ' + ((res && res.message) || 'Lỗi')), 'error');
                            }
                        }).catch(function(err) {
                            savePkgBtn.textContent = '💾 Lưu Cú Pháp';
                            alert('Lỗi: ' + err);
                        });
                }
            }, '💾 Lưu Cú Pháp');

            var renewLogBox = E('div', {
                id: 'sms-renew-log-box',
                style: 'margin-top: 10px; background: #0f172a; color: #38bdf8; font-family: monospace; font-size: 11.5px; padding: 10px 14px; border-radius: 6px; line-height: 1.5; max-height: 120px; overflow-y: auto; white-space: pre-wrap;'
            }, simMgrData.last_renew_log || 'Chưa có nhật ký gia hạn.');

            var testRenewBtn = E('button', {
                class: 'btn cbi-button',
                style: 'font-size: 12px; font-weight: 750; padding: 6px 14px; border-radius: 6px; background: #16a34a; color: #ffffff; border: none; cursor: pointer; display: flex; align-items: center; gap: 6px;',
                click: function(ev) {
                    var curPkg = schedPkgInput ? schedPkgInput.value.trim() : '5G150N';
                    var curDest = schedDestInput ? schedDestInput.value.trim() : '191';
                    if (!confirm('⚡ Xác nhận gửi thử gia hạn gói [' + curPkg + '] tới [' + curDest + '] ngay bây giờ?')) return;
                    ev.target.disabled = true;
                    ev.target.textContent = '⏳ Đang kích hoạt...';
                    callSimTestSendNow()
                        .then(function(d) {
                            ev.target.disabled = false;
                            ev.target.textContent = '⚡ Gia Hạn Thử Ngay';
                            if (d && d.status === 'success') {
                                ui.addNotification(null, E('p', '✅ ' + d.message), 'info');
                                setTimeout(function() {
                                    callSimGetState()
                                        .then(function(data) {
                                            var lb = document.getElementById('sms-renew-log-box');
                                            if (lb && data && data.last_renew_log) lb.textContent = data.last_renew_log;
                                        }).catch(function() {});
                                }, 3500);
                            } else {
                                ui.addNotification(null, E('p', '❌ ' + ((d && d.message) || 'Lỗi gửi SMS')), 'error');
                            }
                        }).catch(function(err) {
                            ev.target.disabled = false;
                            ev.target.textContent = '⚡ Gia Hạn Thử Ngay';
                            alert('Lỗi: ' + err);
                        });
                }
            }, '⚡ Gia Hạn Thử Ngay');

            scheduleSectionNode = E('div', {
                style: 'background: #f0fdf4; border: 1.5px solid #86efac; border-radius: 8px; padding: 14px 16px; margin-bottom: 16px;'
            }, [
                E('div', { style: 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; flex-wrap: wrap; gap: 8px;' }, [
                    E('div', { style: 'display: flex; align-items: center; gap: 8px;' }, [
                        E('span', { style: 'font-size: 16px;' }, '⏰'),
                        E('span', { style: 'font-weight: 800; font-size: 14px; color: #166534;' }, 'Lịch SMS Tự Động Gia Hạn (Khung giờ vàng 00h20 - 05h40 sáng)'),
                        countdownSpan
                    ]),
                    testRenewBtn
                ]),
                E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 8px;' }, [
                    E('span', { style: 'font-size: 13px; font-weight: 700; color: #334155;' }, 'Giờ gửi tự động hàng ngày:'),
                    schedTimeInput,
                    saveSchedBtn,
                    E('span', { style: 'font-size: 12px; color: #15803d; font-weight: 600;' }, '• Khung giờ vàng 00h20 - 05h40')
                ]),
                E('div', { style: 'display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 8px;' }, [
                    E('span', { style: 'font-size: 13px; font-weight: 700; color: #334155;' }, 'Cú pháp gói cước gia hạn:'),
                    schedPkgInput,
                    E('span', { style: 'font-size: 13px; font-weight: 700; color: #334155;' }, 'gửi tới'),
                    schedDestInput,
                    savePkgBtn,
                    E('span', { style: 'font-size: 12px; color: #64748b;' }, '• Mặc định: 5G150N gửi 191')
                ]),
                E('div', { style: 'font-size: 12px; color: #0369a1; background: #e0f2fe; padding: 6px 10px; border-radius: 6px; border: 1px solid #bae6fd;' }, 
                    '💡 <b>Quy trình tự hành chuẩn 4 pha:</b> Gửi gói cước ➔ Sau 2s gửi xác nhận Y ➔ Sau 10s bật máy bay ngắt sóng ➔ Sau 10s tắt máy bay lấy IP WAN mới 100%!'
                ),
                renewLogBox
            ]);
        } else {
            // Khi SIM KHÔNG nằm trong danh mục hợp lệ: Ẩn hoàn toàn mục hẹn giờ gửi tin nhắn!
            scheduleSectionNode = E('div', {
                style: 'display: none;'
            });
        }

        var vipImeiInput = E('input', {
            type: 'text',
            class: 'cbi-input-text',
            value: (rfStatus && rfStatus.imei) ? rfStatus.imei : '',
            placeholder: 'Nhập 15 số IMEI',
            style: 'width: 190px; height: 34px; font-weight: 800; font-family: monospace; border-radius: 6px; font-size: 13px;'
        });

        var saveVipImeiBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-size: 12px; font-weight: 750; padding: 5px 14px; border-radius: 6px;',
            click: function() {
                var im = vipImeiInput.value.trim();
                if (!im.match(/^[0-9]{15}$/)) {
                    alert('Số IMEI phải gồm đúng 15 chữ số!');
                    return;
                }
                saveVipImeiBtn.textContent = '⏳ Đang lưu...';
                callChangeIMEI(im, 'auto').then(function(res) {
                    saveVipImeiBtn.textContent = '💾 Lưu Số IMEI';
                    ui.addNotification(null, E('p', (res && res.success ? '✅ ' : '❌ ') + ((res && res.message) || 'Đã cập nhật số IMEI thiết bị!')), (res && res.success) ? 'info' : 'error');
                }).catch(function(err) {
                    saveVipImeiBtn.textContent = '💾 Lưu Số IMEI';
                    alert('Lỗi: ' + err);
                });
            }
        }, '💾 Lưu Số IMEI');

        var simIccidSection = null;
        if (isWhitelisted) {
            simIccidSection = E('div', {
                style: 'background: #ffffff; border: 1.5px solid #cbd5e1; border-radius: 8px; padding: 14px 16px; margin-bottom: 16px;'
            }, [
                E('div', { style: 'display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f1f5f9; padding-bottom: 8px; margin-bottom: 12px; flex-wrap: wrap; gap: 8px;' }, [
                    E('div', { style: 'display: flex; align-items: center; gap: 8px;' }, [
                        E('span', { style: 'font-size: 18px;' }, '💳'),
                        E('span', { style: 'font-weight: 800; font-size: 15px; color: #0f172a;' }, 'Thông Tin SIM & Thiết Bị')
                    ]),
                    E('span', { style: 'font-size: 12px; color: #64748b; font-weight: 600;' }, 'Cổng AT: ' + activePort)
                ]),
                E('div', { style: 'display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 14px;' }, [
                    E('div', {}, [
                        E('div', { style: 'font-size: 12.5px; font-weight: 700; color: #475569; margin-bottom: 4px;' }, '📱 Mã ICCID Đang Gắn:'),
                        E('div', { style: 'display: flex; align-items: center; gap: 8px;' }, [ iccidTextSpan, toggleMaskBtn ])
                    ]),
                    E('div', { style: 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, [
                        E('span', { style: 'font-size: 12.5px; font-weight: 750; color: #1e293b;' }, '📱 Số IMEI Thiết Bị:'),
                        vipImeiInput,
                        saveVipImeiBtn
                    ])
                ])
            ]);
        } else {
            simIccidSection = null;
        }

        var inboxContainer = E('div', {
            id: 'modem-ctrl-sms-inbox',
            style: 'height: auto; max-height: 520px; overflow-y: auto; display: flex; flex-direction: column; gap: 8px; width: 100%; box-sizing: border-box; margin-top: 10px;'
        }, parseAndRenderSMS(typeof smsRes.inbox === 'string' ? smsRes.inbox : JSON.stringify(smsRes.inbox)));

        var smsTargetInput = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Người nhận (vd: 191 hoặc số điện thoại)', style: 'width: 100%; margin-bottom: 8px; font-weight: 700; height: 38px; border-radius: 6px;' });
        var smsMsgInput = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'Nội dung tin nhắn...', style: 'width: 100%; margin-bottom: 10px; height: 38px; border-radius: 6px;' });

        var sendSmsBtn = E('button', {
            class: 'btn cbi-button cbi-button-action',
            style: 'font-weight: 750; font-size: 13px; padding: 7px 18px; border-radius: 6px;',
            click: function() {
                var tgt = smsTargetInput.value.trim();
                var msg = smsMsgInput.value.trim();
                if (!tgt || !msg) { alert('Vui lòng nhập người nhận và nội dung!'); return; }
                sendSmsBtn.disabled = true;
                sendSmsBtn.textContent = '⏳ Đang gửi...';
                callSendSMS(tgt, msg).then(function(res) {
                    sendSmsBtn.disabled = false;
                    sendSmsBtn.textContent = '📨 Gửi Tin Nhắn';
                    if (res && res.success) {
                        ui.addNotification(null, E('p', '✅ ' + (res.message || ('Đã gửi tin nhắn đến ' + tgt))), 'info');
                        smsMsgInput.value = '';
                    } else {
                        ui.addNotification(null, E('p', '❌ ' + ((res && res.message) || 'Gửi tin nhắn thất bại!')), 'error');
                    }
                }).catch(function(err) {
                    sendSmsBtn.disabled = false;
                    sendSmsBtn.textContent = '📨 Gửi Tin Nhắn';
                    ui.addNotification(null, E('p', '❌ Lỗi gửi tin: ' + err), 'error');
                });
            }
        }, '📨 Gửi Tin Nhắn');

        var quickPresets = E('div', { style: 'display: flex; gap: 6px; margin-bottom: 10px; flex-wrap: wrap;' }, [
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 3px 8px; font-weight: 700; background: #eff6ff; color: #1d4ed8; border: 1px solid #bfdbfe; cursor: pointer; border-radius: 6px;', click: function() { smsTargetInput.value = '191'; smsMsgInput.value = 'KTTK'; } }, '⚡ Viettel KTTK'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 3px 8px; font-weight: 700; background: #eff6ff; color: #0284c7; border: 1px solid #bae6fd; cursor: pointer; border-radius: 6px;', click: function() { smsTargetInput.value = '888'; smsMsgInput.value = 'DATA'; } }, '⚡ Vina DATA'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 3px 8px; font-weight: 700; background: #fefce8; color: #a16207; border: 1px solid #fef08a; cursor: pointer; border-radius: 6px;', click: function() { smsTargetInput.value = '999'; smsMsgInput.value = 'KT DATA'; } }, '⚡ Mobi DATA'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 3px 8px; font-weight: 700; background: #fdf2f8; color: #be185d; border: 1px solid #fbcfe8; cursor: pointer; border-radius: 6px;', click: function() { smsTargetInput.value = '123'; smsMsgInput.value = 'KT'; } }, '⚡ VNM KT'),
            E('button', { class: 'btn', style: 'font-size: 11.5px; padding: 3px 8px; font-weight: 700; background: #f0fdf4; color: #15803d; border: 1px solid #bbf7d0; cursor: pointer; border-radius: 6px;', click: function() { smsTargetInput.value = '191'; smsMsgInput.value = 'DATA'; } }, '⚡ Wintel DATA')
        ]);

        var fastCheckDataBtn = E('button', {
            class: 'btn cbi-button',
            style: 'font-weight: 750; font-size: 13px; padding: 7px 18px; border-radius: 6px; background: #ffffff; color: #1e293b; border: 1.5px solid #cbd5e1; margin-left: 8px;',
            click: function() {
                inboxContainer.innerHTML = '<div style="padding: 20px; text-align: center; color: #2563eb; font-weight: 700;">⏳ Đang gửi tra cước data & đọc tin phản hồi tự động...</div>';
                callCheckDataBalance().then(function(res) {
                    if (res && res.success === false) {
                        var errMsg = res.message || 'Gửi lệnh tra cước thất bại!';
                        inboxContainer.innerHTML = '<div style="padding: 16px; color: #b91c1c; font-weight: 700;">❌ ' + errMsg + '</div>';
                        ui.addNotification(null, E('p', '❌ ' + errMsg), 'error');
                        return;
                    }
                    callFetchSMS().then(function(rep) {
                        inboxContainer.innerHTML = '';
                        parseAndRenderSMS(rep.inbox || '').forEach(function(n) { inboxContainer.appendChild(n); });
                    });
                }).catch(function(err) {
                    ui.addNotification(null, E('p', '❌ Lỗi tra cứu: ' + err), 'error');
                });
            }
        }, '🔍 Kiểm Tra Data Nhanh (Tự Động Đọc Tin)');

        var simTabChildren = [
            E('h3', { style: 'margin-top: 0; font-size: 18px; font-weight: 800; color: #1e293b; border-bottom: 1px solid #f1f5f9; padding-bottom: 10px;' }, isWhitelisted ? '📬 Quản Lý SIM & Hộp Thư SMS (Router & SIM)' : '📬 Hộp Thư Tin Nhắn SMS (Router & SIM)')
        ];

        /* ==============================================================================
           === LOCKED: VERIFIED BY DOANDUY - DO NOT MODIFY ===
           BẢO MẬT TUYỆT ĐỐI THEO CHỈ THỊ ANH DUY (DOANDUY):
           Chỉ khi SIM nằm trong danh mục mặc định thì mới hiển thị Thông Tin SIM & Thiết Bị
           và Lịch Hẹn Giờ SMS. Nếu SIM ngoài danh mục: ẨN 100% KHỎI DOM (ZERO LEAK)!
           ============================================================================== */
        if (isWhitelisted) {
            if (simIccidSection) simTabChildren.push(simIccidSection);
            if (scheduleSectionNode) simTabChildren.push(scheduleSectionNode);
        }

        var simTabStatusCard = E('div', { style: 'background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; margin-bottom: 16px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;' }, [
                E('div', {}, [
                    E('span', { style: 'font-weight: 700; color: #475569; font-size: 13px;' }, '📱 Trạng thái SIM: '),
                    E('span', { style: 'font-weight: 800; color: ' + (hasValidIccid ? '#15803d' : '#475569') + '; font-size: 14px;' }, isWhitelisted ? (smsRes.sim_info || 'SIM Viettel (Hoạt động)') : (hasValidIccid ? (smsRes.sim_info || 'SIM Di Động (Đang hoạt động)') : 'Chưa gắn SIM / Chưa phát hiện')),
                    E('span', { style: 'margin-left: 10px; font-weight: 600; color: #64748b; font-size: 12px;' }, '• Cổng AT: ' + activePort)
                ]),
                E('div', { style: 'display: flex; gap: 8px;' }, [
                    E('button', {
                        class: 'btn cbi-button cbi-button-action',
                        style: 'font-weight: 700; font-size: 12px; padding: 6px 14px; border-radius: 6px;',
                        click: function() {
                            inboxContainer.innerHTML = '<div style="padding: 20px; text-align: center; color: #2563eb; font-weight: 700;">⏳ Đang quét toàn bộ tin nhắn từ Router (ME) và Thẻ SIM (SM)...</div>';
                            callFetchSMS().then(function(r) {
                                inboxContainer.innerHTML = '';
                                parseAndRenderSMS(r.inbox || '').forEach(function(n) { inboxContainer.appendChild(n); });
                            });
                        }
                    }, '🔄 Quét Lại Tin'),
                    E('button', {
                        class: 'btn cbi-button cbi-button-remove',
                        style: 'font-weight: 700; font-size: 12px; padding: 6px 14px; border-radius: 6px;',
                        click: function() {
                            if (!confirm("Xóa toàn bộ tin nhắn trên cả Router và SIM?")) return;
                            callDeleteAllSMS().then(function() {
                                inboxContainer.innerHTML = '<div style="padding: 20px; text-align: center; color: #475569; font-size: 14px;">📭 Hộp thư trống.</div>';
                            });
                        }
                    }, '🗑️ Xóa Tất Cả')
                ])
            ]);

            simTabChildren.push(simTabStatusCard);
            simTabChildren.push(E('div', { style: 'margin-bottom: 16px; border: 1px solid #f1f5f9; border-radius: 8px; padding: 14px; background: #fafafa;' }, [
                E('div', { style: 'font-weight: 750; font-size: 13.5px; margin-bottom: 8px; color: #1e293b;' }, '⚡ Gửi Tin Nhắn Nhanh & Tra Cước Data:'),
                quickPresets,
                smsTargetInput,
                smsMsgInput,
                E('div', { style: 'display: flex; gap: 10px;' }, [ sendSmsBtn, fastCheckDataBtn ])
            ]));
            simTabChildren.push(E('div', { style: 'border-top: 1px solid #f1f5f9; padding-top: 12px;' }, [
                E('div', { style: 'font-weight: 800; font-size: 14px; margin-bottom: 6px; color: #1e293b;' }, '📥 Hộp Thư Đến Trực Tiếp:'),
                inboxContainer
            ]));

        var simTabContent = E('div', { class: 'cbi-section', style: 'padding: 20px; background: #ffffff; border-radius: 10px; border: 1px solid #e2e8f0;' }, simTabChildren);
        tabPanes['sms'] = simTabContent;

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
                activePort = ev.target.value;
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
                activePort = chosen;
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
        tabPanes['modem'] = modemTabContent;

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
        tabPanes['sentinel'] = sentinelTabContent;

        var smarthomeTabContent = smarthome.renderPane();
        tabPanes['smarthome'] = smarthomeTabContent;

        var mainWrapper = E('div', { class: 'cbi-map', style: 'padding: 10px 0;' }, [
            navBar,
            simTabContent,
            modemTabContent,
            sentinelTabContent,
            smarthomeTabContent
        ]);

        return mainWrapper;
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});

