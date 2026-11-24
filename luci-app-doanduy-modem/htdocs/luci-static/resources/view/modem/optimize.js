'use strict';
'require view';
'require rpc';
'require ui';

var callOptStatus = rpc.declare({ object: 'doanduy.opt', method: 'status', expect: {} });
var callOptApply = rpc.declare({ object: 'doanduy.opt', method: 'apply', expect: {} });
var callOptOffload = rpc.declare({ object: 'doanduy.opt', method: 'toggleOffload', params: ['enable'], expect: {} });
var callOptReset = rpc.declare({ object: 'doanduy.opt', method: 'reset', expect: {} });

function notify(r) {
	ui.addNotification(null, E('p', (r && r.message) ? r.message : 'Hoàn tất!'), (r && r.success) ? 'info' : 'error');
}

return view.extend({
	load: function() {
		return L.resolveDefault(callOptStatus(), {});
	},

	render: function(st) {
		st = st || {};
		var isNss = (st.soc_type === 'qualcomm_ipq_nss');

		function row(k, v) {
			return E('tr', { class: 'tr' }, [
				E('td', { class: 'td left', width: '35%' }, k),
				E('td', { class: 'td left', style: 'font-weight: 600;' }, String(v != null ? v : '-'))
			]);
		}

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('Tối Ưu Phần Cứng & Mạng Tự Thích Ứng (Mọi Router OpenWrt)')),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Thông số Phần cứng Phát hiện Tự động')),
				E('table', { class: 'table' }, [
					row(_('Thiết bị Router'), st.model || '-'),
					row(_('Kiến trúc SoC'), st.soc_label || st.soc_type || '-'),
					row(_('Số nhân CPU / Nhiệt độ'), (st.cores || 1) + ' Cores  |  ' + (st.temp_c || 'N/A') + '°C'),
					row(_('RAM Vật lý / Khả dụng'), (st.mem_total_mb || 0) + ' MB (' + (st.ram_tier || '-') + ')  |  Còn trống: ' + (st.mem_avail_mb || 0) + ' MB'),
					row(_('Bộ nhớ Flash (/overlay)'), st.flash_info || '-'),
					row(_('Kiểm soát nghẽn TCP'), (st.tcp_cc || 'cubic').toUpperCase() + (st.bbr_supported ? ' (Hỗ trợ BBR)' : '')),
					row(_('Flow Offload Firewall'), st.flow_offload ? (st.flow_offload_hw ? _('BẬT (Hardware + Software)') : _('BẬT (Software)')) : _('TẮT (Tương thích TTL/MWAN3/VPN)')),
					row(_('Hồ sơ Tối ưu DOANDUY'), st.optimized ? _('Đã áp dụng (/etc/sysctl.d/99-doanduy-opt.conf)') : _('Chưa áp dụng (Đang chạy mặc định)'))
				]),
				E('div', { style: 'display: flex; gap: 10px; flex-wrap: wrap; margin-top: 14px;' }, [
					E('button', {
						class: 'btn cbi-button cbi-button-apply',
						click: function() { return callOptApply().then(function(r) { notify(r); location.reload(); }); }
					}, _('Áp Dụng Tối Ưu Tự Động (BBR + RAM Tier + Chống Ngủ USB/PCIe)')),
					!isNss ? E('button', {
						class: 'btn cbi-button cbi-button-action',
						click: function() { return callOptOffload(!st.flow_offload).then(function(r) { notify(r); location.reload(); }); }
					}, st.flow_offload ? _('Tắt Flow Offload (Ưu tiên Ép TTL / MWAN3)') : _('Bật Flow Offload Phần Cứng/Nhân')) : E('span', { style: 'color: #0369a1; font-weight: 600;' }, _('Qualcomm NSS: Tự khóa Software Offload để bảo toàn tăng tốc NSS')),
					E('button', {
						class: 'btn cbi-button cbi-button-reset',
						click: function() { return callOptReset().then(function(r) { notify(r); location.reload(); }); }
					}, _('Khôi Phục Mặc Định OpenWrt'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
