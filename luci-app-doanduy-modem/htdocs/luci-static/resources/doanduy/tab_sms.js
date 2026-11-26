// [VERIFIED-GOLDEN: luci-mod-tab-sms-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
// Scenario 02 (SIM & SMS) — LuCI Tab 1: Quản Lý SIM, Lịch Gia Hạn Tự Động & Hộp Thư SMS (Router ME & SIM SM)
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callFetchSMS         = rpc.declare({ object: 'luci.sms-status', method: 'fetchSMSNow', expect: { } });
var callDeleteAllSMS     = rpc.declare({ object: 'luci.sms-status', method: 'deleteAllSMS', expect: { } });
var callDeleteSingleSMS  = rpc.declare({ object: 'luci.sms-status', method: 'deleteSingleSMS', params: ['indices', 'storage'], expect: { } });
var callSendSMS          = rpc.declare({ object: 'luci.sms-status', method: 'sendSMS', params: ['target', 'msg'] });
var callCheckDataBalance = rpc.declare({ object: 'luci.sms-status', method: 'checkDataBalance', expect: { } });
var callSimGetState      = rpc.declare({ object: 'doanduy.sim', method: 'getState', expect: { } });
var callSimSaveTime      = rpc.declare({ object: 'doanduy.sim', method: 'saveTime', params: ['time'], expect: { } });
var callSimSavePackage   = rpc.declare({ object: 'doanduy.sim', method: 'savePackage', params: ['package', 'dest'], expect: { } });
var callSimTestSendNow   = rpc.declare({ object: 'doanduy.sim', method: 'testSendNow', expect: { } });
var callChangeIMEI       = rpc.declare({ object: 'doanduy.rf', method: 'changeIMEI', params: ['imei', 'brand'] });

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

return baseclass.extend({
    renderPane: function(ctx) {
        var smsRes = ctx.smsRes || {};
        var simMgrData = ctx.simMgrData || {};
        var rfStatus = ctx.rfStatus || {};
        var activePort = ctx.getActivePort();
        var portBadgeTop = E('span', { style: 'font-size: 12px; color: #64748b; font-weight: 600;' }, 'Cổng AT: ' + activePort);
        var portBadgeSub = E('span', { style: 'margin-left: 10px; font-weight: 600; color: #64748b; font-size: 12px;' }, '• Cổng AT: ' + activePort);
        ctx.onPortChange(function(newP) {
            portBadgeTop.textContent = 'Cổng AT: ' + newP;
            portBadgeSub.textContent = '• Cổng AT: ' + newP;
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
                    portBadgeTop
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
                        inboxContainer.innerHTML = '';
                        inboxContainer.appendChild(E('div', { style: 'padding: 16px; color: #b91c1c; font-weight: 700;' }, '❌ ' + errMsg));
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
                    portBadgeSub
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
        return simTabContent;
    }
});
// [/VERIFIED-GOLDEN]
