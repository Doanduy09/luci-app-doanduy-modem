'use strict';
'require view';
'require rpc';
'require ui';

var callAdStatus = rpc.declare({ object: 'doanduy.adshield', method: 'status', expect: {} });
var callAdToggle = rpc.declare({ object: 'doanduy.adshield', method: 'toggle', params: ['action'], expect: {} });
var callAdFamily = rpc.declare({ object: 'doanduy.adshield', method: 'family', params: ['action'], expect: {} });
var callAdUpdate = rpc.declare({ object: 'doanduy.adshield', method: 'update', expect: {} });
var callAdAddBlock = rpc.declare({ object: 'doanduy.adshield', method: 'addBlock', params: ['domain'], expect: {} });
var callAdAddAllow = rpc.declare({ object: 'doanduy.adshield', method: 'addAllow', params: ['domain'], expect: {} });
var callCleanDns = rpc.declare({ object: 'doanduy.adshield', method: 'cleanDns', params: ['action'], expect: {} });

function notify(r) {
	var ok = r && (r.success || r.status === 'active' || r.status === 'inactive');
	ui.addNotification(null, E('p', (r && r.message) ? r.message : 'Đã cập nhật!'), ok ? 'info' : 'error');
}

return view.extend({
	load: function() {
		return L.resolveDefault(callAdStatus(), {});
	},

	render: function(st) {
		st = st || {};
		var blkInput = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'domain cần chặn (vd: ads.example.com)', style: 'min-width: 240px;' });
		var alwInput = E('input', { type: 'text', class: 'cbi-input-text', placeholder: 'domain bỏ chặn (whitelist)', style: 'min-width: 240px;' });

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('Micro AdShield & Smart Clean DNS (0% RAM thừa / Chống mòn Flash)')),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Trạng thái Bảo vệ Mạng')),
				E('table', { class: 'table' }, [
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left', width: '35%' }, _('Micro AdShield')), E('td', { class: 'td left', style: 'font-weight: 700;' }, st.active ? _('Đang BẬT (%d quy tắc)').format(st.rules || 0) : _('Đang TẮT')) ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('Chống vượt DNS / DoT 853')), E('td', { class: 'td left' }, st.dns_hijack ? _('Đang bảo vệ (Nftables Port 53)') : _('Tắt')) ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('Bảo vệ trẻ em (Family SafeSearch)')), E('td', { class: 'td left' }, st.family ? _('Đang BẬT') : _('Tắt')) ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('Clean DNS (Quad-Stack 1.1.1.1 / 8.8.8.8)')), E('td', { class: 'td left' }, st.clean_dns ? _('Đang BẬT') : _('Tắt')) ])
				]),
				E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-top: 12px;' }, [
					E('button', {
						class: 'btn cbi-button ' + (st.active ? 'cbi-button-reset' : 'cbi-button-apply'),
						click: function() { return callAdToggle(st.active ? 'off' : 'on').then(function(r) { notify(r); location.reload(); }); }
					}, st.active ? _('Tắt Chặn Quảng Cáo') : _('Bật Chặn Quảng Cáo')),
					E('button', {
						class: 'btn cbi-button cbi-button-action',
						click: function() { return callAdUpdate().then(notify); }
					}, _('Cập Nhật Bộ Lọc Mới Nhất')),
					E('button', {
						class: 'btn cbi-button',
						click: function() { return callAdFamily(st.family ? 'off' : 'on').then(function(r) { notify(r); location.reload(); }); }
					}, st.family ? _('Tắt Family SafeSearch') : _('Bật Family SafeSearch')),
					E('button', {
						class: 'btn cbi-button',
						click: function() { return callCleanDns(st.clean_dns ? 'off' : 'on').then(function() { location.reload(); }); }
					}, st.clean_dns ? _('Tắt Clean DNS') : _('Bật Clean DNS'))
				])
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Chặn / Cho phép Tên miền Tùy chỉnh')),
				E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px;' }, [
					blkInput,
					E('button', {
						class: 'btn cbi-button cbi-button-negative',
						click: function() {
							var d = blkInput.value.trim();
							if (!d) return;
							return callAdAddBlock(d).then(function(r) { blkInput.value = ''; notify(r); });
						}
					}, _('Thêm Vào Danh Sách Chặn'))
				]),
				E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap;' }, [
					alwInput,
					E('button', {
						class: 'btn cbi-button cbi-button-positive',
						click: function() {
							var d = alwInput.value.trim();
							if (!d) return;
							return callAdAddAllow(d).then(function(r) { alwInput.value = ''; notify(r); });
						}
					}, _('Bỏ Chặn (Whitelist)'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
