'use strict';
'require view';
'require rpc';
'require ui';

var callVaultGet = rpc.declare({ object: 'doanduy.vault', method: 'get', expect: {} });
var callVaultSave = rpc.declare({ object: 'doanduy.vault', method: 'save', params: ['tg_bot_token', 'tg_admin_id', 'tg_owner_name', 'gemini_api_key', 'tailscale_auth_key', 'emergency_phone'], expect: {} });
var callVaultTestTg = rpc.declare({ object: 'doanduy.vault', method: 'testTelegram', expect: {} });

function notify(r) {
	ui.addNotification(null, E('p', (r && r.message) ? r.message : 'Hoàn tất!'), (r && r.success) ? 'info' : 'error');
}

return view.extend({
	load: function() {
		return L.resolveDefault(callVaultGet(), {});
	},

	render: function(v) {
		v = v || {};
		var fields = {
			tg_bot_token: E('input', { type: 'password', class: 'cbi-input-text', value: v.tg_bot_token || '', placeholder: '123456789:AAF...', style: 'width: 100%; max-width: 440px;' }),
			tg_admin_id: E('input', { type: 'text', class: 'cbi-input-text', value: v.tg_admin_id || '', placeholder: 'Chat ID Telegram', style: 'width: 100%; max-width: 440px;' }),
			tg_owner_name: E('input', { type: 'text', class: 'cbi-input-text', value: v.tg_owner_name || '', placeholder: 'Tên thiết bị / Chủ sở hữu', style: 'width: 100%; max-width: 440px;' }),
			tailscale_auth_key: E('input', { type: 'password', class: 'cbi-input-text', value: v.tailscale_auth_key || '', placeholder: 'tskey-auth-...', style: 'width: 100%; max-width: 440px;' }),
			gemini_api_key: E('input', { type: 'password', class: 'cbi-input-text', value: v.gemini_api_key || '', placeholder: 'AIza...', style: 'width: 100%; max-width: 440px;' }),
			emergency_phone: E('input', { type: 'text', class: 'cbi-input-text', value: v.emergency_phone || '', placeholder: '09xxxxxxxx', style: 'width: 100%; max-width: 440px;' })
		};

		function row(label, node) {
			return E('tr', { class: 'tr' }, [
				E('td', { class: 'td left', width: '32%', style: 'font-weight: 600;' }, label),
				E('td', { class: 'td left' }, [ node ])
			]);
		}

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('Kho Key, Token & Thông Báo Telegram (Bảo toàn khi nâng cấp ROM/IPK)')),
			E('div', { class: 'cbi-section' }, [
				E('table', { class: 'table' }, [
					row(_('Telegram Bot Token'), fields.tg_bot_token),
					row(_('Telegram Chat ID'), fields.tg_admin_id),
					row(_('Tên Router / Chủ thiết bị'), fields.tg_owner_name),
					row(_('Tailscale Auth Key'), fields.tailscale_auth_key),
					row(_('Gemini API Key (Tùy chọn)'), fields.gemini_api_key),
					row(_('Số điện thoại dự phòng'), fields.emergency_phone)
				]),
				E('div', { style: 'display: flex; gap: 10px; margin-top: 12px; flex-wrap: wrap;' }, [
					E('button', {
						class: 'btn cbi-button cbi-button-apply',
						click: function() {
							return callVaultSave(
								fields.tg_bot_token.value.trim(),
								fields.tg_admin_id.value.trim(),
								fields.tg_owner_name.value.trim(),
								fields.gemini_api_key.value.trim(),
								fields.tailscale_auth_key.value.trim(),
								fields.emergency_phone.value.trim()
							).then(notify);
						}
					}, _('Lưu Toàn Bộ Key & Token')),
					E('button', {
						class: 'btn cbi-button cbi-button-action',
						click: function() { return callVaultTestTg().then(notify); }
					}, _('Gửi Thử Tin Telegram'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
