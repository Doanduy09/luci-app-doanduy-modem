'use strict';
'require view';
'require rpc';
'require ui';

var callRemoteStatus = rpc.declare({ object: 'doanduy.remote', method: 'status', expect: {} });
var callTailscaleUp = rpc.declare({ object: 'doanduy.remote', method: 'tailscaleUp', params: ['authkey', 'enable_funnel'], expect: {} });
var callTailscaleDown = rpc.declare({ object: 'doanduy.remote', method: 'tailscaleDown', expect: {} });
var callToggleWanPort = rpc.declare({ object: 'doanduy.remote', method: 'toggleWanPort', params: ['service', 'enable', 'port'], expect: {} });
var callStartTunnel = rpc.declare({ object: 'doanduy.remote', method: 'startTunnel', params: ['duration'], expect: {} });
var callStopTunnel = rpc.declare({ object: 'doanduy.remote', method: 'stopTunnel', expect: {} });

function notify(r) {
	ui.addNotification(null, E('p', (r && r.message) ? r.message : 'Hoàn tất!'), (r && r.success) ? 'info' : 'error');
}

return view.extend({
	load: function() {
		return L.resolveDefault(callRemoteStatus(), {});
	},

	render: function(st) {
		st = st || {};
		var tsKeyInput = E('input', { type: 'password', class: 'cbi-input-text', placeholder: st.has_tailscale_key ? _('Đã có key trong Vault (để trống nếu dùng key cũ)') : 'tskey-auth-...', style: 'min-width: 260px;' });
		var funnelChk = E('input', { type: 'checkbox', checked: !!st.tailscale_funnel });
		var luciPortInput = E('input', { type: 'number', class: 'cbi-input-text', value: String(st.wan_luci_port || 80), min: '1', max: '65535', style: 'width: 90px;' });
		var sshPortInput = E('input', { type: 'number', class: 'cbi-input-text', value: String(st.wan_ssh_port || 22), min: '1', max: '65535', style: 'width: 90px;' });
		var tunDurInput = E('input', { type: 'number', class: 'cbi-input-text', value: '15', min: '1', max: '1440', style: 'width: 85px;' });

		var tunnelLinkNode = st.tunnel_url
			? E('a', { href: st.tunnel_url, target: '_blank', style: 'font-weight: 700; color: #2563eb;' }, st.tunnel_url)
			: E('span', {}, _('Chưa mở'));

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('Kết Nối Từ Xa, Tailscale & Mở Port An Toàn')),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('1. Mạng Riêng Ảo Tailscale (Khuyến nghị bảo mật cao nhất)')),
				E('table', { class: 'table' }, [
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left', width: '32%' }, _('Gói Tailscale')), E('td', { class: 'td left' }, st.tailscale_installed ? (st.tailscale_up ? _('Đang kết nối') : _('Đã cài (Chưa bật)')) : _('Chưa cài trên ROM này')) ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('IP Tailscale / DNS')), E('td', { class: 'td left', style: 'font-family: monospace; font-weight: 700;' }, (st.tailscale_ip || '-') + (st.tailscale_dns ? ('  |  ' + st.tailscale_dns) : '')) ])
				]),
				st.tailscale_installed ? E('div', { style: 'display: flex; gap: 10px; flex-wrap: wrap; align-items: center; margin-top: 10px;' }, [
					tsKeyInput,
					E('label', { style: 'display: inline-flex; align-items: center; gap: 5px;' }, [ funnelChk, _('Bật Funnel HTTPS') ]),
					E('button', {
						class: 'btn cbi-button cbi-button-apply',
						click: function() { return callTailscaleUp(tsKeyInput.value.trim(), funnelChk.checked).then(function(r) { notify(r); location.reload(); }); }
					}, _('Kết Nối Tailscale')),
					E('button', {
						class: 'btn cbi-button cbi-button-reset',
						click: function() { return callTailscaleDown().then(function(r) { notify(r); location.reload(); }); }
					}, _('Tắt Tailscale'))
				]) : E('div', { class: 'alert-message warning', style: 'margin-top: 8px;' }, _('Router này chưa cài binary tailscale; anh vẫn dùng được Tunnel hoặc Mở Port bên dưới.'))
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('2. Tự Mở Port Firewall WAN (LuCI / SSH — Đặt mật khẩu root trước khi mở!)')),
				E('div', { style: 'display: flex; flex-direction: column; gap: 10px;' }, [
					E('div', { style: 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap;' }, [
						E('strong', { style: 'min-width: 140px;' }, _('Truy cập Web LuCI WAN:')),
						luciPortInput,
						E('span', {}, st.wan_luci_open ? _('Đang MỞ') : _('Đang ĐÓNG')),
						E('button', {
							class: 'btn cbi-button ' + (st.wan_luci_open ? 'cbi-button-reset' : 'cbi-button-apply'),
							click: function() { return callToggleWanPort('luci', !st.wan_luci_open, parseInt(luciPortInput.value, 10) || 80).then(function(r) { notify(r); location.reload(); }); }
						}, st.wan_luci_open ? _('Đóng Port Web WAN') : _('Mở Port Web WAN'))
					]),
					E('div', { style: 'display: flex; gap: 10px; align-items: center; flex-wrap: wrap;' }, [
						E('strong', { style: 'min-width: 140px;' }, _('Truy cập SSH WAN:')),
						sshPortInput,
						E('span', {}, st.wan_ssh_open ? _('Đang MỞ') : _('Đang ĐÓNG')),
						E('button', {
							class: 'btn cbi-button ' + (st.wan_ssh_open ? 'cbi-button-reset' : 'cbi-button-apply'),
							click: function() { return callToggleWanPort('ssh', !st.wan_ssh_open, parseInt(sshPortInput.value, 10) || 22).then(function(r) { notify(r); location.reload(); }); }
						}, st.wan_ssh_open ? _('Đóng Port SSH WAN') : _('Mở Port SSH WAN'))
					])
				])
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('3. Đường Hầm Quản Trị Từ Xa Tạm Thời (Cloudflare / Funnel / SSH Tunnel)')),
				E('table', { class: 'table' }, [
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left', width: '32%' }, _('Trạng thái')), E('td', { class: 'td left' }, (st.tunnel_status || 'STOPPED') + (st.tunnel_type ? (' (' + st.tunnel_type + ', còn ~' + (st.tunnel_remaining || 0) + ' phút)') : '')) ]),
					E('tr', { class: 'tr' }, [ E('td', { class: 'td left' }, _('Đường dẫn truy cập')), E('td', { class: 'td left' }, [ tunnelLinkNode ]) ])
				]),
				E('div', { style: 'display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-top: 10px;' }, [
					E('span', {}, _('Thời lượng (phút):')),
					tunDurInput,
					E('button', {
						class: 'btn cbi-button cbi-button-apply',
						click: function() {
							return callStartTunnel(parseInt(tunDurInput.value, 10) || 15).then(function(r) {
								if (r && r.url)
									ui.addNotification(null, E('p', _('Đã mở Tunnel: ') + r.url), 'info');
								else
									ui.addNotification(null, E('p', (r && r.msg) || 'Không thể khởi tạo Tunnel!'), 'error');
								location.reload();
							});
						}
					}, _('Mở Tunnel Tạm Thời')),
					E('button', {
						class: 'btn cbi-button cbi-button-reset',
						click: function() { return callStopTunnel().then(function(r) { notify(r); location.reload(); }); }
					}, _('Đóng Tunnel'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
