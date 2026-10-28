'use strict';
'require view';
'require poll';
'require rpc';
'require ui';

var callTopology = rpc.declare({ object: 'luci.airoha_npu', method: 'getTopology' });
var callMulticast = rpc.declare({ object: 'luci.airoha_npu', method: 'getMulticast', nobatch: true });
var callMulticastFilter = rpc.declare({ object: 'luci.airoha_npu', method: 'getMulticastFilter', nobatch: true });
var callNpuStatus = rpc.declare({ object: 'luci.airoha_npu', method: 'getStatus' });
var callPpeEntries = rpc.declare({ object: 'luci.airoha_npu', method: 'getPpeEntries', nobatch: true });
var callTokenInfo = rpc.declare({ object: 'luci.airoha_npu', method: 'getTokenInfo', nobatch: true });
var callFrameEngine = rpc.declare({ object: 'luci.airoha_npu', method: 'getFrameEngine', nobatch: true });
var callSetGovernor = rpc.declare({ object: 'luci.airoha_npu', method: 'setGovernor', params: ['governor'] });
var callSetMaxFreq = rpc.declare({ object: 'luci.airoha_npu', method: 'setMaxFreq', params: ['freq'] });
var callSetOverclock = rpc.declare({ object: 'luci.airoha_npu', method: 'setOverclock', params: ['freq_mhz'] });
var callGetVlanOffload = rpc.declare({ object: 'luci.airoha_npu', method: 'getVlanOffload', nobatch: true });
var callSetVlanOffload = rpc.declare({ object: 'luci.airoha_npu', method: 'setVlanOffload', params: ['enabled'] });
var callGetPPPoEOffload = rpc.declare({ object: 'luci.airoha_npu', method: 'getPPPoEOffload', nobatch: true });
var callSetPPPoEOffload = rpc.declare({ object: 'luci.airoha_npu', method: 'setPPPoEOffload', params: ['enabled'] });

var ppeSnapshot = { entries: [], truncated: false, error: 'not_loaded' };
var boardTopology = {};
var lastStatusPoll = 0;
var lastFilterSample = null;
var ppeReading = false;

function hasWifi() {
	return boardTopology.has_wifi === true;
}

function displayNetdev(name) {
	return /^lan[0-9]+$/.test(name) ? name.toUpperCase() : name;
}

function gdmLabel(key) {
	var devices = boardTopology.gdm && boardTopology.gdm[key];
	if (!Array.isArray(devices)) return _('Port mapping unavailable');
	if (!devices.length) return _('No registered network device');

	return devices.map(function(port) {
		if (port.pon) return _('PON uplink (%s)').format(port.netdev);
		if (Array.isArray(port.switch_ports) && port.switch_ports.length)
			return _('Internal switch (%s)').format(port.switch_ports.map(displayNetdev).join('/'));
		return [displayNetdev(port.netdev), (port.phy_mode || '').toUpperCase()].filter(Boolean).join(' · ');
	}).join(', ');
}

function loadStatusData() {
	return Promise.all([
		L.resolveDefault(callNpuStatus(), {}),
		hasWifi() ? L.resolveDefault(callTokenInfo(), { tx_queues: [], station_counts: [] }) :
			Promise.resolve({ tx_queues: [], station_counts: [] }),
		L.resolveDefault(callFrameEngine(), { error: 'unavailable' }),
		L.resolveDefault(callGetVlanOffload(), { enabled: 0 }),
		L.resolveDefault(callGetPPPoEOffload(), { enabled: 0 }),
		L.resolveDefault(callMulticast(), { error: 'unavailable' }),
		L.resolveDefault(callMulticastFilter(), { error: 'unavailable' })
	]).then(function(data) {
		lastStatusPoll = performance.now();
		return [data[0], ppeSnapshot, data[1], sampleFrameEngine(data[2]), data[3], data[4], data[5], sampleMulticastFilter(data[6])];
	});
}

function addPpeStats(status, ppe) {
	var entries = Array.isArray(ppe && ppe.entries) ? ppe.entries : [];
	var bound = 0;

	for (var i = 0; i < entries.length; i++)
		if (entries[i].state === 'BND')
			bound++;

	status.offload_unavailable = !ppe || !!ppe.error;
	status.offload_bound = bound;
	status.offload_total = entries.length;
	status.offload_truncated = !!(ppe && ppe.truncated);
	return status;
}

function updatePpeView(ppe) {
	if (ppe && !ppe.error && Array.isArray(ppe.entries)) {
		ppeSnapshot = ppe; ppeSnapshot.received = new Date().toLocaleTimeString();
	} else {
		ppeSnapshot = Object.assign({}, ppeSnapshot, { error: 'unavailable' });
	}
	var entries = ppeSnapshot.entries;
	var stats = addPpeStats({}, ppeSnapshot);
	var bound = document.getElementById('fe-ppe-bound');
	var total = document.getElementById('fe-ppe-total');
	var table = document.getElementById('ppe-entries-table');
	var note = document.getElementById('ppe-sample-status');
	if (note) note.textContent = ppeSnapshot.error ? _('PPE sample unavailable; any displayed entries are from the last successful read.') : _('Last successful PPE read: %s').format(ppeSnapshot.received);

	if (bound)
		bound.textContent = stats.offload_unavailable ? _('N/A') : stats.offload_bound.toString() + (ppeSnapshot.truncated ? '+' : '');
	if (total)
		total.textContent = stats.offload_unavailable ? _('N/A') : stats.offload_total.toString() + (ppeSnapshot.truncated ? '+' : '');
	if (table) {
		while (table.rows.length > 1)
			table.deleteRow(1);
		renderPpeRows(entries).forEach(function(row) { table.appendChild(row); });
	}
}

function refreshPpeData() {
	if (ppeReading) return Promise.resolve();
	ppeReading = true;
	return L.resolveDefault(callPpeEntries(), { error:'unavailable' }).then(updatePpeView).finally(function() { ppeReading = false; });
}

/* ── Theme-adaptive CSS ── */
var themeCSS = '\
.soc-card{background:var(--soc-card-bg);border:1px solid var(--soc-border);border-radius:8px;padding:14px;transition:border-color .3s}\
.soc-card-accent{border-left-width:3px;border-left-style:solid}\
.soc-muted{color:var(--soc-muted)}\
.soc-text{color:var(--soc-text)}\
.soc-label{font-size:11px;color:var(--soc-muted)}\
.soc-bar-track{background:var(--soc-bar-track);border-radius:4px;overflow:hidden}\
.soc-pse-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:6px}\
.soc-pse-cell{background:var(--soc-card-bg);border:1px solid var(--soc-border);border-radius:5px;padding:6px 8px;font-size:12px}\
.soc-band-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:10px}\
.soc-gdm-grid,.soc-data-grid-3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-bottom:10px}\
.soc-cdm-grid,.soc-data-grid-2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-bottom:10px}\
.soc-flow-table{overflow-x:auto}\
@media(max-width:900px){.soc-gdm-grid,.soc-data-grid-3{grid-template-columns:1fr}.soc-cdm-grid,.soc-data-grid-2{grid-template-columns:1fr}.soc-band-grid{grid-template-columns:1fr}}\
';

function isDarkMode() {
	var selected = document.documentElement.dataset.theme;
	if (selected === 'dark') return true;
	if (selected === 'light') return false;
	if (selected === 'auto' && window.matchMedia)
		return window.matchMedia('(prefers-color-scheme: dark)').matches;

	// Fall back to sampling rendered backgrounds for themes without a mode flag.
	var els = [document.body, document.querySelector('.main-content'), document.querySelector('#maincontent'), document.querySelector('.cbi-map')];
	for (var i = 0; i < els.length; i++) {
		if (!els[i]) continue;
		var bg = window.getComputedStyle(els[i]).backgroundColor;
		var m = bg.match(/\d+/g);
		if (m && m.length >= 3) {
			var a = m.length >= 4 ? parseFloat(m[3]) : 1;
			if (a < 0.1) continue; // transparent, skip
			var lum = (parseInt(m[0]) * 299 + parseInt(m[1]) * 587 + parseInt(m[2]) * 114) / 1000;
			return lum < 128;
		}
	}
	return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
}

var _lastDarkMode = null;

function injectCSS() {
	var el = document.getElementById('soc-theme-css');
	if (!el) { el = document.createElement('style'); el.id = 'soc-theme-css'; document.head.appendChild(el); }

	var dark = isDarkMode();
	if (dark === _lastDarkMode) return;
	_lastDarkMode = dark;

	var vars = dark
		? ':root{--soc-card-bg:#1e1e1e;--soc-border:#333;--soc-muted:#999;--soc-text:#e0e0e0;--soc-bar-track:#333}'
		: ':root{--soc-card-bg:#fff;--soc-border:#d0d0d0;--soc-muted:#666;--soc-text:#222;--soc-bar-track:#e0e0e0}';
	el.textContent = themeCSS + vars;
}

/* ── Helpers ── */
var bandInfo = [
	{ name: '2.4 GHz', accent: '#ff9800' },
	{ name: '5 GHz', accent: '#2196f3' },
	{ name: '6 GHz', accent: '#9c27b0' }
];

var psePortMap = [
	{ name: 'CDM1', label: _('CPU DMA 1'),       color: '#607d8b' },
	{ name: 'GDM1', label: _('Internal Switch'), color: '#ff9800' },
	{ name: 'GDM2', label: 'GDM2',              color: '#4caf50' },
	{ name: 'GDM3', label: 'GDM3',        color: '#607d8b' },
	{ name: 'PPE1', label: _('PPE Engine 1'),    color: '#2196f3' },
	{ name: 'CDM2', label: _('CPU DMA 2'),       color: '#607d8b' },
	{ name: 'CDM3', label: 'CDM3',        color: '#607d8b' },
	{ name: 'CDM4', label: _('Internal DMA port'), color: '#607d8b' },
	{ name: 'PPE2', label: _('PPE Engine 2'),    color: '#2196f3' },
	{ name: 'GDM4', label: 'GDM4',              color: '#4caf50' }
];

function fmtFreq(khz) { return (!khz || khz === 0) ? _('N/A') : (khz / 1000).toFixed(0) + ' MHz'; }
function fmtK(n) {
	if (!n || n === 0) return '0';
	if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
	if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
	return n.toString();
}

function calcTotalMem(regions) {
	var t = 0;
	(regions || []).forEach(function(r) {
		var m = (r.size || '').match(/(\d+)\s*(KiB|MiB|GiB)/i);
		if (m) { var s = parseInt(m[1]); var u = m[2][0].toUpperCase(); t += u === 'G' ? s*1048576 : u === 'M' ? s*1024 : s; }
	});
	return t >= 1024 ? (t/1024).toFixed(0)+' MiB' : t+' KiB';
}

function tokenHealth(c, s) {
	if (!s) return { text: _('N/A'), color: '#888' };
	var p = c/s*100;
	return p < 50 ? { text:_('Healthy'), color:'#4caf50' } : p < 80 ? { text:_('Warning'), color:'#ff9800' } : { text:_('Critical'), color:'#f44336' };
}

function npuState(st, ti) {
	if (!st || typeof st.npu_loaded !== 'boolean')
		return { text: _('Unknown'), className: 'label-warning' };
	if (st && st.npu_loaded && ti && ti.npu_active)
		return { text: _('Wireless offload active'), className: 'label-success' };
	if (st && st.npu_loaded)
		return { text: _('Driver loaded'), className: 'label-success' };
	return { text: _('Not Active'), className: 'label-danger' };
}

function npuCores(st) {
	return Number.isInteger(st.npu_cores) && st.npu_cores > 0 ? st.npu_cores : null;
}

function npuInfo(st) {
	var version = st.npu_version;
	if (!version || version === 'Unknown') version = _('Unknown');
	else if (st.npu_version_source === 'firmware_file')
		version = _('%s (firmware file; running version unknown)').format(version);
	var cores = npuCores(st);
	return version + ' | ' + (st.npu_clock > 0 ? (st.npu_clock / 1e6).toFixed(0) + ' MHz' : _('N/A')) +
		' | ' + (cores !== null ? _('%d cores').format(cores) : _('Core count unavailable'));
}

function npuMemory(st) {
	var regions = Array.isArray(st.memory_regions) ? st.memory_regions : [];
	return regions.length ? calcTotalMem(regions) + ' (' + _('%d regions').format(regions.length) + ')' : _('N/A');
}

function updateNpuInfo(st) {
	var info = document.getElementById('npu-info');
	var memory = document.getElementById('npu-memory');
	if (info) info.textContent = npuInfo(st);
	if (memory) memory.textContent = npuMemory(st);
}

function getBandStats(ti, b) {
	var c = Array.isArray(ti.station_counts) ? ti.station_counts : [];
	for (var i=0;i<c.length;i++) if (c[i].band===b) return c[i];
	return { band:b, count:0, tx_packets:0, tx_retries:0 };
}

function getTxQueue(ti, b) {
	var q = Array.isArray(ti.tx_queues) ? ti.tx_queues : [];
	for (var i=0;i<q.length;i++) if (q[i].band===b) return q[i];
	return null;
}

function bandHealth(s, q) {
	if (!s || s.count===0) return { text:_('No clients'), color:'#888' };
	if (q && q.type === 'npu') return { text:_('Connected'), color:'#4caf50' };
	if (!s.tx_packets) return { text:_('Idle'), color:'#888' };
	var r = s.tx_retries/(s.tx_packets+s.tx_retries);
	return r>0.5 ? {text:_('Poor'),color:'#f44336'} : r>0.2 ? {text:_('Fair'),color:'#ff9800'} : {text:_('Good'),color:'#4caf50'};
}

function retryPct(s, q) {
	// NPU TX bypasses the host tx_packets counter while firmware retry
	// counters continue to advance, so a percentage would be meaningless.
	if (q && q.type === 'npu') return '';
	if (!s || !s.tx_packets) return '-';
	return (s.tx_retries/(s.tx_packets+s.tx_retries)*100).toFixed(1)+'%';
}

/* ── Mini Band Chip (compact for FE diagram) ── */
function renderBandChip(band, txQ, stats) {
	var info = bandInfo[band] || { name: _('Band %d').format(band), accent: '#888' };
	var id = 'band-'+band;
	var h = bandHealth(stats, txQ);
	var type = txQ ? txQ.type : '?';
	var rp = retryPct(stats, txQ);

	return E('div', { 'id': id, 'style': 'background:var(--soc-card-bg);border:1px solid var(--soc-border);border-left:2px solid '+info.accent+';border-radius:6px;padding:10px 12px' }, [
		E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px' }, [
			E('span', { 'class': 'soc-text', 'style': 'font-size:13px;font-weight:bold' }, info.name),
			E('span', { 'style': 'background:'+(type==='npu'?'#1565c0':'#666')+';color:#fff;padding:1px 6px;border-radius:3px;font-size:9px;font-weight:600' }, type.toUpperCase())
		]),
		E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;font-size:12px' }, [
			E('div', { 'id': id+'-health', 'style': 'display:flex;align-items:center;gap:4px' }, [
				E('span', { 'style': 'width:7px;height:7px;border-radius:50%;background:'+h.color+';display:inline-block' }),
				E('span', { 'style': 'color:'+h.color+';font-weight:500' }, h.text)
			]),
			E('span', { 'id': id+'-clients', 'class': 'soc-muted' }, _('%d stations').format(stats.count)),
			rp ? E('span', { 'id': id+'-retries', 'class': 'soc-muted' }, rp) : E('span')
		])
	]);
}

function updateBandChip(band, stats, txQ) {
	var id = 'band-'+band, h = bandHealth(stats, txQ);
	var el = document.getElementById(id+'-health');
	if (el) { el.innerHTML = ''; el.appendChild(E('span',{'style':'width:6px;height:6px;border-radius:50%;background:'+h.color+';display:inline-block'})); el.appendChild(E('span',{'style':'color:'+h.color+';font-weight:500;font-size:11px'},h.text)); }
	var cl = document.getElementById(id+'-clients');
	if (cl) cl.textContent = _('%d stations').format(stats.count);
	var re = document.getElementById(id+'-retries');
	if (re) { var rp2 = retryPct(stats, txQ); re.textContent = rp2; }
}

/* Compare only valid counters from the same device boot and a short interval.
 * A decrease is ambiguous (reset or wrap), so report no delta and rebase. */
var previousFe = null;
function counterDelta(value, before) {
	return Number.isSafeInteger(value) && Number.isSafeInteger(before) &&
		value >= 0 && before >= 0 && value >= before ? value - before : null;
}
function sampleFrameEngine(fe) {
	if (!fe || fe.error || !Number.isFinite(fe.time) || !fe.boot_id) { previousFe = null; return fe; }
	var prev = previousFe, dt = prev ? fe.time - prev.time : 0;
	var valid = prev && fe.boot_id == prev.boot_id && dt > 0 && dt <= 60;
	fe.interval = valid ? dt : null;
	fe.delta = {};
	['gdm1','gdm2','gdm4','cdm1','cdm2'].forEach(function(key) {
		fe.delta[key] = {};
		Object.keys(fe[key] || {}).forEach(function(field) {
			fe.delta[key][field] = valid ? counterDelta(fe[key][field], (prev[key] || {})[field]) : null;
		});
	});
	(fe.pse_ports || []).forEach(function(port) {
		var old = valid && (prev.pse_ports || []).find(function(p) { return p.port == port.port; });
		port.drop_delta = old ? counterDelta(port.drops, old.drops) : null;
	});
	previousFe = fe;
	return fe;
}
function counterText(value, delta) {
	if (!Number.isSafeInteger(value)) return _('N/A');
	return String(value) + ' / ' + (Number.isSafeInteger(delta) ? '+' + delta : '—');
}

/* ── Frame Engine Diagram ── */
function renderFeDiagram(fe, ti, st) {
	if (!fe || fe.error) return E('div', { 'class': 'soc-muted' }, _('Hardware sample unavailable'));
	ti = ti || {}; st = st || {};
	var ports = Array.isArray(fe.pse_ports) ? fe.pse_ports : [];

	function counters(key, fields) {
		var d = fe[key] || {}, delta = (fe.delta || {})[key] || {};
		var rows = [];
		fields.forEach(function(field) {
			var changed = field[0].indexOf('drop') >= 0 && delta[field[0]] > 0;
			rows.push(E('span', { 'class':'soc-muted' }, field[1]),
				E('span', { 'style':'text-align:right' + (changed ? ';color:#e69500' : '') }, counterText(d[field[0]], delta[field[0]])));
		});
		return E('div', { 'style':'display:grid;grid-template-columns:auto 1fr;gap:2px 10px;font-size:12px' }, rows);
	}
	function card(key, name, label, color, pse, fields) {
		return E('div', { 'class':'soc-card soc-card-accent', 'style':'border-left-color:'+color }, [
			E('div', { 'style':'display:flex;justify-content:space-between;margin-bottom:4px' }, [
				E('strong', { 'style':'color:'+color }, name), E('span', {'class':'soc-label'}, pse)]),
			E('div', {'class':'soc-label'}, label),
			E('div', {'class':'soc-muted'}, _('Counter / interval change')), counters(key, fields)
		]);
	}
	function gdmCard(key, name, label, color, pse) {
		return card(key, name, label, color, pse, [
			['tx','TX'], ['rx','RX'], ['tx_drop',_('TX Drops')],
			['rx_fc_drop',_('RX flow-control drops')], ['rx_rc_drop',_('RX RC drops')],
			['rx_overflow_drop',_('RX overflow drops')], ['rx_error_drop',_('RX error drops')],
			['rx_eth_drop',_('RX Ethernet drops')]
		]);
	}
	function cdmCard(key, name, label, pse) {
		return card(key, name, label, '#607d8b', pse, [
			['tx','TX'], ['rx_cpu','RX CPU'], ['rx_hwf','RX HWF'],
			['rx_cpu_drop',_('RX CPU drops')], ['rx_hwf_drop',_('RX HWF drops')]
		]);
	}

	// WiFi band chips for CDM4
	var bandChips = [];
	if (hasWifi())
		for (var b = 0; b < 3; b++) bandChips.push(renderBandChip(b, getTxQueue(ti, b), getBandStats(ti, b)));

	// CDM4/WDMA + WiFi bands grouped
	var p7 = ports[7] || { iq: null, oq: null, drops: null };
	var p7Counter = ti.npu_active
		? _('NPU handoff: %s').format(counterText(p7.drops, p7.drop_delta))
		: _('Drops: %s').format(counterText(p7.drops, p7.drop_delta));
	var cdm4WiFi = hasWifi() ? E('div', { 'class': 'soc-card soc-card-accent', 'style': 'border-left-color:#9c27b0' }, [
		E('div', { 'style': 'display:flex;justify-content:space-between;align-items:baseline;margin-bottom:2px' }, [
			E('span', { 'style': 'font-weight:bold;color:#9c27b0;font-size:14px' }, 'CDM4'),
			E('span', { 'class': 'soc-label' }, _('P7 WiFi DMA'))
		]),
		E('div', { 'style': 'display:flex;gap:12px;font-size:11px;margin-bottom:8px' }, [
			E('span', { 'class': 'soc-muted' }, 'IQ '+p7.iq),
			E('span', { 'class': 'soc-muted' }, 'OQ '+p7.oq),
			E('span', { 'class': 'soc-muted' }, p7Counter)
		].filter(Boolean)),
		// WiFi bands inside
		E('div', { 'style': 'display:grid;grid-template-columns:repeat(3,1fr);gap:6px' }, bandChips)
	]) : null;

	// NPU indicator
	var npuReady = !!st.npu_loaded;
	var npuActive = npuReady && !!ti.npu_active;
	var npuLabel = typeof st.npu_loaded !== 'boolean' ? _('Unknown') :
		npuActive ? _('Wireless offload active') : npuReady ? _('Driver loaded') : _('OFF');
	var npuCard = E('div', { 'class': 'soc-card', 'style': 'border-color:'+(npuActive?'#00bcd4':'var(--soc-border)') }, [
		E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:4px' }, [
			E('span', { 'style': 'font-weight:bold;color:#00bcd4;font-size:14px' }, 'NPU'),
			E('span', { 'style': 'background:'+(npuActive?'#00695c':'#666')+';color:#fff;padding:1px 7px;border-radius:3px;font-size:10px;font-weight:600' }, npuLabel)
		]),
		E('div', { 'class': 'soc-label', 'style': 'margin-bottom:4px' }, npuCores(st) !== null ?
			_('%dx RISC-V via reserved RAM').format(npuCores(st)) : _('Core count unavailable')),
		E('div', { 'style': 'font-size:11px' }, [
			E('span', { 'class': 'soc-muted' }, _('Manages:') + ' '),
			E('span', { 'class': 'soc-text', 'style': 'font-size:11px' }, hasWifi() ?
				_('PPE initialization, WDMA rings, flow statistics') : _('PPE initialization and flow statistics'))
		])
	]);

	// PPE engines with flow count
	var ppeCard = E('div', { 'class': 'soc-card', 'style': 'border-color:#2196f3' }, [
		E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:4px' }, [
			E('span', { 'style': 'font-weight:bold;color:#2196f3;font-size:14px' }, _('PPE Engines')),
			E('span', { 'class': 'soc-label' }, 'P4 + P8')
		]),
		E('div', { 'style': 'display:flex;gap:16px;font-size:12px' }, [
			E('span', {}, [
				E('span', { 'class': 'soc-muted' }, _('Bound') + ' '),
				E('span', { 'class': 'soc-text', 'style': 'font-weight:bold', 'id': 'fe-ppe-bound' }, st.offload_unavailable ? _('N/A') : st.offload_bound.toString()+(st.offload_truncated?'+':''))
			]),
			E('span', {}, [
				E('span', { 'class': 'soc-muted' }, _('Total') + ' '),
				E('span', { 'class': 'soc-text', 'id': 'fe-ppe-total' }, st.offload_unavailable ? _('N/A') : st.offload_total.toString()+(st.offload_truncated?'+':''))
			])
		])
	]);

	// PSE buffer
	var pseValid = Number.isInteger(fe.pse_used) && Number.isInteger(fe.pse_free);
	var pseT = pseValid ? fe.pse_used + fe.pse_free : 0;
	var pseP = pseValid && pseT>0 ? ((fe.pse_used/pseT)*100).toFixed(1) : null;
	var pseCol = parseFloat(pseP)>80?'#f44336':parseFloat(pseP)>50?'#ff9800':'#4caf50';

	// P7 exists independently of registered WiFi PHYs. Describe the hardware
	// port here; wireless topology belongs to the optional WiFi card above.
	var portCells = ports.filter(function(p){ return p.port !== 7 || !hasWifi(); }).map(function(p) {
		var info = psePortMap[p.port] || { name:'P'+p.port, label:'?', color:'#666' };
		var gdmKey = { 1: 'gdm1', 2: 'gdm2', 9: 'gdm4' }[p.port];
		var label = gdmKey ? gdmLabel(gdmKey) : info.label;
		var drop = p.drop_delta > 0;
		return E('div', { 'class': 'soc-pse-cell', 'style': drop ? 'border-color:#e69500' : '' }, [
			E('div', { 'style': 'font-weight:600;color:'+info.color+';font-size:11px' }, 'P'+p.port+' '+info.name),
			E('div', { 'class': 'soc-label' }, label),
			E('div', {
				'style': 'display:flex;gap:8px;font-size:11px;margin-top:2px',
				'title': _('IQ/OQ are raw hardware queue counters, not wireless device or client counts.')
			}, [
				E('span', { 'class': 'soc-muted' }, 'IQ '+(p.iq == null ? _('N/A') : p.iq)),
				E('span', { 'class': 'soc-muted' }, 'OQ '+(p.oq == null ? _('N/A') : p.oq)),
				E('span', { 'class':'soc-muted' }, _('Drops: %s').format(counterText(p.drops, p.drop_delta)))
			].filter(Boolean))
		]);
	});

	return E('div', { 'id': 'fe-diagram' }, [
		E('p', {'class':'soc-muted'}, _('Raw 32-bit hardware counters may wrap or reset. Drop classes can overlap and are not added together.')),
		E('p', {'class':'soc-muted'}, fe.interval == null ? _('Waiting for a second hardware sample') : _('Last interval: %s s').format(fe.interval.toFixed(1))),
		// PSE buffer bar
		E('div', { 'class': 'soc-card', 'style': 'margin-bottom:10px' }, [
			E('div', { 'style': 'display:flex;justify-content:space-between;margin-bottom:4px' }, [
				E('span', { 'class': 'soc-text', 'style': 'font-weight:bold;font-size:13px' }, _('PSE Shared Buffer')),
				E('span', { 'class': 'soc-muted', 'style': 'font-size:12px' }, pseP == null ? _('N/A') : _('%d used / %d free (%s%%)').format(fe.pse_used, fe.pse_free, pseP))
			]),
			E('div', { 'class': 'soc-bar-track', 'style': 'height:8px' }, [
				E('div', { 'style': 'background:'+pseCol+';height:100%;width:'+(pseP || 0)+'%;border-radius:4px;transition:width .5s' })
			])
		]),
		// Row 1: GDM ports
		E('div', { 'class': 'soc-gdm-grid' }, [
			gdmCard('gdm1', 'GDM1', gdmLabel('gdm1'), '#ff9800', 'P1'),
			gdmCard('gdm2', 'GDM2', gdmLabel('gdm2'), '#4caf50', 'P2'),
			gdmCard('gdm4', 'GDM4', gdmLabel('gdm4'), '#4caf50', 'P9')
		]),
		// Row 2: CDM1/CDM2 (CPU) + CDM4/WiFi
		E('div', { 'class': hasWifi() ? 'soc-data-grid-3' : 'soc-data-grid-2' }, [
			cdmCard('cdm1', 'CDM1', _('CPU DMA 1'), 'P0'),
			cdmCard('cdm2', 'CDM2', _('CPU DMA 2'), 'P5'),
			cdm4WiFi
		].filter(Boolean)),
		// Row 3: PPE + NPU
		E('div', { 'class': 'soc-data-grid-2' }, [
			ppeCard,
			npuCard
		]),
		// PSE port grid
		E('div', { 'class': 'soc-text', 'style': 'font-size:12px;font-weight:600;margin-bottom:6px' }, _('PSE Port Queue Status')),
		E('div', { 'class': 'soc-pse-grid' }, portCells)
	]);
}

/* ── CPU Frequency ── */
function freqBarState(hw, min, max, pll, gov) {
	var oc = gov==='performance' && pll>0 && (pll*1000)>max;
	return { freq: oc ? pll*1000 : Math.min(hw,max), max: oc ? pll*1000 : max, oc: oc };
}

function renderFreqBar(hw, min, max, pll, gov) {
	if (!max) return E('span',{},_('N/A'));
	var s = freqBarState(hw,min,max,pll,gov);
	var pct = Math.round(((s.freq-min)/(s.max-min))*100);
	pct = Math.max(0,Math.min(100,pct));
	var bg = s.oc ? 'linear-gradient(90deg,#e65100,#ff9800)' : 'linear-gradient(90deg,#2e7d32,#66bb6a)';
	var label = s.oc ? (pll+' MHz (OC)') : fmtFreq(s.freq);

	return E('div', { 'id':'cpu-freq-bar-wrap', 'style':'display:flex;align-items:center;gap:10px' }, [
		E('span', { 'class':'soc-muted', 'style':'font-size:90%' }, fmtFreq(min)),
		E('div', { 'style':'flex:1;border-radius:4px;height:22px;position:relative;min-width:180px;max-width:350px;overflow:hidden', 'class':'soc-bar-track' }, [
			E('div', { 'id':'cpu-freq-fill', 'style':'background:'+bg+';height:100%;border-radius:4px;width:'+pct+'%;transition:width .5s' }),
			E('span', { 'id':'cpu-freq-text', 'style':'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-weight:bold;font-size:13px;color:#fff;text-shadow:0 1px 2px rgba(0,0,0,.6)' }, label)
		]),
		E('span', { 'id':'cpu-freq-max-label', 'class':'soc-muted', 'style':'font-size:90%' }, fmtFreq(s.max))
	]);
}

function updateFreqBar(hw, min, max, pll, gov) {
	var s = freqBarState(hw,min,max,pll,gov);
	var el = document.getElementById('cpu-freq-text'), fl = document.getElementById('cpu-freq-fill'), ml = document.getElementById('cpu-freq-max-label');
	if (el) el.textContent = s.oc ? (pll+' MHz (OC)') : fmtFreq(s.freq);
	if (fl && s.max>0) { var pct=Math.max(0,Math.min(100,Math.round(((s.freq-min)/(s.max-min))*100))); fl.style.width=pct+'%'; fl.style.background=s.oc?'linear-gradient(90deg,#e65100,#ff9800)':'linear-gradient(90deg,#2e7d32,#66bb6a)'; }
	if (ml) ml.textContent = fmtFreq(s.max);
}

function renderGovSelect(avail, active) {
	var gs = (avail||'').trim().split(/\s+/).filter(Boolean);
	if (!gs.length) return E('span',{},_('N/A'));
	return E('select', { 'id':'cpu-governor-select','class':'cbi-input-select','style':'min-width:140px','change':function(ev){
		var g=ev.target.value; ev.target.disabled=true;
		callSetGovernor(g).then(function(r){ev.target.disabled=false;if(r&&r.error) ui.addNotification(null,E('p',{},_('Error:')+' '+r.error),'error');}).catch(function(){ev.target.disabled=false;});
	}}, gs.map(function(g){return E('option',{'value':g,'selected':g===active?'':null},g);}));
}

function renderMaxFreqSelect(avail, cur) {
	var fs = (avail||'').trim().split(/\s+/).filter(Boolean);
	if (!fs.length) return E('span',{},_('N/A'));
	return E('select', { 'id':'cpu-maxfreq-select','class':'cbi-input-select','style':'min-width:140px','change':function(ev){
		var f=ev.target.value; ev.target.disabled=true;
		callSetMaxFreq(parseInt(f)).then(function(r){ev.target.disabled=false;if(r&&r.error) ui.addNotification(null,E('p',{},_('Error:')+' '+r.error),'error');}).catch(function(){ev.target.disabled=false;});
	}}, fs.map(function(f){return E('option',{'value':f,'selected':parseInt(f)===parseInt(cur)?'':null},(parseInt(f)/1000).toFixed(0)+' MHz');}));
}

function renderOcControls(nativePll) {
	if (nativePll) return E('span', {'class':'soc-muted'},
		_('Native CPUFreq: use Max Frequency to set the upper limit. This keeps the selected governor. The firmware frequency table supplies the boot default; changes here last until reboot.'));
	var inp = E('input',{'id':'oc-freq-input','type':'number','min':'500','max':'1600','step':'50','value':'1400','class':'cbi-input-text','style':'width:100px'});
	var btn = E('button',{'class':'cbi-button cbi-button-action','style':'margin-left:8px','click':function(){
		var f=parseInt(document.getElementById('oc-freq-input').value);
		if(isNaN(f)||f<500||f>1600){ui.addNotification(null,E('p',{},_('Must be 500-1600 MHz')),'error');return;}
		if(f>1400&&!confirm(_('Frequencies above 1400 MHz may be unstable. Continue?'))) return;
		btn.disabled=true;btn.textContent=_('Applying...');
		callSetOverclock(f).then(function(r){btn.disabled=false;btn.textContent=_('Apply');
			if(r&&r.error) ui.addNotification(null,E('p',{},_('Failed:')+' '+r.error),'error');
			else if(r&&r.result==='ok') ui.addNotification(null,E('p',{},_('CPU set to')+' '+r.actual_mhz+' MHz'),'info');
		}).catch(function(e){btn.disabled=false;btn.textContent=_('Apply');});
	}},_('Apply'));
	return E('div',{'style':'display:flex;align-items:center;gap:8px;flex-wrap:wrap'},[
		inp, E('span',{'class':'soc-muted'},'MHz'), btn,
		E('span',{'class':'soc-muted','style':'font-size:85%;margin-left:8px'},_('Legacy direct PLL control forces the performance governor and bypasses the CPUFreq frequency table. Stability above the stock limit depends on the device. Changes last until reboot.'))
	]);
}

function renderTempBar(temp) {
	// temp is now an integer in 0.1 C units (e.g. 516 == 51.6 C)
	var v = (temp||0) / 10;
	var pos = Math.max(0, Math.min(125, v)) * 100 / 125;
	var color = v>=100?'linear-gradient(90deg,#b71c1c,#f44336)' : v>=80?'linear-gradient(90deg,#e65100,#ff9800)' : 'linear-gradient(90deg,#2e7d32,#66bb6a)';
	var label = v.toFixed(1) + ' \u00B0C';
	return E('div', { 'id':'cpu-temp-bar-wrap', 'style':'display:flex;align-items:center;gap:10px' }, [
		E('span', { 'class':'soc-muted', 'style':'font-size:90%' }, '-25 \u00B0C'),
		E('div', { 'style':'flex:1;border-radius:4px;height:22px;position:relative;min-width:180px;max-width:350px;overflow:hidden', 'class':'soc-bar-track' }, [
			E('div', { 'id':'cpu-temp-fill', 'style':'background:'+color+';height:100%;border-radius:4px;width:'+pos+'%;transition:width .5s' }),
			E('span', { 'id':'cpu-temp-text', 'style':'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-weight:bold;font-size:13px;color:#fff;text-shadow:0 1px 2px rgba(0,0,0,.6)' }, label)
		]),
		E('span', { 'id':'cpu-temp-max-label', 'class':'soc-muted', 'style':'font-size:90%' }, '125 \u00B0C')
	]);
}

function updateTempBar(temp) {
	var v = (temp||0) / 10;
	var pos = Math.max(0, Math.min(125, v)) * 100 / 125;
	var color = v>=100?'linear-gradient(90deg,#b71c1c,#f44336)' : v>=80?'linear-gradient(90deg,#e65100,#ff9800)' : 'linear-gradient(90deg,#2e7d32,#66bb6a)';
	var el = document.getElementById('cpu-temp-text'), fl = document.getElementById('cpu-temp-fill');
	if (el) el.textContent = v.toFixed(1) + ' \u00B0C';
	if (fl) { fl.style.width=pos+'%'; fl.style.background=color; }
}

/* CPU history is local to this view and positioned by device uptime. */
var cpuBaseline = null, cpuHistory = [], cpuIds = [], cpuNow = 0;
var cpuLatest = null, cpuInterval = null;
var cpuUnavailable = false;
var cpuColors = ['#00bcd4', '#ff9800', '#f44336', '#4caf50'];

function acceptCpuSample(sample) {
	cpuLatest = null;
	if (!sample || typeof sample.boot_id != 'string' || !Number.isFinite(sample.time) ||
		!Array.isArray(sample.cpus) || !sample.cpus.length || !sample.cpus.every(function(c) {
			return /^cpu[0-9]+$/.test(c.id) && Number.isSafeInteger(c.total) &&
				Number.isSafeInteger(c.idle) && c.total >= c.idle && c.idle >= 0;
		})) { cpuBaseline = null; cpuUnavailable = true; return; }
	cpuUnavailable = false;
	var ids = sample.cpus.map(function(c) { return c.id; });
	var old = cpuBaseline;
	if (!old || old.boot_id != sample.boot_id || sample.time <= old.time ||
		JSON.stringify(ids) != JSON.stringify(cpuIds)) {
		cpuHistory = []; cpuIds = ids; cpuNow = sample.time; cpuBaseline = sample;
		return;
	}
	cpuNow = sample.time;
	cpuInterval = sample.time - old.time;
	// Ignore an immediate second request without shortening the baseline.
	if (cpuInterval < 5) return;
	var values = [], busy = 0, total = 0, valid = true;
	sample.cpus.forEach(function(c, i) {
		var dt = c.total - old.cpus[i].total, di = c.idle - old.cpus[i].idle;
		if (dt <= 0 || di < 0 || di > dt) { valid = false; return; }
		values.push(100 * (dt - di) / dt); busy += dt - di; total += dt;
	});
	cpuBaseline = sample;
	if (!valid) { cpuHistory = []; return; }
	cpuLatest = 100 * busy / total;
	cpuHistory.push({ time: sample.time, gap: cpuInterval > 20, values: values });
	cpuHistory = cpuHistory.filter(function(p) { return cpuNow - p.time <= 600; }).slice(-61);
}

function cpuChartContents() {
	var children = [E('span', {'class':'soc-muted'}, _('Last 10 minutes'))];
	cpuIds.forEach(function(id, i) {
		var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
		svg.setAttribute('viewBox', '0 0 140 50');
		svg.setAttribute('role', 'img');
		svg.setAttribute('aria-label', id);
		svg.style.cssText = 'width:140px;height:50px;background:var(--soc-bar-track);border-radius:3px';
		var path = document.createElementNS(svg.namespaceURI, 'path');
		var d = '';
		cpuHistory.forEach(function(p, n) {
			var x = 140 * (1 - (cpuNow - p.time) / 600);
			var y = 50 * (1 - p.values[i] / 100);
			d += (n === 0 || p.gap ? 'M' : 'L') + x.toFixed(2) + ',' + y.toFixed(2) + ' ';
		});
		path.setAttribute('d', d); path.setAttribute('fill', 'none');
		path.setAttribute('stroke', cpuColors[i % cpuColors.length]); path.setAttribute('stroke-width', '2');
		svg.appendChild(path);
		var last = cpuHistory[cpuHistory.length - 1];
		if (last && cpuLatest != null) {
			var dot = document.createElementNS(svg.namespaceURI, 'circle');
			dot.setAttribute('cx', '140'); dot.setAttribute('cy', String(50 * (1 - last.values[i] / 100)));
			dot.setAttribute('r', '2'); dot.setAttribute('fill', cpuColors[i % cpuColors.length]); svg.appendChild(dot);
		}
		children.push(E('div', {}, [E('div', {'class':'soc-muted'}, id + ': ' +
			(cpuLatest != null && last ? last.values[i].toFixed(1) + '%' : _('N/A'))), svg]));
	});
	children.push(E('span', {'id':'cpu-usage-text'}, cpuUnavailable ? _('CPU sample unavailable') : cpuLatest == null ? _('Waiting for CPU samples') : cpuLatest.toFixed(1) + '%'));
	children.push(E('span', {'class':'soc-muted'}, _('Samples approximately every 10 seconds; history starts when this page opens.')));
	if (cpuLatest != null) children.push(E('span', {'class':'soc-muted'}, _('Last interval: %s s').format(cpuInterval.toFixed(1))));
	return children;
}

function renderCpuUsageChart(sample) {
	acceptCpuSample(sample);
	return E('div', {'id':'cpu-usage-chart-wrap', 'style':'display:flex;align-items:center;gap:8px;flex-wrap:wrap'}, cpuChartContents());
}

function updateCpuUsageChart(sample) {
	acceptCpuSample(sample);
	var node = document.getElementById('cpu-usage-chart-wrap');
	if (node) { node.textContent = ''; cpuChartContents().forEach(function(c) { node.appendChild(c); }); }
}

/* ── PPE Table ── */
function renderPpeRows(entries) {
	return entries.slice(0,100).map(function(e) {
		var eth = e.eth||''; if(eth==='00:00:00:00:00:00->00:00:00:00:00:00') eth='-';
		if (e.type && e.type.indexOf('IPv6') === 0 && e.state != 'UNB') {
			eth = e.smac_id === 15 ? _('Original source MAC preserved') : Number.isInteger(e.smac_id) ? _('Source MAC index %s').format(e.smac_id) : _('Source MAC unavailable');
			if (e.dest_mac) eth += ' → ' + e.dest_mac;
			if (Number.isInteger(e.pppoe_sid)) eth += ' · PPPoE SID ' + e.pppoe_sid;
		}
		return E('tr',{'class':'tr'},[
			E('td',{'class':'td'},e.index), E('td',{'class':'td'},E('span',{'class':e.state==='BND'?'label-success':''},e.state)),
			E('td',{'class':'td'},e.type), E('td',{'class':'td'},e.orig||'-'), E('td',{'class':'td'},e.new_flow||'-'), E('td',{'class':'td'},eth)
		]);
	});
}

function renderVlanOffloadSelect(state) {
	if (!state || state.available !== true) return E('span', { 'class': 'soc-muted' }, _('Not available'));
	var cur = state.bridge_filter ? '1' : '0';
	return E('select', { 'id': 'vlan-offload-select', 'class': 'cbi-input-select', 'style': 'min-width:140px', 'change': function(ev) {
		var v = parseInt(ev.target.value);
		ev.target.disabled = true;
		callSetVlanOffload(1 - v).then(function(r) {
			ev.target.disabled = false;
			if (r && r.error) ui.addNotification(null, E('p', {}, _('Error:') + ' ' + r.error), 'error');
		}).catch(function() { ev.target.disabled = false; });
	}}, [
		E('option', { 'value': '0', 'selected': cur === '0' ? '' : null }, _('Disabled')),
		E('option', { 'value': '1', 'selected': cur === '1' ? '' : null }, _('Enabled'))
	]);
}

function renderPPPoEOffloadSelect(state) {
	if (!state || state.available !== true) return E('span', { 'class': 'soc-muted' }, _('Not available'));
	var cur = state.bridge_filter ? '1' : '0';
	return E('select', { 'id': 'pppoe-offload-select', 'class': 'cbi-input-select', 'style': 'min-width:140px', 'change': function(ev) {
		var v = parseInt(ev.target.value);
		ev.target.disabled = true;
		callSetPPPoEOffload(1 - v).then(function(r) {
			ev.target.disabled = false;
			if (r && r.error) ui.addNotification(null, E('p', {}, _('Error:') + ' ' + r.error), 'error');
		}).catch(function() { ev.target.disabled = false; });
	}}, [
		E('option', { 'value': '0', 'selected': cur === '0' ? '' : null }, _('Disabled')),
		E('option', { 'value': '1', 'selected': cur === '1' ? '' : null }, _('Enabled'))
	]);
}

function unsignedCounter(value) {
	return typeof value === 'string' && /^[0-9]{1,20}$/.test(value);
}

function sampleMulticastFilter(input) {
	var m = Object.assign({}, input || {});
	m.drops_per_second = null;
	if (m.error || !m.available || m.broken || m.hardware_drops_error != null ||
		!unsignedCounter(m.hardware_drops) || typeof m.boot_id !== 'string' || !m.boot_id ||
		!Number.isFinite(m.uptime) || typeof BigInt !== 'function') {
		lastFilterSample = null;
		return m;
	}
	var prev = lastFilterSample;
	lastFilterSample = m;
	if (prev && prev.boot_id === m.boot_id && m.uptime > prev.uptime && m.uptime-prev.uptime <= 60 &&
		prev.errors === m.errors && (!unsignedCounter(m.generation) || !unsignedCounter(prev.generation) ||
			BigInt(m.generation) >= BigInt(prev.generation))) {
		var delta = BigInt(m.hardware_drops)-BigInt(prev.hardware_drops);
		if (delta >= BigInt(0) && delta <= BigInt(Number.MAX_SAFE_INTEGER))
			m.drops_per_second = Number(delta)/(m.uptime-prev.uptime);
	}
	return m;
}

function multicastFilterState(m) {
	if (!m || m.error || !m.available) return _('Filter status unavailable');
	if (m.broken) return _('Hardware failure; filtering bypassed');
	if (!m.detailed) return _('Basic status only; applied group list unavailable on this kernel');
	if ((m.state === 'active' || m.state === 'partial-bypass') &&
		(m.snapshot_current !== 1 || m.generation !== m.applied_generation || m.active !== 1))
		return _('Updating; previous admission snapshot is not active');
	return ({
		'active': _('Active: unsubscribed PON multicast is filtered'),
		'partial-bypass': _('Active with bypassed scopes'),
		'updating': _('Updating; previous admission snapshot is not active'),
		'bypass': _('Filtering bypassed'),
		'capacity-exceeded': _('Capacity exceeded; filtering bypassed'),
		'unsupported-scope': _('Unsupported topology; filtering bypassed'),
		'hardware-failure': _('Hardware failure; filtering bypassed')
	})[m.state] || _('Filter status unavailable');
}

function renderMulticastFilter(m) {
	var lines = [E('strong', {}, multicastFilterState(m))];
	if (m && m.available && !m.error) {
		lines.push(E('div', {}, _('Discarded packets: %s; current rate: %s packets/s').format(
			m.hardware_drops_error == null && unsignedCounter(m.hardware_drops) ? m.hardware_drops : _('N/A'),
			Number.isFinite(m.drops_per_second) ? m.drops_per_second.toFixed(1) : _('N/A'))));
		if (m.detailed) {
			var current = m.snapshot_current === 1 && m.active === 1 && m.generation === m.applied_generation;
			lines.push(E('div', {}, _('Generation: %s; last applied: %s').format(m.generation || '?', m.applied_generation || '?')));
			lines.push(E('div', {}, _('Last applied resources: rules %s/%s; lookups %s/%s').format(
				m.applied_rules == null ? '?' : m.applied_rules, m.rule_capacity || '?',
				m.applied_lookups == null ? '?' : m.applied_lookups, m.lookup_capacity || '?')));
			lines.push(E('h4', {}, current ? _('Applied admissions') : _('Previous admissions (not currently active)')));
			var admissions = Array.isArray(m.admissions) ? m.admissions : [];
			lines.push(E('ul', {}, admissions.length ? admissions.map(function(a) {
				return E('li', {}, (a.tagged ? _('VLAN %s').format(a.vid) : _('Untagged PON')) + ': ' +
					(a.bypass ? _('Bypassed scope') : (Array.isArray(a.groups) ? a.groups.join(', ') : '?')));
			}) : [E('li', {}, current ? _('No subscribed group exceptions') : _('No applied snapshot available'))]));
		}
	}
	lines.push(E('p', {'class':'soc-muted'}, _('Automatic kernel policy; no player-specific configuration. Link-local control traffic and unsupported encapsulations follow their normal paths.')));
	return E('div', {}, lines);
}

/* ── Main View ── */
function multicastState(m) {
	if (!m || m.error || !Number.isInteger(m.enabled)) return _('Multicast status unavailable');
	if (m.broken) return m.ppe_stopped ? _('Hardware fault; PPE stopped, reboot required') :
		_('Multicast fault; delivery may be interrupted, reboot required');
	if (m.scope_lost) return m.live_apply ? _('Configured interface removed; waiting for online rebinding') : _('Configured interface removed; reboot required');
	if (!m.frozen) return _('Waiting for boot policy');
	if (!m.enabled) return _('Disabled; software multicast');
	if (m.paused) return _('Paused; software multicast');
	if (!m.running) return _('Waiting for hardware initialization');
	if (!m.active) return _('Ready; no multicast entries installed');
	return _('%d multicast entries installed').format(m.active);
}

function renderMulticast(m) {
	var lines = [E('strong', {}, multicastState(m))];
	if (m && !m.error && Number.isInteger(m.enabled)) {
		lines.push(E('div', {}, _('Configured scope: %s → %s').format(
			m.configured_upstream || '?', m.configured_downstream || '?')));
		lines.push(E('div', {}, _('Boot scope: ifindex %s → %s; VID %s → %s').format(
			m.ingress, m.egress, m.ingress_vid, m.egress_vid)));
		lines.push(E('div', {}, _('Pending: %s; CPU copies delivered: %s; malformed: %s; stale: %s').format(
			m.pending, m.delivered, m.bad_copies, m.stale_copies)));
		var reasons = m.reject || {};
		lines.push(E('div', {}, _('Admission rejections') + ': ' +
			['packet', 'ingress', 'scope', 'route', 'bridge', 'resource', 'sample'].map(function(k) {
				return k + '=' + (Number.isSafeInteger(reasons[k]) ? reasons[k] : '?');
			}).join(', ')));
		lines.push(E('p', {'class':'soc-muted'}, _('Entry counts are not traffic measurements. CPU-copy counts exclude packets forwarded entirely in hardware. Hardware qualification is pending.')));
	}
	lines.push(E('p', {'class':'soc-muted'}, m && m.live_apply ?
		_('Multicast policy supports online application. Interface recovery reuses the last applied scope. Hardware faults still require recovery.') :
		_('This kernel requires a reboot to change multicast policy.')));
	lines.push(E('a', { 'href': L.url('admin/network/airoha-multicast') }, _('Configure multicast offload')));
	return E('div', {}, lines);
}

return view.extend({
	load: function() {
		// Board wiring is static for this view; avoid probing every poll.
		return L.resolveDefault(callTopology(), {}).then(function(topology) {
			boardTopology = topology || {};
			return loadStatusData();
		});
	},

	render: function(data) {
		injectCSS();
		var st = data[0]||{}, ppe = data[1]||{}, ti = data[2]||{}, fe = data[3]||{}, vo = data[4]||{}, po = data[5]||{};
		var entries = Array.isArray(ppe.entries) ? ppe.entries : [];
		st = addPpeStats(st, ppe);
		var ns = npuState(st, ti);

		var view = E('div',{'class':'cbi-map'},[
			E('h2',{},_('Airoha SoC Status')),

			// CPU Frequency
			E('div',{'class':'cbi-section'},[
				E('h3',{},_('CPU Frequency')),
				E('table',{'class':'table'},[
					E('tr',{'class':'tr'},[ E('td',{'class':'td','width':'33%'},E('strong',{},_('Current Frequency'))), E('td',{'class':'td'}, renderFreqBar(st.cpu_cur_freq||st.cpu_hw_freq,st.cpu_min_freq,st.cpu_max_freq,st.pll_freq_mhz,st.cpu_governor)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Governor'))), E('td',{'class':'td'}, renderGovSelect(st.cpu_avail_governors,st.cpu_governor)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Max Frequency'))), E('td',{'class':'td'}, renderMaxFreqSelect(st.cpu_avail_freqs,st.cpu_max_freq)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Frequency Control'))), E('td',{'class':'td'}, renderOcControls(st.cpu_native_pll)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('CPU Cores'))), E('td',{'class':'td'},(st.cpu_count||0).toString()) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('CPU Temperature'))), E('td',{'class':'td'}, renderTempBar(st.cpu_temp)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('CPU Usage (%)'))), E('td',{'class':'td'}, renderCpuUsageChart(st.cpu_sample)) ])
				])
			]),

			// NPU & Frame Engine (unified)
			E('div',{'class':'cbi-section'},[
				E('h3',{},_('NPU & Offload Engine')),
				E('table',{'class':'table'},[
					E('tr',{'class':'tr'},[ E('td',{'class':'td','width':'33%'},E('strong',{},_('NPU Status'))),
						E('td',{'class':'td','id':'npu-status'}, E('span',{'class':ns.className},ns.text+(st.npu_device?' ('+st.npu_device+')':''))) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Firmware / Clock / Cores'))),
						E('td',{'class':'td','id':'npu-info'}, npuInfo(st)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Reserved Memory'))),
						E('td',{'class':'td','id':'npu-memory'}, npuMemory(st)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Bridge filtering: VLAN-tagged frames'))),
						E('td',{'class':'td'}, renderVlanOffloadSelect(vo)) ]),
					E('tr',{'class':'tr'},[ E('td',{'class':'td'},E('strong',{},_('Bridge filtering: PPPoE-tagged frames'))),
						E('td',{'class':'td'}, renderPPPoEOffloadSelect(po)) ])
				]),

				E('p', {'class':'soc-muted'}, _('These bridge Netfilter settings are not hardware-offload switches. Driver status reports initialization; PPE bound counts report installed entries, not utilization.')),
				// Frame Engine diagram
				E('div',{'style':'margin-top:12px'},[ E('h4',{'class':'soc-text','style':'font-size:14px;margin-bottom:8px'},_('Frame Engine'))]),
				E('div',{'id':'fe-container'}, renderFeDiagram(fe, ti, st))
			]),

			E('div', {'class':'cbi-section'}, [
				E('h3', {}, _('Routed multicast offload')),
				E('div', {'id':'multicast-status'}, renderMulticast(data[6]))
			]),
			E('div', {'class':'cbi-section'}, [
				E('h3', {}, _('PON multicast admission filter (IFC)')),
				E('div', {'id':'multicast-filter-status'}, renderMulticastFilter(data[7]))
			]),

			// PPE Flow Table
			E('div',{'class':'cbi-section'},[
				E('h3',{},_('PPE Flow Offload Entries')),
				E('p', {'id':'ppe-sample-status','class':'soc-muted'}, _('PPE table is read only on request.')),
				E('button', {'class':'cbi-button cbi-button-action', 'click':refreshPpeData}, _('Read PPE table')),
				E('p', {'class':'soc-muted'}, _('UNB is an unbound learning record, not evidence of forwarding or a bound DROP rule. BND/BIND means an installed action; it does not by itself prove traffic delivery.')),
				E('div',{'class':'soc-flow-table'},E('table',{'class':'table','id':'ppe-entries-table'},[
					E('tr',{'class':'tr cbi-section-table-titles'},[
						E('th',{'class':'th'},_('Index')), E('th',{'class':'th'},_('State')), E('th',{'class':'th'},_('Type')),
						E('th',{'class':'th'},_('Original Flow')), E('th',{'class':'th'},_('New Flow')), E('th',{'class':'th'},_('Ethernet'))
					])
				].concat(renderPpeRows(entries))))
			])
		]);

		poll.add(L.bind(function() {
			if (performance.now() - lastStatusPoll < 9000) return Promise.resolve();
			return loadStatusData().then(L.bind(function(d) {
				injectCSS();
				var st=d[0]||{}, ppe=d[1]||{}, ti=d[2]||{}, fe=d[3]||{}, vo=d[4]||{}, po=d[5]||{};
				st = addPpeStats(st, ppe);

				updateFreqBar(st.cpu_cur_freq||st.cpu_hw_freq,st.cpu_min_freq,st.cpu_max_freq,st.pll_freq_mhz,st.cpu_governor);
				updateTempBar(st.cpu_temp);
				updateCpuUsageChart(st.cpu_sample);
				updateNpuInfo(st);
				var gs=document.getElementById('cpu-governor-select'); if(gs&&!gs.matches(':focus')) gs.value=st.cpu_governor||'';
				var fs=document.getElementById('cpu-maxfreq-select'); if(fs&&!fs.matches(':focus')) fs.value=(st.cpu_max_freq||0).toString();
				var vs=document.getElementById('vlan-offload-select'); if(vs&&!vs.matches(':focus')) vs.value=(vo.bridge_filter?'1':'0');
				var ps=document.getElementById('pppoe-offload-select'); if(ps&&!ps.matches(':focus')) ps.value=(po.bridge_filter?'1':'0');

				var se=document.getElementById('npu-status'), ns=npuState(st,ti);
				if(se){se.innerHTML='';var sp=document.createElement('span');sp.className=ns.className;sp.textContent=ns.text+(st.npu_device?' ('+st.npu_device+')':'');se.appendChild(sp);}

				var mc=document.getElementById('multicast-status'); if(mc){mc.innerHTML='';mc.appendChild(renderMulticast(d[6]));}
				var mf=document.getElementById('multicast-filter-status'); if(mf){mf.innerHTML='';mf.appendChild(renderMulticastFilter(d[7]));}

				var fc=document.getElementById('fe-container'); if(fc){fc.innerHTML='';fc.appendChild(renderFeDiagram(fe, ti, st));}

			},this));
		},this), 10);

		return view;
	},

	handleSaveApply: null, handleSave: null, handleReset: null
});
