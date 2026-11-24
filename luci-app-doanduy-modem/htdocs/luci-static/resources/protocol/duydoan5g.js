'use strict';
'require rpc';
'require form';
'require network';

network.registerPatternVirtual(/^duydoan5g-.+$/);
network.registerErrorCode('NO_DEVICE', _('Không tìm thấy thiết bị modem 5G/LTE'));
network.registerErrorCode('NO_IP', _('Không nhận được địa chỉ IP từ mạng di động'));
network.registerErrorCode('CALL_FAILED', _('Quay số mạng di động thất bại'));

return network.registerProtocol('duydoan5g', {
	getI18n: function() {
		return _('DuyDoan 5G/LTE Cellular (PCIe/USB)');
	},

	getIfname: function() {
		return this._ubus('l3_device') || 'wwan0';
	},

	getDevice: function() {
		return this.getL3Device() || this.getL2Device() || network.instantiateDevice(this.getIfname(), this);
	},

	getPackageName: function() {
		return null;
	},

	isFloating: function() {
		return true;
	},

	isVirtual: function() {
		return false;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return (network.getIfnameOf(ifname) == this.getIfname());
	},

	renderFormOptions: function(s) {
		let dev = this.getL3Device() || this.getDevice(), o;

		o = s.taboption('general', form.Value, 'apn', _('Điểm truy cập APN (Mặc định: v-internet)'));
		o.placeholder = 'v-internet';
		o.default = 'v-internet';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'pincode', _('Mã PIN SIM'));
		o.password = true;
		o.rmempty = true;

		o = s.taboption('general', form.ListValue, 'auth', _('Xác thực PAP/CHAP'));
		o.value('none', _('Không (Mặc định)'));
		o.value('pap', 'PAP');
		o.value('chap', 'CHAP');
		o.value('both', _('PAP/CHAP/MSCHAPv2'));
		o.default = 'none';
		o.rmempty = true;

		o = s.taboption('general', form.Value, 'username', _('Tên đăng nhập APN'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'both');
		o.rmempty = true;

		o = s.taboption('general', form.Value, 'password', _('Mật khẩu APN'));
		o.password = true;
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'both');
		o.rmempty = true;

		o = s.taboption('advanced', form.ListValue, 'pdptype', _('Giao thức PDP'));
		o.value('ipv4v6', _('IPv4/IPv6 Dual-Stack'));
		o.value('ip', _('IPv4 Only'));
		o.value('ipv6', _('IPv6 Only'));
		o.default = 'ipv4v6';
		o.rmempty = true;

		o = s.taboption('advanced', form.Value, 'mtu', _('MTU'));
		o.datatype = 'range(1280,1500)';
		o.placeholder = '1460';
		o.default = '1460';
		o.rmempty = true;

		o = s.taboption('advanced', form.Value, 'metric', _('Độ ưu tiên Gateway (Metric)'));
		o.datatype = 'uinteger';
		o.placeholder = '10';
		o.default = '10';
		o.rmempty = true;

		o = s.taboption('advanced', form.Value, 'pdp_index', _('PDP Context ID (Tùy chọn)'));
		o.datatype = 'uinteger';
		o.placeholder = 'Auto';
		o.rmempty = true;

		o = s.taboption('advanced', form.Flag, 'force_apn', _('Ép đặt lại APN (Telit / QMI nghiêm ngặt)'));
		o.default = '0';
		o.rmempty = true;
	}
});
