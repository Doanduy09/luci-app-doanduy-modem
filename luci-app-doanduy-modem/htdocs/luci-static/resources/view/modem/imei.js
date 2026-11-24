'use strict';
'require view';
'require rpc';
'require ui';

var callRfStatus = rpc.declare({ object: 'doanduy.rf', method: 'getStatus', expect: {} });
var callChangeIMEI = rpc.declare({ object: 'doanduy.rf', method: 'changeIMEI', params: ['imei', 'brand'], expect: {} });
var callRestoreIMEI = rpc.declare({ object: 'doanduy.rf', method: 'restoreIMEI', expect: {} });
var callSetTTL = rpc.declare({ object: 'doanduy.rf', method: 'setTTL', params: ['ttl'], expect: {} });
var callSendAT = rpc.declare({ object: 'doanduy.rf', method: 'sendAT', params: ['cmd', 'port'], expect: {} });

function notify(res) {
	var ok = res && res.success;
	ui.addNotification(null, E('p', (res && res.message) ? res.message : (ok ? 'Thành công!' : 'Thao tác thất bại!')), ok ? 'info' : 'error');
}

return view.extend({
	load: function() {
		return L.resolveDefault(callRfStatus(), {});
	},

	render: function(st) {
		st = st || {};
		var imeiInput = E('input', {
			type: 'text',
			class: 'cbi-input-text',
			placeholder: 'Nhập 15 chữ số IMEI mới',
			value: st.imei || '',
			maxlength: '15',
			style: 'min-width: 210px; font-family: monospace; font-weight: 700;'
		});

		var brandSel = E('select', { class: 'cbi-input-select' }, [
			E('option', { value: 'auto', selected: true }, _('Tự động nhận diện (' + (st.vendor || 'auto') + ')')),
			E('option', { value: 'quectel' }, 'Quectel (RM502Q / RM520N / EC25)'),
			E('option', { value: 'fibocom' }, 'Fibocom (FM350 / FM150 / FM160)'),
			E('option', { value: 'sierra' }, 'Sierra Wireless (EM9190 / EM7565)'),
			E('option', { value: 'simcom' }, 'Simcom (SIM8200 / SIM7600)'),
			E('option', { value: 'meig' }, 'MeiG (SRM821 / SLM)')
		]);

		var ttlInput = E('input', {
			type: 'number',
			class: 'cbi-input-text',
			value: String(st.ttl || 64),
			min: '0',
			max: '255',
			style: 'width: 90px; font-weight: 700; text-align: center;'
		});

		var atInput = E('input', {
			type: 'text',
			class: 'cbi-input-text',
			placeholder: 'Ví dụ: ATI, AT+COPS?, AT+QENG="servingcell"',
			value: 'ATI',
			style: 'min-width: 260px; font-family: monospace;'
		});

		var atOutput = E('pre', {
			style: 'background: #0f172a; color: #38bdf8; padding: 12px; border-radius: 6px; min-height: 90px; max-height: 280px; overflow: auto; font-size: 12px; margin-top: 10px;'
		}, _('Sẵn sàng gửi lệnh AT trên cổng: %s').format(st.at_port || 'auto'));

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('Đổi IMEI, TTL & Lệnh AT (Mọi Card WWAN)')),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Thông số Modem hiện tại')),
				E('table', { class: 'table' }, [
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left', width: '30%' }, _('Model / Hãng')), E('td', { class: 'td left' }, (st.model || '-') + ' (' + (st.vendor || 'auto') + ')') ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('Cổng AT')), E('td', { class: 'td left' }, st.at_port || 'Chưa phát hiện') ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('IMEI hiện tại / Gốc')), E('td', { class: 'td left', style: 'font-family: monospace; font-weight: 700;' }, (st.imei || '-') + '  |  Gốc: ' + (st.original_imei || 'Chưa sao lưu')) ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('TTL hiện tại')), E('td', { class: 'td left' }, String(st.ttl || 64) + (st.ttl_custom ? ' (Đang ghim tùy chỉnh)' : ' (Mặc định)')) ])
				])
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Đổi IMEI Đa Hãng (Tự sao lưu IMEI gốc)')),
				E('div', { style: 'display: flex; gap: 10px; flex-wrap: wrap; align-items: center;' }, [
					imeiInput,
					brandSel,
					E('button', {
						class: 'btn cbi-button cbi-button-apply',
						click: ui.createHandlerFn(this, function() {
							var val = imeiInput.value.trim();
							if (!val.match(/^[0-9]{15}$/))
								return ui.addNotification(null, E('p', _('IMEI phải gồm đúng 15 chữ số!')), 'error');
							return callChangeIMEI(val, brandSel.value).then(function(r) {
								notify(r);
							});
						})
					}, _('Đổi IMEI Ngay')),
					E('button', {
						class: 'btn cbi-button',
						click: ui.createHandlerFn(this, function() {
							return callRestoreIMEI().then(function(r) {
								notify(r);
							});
						})
					}, _('Khôi Phục IMEI Gốc'))
				])
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Ghim TTL Né Bóp Băng Thông')),
				E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center;' }, [
					ttlInput,
					E('button', {
						class: 'btn cbi-button cbi-button-apply',
						click: ui.createHandlerFn(this, function() {
							return callSetTTL(parseInt(ttlInput.value, 10) || 0).then(notify);
						})
					}, _('Áp Dụng TTL')),
					E('button', { class: 'btn cbi-button', click: function() { ttlInput.value = '65'; return callSetTTL(65).then(notify); } }, 'TTL 65 (Hotspot)'),
					E('button', { class: 'btn cbi-button', click: function() { ttlInput.value = '128'; return callSetTTL(128).then(notify); } }, 'TTL 128 (Windows)'),
					E('button', { class: 'btn cbi-button cbi-button-reset', click: function() { ttlInput.value = '64'; return callSetTTL(0).then(notify); } }, _('Tắt Ép TTL'))
				])
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Gửi Lệnh AT Trực Tiếp')),
				E('div', { style: 'display: flex; gap: 8px; flex-wrap: wrap; align-items: center;' }, [
					atInput,
					E('button', {
						class: 'btn cbi-button cbi-button-action',
						click: ui.createHandlerFn(this, function() {
							var cmd = atInput.value.trim();
							if (!cmd) return;
							atOutput.textContent = _('Đang gửi: %s...').format(cmd);
							return callSendAT(cmd, st.at_port || '').then(function(r) {
								atOutput.textContent = (r && r.response) ? r.response : ((r && r.message) || 'Không có phản hồi.');
							});
						})
					}, _('Gửi Lệnh AT'))
				]),
				atOutput
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
