#!/usr/bin/env node
// Host view contracts; actual JavaScript, mocked LuCI/DOM, no router/browser.
const fs = require('fs');
const path = require('path');
const assert = require('assert').strict;
const root = path.resolve(__dirname, '../..');
const pkg = path.join(root, 'luci-app-airoha-npu');
const source = fs.readFileSync(path.join(pkg, 'htdocs/luci-static/resources/view/airoha_npu/status.js'), 'utf8');
String.prototype.format = function(...args) {
	let index = 0;
	return this.replace(/%[sd]/g, () => String(args[index++]));
};
const calls = [];
const nodes = { 'npu-info': {}, 'npu-memory': {} };
const replies = {};
const rpc = { declare: spec => () => {
	calls.push(spec.method);
	return Promise.resolve(replies[spec.method] || {});
}};
const code = source.replace('return view.extend({', 'var page = view.extend({') +
	'\nreturn {page, npuState, npuCores, npuInfo, npuMemory, updateNpuInfo, gdmLabel, loadStatusData, multicastState, multicastFilterState, sampleMulticastFilter, renderMulticastFilter};';
const api = new Function('view', 'poll', 'rpc', 'ui', 'L', '_', 'E', 'document', code)(
	{extend: x => x}, {}, rpc, {}, {resolveDefault: (promise, fallback) => promise.catch(() => fallback)},
	x => x, (tag, attrs, children) => ({tag, attrs, children}), {getElementById: id => nodes[id]});
assert.equal(api.npuState({}, {}).text, 'Unknown');
assert.equal(api.npuState({npu_loaded: false}, {}).text, 'Not Active');
assert.equal(api.npuState({npu_loaded: true}, {}).text, 'Driver loaded');
assert.equal(api.npuState({npu_loaded: true}, {npu_active: true}).text, 'Wireless offload active');
for (const value of [undefined, null, 0, -1, '8', 0.5]) {
	assert.equal(api.npuCores({npu_cores: value}), null);
	assert(!api.npuInfo({npu_cores: value}).includes('0 cores'));
}
const known = {npu_version: '1456.62', npu_version_source: 'driver', npu_cores: 8, npu_clock: 600000000};
assert.equal(api.npuInfo(known), '1456.62 | 600 MHz | 8 cores');
assert(api.npuInfo({...known, npu_version_source: 'firmware_file'}).includes('running version unknown'));
assert.equal(api.npuMemory({}), 'N/A');
api.updateNpuInfo(known);
assert.equal(nodes['npu-info'].textContent, api.npuInfo(known));
api.updateNpuInfo({});
assert.equal(nodes['npu-memory'].textContent, 'N/A');
assert.equal(nodes['npu-info'].textContent, api.npuInfo({}));
assert(source.includes('updateNpuInfo(st);'));
assert.equal(api.page.handleSaveApply, null);
assert.equal(api.multicastState({error: 'unavailable'}), 'Multicast status unavailable');
assert.equal(api.multicastState({enabled:0, frozen:1}), 'Disabled; software multicast');
assert.equal(api.multicastState({enabled:1, frozen:1, running:1, active:0}), 'Ready; no multicast entries installed');
assert.equal(api.multicastState({enabled:1, frozen:1, running:1, active:2}), '2 multicast entries installed');
assert(api.multicastState({enabled:1, broken:1}).includes('delivery may be interrupted'));
assert(api.multicastState({enabled:1, broken:1, ppe_stopped:1}).includes('PPE stopped'));
assert(api.multicastState({enabled:1, scope_lost:1}).includes('interface removed'));
const acl = JSON.parse(fs.readFileSync(path.join(pkg, 'root/usr/share/rpcd/acl.d/luci-app-airoha-npu.json')));
assert(acl['luci-app-airoha-npu'].read.ubus['luci.airoha_npu'].includes('getTopology'));
assert(acl['luci-app-airoha-npu'].read.ubus['luci.airoha_npu'].includes('getMulticastFilter'));
assert(!acl['luci-app-airoha-npu'].write.ubus['luci.airoha_npu'].includes('getMulticastFilter'));
assert(!source.includes('poll.add(refreshPpeData'));
assert(source.includes("'click':refreshPpeData"));
const filter = {available: true, detailed: true, active: 1, broken: 0, state: 'active',
	snapshot_current: 1, generation: '5', applied_generation: '5', boot_id: 'boot',
	uptime: 100, hardware_drops: '9007199254740993', errors: '0', admissions: []};
assert(api.multicastFilterState(filter).startsWith('Active:'));
assert(api.multicastFilterState({...filter, generation: '6'}).startsWith('Updating;'));
assert(api.multicastFilterState({...filter, snapshot_current: 0}).startsWith('Updating;'));
assert(api.multicastFilterState({...filter, detailed: false}).startsWith('Basic status only'));
assert.equal(api.multicastFilterState({...filter, error: 'timeout'}), 'Filter status unavailable');
assert.equal(api.sampleMulticastFilter(filter).drops_per_second, null);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 110, hardware_drops: '9007199254741003'}).drops_per_second, 1);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 120, hardware_drops_error: -5}).drops_per_second, null);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 130}).drops_per_second, null);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 140, boot_id: 'new-boot'}).drops_per_second, null);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 150, boot_id: 'new-boot', hardware_drops: '10'}).drops_per_second, null);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 160, boot_id: 'new-boot', hardware_drops: '20', generation: '1'}).drops_per_second, null);
assert.equal(api.sampleMulticastFilter({...filter, uptime: 160, hardware_drops: 'garbage'}).drops_per_second, null);
const historical = JSON.stringify(api.renderMulticastFilter({...filter, snapshot_current: 0,
	admissions:[{tagged: 1, vid: 4001, bypass: 0, groups:['239.1.1.1']}]}));
assert(historical.includes('Previous admissions (not currently active)'));
assert(historical.includes('VLAN 4001'));
(async () => {
	replies.getTopology = {has_wifi: false, gdm: {
		gdm1: [{netdev: 'eth0', switch_ports: ['lan2', 'lan3', 'lan4']}],
		gdm2: [{netdev: 'pon0', pon: true}],
		gdm4: [{netdev: 'lan1', phy_mode: '2500base-x'}]
	}};
	await api.page.load();
	assert.equal(api.gdmLabel('gdm1'), 'Internal switch (LAN2/LAN3/LAN4)');
	assert.equal(api.gdmLabel('gdm2'), 'PON uplink (pon0)');
	assert.equal(api.gdmLabel('gdm4'), 'LAN1 · 2500BASE-X');
	assert(!calls.includes('getTokenInfo'));
	calls.length = 0;
	await api.loadStatusData();
	assert(calls.includes('getMulticast'));
	assert.equal(calls.filter(x => x === 'getMulticastFilter').length, 1);
	assert(!calls.includes('getPpeEntries'));
	assert(!calls.includes('getTopology')); // no repeated topology discovery
	assert(!calls.some(x => x.startsWith('set')));
	replies.getTopology = {has_wifi: true};
	await api.page.load();
	assert(calls.includes('getTokenInfo'));
	replies.getTopology = {};
	calls.length = 0;
	await api.page.load();
	assert(!calls.includes('getTokenInfo'));
	assert.equal(api.gdmLabel('gdm1'), 'Port mapping unavailable');
	console.log('PASS: NPU identity/unknown states, refresh, topology, wired-only polling and unchanged read ACL');
})().catch(err => { console.error(err); process.exitCode = 1; });
