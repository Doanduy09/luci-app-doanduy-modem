// [VERIFIED-GOLDEN: part4-luci-overview-11-modem | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
'use strict';
'require baseclass';
'require rpc';

var callModemInfo = rpc.declare({
	object: 'modem_ctrl',
	method: 'info'
});

function progressbar(value, max, min, unit) {
	var val = parseInt(value, 10) || 0,
	    mx = parseInt(max, 10) || 100,
	    mn = parseInt(min, 10) || 0,
	    u = unit || '%',
	    span = (mx - mn) > 0 ? (mx - mn) : 100,
	    pct = Math.min(100, Math.max(0, Math.floor((100 / span) * (val - mn)))),
	    color = (pct >= 60) ? '#16a34a' : (pct >= 30 ? '#d97706' : '#dc2626');

	return E('div', {
		'class': 'cbi-progressbar',
		'title': '%s / %s%s (%d%%)'.format(val, mx, u, pct)
	}, E('div', {
		'style': 'width:%.2f%%; background:%s;'.format(pct, color)
	}));
}

return baseclass.extend({
	title: _('Thông tin Modem'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callModemInfo(), {})
		]);
	},

	render: function(data) {
		var table = E('table', { 'class': 'table' });
		try {
			var infos = (data && data[0] && Array.isArray(data[0].info)) ? data[0].info : [];
			var hasRows = false;

			for (var idx = 0; idx < infos.length; idx++) {
				var modemObj = infos[idx];
				var items = (modemObj && Array.isArray(modemObj.modem_info)) ? modemObj.modem_info : [];
				if (!items.length)
					continue;

				if (infos.length > 1) {
					table.appendChild(E('tr', { 'class': 'tr cbi-section-table-titles' }, [
						E('th', { 'class': 'th left', 'colspan': '2' }, [ _('Modem #%d').format(idx + 1) ])
					]));
				}

				for (var j = 0; j < items.length; j++) {
					var entry = items[j];
					if (!entry || entry.value == null || entry.value === '')
						continue;

					var label = entry.extra_info
						? '%s (%s)'.format(_(entry.full_name || ''), entry.extra_info)
						: _(entry.full_name || '');

					var valNode;
					if (entry.type === 'progress_bar') {
						valNode = E('td', { 'class': 'td left' }, [
							progressbar(entry.value, entry.max_value, entry.min_value, entry.unit)
						]);
					} else {
						valNode = E('td', { 'class': 'td left', 'style': 'font-weight: 600;' }, [
							String(entry.value)
						]);
					}

					table.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, [ label ]),
						valNode
					]));
					hasRows = true;
				}
			}

			if (!hasRows) {
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '100%' }, [ _('Chưa phát hiện thiết bị Modem 4G/5G') ])
				]));
			}
			return table;
		} catch (e) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '100%' }, [ _('Chưa phát hiện thiết bị Modem 4G/5G') ])
			]));
			return table;
		}
	}
});
// [/VERIFIED-GOLDEN]
