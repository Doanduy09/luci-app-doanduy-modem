// [VERIFIED-GOLDEN: part4-luci-view-modem-control-shell-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
// Modular Master Shell for DOANDUY 5G Modem, SMS, RF, AI Sentinel & SmartHome Suite
// Tab Modules: doanduy/tab_sms.js | doanduy/tab_modem.js | doanduy/tab_sentinel.js | doanduy/smarthome.js
'use strict';
'require view';
'require rpc';
'require doanduy.tab_sms as tabSms';
'require doanduy.tab_modem as tabModem';
'require doanduy.tab_sentinel as tabSentinel';
'require doanduy.smarthome as smarthome';

var callSMSInfo           = rpc.declare({ object: 'luci.sms-status', method: 'getSMSInfo', expect: { } });
var callGetPorts          = rpc.declare({ object: 'luci.sms-status', method: 'getAvailablePorts', expect: { } });
var callSimGetState       = rpc.declare({ object: 'doanduy.sim', method: 'getState', expect: { } });
var callGetSentinelConfig = rpc.declare({ object: 'doanduy.vault', method: 'get', expect: { } });
var callRemoteStatus      = rpc.declare({ object: 'doanduy.remote', method: 'status', expect: { } });
var callRfStatus          = rpc.declare({ object: 'doanduy.rf', method: 'getStatus', expect: { } });

function withTimeout(promise, ms, fallback) {
    return new Promise(function(resolve) {
        var done = false;
        var timer = setTimeout(function() {
            if (!done) { done = true; resolve(fallback); }
        }, ms);
        Promise.resolve(promise).then(function(val) {
            if (!done) { done = true; clearTimeout(timer); resolve(val || fallback); }
        }).catch(function() {
            if (!done) { done = true; clearTimeout(timer); resolve(fallback); }
        });
    });
}

return view.extend({
    title: _('Tiện Ích 5G & Quản Trị Modem'),

    load: function() {
        return Promise.all([
            withTimeout(callSMSInfo(), 2200, {}),
            withTimeout(callGetPorts(), 2200, {}),
            withTimeout(callSimGetState(), 2200, {}),
            withTimeout(callGetSentinelConfig(), 2000, {}),
            withTimeout(callRemoteStatus(), 2000, {}),
            withTimeout(callRfStatus(), 2000, {})
        ]);
    },

    render: function(data) {
        var smsRes         = data[0] || {};
        var portsData      = data[1] || {};
        var cellRes        = {};
        var simMgrData     = data[2] || {};
        var sentinelConfig = data[3] || {};
        var remoteState    = data[4] || {};
        var rfStatus       = data[5] || {};

        var activePort = (portsData && portsData.current_port && portsData.current_port.indexOf('/dev/') !== -1)
            ? portsData.current_port
            : ((smsRes && smsRes.port && smsRes.port.indexOf('/dev/') !== -1)
                ? smsRes.port
                : '/dev/wwan0at0');
        var portListeners = [];

        var sharedCtx = {
            smsRes: smsRes,
            portsData: portsData,
            cellRes: cellRes,
            simMgrData: simMgrData,
            sentinelConfig: sentinelConfig,
            remoteState: remoteState,
            rfStatus: rfStatus,
            getActivePort: function() { return activePort; },
            setActivePort: function(newP) {
                activePort = newP;
                portListeners.forEach(function(fn) { try { fn(newP); } catch (e) {} });
            },
            onPortChange: function(fn) {
                if (typeof fn === 'function') portListeners.push(fn);
            }
        };

        var tabButtons = [
            { id: 'tab-btn-sms',       key: 'sms',       icon: '📬', title: 'Quản Lý SIM & Tin Nhắn SMS' },
            { id: 'tab-btn-modem',     key: 'modem',     icon: '📶', title: 'Modem 5G, Băng Tần & Lệnh AT' },
            { id: 'tab-btn-sentinel',  key: 'sentinel',  icon: '🤖', title: 'Telegram, AI & Từ Xa' },
            { id: 'tab-btn-smarthome', key: 'smarthome', icon: '🏠', title: 'Thiết Bị Điều Khiển Nhà' }
        ];

        var tabPanes = {
            sms:       tabSms.renderPane(sharedCtx),
            modem:     tabModem.renderPane(sharedCtx),
            sentinel:  tabSentinel.renderPane(sharedCtx),
            smarthome: smarthome.renderPane()
        };

        function switchSubTab(targetKey) {
            tabButtons.forEach(function(b) {
                var btnEl = document.getElementById(b.id);
                var paneEl = tabPanes[b.key];
                if (btnEl && paneEl) {
                    var act = (b.key === targetKey);
                    btnEl.style.background  = act ? '#2563eb' : '#ffffff';
                    btnEl.style.color       = act ? '#ffffff' : '#334155';
                    btnEl.style.borderColor = act ? '#2563eb' : '#cbd5e1';
                    paneEl.style.display    = act ? 'block' : 'none';
                    if (act && typeof paneEl._onShow === 'function') {
                        try { paneEl._onShow(); } catch (e) {}
                    }
                }
            });
        }

        var navBar = E('div', {
            style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 20px; padding-bottom: 12px; border-bottom: 2px solid #e2e8f0;'
        });

        tabButtons.forEach(function(b, idx) {
            var isFirst = (idx === 0);
            var btn = E('button', {
                id: b.id,
                class: 'btn',
                style: 'display: flex; align-items: center; gap: 6px; padding: 9px 18px; font-weight: 750; font-size: 13.5px; border-radius: 8px; border: 1.5px solid ' + (isFirst ? '#2563eb' : '#cbd5e1') + '; cursor: pointer; transition: all 0.2s; background: ' + (isFirst ? '#2563eb' : '#ffffff') + '; color: ' + (isFirst ? '#ffffff' : '#334155') + ';',
                click: function() { switchSubTab(b.key); }
            }, [ E('span', { style: 'font-size: 16px;' }, b.icon), b.title ]);
            navBar.appendChild(btn);
        });

        return E('div', { class: 'cbi-map', style: 'padding: 10px 0;' }, [
            navBar,
            tabPanes.sms,
            tabPanes.modem,
            tabPanes.sentinel,
            tabPanes.smarthome
        ]);
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
// [/VERIFIED-GOLDEN]
