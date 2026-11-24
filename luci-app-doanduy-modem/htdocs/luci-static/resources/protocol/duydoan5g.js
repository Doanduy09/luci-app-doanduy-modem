'use strict';
'require rpc';
'require form';
'require network';

network.registerPatternVirtual(/^duydoan5g-.+$/);
network.registerErrorCode('NO_IP', _('Không nhận được địa chỉ IP từ mạng di động'));
network.registerErrorCode('CALL_FAILED', _('Quay số mạng di động thất bại'));

return network.registerProtocol('duydoan5g', {
	getI18n: function() {
		return _('DuyDoan 5G/LTE Cellular (PCIe/USB)');
	},

	getIfname: function() {
		return this._ubus('l3_device') || 'mhi_hwip0';
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

		o = s.taboption('advanced', form.Value, 'metric', _('Độ ưu tiên Gateway (Metric)'));
		o.datatype = 'uinteger';
		o.placeholder = '10';
		o.default = '10';
		o.rmempty = true;
	}
});
